import Lanius.X86.Lower.Index
import Lanius.X86.Storage.Slice.Raw
import Lanius.X86.Storage.Slice.Descriptor

namespace Lanius.X86.Lower.Slice.Raw

open Lanius.Core Lanius.Semantics

namespace Descriptor

open Storage.Slice.Descriptor

/-- Construct the native descriptor while retaining the protected Core view
and the entire raw-heap correspondence. Descriptor bytes must be private
storage: overwriting the backing array is not a valid initialization. -/
theorem describe
    (constructed : Storage.Slice.Raw.Constructed before after address count
      memory data locations values)
    (destination : Machine.Address)
    (separate : ∀ block ∈ after.heap.blocks, ∀ base,
      locations.pointer block.base = some base → ∀ offset, offset < block.size →
      Outside destination (base + BitVec.ofNat 64 offset)) :
    Storage.Slice.Raw.Constructed before after address count
      (written memory destination data count) data
      (install locations before.nextCell [] 0 data) values ∧
    Storage.Represents (install locations before.nextCell [] 0 data)
      (written memory destination data count) destination
      (.slice (.scalar (.signed .i32)) before.nextCell [] 0 count) := by
  have framed := constructed.frameMemory (nextMemory := written memory destination data count)
    (fun block member base mapped offset inside =>
      written_frame _ _ _ _ _ (separate block member base mapped offset inside))
  refine ⟨{ framed with correspondence := ?_ }, ?_⟩
  · exact written_heap constructed.correspondence destination data before.nextCell [] 0 count separate
  · exact written_represents locations memory destination data before.nextCell [] 0 count
      constructed.length64

/-- The generic two-store initializer executes and establishes the descriptor
and backing facts needed by a continuation. This is not yet a theorem about
the Lanius raw-slice emitter, whose sign check separates its two stores. -/
theorem initializes
    {native : Machine.State}
    (constructed : Storage.Slice.Raw.Constructed before after address count
      native.memory data locations values)
    (pointer length destination : Machine.Register) (tail : List UInt8)
    (pointerValue : native.registers pointer = data)
    (lengthValue : native.registers length = BitVec.ofNat 64 count)
    (destinationBound : (native.registers destination).toNat + 16 ≤ 2^64)
    (loaded : Machine.CodeAt native.memory native.rip (bytes pointer length destination ++ tail))
    (codeSeparate : ∀ index, index < (bytes pointer length destination ++ tail).length →
      Outside (native.registers destination) (native.rip + BitVec.ofNat 64 index))
    (heapSeparate : ∀ block ∈ after.heap.blocks, ∀ base,
      locations.pointer block.base = some base → ∀ offset, offset < block.size →
      Outside (native.registers destination) (base + BitVec.ofNat 64 offset)) :
    Machine.Steps 2 native (run native pointer length destination) ∧
    Storage.Slice.Raw.Constructed before after address count
      (run native pointer length destination).memory data
      (install locations before.nextCell [] 0 data) values ∧
    Storage.Represents (install locations before.nextCell [] 0 data)
      (run native pointer length destination).memory (native.registers destination)
      (.slice (.scalar (.signed .i32)) before.nextCell [] 0 count) ∧
    Machine.CodeAt (run native pointer length destination).memory
      (run native pointer length destination).rip tail := by
  have initialized := constructs locations native pointer length destination before.nextCell [] 0 count
    tail constructed.length64 destinationBound lengthValue loaded codeSeparate
  have described := describe constructed (native.registers destination) heapSeparate
  have fields := run_fields native pointer length destination count lengthValue
  refine ⟨initialized.1, ?_, ?_, initialized.2.2.2⟩
  · simpa only [fields.1, pointerValue] using described.1
  · simpa only [fields.1, pointerValue] using described.2

end Descriptor

/-- A Core helper expression, not a source-literal transport claim. Core
values permit noncanonical `.signed .i32` integers; a compiler-facing caller
must additionally establish `count ≤ 2147483647`. -/
def expression (address count : Nat) : Expr :=
  .i32SliceFromRawParts (.value (.pointer address)) (.value (.signed .i32 count))

/-- The raw-slice expression really executes its pointer/length operands and
the protected constructor. There is no assumed constructor execution. -/
theorem expression_evaluates
    (constructed : Storage.Slice.Raw.Constructed before after address count
      memory data locations values) :
    Evaluates program before (expression address count)
      (.slice (.scalar (.signed .i32)) before.nextCell [] 0 count) after :=
  evaluatesI32SliceFromRawParts (pointer := .value (.pointer address))
    (length := .value (.signed .i32 count)) ⟨1, rfl⟩ ⟨1, rfl⟩ constructed.run

