import Lanius.X86.Transport.Core
import Lanius.X86.Tests.Harness
import Lanius.X86.Tests.Memory
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract

/-! Execute closed, currently supported functions from the exact extractor,
not copies of those functions in a fixture. Assembly only supplies the host
entry and checks the documented internal value ABI. -/
namespace Lanius.X86.Tests.Extractor

open Lanius.Core Lanius.Semantics Lanius.Extraction
open Lanius.Extraction.CoreSynthesis.Program Harness

private def sample (program : Program) : Nat → Ty → Nat → Option Value
  | 0, _, _ => none
  | fuel + 1, type, seed => match type with
    | .scalar (.signed .i32) => some (.signed .i32
        ([0, 1, -1, 2147483647, -2147483648, 17, -99, 4096][seed % 8]!))
    | .scalar .bool => some (.boolean (seed % 2 == 1))
    | .scalar (.unsigned .usize) => some (.unsigned .usize
        ([0, 1, 4294967295, 4294967296, 18446744073709551615][seed % 5]!))
    | .scalar .rawPtr => some (.pointer (seed * 4294967296))
    | .structure id => do
        let declaration ← program.structure? id
        let fields ← declaration.fields.zipIdx |>.mapM fun (type, index) => sample program fuel type (seed + index)
        pure (.structure id fields)
    | _ => none

private def words : Value → Option (List (Nat × Nat))
  | .signed .i32 value => some [(32, (BitVec.ofInt 32 value).toNat)]
  | .boolean value => some [(32, if value then 1 else 0)]
  | .unsigned .usize value | .pointer value => some [(64, value)]
  | .structure _ values => do
      let fields ← values.mapM words
      pure (if fields.flatten.isEmpty then [(64, 0)] else fields.flatten)
  | _ => none

private def aggregate : Value → Bool
  | .structure _ _ => true
  | _ => false

private def scalarBits : Value → Nat
  | .signed .i32 value => argumentBits (.scalar (.signed .i32)) value
  | .boolean value => argumentBits (.scalar .bool) (if value then 1 else 0)
  | .unsigned .usize value | .pointer value => value
  | _ => 0

private def harness (binary : System.FilePath) (arguments : List Value) (expected : Value) : Option String := do
  let output ← words expected
  let inputs ← arguments.mapM words
  let hidden := aggregate expected
  let addresses := arguments.zipIdx |>.map fun (value, index) =>
    if aggregate value then s!"lea argument_{index}(%rip),%rax\n"
    else s!"movabs ${scalarBits value},%rax\n"
  let abi := (if hidden then ["lea result(%rip),%rax\n"] else []) ++ addresses
  let extras := abi.drop 6
  let padding := extras.length % 2 * 8
  let saved := ["rbx", "rbp", "r12", "r13", "r14"]
  let initial := String.join (saved.map fun register => s!"movabs $1311768467750121217,%{register}\n")
  let pushes := String.join (extras.reverse.map (· ++ "push %rax\n"))
  let registers := String.join ((abi.zip ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]).map fun (code, register) =>
    code ++ s!"mov %rax,%{register}\n")
  let frame := "movabs $1311768467750121217,%r10\n" ++
    String.join (saved.map fun register => s!"cmp %r10,%{register}\njne bad\n")
  let result := if hidden then
      "lea result(%rip),%r11\ncmp %r11,%rax\njne bad\n" ++
      String.join (output.zipIdx |>.map fun ((width, value), index) =>
        if width == 32 then s!"mov {index * 8}(%rax),%r10d\nmov ${value},%r11d\ncmp %r11d,%r10d\njne bad\n"
        else s!"mov {index * 8}(%rax),%r10\nmovabs ${value},%r11\ncmp %r11,%r10\njne bad\n")
    else s!"movabs ${output.head!.2},%r10\ncmp %r10,%rax\njne bad\n"
  let mut data := s!".data\n.balign 16\n.quad 171\nresult:\n.zero {output.length * 8}\n.quad 205\n"
  let mut unchanged := ""
  for (input, index) in inputs.zipIdx do
    data := data ++ s!"argument_{index}:\n"
    for ((width, value), lane) in input.zipIdx do
      -- Padding is deliberately dirty. The low word still represents exactly
      -- the Core i32/bool; aggregate parameters are the internal Lanius ABI.
      let bits := value + if width == 32 then 1311768464867721216 else 0
      data := data ++ s!".quad {bits}\n"
      unchanged := unchanged ++ s!"movabs ${bits},%r10\ncmp %r10,argument_{index}+{lane * 8}(%rip)\njne bad\n"
  pure (".text\n.global _start\n_start:\ncld\nmov %rsp,%r15\n" ++ initial ++
    s!"sub ${padding},%rsp\n" ++ pushes ++ registers ++
    s!"call compiled\nadd ${extras.length * 8 + padding},%rsp\ncmp %r15,%rsp\njne bad\n" ++
    frame ++ result ++ unchanged ++
    s!"cmpq $171,result-8(%rip)\njne bad\ncmpq $205,result+{output.length * 8}(%rip)\njne bad\n" ++
    "pushfq\npop %r10\ntest $1024,%r10\njnz bad\nmov $60,%eax\nxor %edi,%edi\nsyscall\n" ++
    "bad:\nmov $60,%eax\nmov $77,%edi\nsyscall\n" ++
    s!"compiled:\n.incbin \"{binary}\"\n" ++ data ++ ".section .note.GNU-stack,\"\",@progbits\n")

