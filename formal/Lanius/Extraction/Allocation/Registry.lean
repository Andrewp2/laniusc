import Lanius.Extraction.Allocation.Host

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Semantics Lanius.Memory Lanius.Properties

/-- The structural invariant required by each subsequent host allocation. -/
structure Registry (state : State) : Prop where
  wellFormed : StateWellFormed state
  blocks : ∀ view ∈ state.i32ArrayViews, I32ArrayViewBlockWellFormed state.heap view
  roots : ∀ view ∈ state.i32ArrayViews, view.projections = []
  distinct : state.i32ArrayViews.Pairwise fun left right => left.root ≠ right.root
  arrays : ∀ view ∈ state.i32ArrayViews, ∃ elements,
    readCellProjection state view.root view.projections = .ok (.array elements) ∧
    elements.length = view.length ∧
    ∀ element ∈ elements, ∃ value, element = .signed .i32 value

theorem Registry.of_empty_views (valid : StateWellFormed state) (empty : state.i32ArrayViews = []) :
    Registry state := by
  refine ⟨valid, ?_, ?_, ?_, ?_⟩ <;> simp [empty]

theorem Registry.root_lt_next (valid : Registry state) (member : view ∈ state.i32ArrayViews) :
    view.root < state.nextCell := by
  obtain ⟨elements, read, _, _⟩ := valid.arrays view member
  cases found : state.cellEntry? view.root with
  | none => simp [readCellProjection, found] at read
  | some entry => exact found_cell_is_below_next state view.root entry valid.wellFormed found

theorem Registry.allocate
    {program : Program} {function : Function} {before : State}
    {bindings : List (Lanius.VarId × Value)} (buffer : Buffer)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.unsigned .usize (buffer.count * 4), .unsigned .usize 4] = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host .alloc))
    (initial : Registry before)
    (room : ∀ available, before.heap.remaining = some available → buffer.count * 4 ≤ available) :
    ∃ after, Evaluates program before (hostInitializer function.id buffer)
      (.slice (.scalar (.signed .i32)) before.nextCell [] 0 buffer.count) after ∧
      Registry after ∧ after.world = Lanius.World.record before.world .alloc ∧
      after.heap.remaining = before.heap.remaining.map (fun available => available - buffer.count * 4) ∧
      after.nextCell = before.nextCell + 1 ∧ after.locals = before.locals ∧
      (∀ cell, cell < before.nextCell → (∀ view ∈ before.i32ArrayViews, cell ≠ view.root) →
        after.cellEntry? cell = before.cellEntry? cell) ∧
      ∃ address elements,
        after.i32ArrayViews = before.i32ArrayViews ++
          [{ address, root := before.nextCell, projections := [], length := buffer.count }] ∧
        readCellProjection after before.nextCell [] = .ok (.array elements) ∧
        elements.length = buffer.count ∧
        ∀ element ∈ elements, ∃ value, element = .signed .i32 value := by
  obtain ⟨after, evaluated, valid, world, remaining, next, locals, preserved, frame,
      arrays, address, elements, views, block, read, length, typed⟩ :=
    hostSlice_exists buffer functionFound parametersBound noBody host initial.wellFormed room
      initial.blocks initial.roots initial.distinct initial.arrays
  refine ⟨after, evaluated, ⟨valid, ?_, ?_, ?_, arrays⟩, world, remaining, next, locals, frame,
    address, elements, views, read, length, typed⟩
  · intro view member
    rw [views] at member
    rcases List.mem_append.mp member with old | fresh
    · exact preserved view old (initial.blocks view old)
    · simp only [List.mem_singleton] at fresh
      subst view
      exact block
  · intro view member
    rw [views] at member
    rcases List.mem_append.mp member with old | fresh
    · exact initial.roots view old
    · simp only [List.mem_singleton] at fresh
      subst view
      rfl
  · rw [views, List.pairwise_append]
    refine ⟨initial.distinct, by simp, ?_⟩
    intro left member right fresh
    simp only [List.mem_singleton] at fresh
    subst right
    exact Nat.ne_of_lt (initial.root_lt_next member)

theorem Registry.bindLocal (valid : Registry state) (id : Lanius.VarId) (value : Value) :
    Registry (state.bindLocal id value) := by
  refine ⟨bindLocal_preserves_well_formed _ _ _ valid.wellFormed,
    valid.blocks, valid.roots, valid.distinct, ?_⟩
  intro view member
  obtain ⟨elements, read, length, typed⟩ := valid.arrays view member
  refine ⟨elements, ?_, length, typed⟩
  have old := valid.root_lt_next member
  have kept : (state.bindLocal id value).cellEntry? view.root = state.cellEntry? view.root := by
    simpa only [State.bindLocal, State.bindCell, State.allocateTemporary, State.cellEntry?] using
      allocateTemporary_preserves_old_cell state value view.root old
  simpa only [readCellProjection, kept] using read

