import Lanius.X86.Machine.Slice.Raw
import Lanius.X86.Storage.Slice.Raw
import Lanius.ExecutionRules

namespace Lanius.X86.Lower.Expression.Raw.Native

open Lanius.Core Lanius.Semantics Lanius.Properties

variable {before : State} {native entry started : Machine.State}
  {address : Nat} {length : Int} {data : Machine.Address}
  {locations : Storage.Locations} {block : Lanius.Memory.Block}

/-- The value-operand Core expression at the raw-constructor boundary. The
recursive operand evaluations and compiler emission remain separate obligations. -/
def expression (address : Nat) (length : Int) : Expr :=
  .i32SliceFromRawParts (.value (.pointer address)) (.value (.signed .i32 length))

/-- Connect the real native sign guard and descriptor continuation to Core's
actual protected raw-slice construction. Pointer storage was prepared before
this suffix; the length is the canonical low i32 value in RAX. Exact live-block
metadata, not an assumed successful constructor, determines the valid domain.
Zero length is included and grants no element access. -/
theorem constructs (program : Program) (auxiliary : Bool)
    (wellFormed : StateWellFormed before)
    (related : Storage.Heap.Correspondence before.heap native.memory locations)
    (found : before.heap.block? address = some block)
    (mapped : locations.pointer address = some data)
    (size : block.size = length.toNat * 4) (alignment : block.alignment = 4)
    (canonical : -2147483648 ≤ length ∧ length ≤ 2147483647)
    (nonnegative : 0 ≤ length)
    (value : (native.registers 0).setWidth 32 = BitVec.ofInt 32 length)
    (layout : Frame.Layout) (slot : Fin layout.slots) (oldTop : Nat)
    (allocated : slot.val = oldTop + 1) (bounded : layout.slots ≤ 1048576)
    (base : native.registers 5 = BitVec.ofNat 64 layout.base)
    (saved : Machine.read64 native.memory (layout.address slot) = data)
    (caller : Frame.BodyFrame entry started native)
    (headerBound : layout.base + 16 ≤ 2^64) (tail : List UInt8)
    (loaded : Machine.CodeAt native.memory native.rip (Machine.Slice.Raw.bytes slot.val ++ tail))
    (codeSeparate : ∀ index, index < (Machine.Slice.Raw.bytes slot.val ++ tail).length → ∀ lane : Fin 8,
      native.rip + BitVec.ofNat 64 index ≠ layout.address slot + 8 + BitVec.ofNat 64 lane.val)
    (heapSeparate : ∀ candidate ∈ before.heap.blocks, ∀ pointer,
      locations.pointer candidate.base = some pointer → ∀ offset, offset < candidate.size → ∀ lane : Fin 8,
      pointer + BitVec.ofNat 64 offset ≠ layout.address slot + 8 + BitVec.ofNat 64 lane.val) :
    let after := Machine.Slice.Raw.continuation (Machine.Slice.Raw.guarded native auxiliary) slot.val
    let installed := Storage.Slice.Descriptor.install locations before.nextCell [] 0 data
    ∃ coreAfter values,
      Evaluates program before (expression address length)
        (.slice (.scalar (.signed .i32)) before.nextCell [] 0 length.toNat) coreAfter ∧
      Storage.Slice.Raw.Constructed before coreAfter address length.toNat
        after.memory data installed values ∧
      Machine.Steps 5 native after ∧
      Storage.Represents installed after.memory (layout.address slot)
        (.slice (.scalar (.signed .i32)) before.nextCell [] 0 length.toNat) ∧
      after.registers 0 = layout.address slot ∧
      Storage.Heap.Correspondence before.heap after.memory locations ∧
      Frame.BodyFrame entry started after ∧
      (∀ live : Fin layout.slots, live.val < oldTop → ∀ lane : Fin 8,
        after.memory (layout.address live + BitVec.ofNat 64 lane.val) =
          native.memory (layout.address live + BitVec.ofNat 64 lane.val)) ∧
      after.memory = Machine.write64 native.memory (layout.address slot + 8) (BitVec.ofNat 64 length.toNat) ∧
      (∀ register, register ≠ 0 → after.registers register = native.registers register) ∧
      after.flags.getLsbD 10 = native.flags.getLsbD 10 ∧
      after.rip = native.rip + BitVec.ofNat 64 (Machine.Slice.Raw.bytes slot.val).length ∧
      Machine.CodeAt after.memory after.rip tail := by
  have positive : 0 < slot.val := by omega
  have scalar := Machine.Slice.Raw.canonical_i32 length canonical value
  have machine := Machine.Slice.Raw.correct locations native auxiliary layout slot positive bounded base
    scalar nonnegative saved before.nextCell [] 0 tail loaded codeSeparate
  have framed := Machine.Slice.Raw.preserves_heap native auxiliary layout slot positive bounded base related heapSeparate
  obtain ⟨coreAfter, values, run, constructed⟩ := Storage.Slice.Raw.map_signed length nonnegative
    wellFormed framed found mapped size alignment
  have core : Evaluates program before (expression address length)
      (.slice (.scalar (.signed .i32)) before.nextCell [] 0 length.toNat) coreAfter :=
    evaluatesI32SliceFromRawParts ⟨1, rfl⟩ ⟨1, rfl⟩ run
  have installed : Storage.Slice.Raw.Constructed before coreAfter address length.toNat
      (Machine.Slice.Raw.continuation (Machine.Slice.Raw.guarded native auxiliary) slot.val).memory
      data (Storage.Slice.Descriptor.install locations before.nextCell [] 0 data) values :=
    { constructed with correspondence :=
      ⟨constructed.correspondence.wellFormed, constructed.correspondence.mappedBlock,
        constructed.correspondence.offsets, constructed.correspondence.covered,
        constructed.correspondence.disjoint⟩ }
  have header : started.registers 5 = BitVec.ofNat 64 layout.base := caller.framePointer.symm.trans base
  have callerAfter := Machine.Slice.Raw.preserves_caller native auxiliary layout slot positive bounded base caller (by
    intro word lane
    rw [header, ← Machine.Slice.Raw.previous_address layout slot positive]
    exact layout.saved_word_disjoint (Machine.Slice.Raw.lengthSlot slot) headerBound word lane)
  have liveSlots : ∀ live : Fin layout.slots, live.val < oldTop → ∀ lane : Fin 8,
      (Machine.Slice.Raw.continuation (Machine.Slice.Raw.guarded native auxiliary) slot.val).memory
        (layout.address live + BitVec.ofNat 64 lane.val) =
      native.memory (layout.address live + BitVec.ofNat 64 lane.val) := by
    intro live within lane
    apply Machine.Slice.Raw.preserves_slot native auxiliary layout slot live positive bounded base
      (lane := lane)
    intro same
    have equal := congrArg Fin.val same
    simp only [Machine.Slice.Raw.lengthSlot] at equal
    omega
  exact ⟨coreAfter, values, core, installed, machine.1, machine.2.2.1, machine.2.1,
    framed, callerAfter, liveSlots, machine.2.2.2⟩

