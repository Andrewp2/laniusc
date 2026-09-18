import Lanius.X86.Transport.Core
import Lanius.X86.Tests.Harness
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract
import Lanius.X86.Machine.Boolean

open Lanius.Core Lanius.Semantics Lanius.Separation Lanius.Extraction
open Lanius.Extraction.CoreSynthesis.Program Lanius.X86.Tests.Harness

private def casesFor (name : String) : List Int :=
  if name == "factorial" then [0, 1, 2, 5, 10, 12, 13]
  else if name == "mutual" then [0, 1, 2, 7, 16, 31]
  else if name.startsWith "pointer_" || name.startsWith "word_" || name == "narrow" then
    [0, 1, 4294967295, 4294967296, 1311768467750121217, 18446744073709551615]
  else [0, 1, -1, 123, -456, 2147483647, -2147483648]

private def inputValue (type : Ty) (value : Int) : Value :=
  if type == .scalar (.unsigned .usize) then .unsigned .usize value.toNat
  else if type == .scalar .rawPtr then .pointer value.toNat
  else .signed .i32 value

private def resultBytes : Value → Option (List UInt8)
  | .signed .i32 value => some (i32Bytes value ++ [0,0,0,0])
  | .unsigned .usize value | .pointer value => some (i32Bytes value ++ i32Bytes (value / 4294967296))
  | _ => none

private def descriptorHarness (binary : System.FilePath) (length : Nat) : String :=
  ".text\n.global _start\n_start:\ncld\nmov %rsp,%r15\nmovabs $1311768467750121217,%rbp\n" ++
  "lea result(%rip),%rdi\nlea argument(%rip),%rsi\ncall compiled\ncmp %r15,%rsp\njne bad\n" ++
  "movabs $1311768467750121217,%r10\ncmp %r10,%rbp\njne bad\nlea result(%rip),%r11\ncmp %r11,%rax\njne bad\n" ++
  "lea data_words(%rip),%r10\ncmp %r10,result(%rip)\njne bad\ncmp %r10,argument(%rip)\njne bad\n" ++
  s!"movabs ${length},%r10\ncmp %r10,result+8(%rip)\njne bad\ncmp %r10,argument+8(%rip)\njne bad\n" ++
  "cmpq $171,result-8(%rip)\njne bad\ncmpq $205,result+16(%rip)\njne bad\n" ++
  "mov $60,%eax\nxor %edi,%edi\nsyscall\nbad:\nmov $60,%eax\nmov $77,%edi\nsyscall\n" ++
  s!"compiled:\n.incbin \"{binary}\"\n.data\n.balign 16\n.quad 171\nresult:\n.quad 0,0,205\nargument:\n.quad data_words,{length}\ndata_words:\n.long 1,2,3\n.section .note.GNU-stack,\"\",@progbits\n"