/-- The actual raw constructor supplies both the Core backing array and its
native packed representation. The existing decoded bounds/address/load
sequence therefore needs neither fact as an independent caller premise.
The index operand here is a value, so no mutation is hidden between mapping
the array and reading it. Descriptor construction and index-register setup
are separate machine continuations. -/
theorem read_constructed
    {native : Machine.State}
    (constructed : Storage.Slice.Raw.Constructed before coreAfter address count
      native.memory data locations values)
    (program : Program) (value : Index.Value) (index : Nat)
    (inside : index < count) (integer : integerIndex value.core = .ok index)
    (argument : value.argument (native.registers 0))
    (layout : Frame.Layout) (slot : Fin layout.slots)
    (bounded : layout.slots ≤ 1048576)
    (frame : native.registers 5 = BitVec.ofNat 64 layout.base)
    (descriptor : Machine.Address)
    (saved : Machine.read64 native.memory (layout.address slot) = descriptor)
    (pointer : Machine.read64 native.memory descriptor = data)
    (extent : Machine.read64 native.memory (descriptor + 8) = BitVec.ofNat 64 count)
    (loaded : Machine.CodeAt native.memory native.rip
      (Machine.Index.bytes value.narrow slot.val ++ Slice.loadBytes)) :
    ∃ after, Machine.Steps ((Machine.Index.prepare value.narrow slot.val).length + 3) native after ∧
      Evaluates program before (.index (expression address count) (.value value.core))
        (.signed .i32 ((after.registers 0).setWidth 32).toInt) coreAfter ∧
      after.memory = native.memory := by
  apply Index.read_refines program before coreAfter coreAfter
    (expression address count) (.value value.core) before.nextCell [] values 0 count index value
    (by simp [constructed.length]) inside (expression_evaluates constructed) ⟨1, rfl⟩
    integer constructed.read native argument layout slot bounded frame descriptor data
    constructed.packed saved _ extent loaded
  simpa [Storage.Slice.address] using pointer

/-- Invalid indices after an actual raw-slice construction reach Core's
bounds trap and native UD2 without loading an element. The zero-length
allocation case is included; constructing it grants no element access. -/
theorem reject_constructed
    {native : Machine.State}
    (constructed : Storage.Slice.Raw.Constructed before coreAfter address count
      native.memory data locations values)
    (program : Program) (value : Index.Value)
    (rejected : ¬ ∃ index, integerIndex value.core = .ok index ∧ index < count)
    (argument : value.argument (native.registers 0))
    (layout : Frame.Layout) (slot : Fin layout.slots)
    (bounded : layout.slots ≤ 1048576)
    (frame : native.registers 5 = BitVec.ofNat 64 layout.base)
    (descriptor : Machine.Address)
    (saved : Machine.read64 native.memory (layout.address slot) = descriptor)
    (pointer : Machine.read64 native.memory descriptor = data)
    (extent : Machine.read64 native.memory (descriptor + 8) = BitVec.ofNat 64 count)
    (loaded : Machine.CodeAt native.memory native.rip (Machine.Index.bytes value.narrow slot.val)) :
    (∃ fuel, evalExpr fuel program before (.index (expression address count) (.value value.core)) =
      .trapped .arrayBounds coreAfter) ∧
      ∃ after, Machine.Steps ((Machine.Index.prepare value.narrow slot.val).length + 1) native after ∧
        Machine.Fault after ∧ after.memory = native.memory := by
  apply Index.reject_refines program before coreAfter coreAfter
    (expression address count) (.value value.core) before.nextCell [] values 0 count value
    (by simp [constructed.length]) (expression_evaluates constructed) ⟨1, rfl⟩ rejected
    native argument layout slot bounded frame descriptor data constructed.packed saved _ extent loaded
  simpa [Storage.Slice.address] using pointer

/-- A connected decoded instruction window: initialize both descriptor words,
then bounds-check and read the actual raw array. The descriptor, backing
elements, and Core constructor execution are conclusions of the component
proofs, not independently assumed results. Pointer/length operands and the
saved descriptor slot are already prepared; binding their preparation to the
Lanius emitter is a separate obligation. -/
theorem read_initialized
    {native : Machine.State}
    (constructed : Storage.Slice.Raw.Constructed before coreAfter address count
      native.memory data locations values)
    (program : Program) (value : Index.Value) (index : Nat)
    (inside : index < count) (integer : integerIndex value.core = .ok index)
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
      (Storage.Slice.Descriptor.bytes pointer length destination ++
        (Machine.Index.bytes value.narrow slot.val ++ Slice.loadBytes)))
    (codeSeparate : ∀ index, index < (Storage.Slice.Descriptor.bytes pointer length destination ++
        (Machine.Index.bytes value.narrow slot.val ++ Slice.loadBytes)).length →
      Storage.Slice.Descriptor.Outside (native.registers destination)
        (native.rip + BitVec.ofNat 64 index))
    (heapSeparate : ∀ block ∈ coreAfter.heap.blocks, ∀ base,
      locations.pointer block.base = some base → ∀ offset, offset < block.size →
      Storage.Slice.Descriptor.Outside (native.registers destination)
        (base + BitVec.ofNat 64 offset)) :
    ∃ after, Machine.Steps (2 + ((Machine.Index.prepare value.narrow slot.val).length + 3)) native after ∧
      Evaluates program before (.index (expression address count) (.value value.core))
        (.signed .i32 ((after.registers 0).setWidth 32).toInt) coreAfter ∧
      after.memory = Storage.Slice.Descriptor.written native.memory
        (native.registers destination) data count := by
  let middle := Storage.Slice.Descriptor.run native pointer length destination
  have initialized := Descriptor.initializes constructed pointer length destination
    (Machine.Index.bytes value.narrow slot.val ++ Slice.loadBytes)
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
  obtain ⟨after, steps, evaluated, unchanged⟩ := read_constructed (native := middle)
    initialized.2.1 program value index inside integer (by simpa only [middle, fields.2.1] using argument)
    layout slot bounded (by simpa only [middle, fields.2.1] using frame) (native.registers destination)
    savedAfter (by simpa only [memory] using words.1) (by simpa only [memory] using words.2)
    initialized.2.2.2
  exact ⟨after, initialized.1.trans steps, evaluated, unchanged.trans memory⟩

end Lanius.X86.Lower.Slice.Raw
