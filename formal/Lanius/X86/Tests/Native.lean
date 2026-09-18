import Lean

private def run (cmd : String) (args : Array String) : IO Unit := do
  let result ← IO.Process.output { cmd, args }
  unless result.exitCode == 0 do
    throw (IO.userError s!"{cmd} failed ({result.exitCode}): {result.stderr}")

/-- Link the raw code produced by Lanius into a test-only ELF. GNU ld is not
part of the production backend; ELF emission is still a separate deliverable. -/
def main (arguments : List String) : IO UInt32 := do
  let [producer, directory] := arguments
    | throw (IO.userError "expected Lanius native-code test producer and fixture directory")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  let child ← IO.Process.spawn { cmd := producer, stdout := .piped }
  let mut bytes := ByteArray.empty
  repeat
    let chunk ← child.stdout.read 4096
    if chunk.isEmpty then break
    bytes := bytes ++ chunk
  unless (← child.wait) == 0 do throw (IO.userError "Lanius native-code production failed")
  unless bytes.size > 0 && bytes.size ≤ 4096 do throw (IO.userError "invalid native-code length")
  let code := directory / "native-code.bin"
  let assembly := directory / "native-wrapper.s"
  let object := directory / "native-wrapper.o"
  let executable := directory / "native-code"
  IO.FS.writeBinFile code bytes
  IO.FS.writeFile assembly s!".text\n.global _start\n_start:\n.incbin \"{code}\"\n.section .note.GNU-stack,\"\",@progbits\n"
  run "as" #["--64", "-o", object.toString, assembly.toString]
  run "ld" #["-m", "elf_x86_64", "-e", "_start", "-o", executable.toString, object.toString]
  run "timeout" #["--kill-after=1s", "10s", executable.toString]
  IO.println s!"{bytes.size} bytes of Lanius-emitted x86 executed: 64-bit/byte memory, signed quotient/remainder, backward loop, forward call, return, and patched failure edges passed"
  pure 0
