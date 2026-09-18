import Lanius.X86.Encode.Immediate.Wide
import Lanius.X86.Buffer.Emission
import Lanius.X86.Transport.Unsigned

namespace Lanius.X86.Encode.Immediate.Wide

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- The complete emitted instruction writes exactly this 64-bit RAX value.
The contract is about bits; arbitrary low/high Int inputs are not assumed to
be canonical signed integers or an existing Core usize literal. -/
def NativeWrites (value : BitVec 64) (code : List UInt8) : Prop :=
  ∀ (before : Machine.State) (tail : List UInt8),
    Machine.CodeAt before.memory before.rip (code ++ tail) →
    ∃ after, Machine.Steps 1 before after ∧ after.registers 0 = value ∧
      (∀ register, register ≠ 0 → after.registers register = before.registers register) ∧
      after.memory = before.memory ∧ after.flags = before.flags ∧
      after.rip = before.rip + BitVec.ofNat 64 code.length ∧
      Machine.CodeAt after.memory after.rip tail

theorem window_writes (window : Emission original start (bytes low high) emitted) :
    NativeWrites (Machine.Immediate.word low high) (byteSlice emitted start 10) := by
  have exactBytes : byteSlice emitted start 10 = bytes low high := by
    simpa only [bytes_length] using window.bytes
  rw [exactBytes]
  intro before tail loaded
  obtain ⟨after, steps, result, registers, memory, flags, position, continuation⟩ :=
    Machine.Immediate.preserves before loaded
  exact ⟨after, steps, result, registers, memory, flags,
    by simpa [bytes_length] using position, continuation⟩

namespace Preservation

/-- Actual source execution produces the exact ten-byte instruction, whose
native execution writes both immediate words. Helper execution, emission,
and native execution are proved, not supplied as induction hypotheses. -/
theorem emits (checked : Source.Immediate.Checked program valid width rex fits word)
    (capacity start : Nat) (low high : Int) (wellFormed : StateWellFormed before)
    (room : start + 10 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (inputs (.slice i32 cell [] 0 values.length) capacity start low high) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (start + 10 : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written values start low high))) } ∧
      Emission values start (bytes low high) (written values start low high) ∧
      NativeWrites (Machine.Immediate.word low high) (byteSlice (written values start low high) start 10) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  obtain ⟨after, run, contents, effect, heap⟩ :=
    succeeds64 checked capacity start low high wellFormed room storage bounded backing argumentsResult
  have window : Emission values start (bytes low high) (written values start low high) :=
    ⟨written_length, by simpa only [bytes_length] using emission (by omega : start + 10 ≤ values.length),
      fun _ outside => frame (by simpa only [bytes_length] using outside)⟩
  exact ⟨after, run, contents, window, window_writes window, effect, heap⟩

/-- If the words come from the actual usize serializer, the generated MOV
writes that precise Core value. This does not assert execution of an
expression wrapper: the source call here remains the immediate emitter. -/
theorem from_transport (checked : Source.Immediate.Checked program valid width rex fits word)
    (capacity start : Nat) (low high : Int)
    (serialized : Transport.literal? (.unsigned .usize value) = some [3, low, high])
    (wellFormed : StateWellFormed before)
    (room : start + 10 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (inputs (.slice i32 cell [] 0 values.length) capacity start low high) before) :
    value < 2 ^ 64 ∧
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (start + 10 : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written values start low high))) } ∧
      Emission values start (bytes low high) (written values start low high) ∧
      NativeWrites (BitVec.ofNat 64 value) (byteSlice (written values start low high) start 10) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  obtain ⟨range, exactWord⟩ := Transport.usize_serialized serialized
  obtain ⟨after, run, contents, window, native, effect, heap⟩ :=
    emits checked capacity start low high wellFormed room storage bounded backing argumentsResult
  rw [exactWord] at native
  exact ⟨range, after, run, contents, window, native, effect, heap⟩

end Preservation
end Lanius.X86.Encode.Immediate.Wide
