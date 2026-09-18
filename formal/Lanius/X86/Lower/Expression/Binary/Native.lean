import Lanius.X86.Machine.Block
import Lanius.X86.Encode.Arithmetic
import Lanius.X86.Encode.Direct
import Lanius.X86.Frame.Slot
import Lanius.X86.Frame.Function

namespace Lanius.X86.Lower.Expression.Binary

open Machine

/-- The actual eager-binary suffix first preserves the right result in ECX,
then reloads the left result from its frame slot. The encodings are the same
ones retained by the existing source-emitter contracts. -/
def prepare (slot : Nat) : List ReadOnly := [
  ⟨.move32 1 0, (Encode.Direct.config .move .w32 1 0).bytes.map UInt8.ofNat,
    by decide, fun _ => rfl, fun _ => rfl⟩,
  ⟨.load32 0 5 (BitVec.ofInt 32 (Frame.displacement slot)), Frame.Slot.bytes .load32 slot 0,
    by simpa only [Frame.Slot.bytes, Source.Slot.Kind.width, Source.Slot.Kind.load,
      memoryInstruction, ↓reduceIte, List.append_nil] using
      memory_decodes .w32 true 0 5 (Frame.displacement slot) [], fun _ => rfl, fun _ => rfl⟩]

def arithmeticBytes (operation : Alu) : List UInt8 :=
  (Encode.Arithmetic.config operation 0 1).bytes.map UInt8.ofNat

def finishBytes (operation : Alu) (slot : Nat) : List UInt8 :=
  ReadOnly.code (prepare slot) ++ arithmeticBytes operation

def leftWord (before : State) (slot : Nat) : BitVec 32 :=
  read32 before.memory (before.registers 5 + (BitVec.ofInt 32 (Frame.displacement slot)).signExtend 64)

theorem prepared (slot : Nat) (before : State) :
    let after := ReadOnly.run (prepare slot) before
    (after.registers 0).setWidth 32 = leftWord before slot ∧
    (after.registers 1).setWidth 32 = (before.registers 0).setWidth 32 ∧
    (∀ register, register ≠ 0 → register ≠ 1 → after.registers register = before.registers register) ∧
    after.flags = before.flags := by
  simp [prepare, ReadOnly.run, execute, State.move32, State.load32, State.immediate32, leftWord]
  intro register notRax notRcx
  simp [notRax, notRcx]

/-- Core arithmetic observed through the native signed-i32 result. -/
def CoreResult (target : Lanius.Core.Target) (operation : Alu) (left right : BitVec 32) (after : State) : Prop :=
  Lanius.Semantics.evalBinaryValue target (Encode.Arithmetic.coreOp operation)
    (.signed .i32 left.toInt) (.signed .i32 right.toInt) = .ok (.signed .i32 ((after.registers 0).setWidth 32).toInt)

/-- The suffix's complete architectural result. The saved left value comes
from memory, not from a premise that ECX or EAX already has both operands. -/
structure Finished (target : Lanius.Core.Target) (operation : Alu) (slot : Nat)
    (before after : State) (auxiliary : Bool) : Prop where
  result : CoreResult target operation (leftWord before slot) ((before.registers 0).setWidth 32) after
  narrow : after.registers 0 = ((after.registers 0).setWidth 32).setWidth 64
  registers : ∀ register, register ≠ 0 → register ≠ 1 → after.registers register = before.registers register
  flags : after.flags = operation.flags before.flags (leftWord before slot) ((before.registers 0).setWidth 32) auxiliary
  memory : after.memory = before.memory

theorem finishes (operation : Alu) (slot : Nat) (before : State) (auxiliary : Bool) :
    Block 3 (finishBytes operation slot) tail before (fun after => Finished target operation slot before after auxiliary) := by
  apply Block.append (m := 1) (ReadOnly.block (prepare slot) before)
  intro ready same
  subst ready
  intro loaded
  have fields := prepared slot before
  have preserved := ReadOnly.fields (prepare slot) before
  obtain ⟨after, step, result, narrow, registers, flags, memory, cursor⟩ :=
    Encode.Arithmetic.native (target := target) operation 0 1 (ReadOnly.run (prepare slot) before) auxiliary loaded.prefix
  refine ⟨after, .cons step (.refl _), ⟨?_, narrow, ?_, ?_, memory.trans preserved.1⟩, cursor, ?_⟩
  · simpa only [CoreResult, fields.1, fields.2.1] using result
  · intro register notRax notRcx
    exact (registers register notRax).trans (fields.2.2.1 register notRax notRcx)
  · simpa only [fields.1, fields.2.1, fields.2.2.2] using flags
  · rw [memory, cursor]
    exact loaded.suffix

