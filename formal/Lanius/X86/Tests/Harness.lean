import Lanius.Core

namespace Lanius.X86.Tests.Harness

open Lanius.Core

def run (cmd : String) (args : Array String) : IO _root_.Unit := do
  let result ← IO.Process.output { cmd, args }
  unless result.exitCode == 0 do throw (IO.userError s!"{cmd}: {result.exitCode}: {result.stderr}")

def outputBytes (cmd : String) (args : Array String) : IO (UInt32 × ByteArray) := do
  let child ← IO.Process.spawn { cmd, args, stdout := .piped }
  let mut bytes := ByteArray.empty
  repeat
    let next ← child.stdout.read 4096
    if next.isEmpty then break
    bytes := bytes ++ next
  pure (← child.wait, bytes)

def argumentBits (type : Ty) (value : Int) : Nat :=
  if type == .scalar (.unsigned .usize) || type == .scalar .rawPtr then (BitVec.ofInt 64 value).toNat
  else (BitVec.ofInt 32 value).toNat + 1311768464867721216 +
    (if type == .scalar .bool then 16776960 else 0)

def harness (binary : System.FilePath) (parameters : List (VarId × Ty)) (values : List Int) : String := Id.run do
  let mut text := ".text\n.global _start\n_start:\ncld\nmov %rsp,%r15\n"
  for register in ["rbx", "rbp", "r12", "r13", "r14"] do
    text := text ++ s!"movabs $1311768467750121217,%{register}\n"
  let extras := values.drop 6
  let padding := if extras.length % 2 == 1 then 8 else 0
  if padding != 0 then text := text ++ "sub $8,%rsp\n"
  for (value, parameter) in (extras.zip (parameters.drop 6)).reverse do
    text := text ++ s!"movabs ${argumentBits parameter.2 value},%rax\npush %rax\n"
  for ((register, value), parameter) in ((["rdi","rsi","rdx","rcx","r8","r9"].zip values).zip parameters) do
    -- Boolean arguments also have dirty bits above the low byte.
    text := text ++ s!"movabs ${argumentBits parameter.2 value},%{register}\n"
  text := text ++ s!"call compiled\nadd ${extras.length * 8 + padding},%rsp\ncmp %r15,%rsp\njne bad_frame\n"
  text := text ++ "movabs $1311768467750121217,%r10\n"
  for register in ["rbx", "rbp", "r12", "r13", "r14"] do
    text := text ++ s!"cmp %r10,%{register}\njne bad_frame\n"
  return text ++ "push %rax\nmov $1,%eax\nmov $1,%edi\nmov %rsp,%rsi\nmov $8,%edx\nsyscall\n" ++
    "mov $60,%eax\nxor %edi,%edi\nsyscall\nbad_frame:\nmov $60,%eax\nmov $77,%edi\nsyscall\n" ++
    s!"compiled:\n.incbin \"{binary}\"\n.section .note.GNU-stack,\"\",@progbits\n"

end Lanius.X86.Tests.Harness
