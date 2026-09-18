import Lanius.X86.Lower.Slice.Raw

namespace Lanius.X86.Lower.Slice.Raw

open Lanius.Core Lanius.Semantics

/-- Initialize the two native descriptor words, then reject an invalid index
using the decoded bounds-check sequence. Core reaches arrayBounds and the
machine reaches UD2 without executing an element load; empty slices are
included. Register operands and the saved descriptor slot are explicitly
prepared inputs, not a claim about the actual Lanius raw-slice emitter. -/
theorem reject_initialized
    {native : Machine.State}
    (constructed : Storage.Slice.Raw.Constructed before coreAfter address count
      native.memory data locations values)
    (program : Program) (value : Index.Value)
    (rejected : ¬ ∃ index, integerIndex value.core = .ok index ∧ index < count)
    (argument : value.argument (native.registers 0))
    (layout : Frame.Layout) (slot : Fin layout.slots)
    (bounded : layout.slots ≤ 1048576)
    (frame : native.registers 5 = BitVec.ofNat 64 layout.base)
    (pointer length destination : Machine.Register)
    (pointerValue : native.registers pointer = data)
    (lengthValue : native.registers length = BitVec.ofNat 64 count)
    (destinationBound : (native.registers destination).toNat + 16 ≤ 2^64)
    (saved : Machine.read64 native.memory (layout.address slot) = native.registers destination)
    (savedSeparate : ∀ lane : Fin 8, Storage.Slice.Descriptor.Outside
      (native.registers destination) (layout.address slot + BitVec.ofNat 64 lane.val))
    (loaded : Machine.CodeAt native.memory native.rip
      (Storage.Slice.Descriptor.bytes pointer length destination ++ Machine.Index.bytes value.narrow slot.val))
    (codeSeparate : ∀ index, index < (Storage.Slice.Descriptor.bytes pointer length destination ++
        Machine.Index.bytes value.narrow slot.val).length →
      Storage.Slice.Descriptor.Outside (native.registers destination)
        (native.rip + BitVec.ofNat 64 index))
    (heapSeparate : ∀ block ∈ coreAfter.heap.blocks, ∀ base,
      locations.pointer block.base = some base → ∀ offset, offset < block.size →
      Storage.Slice.Descriptor.Outside (native.registers destination)
        (base + BitVec.ofNat 64 offset)) :
    (∃ fuel, evalExpr fuel program before (.index (expression address count) (.value value.core)) =
      .trapped .arrayBounds coreAfter) ∧
      ∃ after, Machine.Steps (2 + ((Machine.Index.prepare value.narrow slot.val).length + 1)) native after ∧
        Machine.Fault after ∧
        after.memory = Storage.Slice.Descriptor.written native.memory
          (native.registers destination) data count := by
  let middle := Storage.Slice.Descriptor.run native pointer length destination
  have initialized := Descriptor.initializes constructed pointer length destination
    (Machine.Index.bytes value.narrow slot.val)
    pointerValue lengthValue destinationBound loaded codeSeparate heapSeparate
  have fields := Storage.Slice.Descriptor.run_fields native pointer length destination count lengthValue
  have memory : middle.memory = Storage.Slice.Descriptor.written native.memory
      (native.registers destination) data count := by
    simpa only [pointerValue] using fields.1
  have words := Storage.Slice.Descriptor.written_words native.memory
    (native.registers destination) data count
  have savedAfter : Machine.read64 middle.memory (layout.address slot) = native.registers destination := by
    calc
      _ = Machine.read64 native.memory (layout.address slot) := by
        rw [memory]
        apply Machine.read64_congr
        intro lane
        exact Storage.Slice.Descriptor.written_frame _ _ _ _ _ (savedSeparate lane)
      _ = _ := saved
  obtain ⟨trapped, after, steps, fault, unchanged⟩ := reject_constructed (native := middle)
    initialized.2.1 program value rejected (by simpa only [middle, fields.2.1] using argument)
    layout slot bounded (by simpa only [middle, fields.2.1] using frame) (native.registers destination)
    savedAfter (by simpa only [memory] using words.1) (by simpa only [memory] using words.2)
    initialized.2.2.2
  exact ⟨trapped, after, initialized.1.trans steps, fault, unchanged.trans memory⟩

end Lanius.X86.Lower.Slice.Raw
