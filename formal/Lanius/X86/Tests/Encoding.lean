import Lean

namespace Lanius.X86.Tests

private def registers32 := #["eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi",
  "r8d", "r9d", "r10d", "r11d", "r12d", "r13d", "r14d", "r15d"]
private def registers64 := #["rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi",
  "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15"]
private def registers8 := #["al", "cl", "dl", "bl", "spl", "bpl", "sil", "dil",
  "r8b", "r9b", "r10b", "r11b", "r12b", "r13b", "r14b", "r15b"]
private def conditions := #["o", "no", "b", "ae", "e", "ne", "be", "a",
  "s", "ns", "p", "np", "l", "ge", "le", "g"]

private def instruction (kind width destination source : Nat) (value : Int) : String := Id.run do
  if kind == 23 then
    return "{disp32} " ++ s!"lea {registers64[destination]!}, [{registers64[source % 16]!} + {registers64[source / 16]!}*{2^width} + {value}]"
  if kind == 24 then return s!"lea {registers64[destination]!}, [rip + {value}]"
  let registers := if width == 64 then registers64 else registers32
  let dst := registers[destination]!
  let src := registers[source]!
  let mem := s!"[{registers64[source]!} + {value}]"
  let size := if width == 64 then "qword" else "dword"
  match kind with
  | 0 => return s!"mov {dst}, {src}"
  | 1 => return s!"add {dst}, {src}"
  | 2 => return s!"sub {dst}, {src}"
  | 3 => return s!"cmp {dst}, {src}"
  | 4 => return s!"and {dst}, {src}"
  | 5 => return s!"or {dst}, {src}"
  | 6 => return s!"xor {dst}, {src}"
  | 7 => return s!"test {dst}, {src}"
  | 8 => return s!"imul {dst}, {src}"
  | 9 =>
      let low := (value % 4294967296).toNat
      return if width == 64 then s!"movabs {dst}, {305419896 * 4294967296 + low}"
        else s!"mov {dst}, {low}"
  | 10 => return "{disp32} " ++ s!"mov {dst}, {size} ptr {mem}"
  | 11 => return "{disp32} " ++ s!"mov {size} ptr {mem}, {dst}"
  | 12 => return "{disp32} " ++ s!"lea {registers64[destination]!}, {mem}"
  | 13 => return "{disp32} " ++ s!"movzx {registers32[destination]!}, byte ptr {mem}"
  | 14 => return "{disp32} " ++ s!"mov byte ptr {mem}, {registers8[destination]!}"
  | 15 => return s!"movsxd {registers64[destination]!}, {registers32[source]!}"
  | 16 => return s!"movzx {registers32[destination]!}, {registers8[source]!}"
  | 17 => return s!"{if source == 4 then "shl" else if source == 5 then "shr" else "sar"} {dst}, cl"
  | 18 => return s!"{if source == 0 then "div" else "idiv"} {dst}"
  | 19 => return s!"neg {dst}"
  | 20 => return s!"set{conditions[source]!} {registers8[destination]!}"
  | 21 => return s!"push {registers64[destination]!}"
  | 22 => return s!"pop {registers64[destination]!}"
  | _ => panic! "invalid instruction test kind"

private def corpus : Array String := Id.run do
  let mut lines := #[]
  for width in [32, 64] do
    for destination in [:16] do
      for source in [:16] do
        for kind in [:17] do
          lines := lines.push (instruction kind width destination source (-2147483647))
      for operation in [4, 5, 7] do
        lines := lines.push (instruction 17 width destination operation 0)
      for signed in [0, 1] do
        lines := lines.push (instruction 18 width destination signed 0)
      lines := lines.push (instruction 19 width destination 0 0)
      for condition in [:16] do
        lines := lines.push (instruction 20 width destination condition 0)
      for kind in [21, 22] do
        lines := lines.push (instruction kind width destination 0 0)
  for displacement in [:259] do
    for base in [:16] do
      for kind in [10, 11, 12, 13, 14] do
        lines := lines.push (instruction kind 64 7 base (displacement - (129 : Int)))
  for condition in [:16] do
    for target in [0, 16, 32, 2147483647] do
      -- The Lanius local test buffer starts each instruction at cursor 2.
      let relative : Int := target - 2
      lines := lines.push ("{disp32} " ++ s!"jmp . + {relative}")
      lines := lines.push s!"call . + {relative}"
      lines := lines.push ("{disp32} " ++ s!"j{conditions[condition]!} . + {relative}")
      lines := lines.push "ret"
      lines := lines.push "syscall"
      lines := lines.push "ud2"
  lines := lines.push "cdq"
  lines := lines.push "cqo"
  for destination in [:16] do
    for base in [:16] do
      for index in [:16] do
        if index != 4 then
          for scale in [:4] do
            lines := lines.push (instruction 23 scale destination (base + index * 16) (-2147483647))
  for destination in [:16] do
    for displacement in [-2147483648, -1, 0, 1, 2147483647] do
      lines := lines.push (instruction 24 64 destination 0 displacement)
  return lines

private def run (cmd : String) (args : Array String) : IO Unit := do
  let result ← IO.Process.output { cmd, args }
  unless result.exitCode == 0 do
    throw (IO.userError s!"{cmd} failed ({result.exitCode}): {result.stderr}")

private def emittedBytes (executable : String) : IO ByteArray := do
  let child ← IO.Process.spawn { cmd := executable, stdout := .piped }
  let mut bytes := ByteArray.empty
  repeat
    let chunk ← child.stdout.read 65536
    if chunk.isEmpty then break
    bytes := bytes ++ chunk
  let status ← child.wait
  unless status == 0 do
    throw (IO.userError s!"Lanius emitter's operand/capacity/frame checks failed: {status}")
  return bytes

/-- GNU as is an independent test oracle, never a production backend. This
driver produces assembly fixtures only; it does not generate Lanius programs. -/
def check (executable : String) (directory : System.FilePath) : IO Unit := do
  IO.FS.createDirAll directory
  let lines := corpus
  let assembly := directory / "encoding-oracle.s"
  let object := directory / "encoding-oracle.o"
  let binary := directory / "encoding-oracle.bin"
  IO.FS.writeFile assembly (".intel_syntax noprefix\n.text\n" ++ String.intercalate "\n" lines.toList ++ "\n")
  run "as" #["--64", "-o", object.toString, assembly.toString]
  run "objcopy" #["-O", "binary", "-j", ".text", object.toString, binary.toString]
  let expected ← IO.FS.readBinFile binary
  let actual ← emittedBytes executable
  IO.FS.writeBinFile (directory / "encoding-lanius.bin") actual
  unless actual == expected do
    let mut index := 0
    while index < min actual.size expected.size && actual[index]! == expected[index]! do
      index := index + 1
    throw (IO.userError s!"x86 encoding differs at byte {index}: actual={actual[index]?.map UInt8.toNat}, expected={expected[index]?.map UInt8.toNat}; lengths {actual.size}/{expected.size}")
  IO.println s!"{lines.size} x86 instructions: {actual.size} bytes match GNU as; Lanius capacity, operand, and frame checks passed"

end Lanius.X86.Tests

def main (arguments : List String) : IO UInt32 := do
  let [executable, directory] := arguments
    | throw (IO.userError "expected Lanius encoding-test executable and fixture directory")
  Lanius.X86.Tests.check executable directory
  pure 0
