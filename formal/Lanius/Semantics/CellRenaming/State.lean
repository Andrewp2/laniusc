import Lanius.Semantics.CellRenaming.Value
import Lanius.Semantics
import Lanius.Properties

namespace Lanius.Semantics.CellRenaming
open Lanius.Core

def cell (rename : CellId → CellId) (entry : Cell) : Cell :=
  { id := rename entry.id, value := entry.value.map (value rename) }

def state (rename : CellId → CellId) (before : State) : State :=
  { before with
    locals := before.locals.map (fun entry => (entry.1, rename entry.2))
    cells := before.cells.map (cell rename)
    i32ArrayViews := before.i32ArrayViews.map (fun view => { view with root := rename view.root }) }

private theorem find_cells (rename : Permutation boundary) (entries : List Cell) (id : CellId) :
    (entries.map (cell rename.forward)).find? (fun entry => entry.id == rename.forward id) =
      (entries.find? (fun entry => entry.id == id)).map (cell rename.forward) := by
  induction entries with
  | nil => rfl
  | cons first rest induction =>
      by_cases same : first.id = id
      · simp [cell, same]
      · have different : rename.forward first.id ≠ rename.forward id :=
          fun equal => same (rename.injective equal)
        simpa [cell, same, different] using induction

theorem cellEntry (rename : Permutation boundary) (before : State) (id : CellId) :
    (state rename.forward before).cellEntry? (rename.forward id) =
      (before.cellEntry? id).map (cell rename.forward) :=
  find_cells rename before.cells id

/-- The allocation frontier is fixed, so renaming commutes with creation of
a local cell and all later allocations use the same fresh identities. -/
theorem bindCell (rename : Permutation boundary) (before : State)
    (ready : boundary ≤ before.nextCell) (id : VarId) (entry : Option Value) :
    state rename.forward (before.bindCell id entry) =
      (state rename.forward before).bindCell id (entry.map (value rename.forward)) := by
  simp [state, State.bindCell, cell, rename.fresh before.nextCell ready]

theorem allocateTemporary (rename : Permutation boundary) (before : State)
    (ready : boundary ≤ before.nextCell) (entry : Value) :
    (state rename.forward before).allocateTemporary (value rename.forward entry) =
      ((before.allocateTemporary entry).1,
        state rename.forward (before.allocateTemporary entry).2) := by
  simp [state, State.allocateTemporary, cell, rename.fresh before.nextCell ready]

theorem state_leftInverse (outer inner : CellId → CellId)
    (inverse : Function.LeftInverse outer inner) (before : State) :
    state outer (state inner before) = before := by
  have inverseEq : ∀ id, outer (inner id) = id := inverse
  have cells : ∀ entry, cell outer (cell inner entry) = entry := by
    intro entry
    cases entry with
    | mk id contents =>
        cases contents <;> simp [cell, inverseEq, value_leftInverse outer inner inverse]
  simp [state, List.map_map, Function.comp_def, inverseEq, cells]

theorem state_wellFormed (rename : Permutation boundary)
    (ready : boundary ≤ before.nextCell) (wellFormed : Properties.StateWellFormed before) :
    Properties.StateWellFormed (state rename.forward before) := by
  constructor
  · exact wellFormed.heapWellFormed
  · intro left leftMember right rightMember sameId
    obtain ⟨oldLeft, oldLeftMember, rfl⟩ := List.mem_map.mp leftMember
    obtain ⟨oldRight, oldRightMember, rfl⟩ := List.mem_map.mp rightMember
    have same := wellFormed.cellIdsUnique oldLeft oldLeftMember oldRight oldRightMember
      (rename.injective sameId)
    rw [same]
  · intro entry member
    obtain ⟨old, oldMember, rfl⟩ := List.mem_map.mp member
    have below := wellFormed.cellIdsBelowNext old oldMember
    by_cases existing : old.id < boundary
    · exact Nat.lt_of_lt_of_le (rename.below existing) ready
    · simpa only [cell, state, rename.fresh old.id (Nat.le_of_not_gt existing)] using below
  · intro binding member
    obtain ⟨oldBinding, oldMember, rfl⟩ := List.mem_map.mp member
    obtain ⟨oldCell, cellMember, same⟩ := wellFormed.localsReferenceCells oldBinding oldMember
    exact ⟨cell rename.forward oldCell, List.mem_map.mpr ⟨oldCell, cellMember, rfl⟩,
      congrArg rename.forward same⟩

end Lanius.Semantics.CellRenaming
