import Lanius.Extraction.Allocation.Source
import Lanius.CallContracts.Host

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Semantics Lanius.Memory Lanius.Properties Lanius.CallContracts

/-- A host allocation succeeds from structural root-view resources and a byte
budget. Neither synchronization pass is assumed to succeed. -/
theorem hostAllocation_exists
    {program : Program} {function : Function} {before : State}
    {bindings : List (Lanius.VarId × Value)} (count : Nat)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.unsigned .usize (count * 4), .unsigned .usize 4] = some bindings)
    (noBody : function.body = none)
    (host : function.external = some (.host .alloc))
    (wellFormed : StateWellFormed before)
    (room : ∀ available, before.heap.remaining = some available → count * 4 ≤ available)
    (blocks : ∀ view ∈ before.i32ArrayViews, I32ArrayViewBlockWellFormed before.heap view)
    (roots : ∀ view ∈ before.i32ArrayViews, view.projections = [])
    (arrays : ∀ view ∈ before.i32ArrayViews, ∃ elements,
      readCellProjection before view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      ∀ element ∈ elements, ∃ value, element = .signed .i32 value) :
    ∃ address after, Evaluates program before
      (.call function.id [.value (.unsigned .usize (count * 4)), .value (.unsigned .usize 4)])
      (.pointer address) after ∧ after.world = Lanius.World.record before.world .alloc ∧
      StateWellFormed after ∧
      after.heap.block? address = some {
        base := address, size := count * 4, alignment := 4, bytes := List.replicate (count * 4) 0 } ∧
      after.heap.remaining = before.heap.remaining.map (fun available => available - count * 4) ∧
      after.i32ArrayViews = before.i32ArrayViews ∧ after.nextCell = before.nextCell ∧
      after.locals = before.locals ∧
      I32ArrayViewBlocksPreserved before.i32ArrayViews before.heap after.heap ∧
      (∀ cell, (∀ view ∈ before.i32ArrayViews, cell ≠ view.root) →
        after.cellEntry? cell = before.cellEntry? cell) ∧
      (before.i32ArrayViews.Pairwise (fun left right => left.root ≠ right.root) →
        ∀ view ∈ after.i32ArrayViews, ∃ elements,
          readCellProjection after view.root view.projections = .ok (.array elements) ∧
          elements.length = view.length ∧
          ∀ element ∈ elements, ∃ value, element = .signed .i32 value) := by
  obtain ⟨ready, synchronized⟩ := syncI32ViewsToHeap_exists wellFormed.heapWellFormed blocks arrays
  obtain ⟨readyValid, preserved, cells, registry, locals⟩ :=
    syncI32ViewsToHeapFrom_preserves_storage (views := before.i32ArrayViews) wellFormed.heapWellFormed synchronized
  have nextCell := syncI32ViewsToHeapFrom_nextCell synchronized
  have readyStateValid : StateWellFormed ready := by
    constructor
    · exact readyValid
    · simpa only [CellIdsUnique, cells] using wellFormed.cellIdsUnique
    · simpa only [CellIdsBelowNext, cells, nextCell] using wellFormed.cellIdsBelowNext
    · simpa only [LocalsReferenceCells, cells, locals] using wellFormed.localsReferenceCells
  have readyRoom : ∀ available, ready.heap.remaining = some available → count * 4 ≤ available := by
    intro available found
    rw [syncI32ViewsToHeapFrom_remaining synchronized] at found
    exact room available found
  obtain ⟨address, heap, allocated⟩ := ready.heap.allocate_exists (alignment := 4) (by decide) readyRoom
  have heapValid : HeapWellFormed heap := by
    simpa only [allocated, AllocationResultWellFormed] using
      allocate_preserves_heap_well_formed readyValid (size := count * 4) (alignment := 4)
  have allPreserved := preserved.trans
    (allocate_preserves_i32_array_view_blocks (views := before.i32ArrayViews) allocated)
  let changed : State := { ready with heap, world := Lanius.World.record ready.world .alloc }
  have readyCells : ∀ view ∈ changed.i32ArrayViews,
      ∃ cell, changed.cellEntry? view.root = some cell := by
    intro view member
    have original : view ∈ before.i32ArrayViews := by simpa only [changed, registry] using member
    obtain ⟨elements, read, _, _⟩ := arrays view original
    cases found : before.cellEntry? view.root with
    | none => simp [readCellProjection, found] at read
    | some cell =>
        exact ⟨cell, by change ready.cells.find? _ = some cell; rw [cells]; exact found⟩
  obtain ⟨after, refreshed⟩ := syncI32RootViewsFromHeapFrom_exists
    (before := changed) (pending := changed.i32ArrayViews) heapValid
    (fun view member => allPreserved view (by simpa only [changed, registry] using member)
      (blocks view (by simpa only [changed, registry] using member)))
    (fun view member => roots view (by simpa only [changed, registry] using member)) readyCells
  have changedValid : StateWellFormed changed :=
    ⟨heapValid, readyStateValid.cellIdsUnique, readyStateValid.cellIdsBelowNext,
      readyStateValid.localsReferenceCells⟩
  obtain ⟨afterValid, afterHeap, afterRegistry, afterNext⟩ :=
    syncI32RootViewsFromHeapFrom_preserves_structure
      (fun view member => roots view (by simpa only [changed, registry] using member))
      changedValid refreshed
  have arguments : ArgumentsEvaluateTo program before
      [.value (.unsigned .usize (count * 4)), .value (.unsigned .usize 4)]
      [.unsigned .usize (count * 4), .unsigned .usize 4] before := ⟨3, rfl⟩
  refine ⟨address, after, evaluatesHostAllocation arguments functionFound parametersBound
    noBody host synchronized allocated refreshed, ?_, afterValid, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · have initialWorld := syncI32ViewsToHeap_preserves_world synchronized
    have finalWorld := syncI32ViewsFromHeapFrom_preserves_world refreshed
    simpa only [changed, initialWorld] using finalWorld
  · rw [afterHeap]
    exact ready.heap.allocated_block readyValid allocated
  · rw [afterHeap]
    exact (ready.heap.allocate_remaining allocated).trans
      (congrArg (Option.map (fun available => available - count * 4))
        (syncI32ViewsToHeapFrom_remaining synchronized))
  · exact afterRegistry.trans registry
  · exact afterNext.trans nextCell
  · exact (syncI32RootViewsFromHeapFrom_preserves_locals
      (fun view member => roots view (by simpa only [changed, registry] using member)) refreshed).trans locals
  · rw [afterHeap]
    exact allPreserved
  · intro cell separate
    have kept := syncI32RootViewsFromHeapFrom_preserves_other_cell
      (fun view member => roots view (by simpa only [changed, registry] using member))
      (fun view member => separate view (by simpa only [changed, registry] using member)) refreshed
    simpa only [State.cellEntry?, changed, cells] using kept
  · intro distinct view member
    apply syncI32RootViewsFromHeapFrom_arrays
      (fun view member => roots view (by simpa only [changed, registry] using member))
      (by simpa only [changed, registry] using distinct) refreshed view
    simpa only [afterRegistry] using member

