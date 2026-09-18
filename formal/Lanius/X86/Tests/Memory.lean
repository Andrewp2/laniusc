import Lanius.X86.Tests.Harness
import Lanius.Semantics

/-! Native harness for Core values backed by real packed i32 buffers.
It performs no compilation or extraction. Every buffer is checked against the
Core post-state, including alias effects and untouched lanes/canaries. -/
namespace Lanius.X86.Tests.Memory

open Lanius.Core Lanius.Semantics Harness

-- Core assigns abstract raw addresses. Relate views of supplied buffers to
-- assembler labels; never compare those abstract numbers to native pointers.
private def pointerSymbol (post : State) (bufferCount address : Nat) : String :=
  match post.i32ArrayViews.find? fun view =>
      view.root < bufferCount && view.projections.isEmpty &&
        view.address ≤ address && address ≤ view.address + view.length * 4 with
  | some view => s!"data_{view.root}+{address - view.address}"
  | none => toString address

private def stringsIn : Value → List String
  | .string text => [text]
  | .structure _ values => values.flatMap stringsIn
  | _ => []

private def words (post : State) (bufferCount : Nat) (strings : List String) (result : Bool) : Value → Option (List (Nat × String))
  | .signed .i32 value => some [(32, toString (BitVec.ofInt 32 value).toNat)]
  | .boolean value => some [(32, if value then "1" else "0")]
  | .unsigned .usize value => some [(64, toString value)]
  | .pointer value => some [(64, pointerSymbol post bufferCount value)]
  | .string text => some [(if result then 8 else 64,
      if result then text else s!"string_{strings.idxOf text}"), (64, toString text.utf8ByteSize)]
  | .slice (.scalar (.signed .i32)) cell [] start length => do
      let address ← if cell < bufferCount then some s!"data_{cell}+{start * 4}"
        else do
          let view ← post.i32ArrayView? cell []
          pure (pointerSymbol post bufferCount (view.address + start * 4))
      pure [(64, address), (64, toString length)]
  | .structure _ values => do
      let fields ← values.mapM (words post bufferCount strings result)
      pure (if fields.flatten.isEmpty then [(0, "0")] else fields.flatten)
  | _ => none

private def aggregate : Value → Bool
  | .slice .. | .structure .. | .string _ => true
  | _ => false

private def scalarBits : Value → Nat
  | .signed .i32 value => argumentBits (.scalar (.signed .i32)) value
  | .boolean value => argumentBits (.scalar .bool) (if value then 1 else 0)
  | .unsigned .usize value | .pointer value => value
  | _ => 0

def state (buffers : List (List Int)) : State := {
  cells := buffers.zipIdx |>.map fun (values, index) => ⟨index, some (.array (values.map (Value.signed .i32)))⟩
  nextCell := buffers.length }

