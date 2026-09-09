import Lanius.Semantics.I32Views
import Lanius.ExecutionRules

namespace Lanius.Semantics

open Lanius.Core Lanius.Memory

/-- The persistent resources produced by one raw i32 buffer allocation. -/
structure I32AllocationResources (before : State) (count : Nat) (after : State) : Prop where
  storage : ∃ address elements,
    after.i32ArrayViews = before.i32ArrayViews ++
      [{ address, root := before.nextCell, projections := [], length := count }] ∧
    I32ArrayViewBlockWellFormed after.heap
      { address, root := before.nextCell, projections := [], length := count } ∧
    after.cells = before.cells ++ [{ id := before.nextCell, value := some (.array elements) }] ∧
    elements.length = count ∧ ∀ element ∈ elements, ∃ value, element = .signed .i32 value
  wellFormed : Lanius.Properties.StateWellFormed after
  viewsPreserved : Lanius.Properties.I32ArrayViewBlocksPreserved before.i32ArrayViews before.heap after.heap
  nextCell : after.nextCell = before.nextCell + 1
  locals : after.locals = before.locals
  world : after.world = before.world
  remaining : after.heap.remaining = before.heap.remaining.map (fun available => available - count * 4)

/-- Allocation establishes the storage and registry resources consumed by later
buffer operations, while preserving every previously registered view. -/
theorem evaluatesAllocatedI32Slice_resources (program : Program) (state : State) (count : Nat)
    (wellFormed : Lanius.Properties.StateWellFormed state)
    (room : ∀ available, state.heap.remaining = some available → count * 4 ≤ available) :
    ∃ address after elements, Evaluates program state
      (.i32SliceFromRawParts
        (.alloc (.value (.unsigned .usize (count * 4))) (.value (.unsigned .usize 4)))
        (.value (.signed .i32 count)))
      (.slice (.scalar (.signed .i32)) state.nextCell [] 0 count) after ∧
      Lanius.Properties.StateWellFormed after ∧
      after.i32ArrayViews = state.i32ArrayViews ++
        [{ address, root := state.nextCell, projections := [], length := count }] ∧
      I32ArrayViewBlockWellFormed after.heap
        { address, root := state.nextCell, projections := [], length := count } ∧
      Lanius.Properties.I32ArrayViewBlocksPreserved state.i32ArrayViews state.heap after.heap ∧
      after.cells = state.cells ++ [{ id := state.nextCell, value := some (.array elements) }] ∧
      elements.length = count ∧
      (∀ element ∈ elements, ∃ value, element = .signed .i32 value) ∧
      after.nextCell = state.nextCell + 1 ∧ after.locals = state.locals ∧
      after.world = state.world ∧
      after.heap.remaining = state.heap.remaining.map (fun available => available - count * 4) := by
  obtain ⟨address, heap, allocated⟩ := state.heap.allocate_exists (alignment := 4) (by decide) room
  have found := state.heap.allocated_block wellFormed.heapWellFormed allocated
  have valid : HeapWellFormed heap := by
    simpa only [allocated, Lanius.Properties.AllocationResultWellFormed] using
      Lanius.Properties.allocate_preserves_heap_well_formed wellFormed.heapWellFormed
        (size := count * 4) (alignment := 4)
  obtain ⟨after, mapped, views, block, heapValid, next, locals, world, preserved,
      remaining, elements, cells, length, typed⟩ :=
    mapRawI32Slice_exists (state := { state with heap }) valid found rfl rfl rfl
  have temporary := Lanius.Properties.allocateTemporary_preserves_well_formed
    state (.array elements) wellFormed
  have afterValid : Lanius.Properties.StateWellFormed after := by
    constructor
    · exact heapValid
    · simpa only [Lanius.Properties.CellIdsUnique, State.allocateTemporary, cells] using temporary.cellIdsUnique
    · simpa only [Lanius.Properties.CellIdsBelowNext, State.allocateTemporary, cells, next] using temporary.cellIdsBelowNext
    · simpa only [Lanius.Properties.LocalsReferenceCells, State.allocateTemporary, cells, locals] using temporary.localsReferenceCells
  have allocation := evaluatesAlloc
    (show Evaluates program state (.value (.unsigned .usize (count * 4))) (.unsigned .usize (count * 4)) state from ⟨1, rfl⟩)
    (show Evaluates program state (.value (.unsigned .usize 4)) (.unsigned .usize 4) state from ⟨1, rfl⟩) allocated
  exact ⟨address, after, elements, evaluatesI32SliceFromRawParts allocation
    (show Evaluates program { state with heap } (.value (.signed .i32 count)) (.signed .i32 count)
      { state with heap } from ⟨1, rfl⟩) mapped,
    afterValid, views, block,
    (Lanius.Properties.allocate_preserves_i32_array_view_blocks allocated).trans preserved,
    cells, length, typed, next, locals, world,
    remaining.trans (state.heap.allocate_remaining allocated)⟩

/-- The actual Core allocation-plus-slice expression succeeds from a
sufficient byte budget, without assumed subexpression executions. -/
theorem evaluatesAllocatedI32Slice (program : Program) (state : State) (count : Nat)
    (wellFormed : HeapWellFormed state.heap)
    (room : ∀ available, state.heap.remaining = some available → count * 4 ≤ available) :
    ∃ after, Evaluates program state
      (.i32SliceFromRawParts
        (.alloc (.value (.unsigned .usize (count * 4))) (.value (.unsigned .usize 4)))
        (.value (.signed .i32 count)))
      (.slice (.scalar (.signed .i32)) state.nextCell [] 0 count) after ∧
      HeapWellFormed after.heap ∧
      after.heap.remaining = state.heap.remaining.map (fun available => available - count * 4) := by
  obtain ⟨address, heap, after, allocated, mapped, valid, remaining⟩ := allocateI32Slice_exists wellFormed room
  have allocation := evaluatesAlloc
    (show Evaluates program state (.value (.unsigned .usize (count * 4))) (.unsigned .usize (count * 4)) state from ⟨1, rfl⟩)
    (show Evaluates program state (.value (.unsigned .usize 4)) (.unsigned .usize 4) state from ⟨1, rfl⟩) allocated
  exact ⟨after, evaluatesI32SliceFromRawParts allocation
    (show Evaluates program { state with heap } (.value (.signed .i32 count)) (.signed .i32 count)
      { state with heap } from ⟨1, rfl⟩) mapped, valid, remaining⟩

end Lanius.Semantics
