import Lanius.X86.Storage.Heap.Borrow
import Lanius.X86.Storage.Heap.Array
import Lanius.Semantics.I32Views.Registry

namespace Lanius.X86.Storage.Slice.Raw

open Lanius.Core Lanius.Semantics Lanius.Properties

variable {before after : State} {address count : Nat} {signedLength : Int}
  {memory nextMemory : Machine.Memory} {base : Machine.Address} {locations : Locations}
  {block : Lanius.Memory.Block} {values : List Int}

/-- Exact metadata and backing storage produced by the real Core raw-slice
constructor. This does not assert that any native descriptor has been written
or that Locations.slice has already been extended for the new Core root. -/
structure Constructed (before after : State) (address count : Nat)
    (memory : Machine.Memory) (base : Machine.Address) (locations : Locations)
    (values : List Int) : Prop where
  run : mapRawI32Slice before address count =
    .done (.slice (.scalar (.signed .i32)) before.nextCell [] 0 count) after
  cell : after.cellEntry? before.nextCell =
    some { id := before.nextCell, value := some (.array (signedI32Values values)) }
  read : readCellProjection after before.nextCell [] = .ok (.array (signedI32Values values))
  length : values.length = count
  pointer : locations.pointer address = some base
  packed : Slice.Represents memory base values
  correspondence : Heap.Correspondence after.heap memory locations
  wellFormed : StateWellFormed after
  cells : after.cells = before.cells ++
    [{ id := before.nextCell, value := some (.array (signedI32Values values)) }]
  oldCells : ∀ cell, cell < before.nextCell → after.cellEntry? cell = before.cellEntry? cell
  registry : after.i32ArrayViews = before.i32ArrayViews ++
    [{ address, root := before.nextCell, projections := [], length := count }]
  view : I32ArrayViewBlockWellFormed after.heap
    { address, root := before.nextCell, projections := [], length := count }
  nextCell : after.nextCell = before.nextCell + 1
  locals : after.locals = before.locals
  world : after.world = before.world
  heapFrontier : after.heap.nextAddress = before.heap.nextAddress
  budget : after.heap.remaining = before.heap.remaining
  length64 : count < 2 ^ 64

/-- A write outside every represented heap block preserves both the complete
heap correspondence and this slice's packed backing. This is the frame rule
used when separate native descriptor stores are added after construction. -/
theorem Constructed.frameMemory
    (constructed : Constructed before after address count memory base locations values)
    (same : ∀ block ∈ after.heap.blocks, ∀ native,
      locations.pointer block.base = some native → ∀ offset, offset < block.size →
        nextMemory (native + BitVec.ofNat 64 offset) = memory (native + BitVec.ofNat 64 offset)) :
    Constructed before after address count nextMemory base locations values := by
  have nextCorrespondence : Heap.Correspondence after.heap nextMemory locations := by
    refine ⟨constructed.correspondence.wellFormed, ?_, constructed.correspondence.offsets,
      constructed.correspondence.covered, constructed.correspondence.disjoint⟩
    intro block member native mapped
    have represented := constructed.correspondence.mappedBlock block member native mapped
    refine ⟨represented.live, represented.logicalBound, represented.nativeBound, represented.aligned, ?_⟩
    intro offset inside
    rw [same block member native mapped offset inside]
    exact represented.bytes offset inside
  have nextPacked : Slice.Represents nextMemory base values := by
    apply constructed.packed.frame
    intro index inside lane
    obtain ⟨block, found, _, _, size, _⟩ := constructed.view
    change block.size = count * 4 at size
    have blockBase : block.base = address := beq_iff_eq.mp
      (List.find?_some (p := fun block : Lanius.Memory.Block => block.base == address) found)
    have mapped : locations.pointer block.base = some base := by
      simpa only [blockBase] using constructed.pointer
    have indexBound : index < count := by simpa only [constructed.length] using inside
    have frame := same block (List.mem_of_find?_eq_some found) base mapped (index * 4 + lane.val)
      (by have laneBound := lane.isLt; change index * 4 + lane.val < block.size; rw [size]; omega)
    simpa only [Slice.address, BitVec.ofNat_add, BitVec.add_assoc] using frame
  exact { constructed with packed := nextPacked, correspondence := nextCorrespondence }

