import Lanius.X86.Lower.Expression.Binary.Native
import Lanius.X86.Encode.Immediate
import Lean

namespace Lanius.X86.Tests.Binary

open Machine Lower.Expression.Binary

private def literal (value : BitVec 32) : ReadOnly :=
  ⟨.immediate32 0 value, Encode.Immediate.bytes value.toInt,
    by simpa only [Encode.Immediate.bytes_length, BitVec.ofInt_toInt] using Encode.Immediate.decodes value.toInt,
    fun _ => rfl, fun _ => rfl⟩

/-- Discharge the recursive premise with an actual proved child, for every
operand bit pattern and either permitted auxiliary-flag value. -/
theorem literal_right (operation : Alu) (slot : Nat) (before : State) (right : BitVec 32) (auxiliary : Bool)
    (separate : Separated before slot (Frame.slotBytes false 0 slot ++
      ((ReadOnly.code [literal right] ++ finishBytes operation slot) ++ tail))) :
    Block 5 (Frame.slotBytes false 0 slot ++ (ReadOnly.code [literal right] ++ finishBytes operation slot)) tail before
      (CoreResult target operation ((before.registers 0).setWidth 32) right) := by
  have child : Block 1 (ReadOnly.code [literal right]) (finishBytes operation slot ++ tail)
      (captured before slot) (Operand before slot right) := by
    apply (ReadOnly.block [literal right] (captured before slot)).mono
    intro after same
    subst after
    exact ⟨by simp [literal, ReadOnly.run, execute, State.immediate32], rfl, fun _ => rfl⟩
  exact (continues operation slot before auxiliary separate child).mono (fun _ result => result.choose_spec.2.2)

private def executeWindow : Nat → State → Option State
  | 0, state => some state
  | count + 1, state => do
      let bytes := (List.range 15).map fun index => state.memory (state.rip + BitVec.ofNat 64 index)
      let (instruction, size) ← decode bytes
      executeWindow count (execute instruction size state)

private def initial (left : Nat) (code : List UInt8) : State := {
  registers := fun register => if register = 0 then BitVec.ofNat 64 left else if register = 5 then 4096 else 1234
  rip := 8192, flags := 1024
  memory := fun address => if 8192 ≤ address.toNat then (code[address.toNat - 8192]?).getD 0 else 0xa5 }

def check : IO Unit := do
  let mut count := 0
  for operation in ([.add, .subtract, .and, .or, .xor] : List Alu) do
    for slot in [0, 1, 7] do
      for left in [0, 1, 0x7fffffff, 0x80000000, 0xffffffff] do
        for right in [0, 3, 0x7fffffff, 0x80000000, 0xffffffff] do
          let code := Frame.slotBytes false 0 slot ++ Encode.Immediate.bytes (BitVec.ofNat 32 right).toInt ++ finishBytes operation slot
          let before := initial (0xabcdef0100000000 + left) code
          let some after := executeWindow 5 before | throw (IO.userError "binary machine sequence did not decode")
          let expected := (operation.result (BitVec.ofNat 32 left) (BitVec.ofNat 32 right)).setWidth 64
          unless after.registers 0 == expected && after.rip == before.rip + BitVec.ofNat 64 code.length &&
              leftWord after slot == BitVec.ofNat 32 left && after.flags.getLsbD 10 do
            throw (IO.userError s!"binary machine result, saved operand, cursor, or direction flag differs: {repr operation}, {slot}, {left}, {right}")
          for register in List.finRange 16 do
            unless register = 0 || register = 1 || after.registers register == before.registers register do
              throw (IO.userError "binary machine sequence changed another register")
          let effectful := Frame.slotBytes false 0 slot ++ Frame.slotBytes false 0 (slot + 1) ++
            Encode.Immediate.bytes (BitVec.ofNat 32 right).toInt ++ finishBytes operation slot
          let some changed := executeWindow 6 (initial (0xabcdef0100000000 + left) effectful)
            | throw (IO.userError "effectful right operand did not decode")
          unless changed.registers 0 == expected && leftWord changed slot == BitVec.ofNat 32 left &&
              leftWord changed (slot + 1) == BitVec.ofNat 32 left do
            throw (IO.userError "right-operand memory effect lost the captured left operand")
          count := count + 1
  -- A lost capture and reversing the two preparation instructions must be observable.
  let good := Frame.slotBytes false 0 0 ++ Encode.Immediate.bytes 3 ++ finishBytes .subtract 0
  let reversed := Frame.slotBytes false 0 0 ++ Encode.Immediate.bytes 3 ++
    Frame.Slot.bytes .load32 0 0 ++ [137, 193] ++ arithmeticBytes .subtract
  let lost := Frame.slotBytes false 0 0 ++ Encode.Immediate.bytes 3 ++
    [137, 193, 137, 192] ++ arithmeticBytes .subtract
  for bad in [reversed, lost] do
    let some after := executeWindow 5 (initial 10 bad) | throw (IO.userError "mutation did not execute")
    unless after.registers 0 != 7 do throw (IO.userError "operand-order/capture mutation escaped detection")
  let some correct := executeWindow 5 (initial 10 good) | throw (IO.userError "subtraction did not execute")
  unless correct.registers 0 == 7 do throw (IO.userError "subtraction reversed its operands")
  IO.println s!"{count} pure and {count} memory-writing binary machine sequences; two rejected operand-preparation mutations"

/-- Keep the proved suffix connected to actual compiler output. These samples
contain each operation with variable operands, including compound assignment. -/
def checkEmitted (name : String) (code : List UInt8) : IO Unit := do
  let operations : List Alu := if name == "nested" then [.add, .subtract]
    else if name == "bits" then [.and, .or, .xor] else []
  for operation in operations do
    let found := (List.range 64).any fun slot => (List.range code.length).any fun position =>
      (finishBytes operation slot).isPrefixOf (code.drop position)
    unless found do throw (IO.userError s!"{name}: actual compiler output lacks the proved {repr operation} operand-restoration suffix")

run_elab do
  for name in [``Machine.Block.append, ``Machine.Block.mono, ``Machine.ReadOnly.block,
      ``prepared, ``finishes, ``Finished.frame, ``captures, ``Operand.left, ``continues, ``literal_right] do
    for assumption in ← Lean.collectAxioms name do
      unless [``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "{name} depends on unexpected assumption {assumption}"

end Lanius.X86.Tests.Binary