def main (arguments : List String) : IO UInt32 := do
  let backend :: modulePath :: directory :: paths := arguments
    | throw (IO.userError "expected backend, self-extraction, fixture directory, and exact source paths")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid self-extraction framing")
  let encoded := ((emitted.drop ExtractorContract.modulePrefix.length).dropEnd ExtractorContract.moduleSuffix.length).toString
  let sources ← paths.mapM fun (path : String) => do
    let contents ← IO.FS.readBinFile path
    pure ({ path, bytes := contents.toList.map UInt8.toNat } : SourceFile)
  let .success checked := checkCompactCoreSourcePack encoded sources
    | throw (IO.userError "exact extractor source validation failed")
  let program := checked.program.core
  let some entry := checkSourceFunction? checked.program ["app", "main"] "main"
    | throw (IO.userError "missing extractor entry")
  let reachable := Dependencies.closure program [entry.function.id]
  let mut functions := 0
  let mut compiled := 0
  let mut results := 0
  let mut textResults := 0
  for allocation in checked.program.prepared.allocations do
    for (sourceFunction, index) in (ArtifactContextChecker.collectFunctions allocation.unit.surface.items).zipIdx do
      let id := allocation.functionIdStart + index
      if !reachable.contains id then continue
      let some transport := Transport.program? program id | continue
      let some function := program.function? id | throw (IO.userError "missing selected function")
      let name := String.intercalate "::" (allocation.unit.modulePath ++ [sourceFunction.name])
      let path := directory / s!"{id}.core"
      IO.FS.writeBinFile path ⟨(transport.flatMap i32Bytes).toArray⟩
      let (status, code) ← outputBytes "timeout" #["--kill-after=1s", "2s", backend, "--raw", path.toString]
      unless status == 0 && !code.isEmpty do throw (IO.userError s!"backend rejected supported closure {name}: {status}")
      compiled := compiled + 1
      let binary := directory / s!"{id}.bin"
      IO.FS.writeBinFile binary code
      if name == "verified::output::text" then
        for (text, length) in [("", 0), ("A\x00\x00\x00", 1), ("Aλ\x00", 3), ("Aλ🙂\x00", 7), ("12345678", 8)] do
          for capacity in [0, length, length + 1, length + 2] do
            let inputs := [.slice (.scalar (.signed .i32)) 0 [] 2 16,
              .signed .i32 capacity, .signed .i32 1, .string text, .signed .i32 length]
            if ← Lanius.X86.Tests.Memory.check program id binary directory inputs [List.replicate 20 (-333)]
                s!"actual output::text, {length} bytes, capacity {capacity}" then
              throw (IO.userError "output text trapped instead of returning its capacity result")
            textResults := textResults + 1
        IO.println s!"{name}: {textResults} Core/native text-output cases"
      if !(function.parameters.all fun (_, type) => (sample program 16 type 0).isSome) then
        IO.println s!"{name}: compiled {code.size} x86 bytes; buffer-dependent execution belongs to the lexer/parser checks"
        continue
      let mut cases := ""
      for seed in List.range 8 do
        let some inputs := function.parameters.zipIdx |>.mapM (fun ((_, type), index) => sample program 16 type (seed + index))
          | throw (IO.userError s!"missing sample representation for {name}")
        let .done expected _ := evalExpr 10000 program {} (.call id (inputs.map Expr.value))
          | throw (IO.userError s!"Core execution did not return in {name}, seed {seed}")
        let some assembly := harness binary inputs expected
          | throw (IO.userError s!"missing native value representation for {name}")
        -- One assembler/linker/process launch per source function, not per
        -- input. Each independently named case still checks all ABI state.
        let assembly := assembly.replace "mov $60,%eax\nxor %edi,%edi\nsyscall\n" "ret\n"
        let assembly := assembly.replace "mov $77,%edi" s!"mov ${77 + seed},%edi"
        let assembly := (["_start", "compiled", "argument_", "result", "bad"].foldl
          (fun text label => text.replace label s!"{label}_{seed}") assembly)
        cases := cases ++ assembly ++ "\n"
        results := results + 1
      let asm := directory / "run.s"
      let object := directory / "run.o"
      let executable := directory / "run"
      let runner := ".text\n.global _start\n_start:\nsub $8,%rsp\n" ++
        String.join ((List.range 8).map fun seed => s!"call _start_{seed}\n") ++
        "mov $60,%eax\nxor %edi,%edi\nsyscall\n"
      IO.FS.writeFile asm (runner ++ cases)
      run "as" #["--64", "-o", object.toString, asm.toString]
      run "ld" #["-m", "elf_x86_64", "-e", "_start", "-o", executable.toString, object.toString]
      let (returned, _) ← outputBytes "timeout" #["--kill-after=1s", "2s", executable.toString]
      unless returned == 0 do throw (IO.userError s!"Core/native mismatch in {name}: {returned}")
      functions := functions + 1
      IO.println s!"{name}: 8 Core/native results; {code.size} x86 bytes"
  unless functions > 6 do throw (IO.userError "no progress beyond the original scalar-only extractor subset")
  unless textResults > 0 do throw (IO.userError "the actual extractor text-output boundary was not exercised")
  IO.println s!"{compiled} real extractor functions compiled with complete call closures; {functions} non-buffer functions passed {results} Core/native comparisons; {textResults} actual text-output comparisons cover UTF-8, NUL padding and capacity failures. Scalar/aggregate values, input buffers, stack and callee-saved state are checked. This is execution evidence, not a general implementation proof."
  pure 0

end Lanius.X86.Tests.Extractor

def main := Lanius.X86.Tests.Extractor.main