def main (arguments : List String) : IO UInt32 := do
  let [backend, modulePath, sourcePath, directory] := arguments
    | throw (IO.userError "expected backend executable, extracted module, exact values source, fixture directory")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid source pack framing")
  let encoded := ((emitted.drop ExtractorContract.modulePrefix.length).dropEnd ExtractorContract.moduleSuffix.length).toString
  let source ← IO.FS.readBinFile sourcePath
  let checked ← match checkCompactCoreSourcePack encoded [⟨sourcePath, source.toList.map UInt8.toNat⟩] with
    | .success checked => pure checked
    | .failure stage => throw (IO.userError s!"actual values source validation failed: {stage}")
  let mut results := 0
  let mut rejections := 0
  for name in ["copies", "nested", "staged", "factorial", "mutual", "pointer_identity", "word_identity",
      "pointer_null", "pointer_equal", "word_nonzero", "word_equal", "widen", "narrow", "slice_forward"] do
    let some located := checkSourceFunction? checked.program ["examples", "values"] name
      | throw (IO.userError s!"missing source function {name}")
    let some words := Lanius.X86.Transport.program? checked.program.core located.function.id
      | throw (IO.userError s!"unsupported actual Core in {name}")
    let transport := directory / s!"{name}.core"
    IO.FS.writeBinFile transport ⟨(words.flatMap i32Bytes).toArray⟩
    let (status, code) ← outputBytes "timeout" #["--kill-after=1s", "2s", backend, "--raw", transport.toString]
    unless status == 0 && !code.isEmpty do throw (IO.userError s!"backend rejected {name}: {status}")
    -- Keep the native semantic window tied to the current Lanius output.
    -- This is regression evidence, not the still-open emitter theorem.
    if ["pointer_null", "pointer_equal", "word_nonzero", "word_equal"].contains name then
      let condition := if name == "word_nonzero" then 5 else 4
      let window := Lanius.X86.Machine.ReadOnly.code (Lanius.X86.Machine.Boolean.comparison condition)
      unless (List.range code.size).any (fun offset => (code.toList.drop offset).take window.length == window) do
        throw (IO.userError s!"{name}: actual emitted comparison differs from the proved machine window")
    let binary := directory / s!"{name}.bin"
    IO.FS.writeBinFile binary code
    if name == "slice_forward" then
      let array : Value := .array [.signed .i32 1, .signed .i32 2, .signed .i32 3]
      let before : State := { cells := [⟨0, some array⟩], nextCell := 1 }
      let argument : Value := .slice (.scalar (.signed .i32)) 0 [] 0 3
      let .done value after := evalExpr 1000 checked.program.core before (.call located.function.id [.value argument])
        | throw (IO.userError "Core slice forwarding failed")
      unless value == argument && after.cell? 0 == some array do throw (IO.userError "Core slice alias/length changed")
      -- Descriptor transport itself does not dereference the data pointer.
      -- The large opaque length catches truncation, not an array-access claim.
      for length in [0, 3, 4294967299] do
        let assembly := directory / "descriptor.s"
        let object := directory / "descriptor.o"
        let executable := directory / "descriptor"
        IO.FS.writeFile assembly (descriptorHarness binary length)
        run "as" #["--64", "-o", object.toString, assembly.toString]
        run "ld" #["-m", "elf_x86_64", "-e", "_start", "-o", executable.toString, object.toString]
        let (returned, _) ← outputBytes "timeout" #["--kill-after=1s", "2s", executable.toString]
        unless returned == 0 do throw (IO.userError s!"slice descriptor/caller state differs for length {length}: {returned}")
    else
      for value in casesFor name do
        let some (_, type) := located.function.parameters.head? | throw (IO.userError "missing parameter")
        let .done expected _ := evalExpr 5000 checked.program.core {} (.call located.function.id [.value (inputValue type value)])
          | throw (IO.userError s!"Core {name} failed for {value}")
        let some wanted := resultBytes expected | throw (IO.userError "unexpected Core result type")
        let assembly := directory / "run.s"
        let object := directory / "run.o"
        let executable := directory / "run"
        IO.FS.writeFile assembly (harness binary located.function.parameters [value])
        run "as" #["--64", "-o", object.toString, assembly.toString]
        run "ld" #["-m", "elf_x86_64", "-e", "_start", "-o", executable.toString, object.toString]
        let (returned, bytes) ← outputBytes "timeout" #["--kill-after=1s", "2s", executable.toString]
        unless returned == 0 && bytes.toList == wanted do
          throw (IO.userError s!"Core/native {name}({value}) differs: status={returned}, bytes={bytes.toList}, expected={wanted}")
        results := results + 1
    for bad in [words.dropLast, words ++ [0], words.set 0 3, words.set 1 32, words.set 2 2147483647,
        words.set 3 2147483647, words.set 4 2147483647, words.set 5 0] do
      let path := directory / "bad.core"
      IO.FS.writeBinFile path ⟨(bad.flatMap i32Bytes).toArray⟩
      let (status, bytes) ← outputBytes "timeout" #["--kill-after=1s", "2s", backend, "--raw", path.toString]
      unless status == 7 && bytes.isEmpty do throw (IO.userError "malformed program published executable bytes")
      rejections := rejections + 1
  IO.println s!"{results} actual-source Core/native results: nested struct copies/returns, constants, nested argument calls, odd/even stack-argument padding, recursion, mutual recursion, pointers, usize, and signed casts; three full-width slice descriptor transports and one Core alias check; {rejections} malformed programs rejected"
  pure 0