private def assembly (binary : System.FilePath) (arguments : List Value) (buffers : List (List Int))
    (result : Option Value) (post : State) (hidden : Bool) : Option String := do
  let strings := (arguments.flatMap stringsIn).eraseDups
  let inputs ← arguments.mapM (words post buffers.length strings false)
  let output ← match result with | none => some [] | some value => words post buffers.length strings true value
  let argumentsCode := arguments.zipIdx |>.map fun (value, index) =>
    if aggregate value then s!"lea argument_{index}(%rip),%rax\n"
    else s!"movabs ${scalarBits value},%rax\n"
  let abi := (if hidden then ["lea result(%rip),%rax\n"] else []) ++ argumentsCode
  let extras := abi.drop 6
  let padding := extras.length % 2 * 8
  let saved := ["rbx", "rbp", "r12", "r13", "r14"]
  let initial := String.join (saved.map fun register => s!"movabs $1311768467750121217,%{register}\n")
  let pushes := String.join (extras.reverse.map (· ++ "push %rax\n"))
  let registers := String.join ((abi.zip ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]).map fun (code, register) =>
    code ++ s!"mov %rax,%{register}\n")
  let frame := "movabs $1311768467750121217,%r10\n" ++
    String.join (saved.map fun register => s!"cmp %r10,%{register}\njne bad\n")
  let mut checks := ""
  if hidden then
    checks := "lea result(%rip),%r11\ncmp %r11,%rax\njne bad\n" ++
      String.join (output.zipIdx |>.map fun ((width, value), index) =>
        if width == 32 then s!"mov {index * 8}(%rax),%r10d\nmov ${value},%r11d\ncmp %r11d,%r10d\njne bad\n"
        else if width == 64 then s!"mov {index * 8}(%rax),%r10\nmovabs ${value},%r11\ncmp %r11,%r10\njne bad\n"
        else if width == 8 then s!"mov {index * 8}(%rax),%r10\n" ++
          String.join (value.toUTF8.toList.zipIdx.map fun (byte, offset) =>
            s!"cmpb ${byte.toNat},{offset}(%r10)\njne bad\n")
        else "")
  else if let some (_, value) := output.head? then
    checks := s!"movabs ${value},%r10\ncmp %r10,%rax\njne bad\n"
  let mut data := s!".data\n.balign 16\n.quad 171\nresult:\n.zero {output.length * 8}\n.quad 205\n"
  for (text, index) in strings.zipIdx do
    data := data ++ s!".balign 4\n.byte 171,171,171,171\nstring_{index}:\n" ++
      String.join (text.toUTF8.toList.map fun byte => s!".byte {byte.toNat}\n") ++ ".byte 205\n"
    checks := checks ++ s!"cmpb $171,string_{index}-1(%rip)\njne bad\ncmpb $205,string_{index}+{text.utf8ByteSize}(%rip)\njne bad\n" ++
      String.join (text.toUTF8.toList.zipIdx.map fun (byte, offset) =>
        s!"cmpb ${byte.toNat},string_{index}+{offset}(%rip)\njne bad\n")
  for (input, index) in inputs.zipIdx do
    data := data ++ s!"argument_{index}:\n"
    for ((width, value), lane) in input.zipIdx do
      let bits := if width == 32 then value ++ "+1311768464867721216" else value
      data := data ++ s!".quad {bits}\n"
      checks := checks ++ s!"movabs ${bits},%r10\ncmp %r10,argument_{index}+{lane * 8}(%rip)\njne bad\n"
  for (buffer, cell) in buffers.zipIdx do
    let some (.array expected) := post.cell? cell | none
    if expected.length != buffer.length then none else do
      data := data ++ s!".balign 16\n.long 171\ndata_{cell}:\n" ++
        String.join (buffer.map fun value => s!".long {(BitVec.ofInt 32 value).toNat}\n") ++ ".long 205\n"
      checks := checks ++ s!"cmpl $171,data_{cell}-4(%rip)\njne bad\ncmpl $205,data_{cell}+{buffer.length * 4}(%rip)\njne bad\n"
      for (value, lane) in expected.zipIdx do
        let .signed .i32 number := value | none
        checks := checks ++ s!"cmpl ${(BitVec.ofInt 32 number).toNat},data_{cell}+{lane * 4}(%rip)\njne bad\n"
  pure (".text\n.global _start\n_start:\ncld\nmov %rsp,%r15\n" ++ initial ++
    s!"sub ${padding},%rsp\n" ++ pushes ++ registers ++
    s!"call compiled\nadd ${extras.length * 8 + padding},%rsp\ncmp %r15,%rsp\njne bad\n" ++
    frame ++ checks ++
    s!"cmpq $171,result-8(%rip)\njne bad\ncmpq $205,result+{output.length * 8}(%rip)\njne bad\n" ++
    "pushfq\npop %r10\ntest $1024,%r10\njnz bad\nmov $60,%eax\nxor %edi,%edi\nsyscall\n" ++
    "bad:\nmov $60,%eax\nmov $77,%edi\nsyscall\n" ++
    s!".balign 16\ncompiled:\n.incbin \"{binary}\"\n" ++ data ++ ".section .note.GNU-stack,\"\",@progbits\n")

/-- Returns true for an intentional bounds/uninitialized trap. A timeout, signal other
than UD2/SIGILL, or Core fuel exhaustion is never counted as agreement. -/
def check (program : Program) (function : FunctionId) (binary directory : System.FilePath)
    (arguments : List Value) (buffers : List (List Int)) (label : String) : IO Bool := do
  let initial := state buffers
  let outcome := evalExpr 20000 program initial (.call function (arguments.map Expr.value))
  let (result, post, trap) ← match outcome with
    | .done value after => pure (some value, after, false)
    | .trapped .arrayBounds after | .trapped .rawMemoryBounds after
    | .trapped .uninitializedLocal after => pure (none, after, true)
    | .trapped reason _ => throw (IO.userError s!"unexpected Core trap in {label}: {reprStr reason}")
    | .exited code _ => throw (IO.userError s!"unexpected Core exit in {label}: {code}")
    | .outOfFuel => throw (IO.userError s!"Core fuel exhausted in {label}")
  let some declaration := program.function? function
    | throw (IO.userError s!"missing Core declaration in {label}")
  -- A trapping aggregate function still receives its hidden result argument.
  let hidden := match declaration.returnType with | .slice _ | .structure _ | .scalar .string => true | _ => false
  let some source := assembly binary arguments buffers result post hidden
    | throw (IO.userError s!"unsupported native memory case {label}")
  let asm := directory / "run.s"
  let object := directory / "run.o"
  let executable := directory / "run"
  IO.FS.writeFile asm source
  run "as" #["--64", "-o", object.toString, asm.toString]
  run "ld" #["-m", "elf_x86_64", "-e", "_start", "-o", executable.toString, object.toString]
  let (returned, _) ← outputBytes "timeout" #["--kill-after=1s", "2s", executable.toString]
  let expected := if trap then 132 else 0
  unless returned == expected do
    throw (IO.userError s!"Core/native memory mismatch in {label}: native status {returned}, expected {expected}; Core result {reprStr result}")
  pure trap

end Lanius.X86.Tests.Memory