/-- The actual source initializer, including host allocation, both registry
synchronizations, and registration of the new raw slice. -/
theorem hostSlice_exists
    {program : Program} {function : Function} {before : State}
    {bindings : List (Lanius.VarId × Value)} (buffer : Buffer)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.unsigned .usize (buffer.count * 4), .unsigned .usize 4] = some bindings)
    (noBody : function.body = none)
    (host : function.external = some (.host .alloc))
    (wellFormed : StateWellFormed before)
    (room : ∀ available, before.heap.remaining = some available → buffer.count * 4 ≤ available)
    (blocks : ∀ view ∈ before.i32ArrayViews, I32ArrayViewBlockWellFormed before.heap view)
    (roots : ∀ view ∈ before.i32ArrayViews, view.projections = [])
    (distinct : before.i32ArrayViews.Pairwise fun left right => left.root ≠ right.root)
    (arrays : ∀ view ∈ before.i32ArrayViews, ∃ elements,
      readCellProjection before view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      ∀ element ∈ elements, ∃ value, element = .signed .i32 value) :
    ∃ after, Evaluates program before (hostInitializer function.id buffer)
      (.slice (.scalar (.signed .i32)) before.nextCell [] 0 buffer.count) after ∧
      StateWellFormed after ∧ after.world = Lanius.World.record before.world .alloc ∧
      after.heap.remaining = before.heap.remaining.map (fun available => available - buffer.count * 4) ∧
      after.nextCell = before.nextCell + 1 ∧ after.locals = before.locals ∧
      I32ArrayViewBlocksPreserved before.i32ArrayViews before.heap after.heap ∧
      (∀ cell, cell < before.nextCell → (∀ view ∈ before.i32ArrayViews, cell ≠ view.root) →
        after.cellEntry? cell = before.cellEntry? cell) ∧
      (∀ view ∈ after.i32ArrayViews, ∃ elements,
        readCellProjection after view.root view.projections = .ok (.array elements) ∧
        elements.length = view.length ∧
        ∀ element ∈ elements, ∃ value, element = .signed .i32 value) ∧
      ∃ address elements,
        after.i32ArrayViews = before.i32ArrayViews ++
          [{ address, root := before.nextCell, projections := [], length := buffer.count }] ∧
        I32ArrayViewBlockWellFormed after.heap
          { address, root := before.nextCell, projections := [], length := buffer.count } ∧
        readCellProjection after before.nextCell [] = .ok (.array elements) ∧
        elements.length = buffer.count ∧
        ∀ element ∈ elements, ∃ value, element = .signed .i32 value := by
  obtain ⟨address, middle, called, middleWorld, middleValid, found, budget,
      registry, nextCell, middleLocals, kept, middleFrame, middleArrays⟩ :=
    hostAllocation_exists buffer.count functionFound parametersBound noBody host wellFormed room blocks roots arrays
  obtain ⟨after, mapped, views, block, heapValid, next, locals, world, preserved,
      remaining, elements, cells, length, typed⟩ :=
    mapRawI32Slice_exists middleValid.heapWellFormed found rfl rfl rfl
  have temporary := allocateTemporary_preserves_well_formed middle (.array elements) middleValid
  have valid : StateWellFormed after := by
    constructor
    · exact heapValid
    · simpa only [CellIdsUnique, State.allocateTemporary, cells] using temporary.cellIdsUnique
    · simpa only [CellIdsBelowNext, State.allocateTemporary, cells, next] using temporary.cellIdsBelowNext
    · simpa only [LocalsReferenceCells, State.allocateTemporary, cells, locals] using temporary.localsReferenceCells
  have evaluated := evaluatesI32SliceFromRawParts called
    (show Evaluates program middle (.value (.signed .i32 buffer.count)) (.signed .i32 buffer.count) middle
      from ⟨1, rfl⟩) mapped
  have newRead : readCellProjection after before.nextCell [] = .ok (.array elements) := by
    have fresh := allocateTemporary_finds_fresh_cell middle (.array elements) middleValid
    have lookup : after.cellEntry? before.nextCell =
        some { id := before.nextCell, value := some (.array elements) } := by
      simpa only [State.allocateTemporary, State.cellEntry?, cells, nextCell] using fresh
    simp only [readCellProjection, lookup, projectedValue]
  refine ⟨after, ?_, valid, world.trans middleWorld, remaining.trans budget,
    next.trans (congrArg (· + 1) nextCell), locals.trans middleLocals, ?_, ?_, ?_,
    address, elements, ?_, ?_, ?_, length, typed⟩
  · simpa only [hostInitializer, nextCell] using evaluated
  · apply kept.trans
    simpa only [registry] using preserved
  · intro cell old separate
    have oldMiddle : cell < middle.nextCell := by simpa only [nextCell] using old
    have unchanged := allocateTemporary_preserves_old_cell middle (.array elements) cell oldMiddle
    have same : after.cellEntry? cell = middle.cellEntry? cell := by
      simpa only [State.allocateTemporary, State.cellEntry?, cells] using unchanged
    exact same.trans (middleFrame cell separate)
  · intro view member
    rw [views] at member
    rcases List.mem_append.mp member with old | fresh
    · obtain ⟨oldElements, read, oldLength, oldTyped⟩ := middleArrays distinct view old
      refine ⟨oldElements, ?_, oldLength, oldTyped⟩
      cases foundCell : middle.cellEntry? view.root with
      | none => simp [readCellProjection, foundCell] at read
      | some cell =>
          have bound := found_cell_is_below_next middle view.root cell middleValid foundCell
          have keptCell := allocateTemporary_preserves_old_cell middle (.array elements) view.root bound
          have sameCell : after.cellEntry? view.root = middle.cellEntry? view.root := by
            simpa only [State.allocateTemporary, State.cellEntry?, cells] using keptCell
          simpa only [readCellProjection, sameCell] using read
    · simp only [List.mem_singleton] at fresh
      subst view
      exact ⟨elements, by simpa only [nextCell] using newRead, length, typed⟩
  · simpa only [registry, nextCell] using views
  · simpa only [nextCell] using block
  · exact newRead

end Lanius.Extraction.Allocation
