import Lanius.Semantics.Typing.Store

namespace Lanius.Semantics

open Lanius Lanius.Core Lanius.Typing

/-- An initialized target follows its cell's declared type, not a cached value.
    The store invariant supplies the root contents and their typing separately. -/
def CellTargetValid (program : Program) (types : CellTypes) (state : State)
    (cell : CellId) (projections : List ValueProjection) (type : Ty) : Prop :=
  ∃ rootType, types cell = some rootType ∧
    ProjectionHasType program rootType projections type ∧ state.cell? cell ≠ none

theorem CellTargetValid.read (valid : CellTargetValid program types state cell projections type)
    (store : state.CellsHaveTypes program types) :
    ∃ value, readCellProjection state cell projections = .ok value ∧
      ValueHasType program value type := by
  obtain ⟨rootType, declared, path, initialized⟩ := valid
  exact store.read (place := { root := cell, projections, value := none })
    ⟨rootType, declared, path, rfl⟩ initialized

/-- Root targets provide the live local value directly, without rebuilding
    cell-entry matches at every borrowing or native-view call site. -/
theorem CellTargetValid.localRead (valid : CellTargetValid program types state cell [] type)
    (store : state.CellsHaveTypes program types) (binding : state.cellId? localId = some cell) :
    ∃ value, state.local? localId = some value ∧ ValueHasType program value type := by
  obtain ⟨rootType, declared, path, initialized⟩ := valid
  cases path
  obtain ⟨contents, present, typed⟩ := store cell type declared
  cases contents with
  | none => simp [State.cell?, present] at initialized
  | some value => exact ⟨value, by simp [State.local?, binding, State.cell?, present], typed⟩

/-- Extending a declaration map preserves old targets only if their existing
    declarations are retained. This does not assert types for new storage. -/
theorem CellTargetValid.weaken (valid : CellTargetValid program types state cell projections type)
    (extension : ∀ cell type, types cell = some type → moreTypes cell = some type) :
    CellTargetValid program moreTypes state cell projections type := by
  obtain ⟨rootType, declared, path, initialized⟩ := valid
  exact ⟨rootType, extension _ _ declared, path, initialized⟩

theorem CellTargetValid.retained (valid : CellTargetValid program types before cell projections type)
    (frame : FreshCellFrame before after) :
    CellTargetValid program types after cell projections type := by
  obtain ⟨rootType, declared, path, initialized⟩ := valid
  refine ⟨rootType, declared, path, ?_⟩
  cases present : before.cellEntry? cell with
  | none => simp [State.cell?, present] at initialized
  | some entry =>
    simpa only [State.cell?, frame.cellEntryFound present, present, Option.bind_some] using initialized

/-- Even an aliased write retains target identity and initialization. Reading
    with the advertised type additionally requires the preserved typed store. -/
theorem CellTargetValid.cellEffect (valid : CellTargetValid program types before cell projections type)
    (effect : CellEffect before after assigned replacement) :
    CellTargetValid program types after cell projections type := by
  obtain ⟨rootType, declared, path, initialized⟩ := valid
  refine ⟨rootType, declared, path, ?_⟩
  cases present : before.cellEntry? cell with
  | none => simp [State.cell?, present] at initialized
  | some entry =>
    by_cases same : cell = assigned
    · subst assigned
      have found : after.cellEntry? cell = some { entry with value := some replacement } := by
        unfold State.cellEntry? at present ⊢
        rw [effect.cells, replaceCell_find_same before.cells cell replacement entry present]
      simp [State.cell?, found]
    · simpa only [State.cell?, effect.otherCell same present, present, Option.bind_some] using initialized

#print axioms CellTargetValid.cellEffect

end Lanius.Semantics
