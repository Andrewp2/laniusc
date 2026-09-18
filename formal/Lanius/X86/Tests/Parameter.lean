import Lanius.X86.Lower.Return
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract

open Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Extraction.CoreSynthesis.Program
open Lanius.FunctionalView.Core
open Lanius.Separation

private def run (cmd : String) (args : Array String) : IO _root_.Unit := do
  let result ← IO.Process.output { cmd, args }
  unless result.exitCode == 0 do throw (IO.userError s!"{cmd}: {result.exitCode}: {result.stderr}")

private def outputBytes (cmd : String) (args : Array String) : IO (UInt32 × ByteArray) := do
  let child ← IO.Process.spawn { cmd, args, stdout := .piped }
  let mut bytes := ByteArray.empty
  repeat
    let next ← child.stdout.read 4096
    if next.isEmpty then break
    bytes := bytes ++ next
  pure (← child.wait, bytes)

private def programWords (words : List Int) : List Int :=
  [2, 64, (words[2]?).getD 0, 0, 0, 1, (words.length : Int)] ++ words

def main (arguments : List String) : IO UInt32 := do
  let [backend, modulePath, sourcePath, directory] := arguments
    | throw (IO.userError "expected backend executable, extracted module, exact source file, fixture directory")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid extracted source pack framing")
  let encoded := ((emitted.drop ExtractorContract.modulePrefix.length).dropEnd ExtractorContract.moduleSuffix.length).toString
  let contents ← IO.FS.readBinFile sourcePath
  let source : SourceFile := ⟨sourcePath, contents.toList.map UInt8.toNat⟩
  let .success checked := checkCompactCoreSourcePack encoded [source]
    | throw (IO.userError "actual input-source validation failed")
  let mut count := 0
  let mut rejected := 0
  for name in ["first", "second", "third", "fourth", "fifth", "sixth"] do
    let some located := checkSourceFunction? checked.program ["examples", "parameters"] name
      | throw (IO.userError s!"missing source function {name}")
    let some selected := Lanius.X86.Lower.Parameter.check? located.function
      | throw (IO.userError s!"unsupported source function {name}")
    let transport := directory / s!"{name}.core"
    IO.FS.writeBinFile transport ⟨((programWords selected.words).flatMap i32Bytes).toArray⟩
    let (status, code) ← outputBytes backend #[transport.toString]
    unless status == 0 && code.toList.take 5 == [233, 0, 0, 0, 0] && code.size > 5 && code.size ≤ 9 do
      throw (IO.userError s!"Lanius backend rejected {name}: status={status}, size={code.size}")
    let bodyCode := code.toList.drop 5
    let some certificate := Lanius.X86.Lower.Parameter.certify? located.function bodyCode
      | throw (IO.userError s!"uncertifiable machine bytes for {name}")
    have _preservation := certificate.preserves
    for wrong in [bodyCode.set 0 195, bodyCode.dropLast, bodyCode ++ [195],
        [137, 192, 195], [72, 137, 248, 195]] do
      unless (Lanius.X86.Lower.Parameter.certify? located.function wrong).isNone do
        throw (IO.userError "machine certificate accepted wrong opcode, register, width, truncation, or trailing code")
    let binary := directory / s!"{name}.bin"
    IO.FS.writeBinFile binary code
    if name == "first" then
      let words := selected.words
      let body := 6 + located.function.parameters.length * 2
      let truncated := (List.range words.length).map words.take
      let malformed := truncated ++ [words ++ [0], words.set 0 2, words.set 1 32,
        words.set 2 (-1), words.set 3 2, words.set 4 0, words.set 4 7,
        words.set 4 2147483647, words.set 5 5, words.set 5 2147483647,
        words.set 6 (-1), words.set 8 0, words.set 7 2,
        words.set body 99, words.set (body + 1) 11, words.set (body + 2) 0,
        words.set (body + 3) 0, words.set (body + 4) 99, words.set (body + 5) 1]
      for bad in malformed do
        let path := directory / "rejected.core"
        IO.FS.writeBinFile path ⟨((programWords bad).flatMap i32Bytes).toArray⟩
        let (status, unexpected) ← outputBytes backend #[path.toString]
        unless status != 0 && unexpected.isEmpty do
          throw (IO.userError s!"backend accepted malformed Core transport: {bad}")
        rejected := rejected + 1
      -- IDs are not register positions: renumber all six parameters, retain
      -- their order, and return the first one through its new local ID.
      let mut renamed := words.set 2 123
      for index in [:6] do renamed := renamed.set (6 + index * 2) (100 + index * 7)
      renamed := renamed.set (body + 4) 100
      let renamedPath := directory / "renamed.core"
      IO.FS.writeBinFile renamedPath ⟨((programWords renamed).flatMap i32Bytes).toArray⟩
      let (renamedStatus, renamedCode) ← outputBytes backend #[renamedPath.toString]
      unless renamedStatus == 0 && renamedCode == code do
        throw (IO.userError "backend confused a Core local ID with an ABI parameter position")
    for values in ([[0, 1, 2, 3, 4, 5], [-2147483648, 2147483647, -1, 0, 256, 305419896],
        [2147483647, -2147483648, 305419896, -1, 65536, 0],
        [-1, -2, -3, -4, -5, -6]] : List (List Int)) do
      let bindings := located.function.parameters.zip values |>.map (fun (parameter, value) =>
        (parameter.1, Value.signed .i32 value))
      let some body := located.function.body | throw (IO.userError "no Core body")
      let .done (.returned (some (.signed .i32 expected))) _ :=
          execStmt 30 checked.program.core (enterCall {} bindings) body
        | throw (IO.userError "actual Core function did not return an i32")
      let args := (["rdi", "rsi", "rdx", "rcx", "r8", "r9"].zip values).map fun (register, value) =>
        -- Nonzero upper halves catch accidental 64-bit copying. i32 returns
        -- must place the value in EAX, clearing the upper half of RAX.
        s!"movabs ${((BitVec.ofInt 32 value).toNat + 1311768464867721216)}, %{register}\n"
      let assembly := directory / "parameter.s"
      let object := directory / "parameter.o"
      let executable := directory / "parameter"
      IO.FS.writeFile assembly (".text\n.global _start\n_start:\n" ++ String.join args ++
        s!"call compiled\npush %rax\nmov $1, %eax\nmov $1, %edi\nmov %rsp, %rsi\nmov $8, %edx\nsyscall\nmov $60, %eax\nxor %edi, %edi\nsyscall\ncompiled:\n.incbin \"{binary}\"\n.section .note.GNU-stack,\"\",@progbits\n")
      run "as" #["--64", "-o", object.toString, assembly.toString]
      run "ld" #["-m", "elf_x86_64", "-e", "_start", "-o", executable.toString, object.toString]
      let (status, returned) ← outputBytes "timeout" #["--kill-after=1s", "2s", executable.toString]
      let wanted := i32Bytes expected ++ [0, 0, 0, 0]
      unless status == 0 && returned.toList == wanted do
        throw (IO.userError s!"Core/native mismatch for {name}, inputs={values}, expected={expected}")
      count := count + 1
  IO.println s!"{count} actual-source Core → Lanius backend → native x86 returns agree, including signed i32 boundaries and dirty upper argument bits; {rejected} malformed transports reject without output, renamed IDs retain parameter order; GNU as/ld are test-harness-only"
  pure 0