theorem Finished.frame (done : Finished target operation slot before after auxiliary)
    (frame : Frame.BodyFrame entry started before) : Frame.BodyFrame entry started after := by
  refine ⟨(done.registers 5 (by decide) (by decide)).trans frame.framePointer, ?_, ?_, ?_, ?_⟩
  · rw [done.memory]; exact frame.savedPointer
  · rw [done.memory]; exact frame.returnAddress
  · intro register saved
    rw [done.registers register]
    · exact frame.registers register saved
    all_goals rcases saved with rfl | rfl | rfl | rfl | rfl <;> decide
  · rw [done.flags, Alu.flags_direction]
    exact frame.direction

def savedAddress (before : State) (slot : Nat) : Machine.Address :=
  before.registers 5 + (BitVec.ofInt 32 (Frame.displacement slot)).signExtend 64

def captured (before : State) (slot : Nat) : State :=
  before.store32 0 5 (BitVec.ofInt 32 (Frame.displacement slot)) (Frame.slotBytes false 0 slot).length

def Separated (before : State) (slot : Nat) (code : List UInt8) : Prop :=
  ∀ index, index < code.length → ∀ lane : Fin 4,
    before.rip + BitVec.ofNat 64 index ≠ savedAddress before slot + BitVec.ofNat 64 lane.val

/-- Explicit code/temporary separation; capture changes only the four saved
bytes. Subsequent operand code is allowed to change other memory. -/
theorem captures (before : State) (slot : Nat)
    (separate : Separated before slot (Frame.slotBytes false 0 slot ++ tail)) :
    Block 1 (Frame.slotBytes false 0 slot) tail before (· = captured before slot) := by
  intro loaded
  refine ⟨captured before slot,
    .cons (.decoded _ loaded.prefix _ _ (Frame.slot_decodes false 0 slot) rfl) (.refl _), rfl, rfl, ?_⟩
  exact (loaded.write32 ((before.registers 0).setWidth 32) separate).suffix

/-- Recursive-child obligation: return the right i32 and preserve the saved
left operand's address and four bytes. No whole-memory equality is required. -/
structure Operand (left : State) (slot : Nat) (value : BitVec 32) (after : State) : Prop where
  result : (after.registers 0).setWidth 32 = value
  base : after.registers 5 = left.registers 5
  saved : ∀ lane : Fin 4,
    after.memory (savedAddress left slot + BitVec.ofNat 64 lane.val) =
      (captured left slot).memory (savedAddress left slot + BitVec.ofNat 64 lane.val)

theorem Operand.left (operand : Operand before slot right evaluated) :
    leftWord evaluated slot = (before.registers 0).setWidth 32 := by
  unfold leftWord
  rw [operand.base]
  exact (read32_congr _ _ _ operand.saved).trans (read32_write32 _ _ _)

/-- Capture, an arbitrary proved right operand, and the restoring suffix.
The recursive premise is still an induction obligation, not a completed
compiler proof. The conclusion derives Core's result from both original values. -/
theorem continues (operation : Alu) (slot : Nat) (before : State) (auxiliary : Bool)
    (separate : Separated before slot (Frame.slotBytes false 0 slot ++ ((rightCode ++ finishBytes operation slot) ++ tail)))
    (right : Block count rightCode (finishBytes operation slot ++ tail) (captured before slot) (Operand before slot rightValue)) :
    Block (1 + (count + 3)) (Frame.slotBytes false 0 slot ++ (rightCode ++ finishBytes operation slot)) tail before
      (fun after => ∃ evaluated, Operand before slot rightValue evaluated ∧ Finished target operation slot evaluated after auxiliary ∧
        CoreResult target operation ((before.registers 0).setWidth 32) rightValue after) := by
  apply (captures before slot separate).append
  intro saved same
  subst saved
  apply right.append
  intro evaluated operand
  apply (finishes operation slot evaluated auxiliary).mono
  intro after result
  exact ⟨evaluated, operand, result, by simpa only [operand.left, operand.result] using result.result⟩

end Lanius.X86.Lower.Expression.Binary
