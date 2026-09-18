import Lanius.X86.Transport.Core
import Lanius.X86.Tests.Harness
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract

namespace Lanius.X86.Tests.Runtime
open Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Extraction.CoreSynthesis.Program Harness

private def execute (image : System.FilePath) (args : Array String) : IO (UInt32 × ByteArray × ByteArray) := do
  let child ← IO.Process.spawn {
    cmd := "timeout"
    args := #["--kill-after=1s", "2s", image.toString] ++ args
    stdout := .piped
    stderr := .piped }
  let mut output := ByteArray.empty
  repeat
    let bytes ← child.stdout.read 4096
    if bytes.isEmpty then break
    output := output ++ bytes
  -- These fixtures emit at most one diagnostic byte; no unbounded stderr producer.
  let error ← child.stderr.read 4096
  pure (← child.wait, output, error)

/-- Check native address properties at the allocator ABI. Core addresses are
abstract identities, so a Core numeric-address comparison would be misleading. -/
private def allocatorABI (backend : String) (program : Program) (directory : System.FilePath) : IO _root_.Unit := do
  let some allocation := program.functions.find? (fun f => f.external == some (.host .alloc))
    | throw (IO.userError "missing allocator declaration")
  let some words := Transport.program? program allocation.id
    | throw (IO.userError "unsupported allocator")
  let input := directory / "allocator.core"
  IO.FS.writeBinFile input ⟨(words.flatMap i32Bytes).toArray⟩
  let (status, bytes) ← outputBytes "timeout" #["--kill-after=1s", "2s", backend, "--raw", input.toString]
  unless status == 0 && !bytes.isEmpty do throw (IO.userError "allocator emission failed")
  let binary := directory / "allocator.bin"
  IO.FS.writeBinFile binary bytes
  let mut assembly := ".text\n.global _start\n_start:\nxor %r12d,%r12d\n"
  let saved := ["rbx", "rbp", "r13", "r14", "r15"]
  for register in saved do assembly := assembly ++ s!"movabs $1311768467750121217,%{register}\n"
  for shift in List.range 21 do
    let alignment := 2^shift
    assembly := assembly ++ s!"mov $17,%edi\nmov ${alignment},%esi\ncall compiled\ntest %rax,%rax\njz bad\n" ++
      s!"mov ${alignment-1},%r10d\ntest %r10,%rax\njnz bad\ncmp %r12,%rax\nje bad\n" ++
      "cmpq $0,(%rax)\njne bad\ncmpq $0,8(%rax)\njne bad\ncmpb $0,16(%rax)\njne bad\n" ++
      "mov %rax,%r12\nmovb $255,(%rax)\nmovabs $1311768467750121217,%r10\n"
    for register in saved do assembly := assembly ++ s!"cmp %r10,%{register}\njne bad\n"
  assembly := assembly ++ "mov $60,%eax\nxor %edi,%edi\nsyscall\nbad:\nmov $60,%eax\nmov $77,%edi\nsyscall\n" ++
    s!"compiled:\n.incbin \"{binary}\"\n.section .note.GNU-stack,\"\",@progbits\n"
  let asm := directory / "allocator.s"
  let object := directory / "allocator.o"
  let image := directory / "allocator"
  IO.FS.writeFile asm assembly
  run "as" #["--64", "-o", object.toString, asm.toString]
  run "ld" #["-m", "elf_x86_64", "-e", "_start", "-o", image.toString, object.toString]
  let (code, output, error) ← execute image #[]
  unless code == 0 && output.isEmpty && error.isEmpty do throw (IO.userError s!"allocator address/ABI contract: {code}")

