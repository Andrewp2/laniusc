import Lanius.Semantics.CellRenaming.State

namespace Lanius.Semantics.CellRenaming
open Lanius.Core

theorem cellValue (rename : Permutation boundary) (before : State) (id : CellId) :
    (state rename.forward before).cell? (rename.forward id) =
      (before.cell? id).map (value rename.forward) := by
  simp only [State.cell?, cellEntry]
  cases before.cellEntry? id <;> simp [cell]

private theorem find_local (rename : CellId → CellId)
    (entries : List (VarId × CellId)) (id : VarId) :
    ((entries.map (fun entry => (entry.1, rename entry.2))).find?
      (fun entry => entry.1 == id)).map Prod.snd =
      ((entries.find? (fun entry => entry.1 == id)).map Prod.snd).map rename := by
  induction entries with
  | nil => rfl
  | cons first rest induction =>
      by_cases same : first.1 == id <;> simp [same, induction, Function.comp_def]

theorem cellId (rename : CellId → CellId) (before : State) (id : VarId) :
    (state rename before).cellId? id = (before.cellId? id).map rename :=
  find_local rename before.locals id

theorem localValue (rename : Permutation boundary) (before : State) (id : VarId) :
    (state rename.forward before).local? id =
      (before.local? id).map (value rename.forward) := by
  simp only [State.local?, cellId]
  cases before.cellId? id <;> simp [cellValue]

private theorem replace_cells (rename : Permutation boundary) (entries : List Cell)
    (id : CellId) (entry : Value) :
    replaceCell (entries.map (cell rename.forward)) (rename.forward id) (value rename.forward entry) =
      (replaceCell entries id entry).map (cell rename.forward) := by
  induction entries with
  | nil => rfl
  | cons first rest induction =>
      by_cases same : first.id = id
      · simp [replaceCell, cell, same, induction]
      · have different : rename.forward first.id ≠ rename.forward id :=
          fun equal => same (rename.injective equal)
        simp [replaceCell, cell, same, different, induction]

theorem assignCell (rename : Permutation boundary) (before : State) (id : CellId) (entry : Value) :
    (state rename.forward before).assignCell (rename.forward id) (value rename.forward entry) =
      (before.assignCell id entry).map (state rename.forward) := by
  simp only [State.assignCell, cellEntry, Option.isSome_map]
  split
  · simp [state, replace_cells]
  · rfl

theorem assignLocal (rename : Permutation boundary) (before : State) (id : VarId) (entry : Value) :
    (state rename.forward before).assignLocal id (value rename.forward entry) =
      (before.assignLocal id entry).map (state rename.forward) := by
  simp only [State.assignLocal, cellId]
  cases before.cellId? id <;> simp [assignCell]

end Lanius.Semantics.CellRenaming
