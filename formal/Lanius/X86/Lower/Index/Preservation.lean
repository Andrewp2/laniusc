import Lanius.X86.Lower.Index.Emission
import Lanius.X86.Lower.Index

namespace Lanius.X86.Lower.Index.Emission

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- The emitted bytes implement Core's checked address calculation on the
represented packed-slice domain. This includes arbitrary offsets, signed
negative indices, and full-width usize failures. The surrounding expression
compiler must establish the captured descriptor/index and frame relation. -/
def Refines (signed : Bool) (slot : Nat) (code : List UInt8) : Prop :=
  ∀ (native : Machine.State) (value : Index.Value), value.argument (native.registers 0) → value.narrow = signed →
    ∀ (layout : Frame.Layout) (savedSlot : Fin layout.slots), savedSlot.val = slot → layout.slots ≤ 1048576 →
    native.registers 5 = BitVec.ofNat 64 layout.base →
    ∀ (descriptor data : Machine.Address) (values : List Int) (origin length : Nat),
    origin + length ≤ values.length → Storage.Slice.Represents native.memory data values →
    Machine.read64 native.memory (layout.address savedSlot) = descriptor →
    Machine.read64 native.memory descriptor = Storage.Slice.address data origin →
    Machine.read64 native.memory (descriptor + 8) = BitVec.ofNat 64 length →
    Machine.CodeAt native.memory native.rip code →
    if value.word.toNat < length then
      ∃ after, Machine.Steps ((Machine.Index.prepare signed slot).length + 2) native after ∧
        integerIndex value.core = .ok value.word.toNat ∧
        after.registers 0 = Storage.Slice.address (Storage.Slice.address data origin) value.word.toNat ∧
        after.memory = native.memory ∧ after.rip = native.rip + BitVec.ofNat 64 code.length ∧
        (∀ register, register ≠ 0 → register ≠ 10 → register ≠ 11 → after.registers register = native.registers register) ∧
        after.flags.getLsbD 10 = native.flags.getLsbD 10
    else
      (¬ ∃ index, integerIndex value.core = .ok index ∧ index < length) ∧
      ∃ after, Machine.Steps ((Machine.Index.prepare signed slot).length + 1) native after ∧
        Machine.Fault after ∧ after.memory = native.memory

theorem window_refines (window : Buffer.Emission original start (Machine.Index.bytes signed slot) emitted) :
    Refines signed slot (byteSlice emitted start (Machine.Index.bytes signed slot).length) := by
  intro native value argument representation layout savedSlot position bounded frame descriptor data values origin length view stored saved pointer extent loaded
  rw [window.bytes] at loaded
  have code : Machine.CodeAt native.memory native.rip (Machine.Index.bytes value.narrow savedSlot.val) := by
    rw [representation, position]
    exact loaded
  have lengthBound := Index.length_bound stored view
  by_cases inside : value.word.toNat < length
  · simp only [if_pos inside]
    have integer := Index.accepted_index value length lengthBound inside
    obtain ⟨after, steps, address, memory, rip, registers, flags⟩ := Index.address_success native value argument layout savedSlot
      bounded frame descriptor data values origin length value.word.toNat view inside stored integer saved pointer extent code
    rw [representation, position] at steps rip
    refine ⟨after, steps, integer, address, memory, ?_, registers, flags⟩
    rw [window.bytes]
    exact rip
  · simp only [if_neg inside]
    have rejected : ¬ ∃ index, integerIndex value.core = .ok index ∧ index < length :=
      fun accepted => inside ((Index.bounds value length lengthBound).mpr accepted)
    obtain ⟨after, steps, fault, memory⟩ := Index.address_rejects native value argument layout savedSlot bounded frame
      descriptor data values origin length view stored rejected saved pointer extent code
    rw [representation, position] at steps
    exact ⟨rejected, after, steps, fault, memory⟩

/-- Actual Lanius execution produces the complete byte window and its Core
address/bounds preservation contract. No assumed helper execution, intended
effective address, or post-hoc output validation is used. -/
theorem compiles (checked : Source.Index.Checked emitters) (signed : Bool) (capacity slot start : Nat)
    (wellFormed : StateWellFormed before) (distinct : output ≠ work)
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[1]? = some (start : Int)) (slotBound : slot ≤ 1048576)
    (room : start + (Machine.Index.bytes signed slot).length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (inputValues output work values.length workspace.length capacity slot (kindValue signed)) before) :
    ∃ after emitted, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (start + (Machine.Index.bytes signed slot).length : Nat)) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values
        (workspace.set 1 (start + (Machine.Index.bytes signed slot).length : Nat)))) } ∧
      Buffer.Emission values start (Machine.Index.bytes signed slot) emitted ∧
      Refines signed slot (byteSlice emitted start (Machine.Index.bytes signed slot).length) ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton work)) before after ∧ HeapFrame before after := by
  obtain ⟨after, emitted, run, outputContents, workContents, window, effect, heap⟩ :=
    emits checked signed capacity slot start wellFormed distinct outputBacking workBacking current slotBound room storage bounded argumentsResult
  exact ⟨after, emitted, run, outputContents, workContents, window, window_refines window, effect, heap⟩

end Lanius.X86.Lower.Index.Emission
