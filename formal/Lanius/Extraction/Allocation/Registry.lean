import Lanius.Extraction.Allocation.Host
import Lanius.Semantics.I32Views.Registry

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
  addresses : state.i32ArrayViews.Pairwise fun left right => left.address ≠ right.address

/-- Registered roots and raw addresses are distinct invariants. The latter,
with owned heap blocks, derives the byte separation needed by host I/O. -/
theorem Registry.disjoint (valid : Registry state) : state.i32ArrayViews.Pairwise I32ViewRangesDisjoint :=
  i32Views_disjoint_of_distinct_addresses valid.wellFormed.heapWellFormed valid.blocks valid.addresses

theorem Registry.apart (valid : Registry state) (leftMember : left ∈ state.i32ArrayViews)
    (rightMember : right ∈ state.i32ArrayViews) (different : left.root ≠ right.root) :
    I32ViewRangesDisjoint left right := by
  have fromPairwise {views : List I32ArrayView} (disjoint : views.Pairwise I32ViewRangesDisjoint)
      (leftMember : left ∈ views) (rightMember : right ∈ views) : I32ViewRangesDisjoint left right := by
    induction views with
    | nil => simp at leftMember
    | cons first rest ih =>
        obtain ⟨head, tail⟩ := List.pairwise_cons.mp disjoint
        rcases List.mem_cons.mp leftMember with rfl | leftTail
        · rcases List.mem_cons.mp rightMember with rfl | rightTail
          · exact False.elim (different rfl)
          · exact head right rightTail
        · rcases List.mem_cons.mp rightMember with rfl | rightTail
          · exact (head left leftTail).symm
          · exact ih tail leftTail rightTail
  exact fromPairwise valid.disjoint leftMember rightMember

theorem Registry.of_empty_views (valid : StateWellFormed state) (empty : state.i32ArrayViews = []) :
    Registry state := by
  refine ⟨valid, ?_, ?_, ?_, ?_, ?_⟩ <;> simp [empty]

theorem Registry.root_lt_next (valid : Registry state) (member : view ∈ state.i32ArrayViews) :
    view.root < state.nextCell := by
  obtain ⟨elements, read, _, _⟩ := valid.arrays view member
  cases found : state.cellEntry? view.root with
  | none => simp [readCellProjection, found] at read
  | some entry => exact found_cell_is_below_next state view.root entry valid.wellFormed found

/-- A backing root identifies one registered view, including its native address. -/
theorem Registry.view_eq (valid : Registry state) (leftMember : left ∈ state.i32ArrayViews)
    (rightMember : right ∈ state.i32ArrayViews) (sameRoot : left.root = right.root) : left = right := by
  have unique {views : List I32ArrayView} (distinct : views.Pairwise fun a b => a.root ≠ b.root)
      (leftMember : left ∈ views) (rightMember : right ∈ views) : left = right := by
    induction views with
    | nil => simp at leftMember
    | cons head rest ih =>
        obtain ⟨apart, tail⟩ := List.pairwise_cons.mp distinct
        rcases List.mem_cons.mp leftMember with rfl | leftTail
        · rcases List.mem_cons.mp rightMember with rfl | rightTail
          · rfl
          · exact False.elim (apart right rightTail sameRoot)
        · rcases List.mem_cons.mp rightMember with rfl | rightTail
          · exact False.elim (apart left leftTail sameRoot.symm)
          · exact ih tail leftTail rightTail
  exact unique valid.distinct leftMember rightMember

theorem Registry.bindLocal (valid : Registry state) (id : Lanius.VarId) (value : Value) :
    Registry (state.bindLocal id value) := by
  refine ⟨bindLocal_preserves_well_formed _ _ _ valid.wellFormed,
    valid.blocks, valid.roots, valid.distinct, ?_, valid.addresses⟩
  intro view member
  obtain ⟨elements, read, length, typed⟩ := valid.arrays view member
  refine ⟨elements, ?_, length, typed⟩
  have old := valid.root_lt_next member
  have kept : (state.bindLocal id value).cellEntry? view.root = state.cellEntry? view.root := by
    simpa only [State.bindLocal, State.bindCell, State.allocateTemporary, State.cellEntry?] using
      allocateTemporary_preserves_old_cell state value view.root old
  simpa only [readCellProjection, kept] using read

theorem Registry.bindUninitialized (valid : Registry state) (id : Lanius.VarId) :
    Registry (state.bindUninitialized id) := by
  refine ⟨bindUninitialized_preserves_well_formed _ _ valid.wellFormed,
    valid.blocks, valid.roots, valid.distinct, ?_, valid.addresses⟩
  intro view member
  obtain ⟨elements, read, length, typed⟩ := valid.arrays view member
  have kept := bindCell_preserves_old_cell state id none view.root (valid.root_lt_next member)
  exact ⟨elements, by simpa only [readCellProjection, State.bindUninitialized, kept] using read,
    length, typed⟩

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
  refine ⟨after, synced, ⟨stateValid, ?_, ?_, ?_, ?_, ?_⟩, cells, locals, views, next,
    syncI32ViewsToHeapFrom_remaining synced, syncI32ViewsToHeap_preserves_world synced⟩
  · intro view member
    rw [views] at member
    exact preserved view member (valid.blocks view member)
  · simpa only [views] using valid.roots
  · simpa only [views] using valid.distinct
  · simpa only [views, readCellProjection, State.cellEntry?, cells] using valid.arrays
  · simpa only [views] using valid.addresses

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
    (Lanius.Semantics.evaluatesLocal read) mapped,
    valid.nonnull member, registry, cells, locals, views, next, remaining, world⟩

end Lanius.Extraction.Allocation