theorem Registry.synchronize (valid : Registry before) :
    ∃ after, syncI32ViewsToHeap before = .ok after ∧ Registry after ∧
      after.cells = before.cells ∧ after.locals = before.locals ∧
      after.i32ArrayViews = before.i32ArrayViews ∧ after.nextCell = before.nextCell ∧
      after.heap.remaining = before.heap.remaining ∧ after.world = before.world := by
  obtain ⟨after, synced⟩ := syncI32ViewsToHeap_exists valid.wellFormed.heapWellFormed valid.blocks valid.arrays
  obtain ⟨heapValid, preserved, cells, views, locals⟩ :=
    syncI32ViewsToHeapFrom_preserves_storage (views := before.i32ArrayViews) valid.wellFormed.heapWellFormed synced
  have next := syncI32ViewsToHeapFrom_nextCell synced
  have stateValid : StateWellFormed after := by
    constructor
    · exact heapValid
    · simpa only [CellIdsUnique, cells] using valid.wellFormed.cellIdsUnique
    · simpa only [CellIdsBelowNext, cells, next] using valid.wellFormed.cellIdsBelowNext
    · simpa only [LocalsReferenceCells, cells, locals] using valid.wellFormed.localsReferenceCells
  refine ⟨after, synced, ⟨stateValid, ?_, ?_, ?_, ?_⟩, cells, locals, views, next,
    syncI32ViewsToHeapFrom_remaining synced, syncI32ViewsToHeap_preserves_world synced⟩
  · intro view member
    rw [views] at member
    exact preserved view member (valid.blocks view member)
  · simpa only [views] using valid.roots
  · simpa only [views] using valid.distinct
  · simpa only [views, readCellProjection, State.cellEntry?, cells] using valid.arrays

private theorem findRootView {views : List I32ArrayView} {view : I32ArrayView}
    (distinct : views.Pairwise fun left right => left.root ≠ right.root)
    (member : view ∈ views) :
    views.find? (fun candidate => decide (candidate.root = view.root ∧ candidate.projections = view.projections)) = some view := by
  induction views with
  | nil => simp at member
  | cons first rest ih =>
      obtain ⟨different, tail⟩ := List.pairwise_cons.mp distinct
      rcases List.mem_cons.mp member with same | member
      · subst view
        simp
      · simp only [List.find?_cons, different view member, false_and, decide_false, Bool.false_eq_true, ↓reduceIte]
        exact ih tail member

theorem Registry.findView (valid : Registry state) (member : view ∈ state.i32ArrayViews) :
    state.i32ArrayView? view.root view.projections = some view :=
  findRootView valid.distinct member

/-- Reading an existing slice's pointer synchronizes its registry but does not
allocate another block or consume budget. -/
theorem Registry.pointer (valid : Registry before) (member : view ∈ before.i32ArrayViews) :
    ∃ after, mapI32SliceDataPtr before view.root view.projections 0 view.length =
      .done (.pointer view.address) after ∧ Registry after ∧
      after.cells = before.cells ∧ after.locals = before.locals ∧
      after.i32ArrayViews = before.i32ArrayViews ∧ after.nextCell = before.nextCell ∧
      after.heap.remaining = before.heap.remaining ∧ after.world = before.world := by
  obtain ⟨elements, read, length, typed⟩ := valid.arrays view member
  obtain ⟨after, synced, registry, cells, locals, views, next, remaining, world⟩ := valid.synchronize
  refine ⟨after, ?_, registry, cells, locals, views, next, remaining, world⟩
  simp [mapI32SliceDataPtr, read, length, mapI32ArrayView, valid.findView member, synced]

theorem Registry.nonnull (valid : Registry state) (member : view ∈ state.i32ArrayViews) :
    view.address ≠ null := by
  obtain ⟨block, found, _⟩ := valid.blocks view member
  have same : block.base = view.address := by
    simpa using (List.find?_some found)
  have nonnull := (valid.wellFormed.heapWellFormed.blocksWellFormed block
    (List.mem_of_find?_eq_some found)).1
  simpa only [same] using nonnull

theorem Registry.evaluatesPointer (program : Program) (valid : Registry before)
    (member : view ∈ before.i32ArrayViews) (binding : Lanius.VarId)
    (read : before.local? binding =
      some (.slice (.scalar (.signed .i32)) view.root view.projections 0 view.length)) :
    ∃ after, Evaluates program before (.i32SliceDataPtr (.local binding)) (.pointer view.address) after ∧
      view.address ≠ null ∧ Registry after ∧
      after.cells = before.cells ∧ after.locals = before.locals ∧
      after.i32ArrayViews = before.i32ArrayViews ∧ after.nextCell = before.nextCell ∧
      after.heap.remaining = before.heap.remaining ∧ after.world = before.world := by
  obtain ⟨after, mapped, registry, cells, locals, views, next, remaining, world⟩ := valid.pointer member
  exact ⟨after, evaluatesI32SliceDataPtr
    ⟨1, evalLocal_of_local 0 program before binding _ read⟩ mapped,
    valid.nonnull member, registry, cells, locals, views, next, remaining, world⟩

end Lanius.Extraction.Allocation