def main (arguments : List String) : IO UInt32 := do
  let backend :: modulePath :: directory :: paths := arguments
    | throw (IO.userError "expected backend, extracted fixture, directory, and exact source closure")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid fixture framing")
  let encoded := ((emitted.drop ExtractorContract.modulePrefix.length).dropEnd ExtractorContract.moduleSuffix.length).toString
  let sources ← paths.mapM fun (path : String) => do
    let bytes ← IO.FS.readBinFile path
    pure ({ path, bytes := bytes.toList.map UInt8.toNat } : SourceFile)
  let checked ← match checkCompactCoreSourcePack encoded sources with
    | .success checked => pure checked
    | .failure message => throw (IO.userError s!"runtime fixture source/Core: {reprStr message}")
  let mut cases := 0
  let mut rejected := 0
  allocatorABI backend checked.program.core directory
  for name in ["arguments", "allocation", "invalid_alignment", "files"] do
    let some entry := checkSourceFunction? checked.program ["examples", "runtime"] name
      | throw (IO.userError s!"missing {name}")
    let some words := Transport.program? checked.program.core entry.function.id
      | throw (IO.userError s!"unsupported {name}")
    let input := directory / s!"{name}.core"
    IO.FS.writeBinFile input ⟨(words.flatMap i32Bytes).toArray⟩
    let (status, bytes) ← outputBytes "timeout" #["--kill-after=1s", "2s", backend, input.toString]
    unless status == 0 && bytes.size > 512 do throw (IO.userError s!"ELF emission {name}: {status}")
    unless bytes.extract 0 7 == ⟨#[127,69,76,70,2,1,1]⟩ && bytes[16]! == 2 && bytes[18]! == 62 &&
        bytes[56]! == 2 && bytes[68]! == 5 && bytes[124]! == 6 do
      throw (IO.userError "not a static x86-64 RX image with non-executable stack")
    let image := directory / name
    IO.FS.writeBinFile image bytes
    run "chmod" #["u+x", image.toString]
    if name == "arguments" then
      for argument in ["", "a", "abcd", "abcde", "abcdef", "Aλ🙂", String.ofList (List.replicate 255 'x')] do
        let (code, output, error) ← execute image #[argument, ""]
        unless code == UInt32.ofNat (argument.utf8ByteSize % 256) &&
            output == argument.toUTF8.extract 0 (min 5 argument.utf8ByteSize) && error.isEmpty do
          throw (IO.userError s!"argv UTF-8/count/copy contract: {reprStr argument}, exit {code}")
        cases := cases + 1
    else if name == "allocation" then
      let (code, output, error) ← execute image #[]
      unless code == 0 && output == ⟨#[255]⟩ && error == ⟨#[65]⟩ do
        throw (IO.userError s!"allocation/byte output contract: {code}, {output.toList}, {error.toList}")
      cases := cases + 1
    else if name == "invalid_alignment" then
      let (code, output, _) ← execute image #[]
      -- `timeout` may print its own signal diagnostic. The program must emit
      -- nothing and die by SIGILL, not return, segfault, or exceed its deadline.
      unless code == 132 && output.isEmpty do
        throw (IO.userError s!"invalid alignment did not trap precisely: {code}")
      cases := cases + 1
    else
      for length in [1, 4, 15, 16, 17, 128] do
        let contents := ByteArray.mk ((List.range length).map fun n => UInt8.ofNat (n * 79 + 251)).toArray
        let path := directory / "data λ.bin"
        IO.FS.writeBinFile path contents
        let (code, output, error) ← execute image #[path.toString]
        unless code == UInt32.ofNat (min 16 length) && output == contents.extract 0 (min 16 length) && error.isEmpty do
          throw (IO.userError s!"file read/close/reopen contract, length {length}: {code}")
        cases := cases + 1
    -- Unknown runtime identities and wrong return/argument types must fail
    -- before publishing an image, even if the byte stream is otherwise valid.
    let selected := checked.program.core.functions.filter fun f => f.external.isSome
    for service in selected do
      let some external := Transport.function? checked.program.core service | continue
      let marker := (external.length : Int) :: external
      let rec replace (input : List Int) : Option (List Int) :=
        if marker.isPrefixOf input then some input else
        match input with | [] => none | _ :: rest => replace rest
      let some tail := replace words | continue
      let start := words.length - tail.length + 1
      for bad in [words.set (start + external.length - 1) 99, words.set (start + 3) 2] do
        IO.FS.writeBinFile input ⟨(bad.flatMap i32Bytes).toArray⟩
        let (code, output) ← outputBytes "timeout" #["--kill-after=1s", "2s", backend, input.toString]
        unless code == 7 && output.isEmpty do throw (IO.userError "malformed runtime signature accepted")
        rejected := rejected + 1
  IO.println s!"Runtime/ELF: {cases} native argument/allocation/file/byte/trap cases; 21 allocator alignments/freshness/zero-fill/caller-ABI checks; {rejected} malformed service rejections."
  pure 0
end Lanius.X86.Tests.Runtime

def main := Lanius.X86.Tests.Runtime.main