/-- A negative canonical i32 length traps in the actual Core constructor and
reaches native UD2 before any descriptor write. No mapped-pointer, allocation,
heap-safety or saved-pointer premise is needed for this rejection path. -/
theorem rejects_negative (program : Program) (auxiliary : Bool) (slot : Nat) (tail : List UInt8)
    (canonical : -2147483648 ≤ length ∧ length ≤ 2147483647)
    (negative : length < 0)
    (value : (native.registers 0).setWidth 32 = BitVec.ofInt 32 length)
    (loaded : Machine.CodeAt native.memory native.rip (Machine.Slice.Raw.bytes slot ++ tail)) :
    evalExpr 2 program before (expression address length) = .trapped .rawMemoryBounds before ∧
    Machine.Steps 2 native (Machine.Slice.Raw.guarded native auxiliary) ∧
    Machine.Fault (Machine.Slice.Raw.guarded native auxiliary) ∧
    (Machine.Slice.Raw.guarded native auxiliary).memory = native.memory ∧
    (Machine.Slice.Raw.guarded native auxiliary).registers = native.registers ∧
    (Machine.Slice.Raw.guarded native auxiliary).flags.getLsbD 10 = native.flags.getLsbD 10 ∧
    (Machine.Slice.Raw.guarded native auxiliary).rip = native.rip + 8 := by
  have rejected := Machine.Slice.Raw.rejects_negative native auxiliary slot tail
    (Machine.Slice.Raw.canonical_i32 length canonical value) negative loaded
  refine ⟨?_, rejected.1, rejected.2.1, rejected.2.2.1, rejected.2.2.2.1, ?_, rejected.2.2.2.2⟩
  · simpa only [expression, evalExpr] using
      (Storage.Slice.Raw.rejects_negative (before := before) (address := address) negative)
  · exact Machine.logical32Flags_direction _ _ auxiliary

end Lanius.X86.Lower.Expression.Raw.Native