/-- Mapping a represented exact raw allocation derives protection, the full
byte read, and i32 decoding. Only allocation/storage premises remain; there
are no assumed helper executions, per-element loads, or descriptor contents.
The empty allocation case is included by the heap's identity-address range. -/
theorem map (wellFormed : StateWellFormed before)
    (related : Heap.Correspondence before.heap memory locations)
    (found : before.heap.block? address = some block)
    (mapped : locations.pointer address = some base)
    (size : block.size = count * 4) (alignment : block.alignment = 4) :
    ∃ after values, Constructed before after address count memory base locations values := by
  obtain ⟨protectedHeap, protection, protectedRelated, borrowed, heapFrontier, budget⟩ :=
    related.protect_exact found mapped
  have protectionExact : before.heap.protectAsBorrowed address (count * 4) 4 = .ok protectedHeap := by
    simpa only [size, alignment] using protection
  have valid := protectAsBorrowed_result_view_block_well_formed
    (root := before.nextCell) (projections := []) before.heap protectedHeap protectionExact
  have blockBase : block.base = address :=
    beq_iff_eq.mp (List.find?_some (p := fun block : Lanius.Memory.Block => block.base == address) found)
  have mappedBlock : locations.pointer block.base = some base := by simpa only [blockBase] using mapped
  obtain ⟨bytes, values, loadedAt, _, decoded, valueLength, packed⟩ := protectedRelated.array_exists
    (List.mem_of_find?_eq_some borrowed) mappedBlock (start := 0) (length := count)
    (by omega : 0 < max block.size 1) (by change 0 + count * 4 ≤ block.size; omega)
  have loaded : protectedHeap.loadBytes address (count * 4) = .ok bytes := by
    simpa only [Nat.add_zero, blockBase] using loadedAt
  have protectedStateWF : StateWellFormed { before with heap := protectedHeap } :=
    ⟨protectedRelated.wellFormed, wellFormed.cellIdsUnique, wellFormed.cellIdsBelowNext, wellFormed.localsReferenceCells⟩
  let temporary := ({ before with heap := protectedHeap }).allocateTemporary (.array (signedI32Values values))
  let after : State := { temporary.2 with i32ArrayViews := temporary.2.i32ArrayViews ++
    [{ address, root := before.nextCell, projections := [], length := count }] }
  have temporaryWF := allocateTemporary_preserves_well_formed
    { before with heap := protectedHeap } (.array (signedI32Values values)) protectedStateWF
  have afterWF : StateWellFormed after :=
    ⟨temporaryWF.heapWellFormed, temporaryWF.cellIdsUnique, temporaryWF.cellIdsBelowNext, temporaryWF.localsReferenceCells⟩
  have cell : after.cellEntry? before.nextCell =
      some { id := before.nextCell, value := some (.array (signedI32Values values)) } :=
    allocateTemporary_finds_fresh_cell { before with heap := protectedHeap }
      (.array (signedI32Values values)) protectedStateWF
  have packedAtBase : Slice.Represents memory base values := by
    change Slice.Represents memory (base + 0) values at packed
    simpa using packed
  refine ⟨after, values, ?_, cell, ?_, valueLength, mapped, packedAtBase, protectedRelated, afterWF, rfl, ?_, rfl,
    valid, rfl, rfl, rfl, heapFrontier, budget, ?_⟩
  · simp only [mapRawI32Slice, if_neg (by omega : ¬ (count : Int) < 0), Int.toNat_natCast,
      protectionExact, loaded, decoded]
    rfl
  · simp only [readCellProjection, cell, projectedValue]
  · intro old below
    exact allocateTemporary_preserves_old_cell { before with heap := protectedHeap }
      (.array (signedI32Values values)) old below
  · have bounded := packedAtBase.bounded
    rw [valueLength] at bounded
    omega

/-- Signed-length form used by Core's raw-slice expression. Nonnegativity is
the constructor's own domain condition. A compiler theorem for a native i32
length additionally establishes its canonical signed-i32 range at that value
boundary; no such restriction is needed to prove this constructor operation. -/
theorem map_signed (signedLength : Int) (nonnegative : 0 ≤ signedLength)
    (wellFormed : StateWellFormed before)
    (related : Heap.Correspondence before.heap memory locations)
    (found : before.heap.block? address = some block)
    (mapped : locations.pointer address = some base)
    (size : block.size = signedLength.toNat * 4) (alignment : block.alignment = 4) :
    ∃ after values,
      mapRawI32Slice before address signedLength =
        .done (.slice (.scalar (.signed .i32)) before.nextCell [] 0 signedLength.toNat) after ∧
      Constructed before after address signedLength.toNat memory base locations values := by
  obtain ⟨after, values, constructed⟩ := map wellFormed related found mapped size alignment
  exact ⟨after, values, by simpa only [Int.toNat_of_nonneg nonnegative] using constructed.run, constructed⟩

theorem rejects_negative (negative : signedLength < 0) :
    mapRawI32Slice before address signedLength = .trapped .rawMemoryBounds before := by
  simp only [mapRawI32Slice, if_pos negative]

end Lanius.X86.Storage.Slice.Raw
