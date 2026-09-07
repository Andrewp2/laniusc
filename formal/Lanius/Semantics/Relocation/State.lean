import Lanius.Core.Relocation
import Lanius.Properties

namespace Lanius.Semantics.Relocation

open Lanius.Core

def cell (symbols : Core.Relocation.Symbols) (entry : Cell) : Cell :=
  { entry with value := entry.value.map (Core.Relocation.value symbols) }

/-- Global-ID relocation does not change memory addresses, cell identity,
lexical bindings, raw views, or the host world. Only tagged language values
carry relocated type IDs. -/
def state (symbols : Core.Relocation.Symbols) (before : State) : State :=
  { before with cells := before.cells.map (cell symbols) }

private theorem find_cells (symbols : Core.Relocation.Symbols) (entries : List Cell) (id : CellId) :
    (entries.map (cell symbols)).find? (fun entry => entry.id == id) =
      (entries.find? (fun entry => entry.id == id)).map (cell symbols) := by
  induction entries with
  | nil => rfl
  | cons first rest induction =>
      by_cases same : first.id == id
      · simp [same, cell]
      · simp [same, cell, induction]

@[simp] theorem cellEntry (symbols : Core.Relocation.Symbols) (before : State) (id : CellId) :
    (state symbols before).cellEntry? id = (before.cellEntry? id).map (cell symbols) :=
  find_cells symbols before.cells id

@[simp] theorem cellValue (symbols : Core.Relocation.Symbols) (before : State) (id : CellId) :
    (state symbols before).cell? id = (before.cell? id).map (Core.Relocation.value symbols) := by
  simp only [State.cell?, cellEntry]
  cases before.cellEntry? id <;> simp [cell]

@[simp] theorem localValue (symbols : Core.Relocation.Symbols) (before : State) (id : VarId) :
    (state symbols before).local? id = (before.local? id).map (Core.Relocation.value symbols) := by
  simp only [State.local?]
  have same : (state symbols before).cellId? id = before.cellId? id := rfl
  rw [same]
  cases before.cellId? id <;> simp [cellValue]

private theorem replace_cells (symbols : Core.Relocation.Symbols) (entries : List Cell)
    (id : CellId) (v : Value) :
    replaceCell (entries.map (cell symbols)) id (Core.Relocation.value symbols v) =
      (replaceCell entries id v).map (cell symbols) := by
  induction entries with
  | nil => rfl
  | cons first rest induction =>
      by_cases same : first.id == id <;> simp [replaceCell, cell, same, induction]

theorem assignCell (symbols : Core.Relocation.Symbols) (before : State) (id : CellId) (v : Value) :
    (state symbols before).assignCell id (Core.Relocation.value symbols v) =
      (before.assignCell id v).map (state symbols) := by
  simp only [State.assignCell, cellEntry, Option.isSome_map]
  split
  · simp [state, replace_cells]
  · rfl

theorem bindCell (symbols : Core.Relocation.Symbols) (before : State)
    (id : VarId) (v : Option Value) :
    state symbols (before.bindCell id v) =
      (state symbols before).bindCell id (v.map (Core.Relocation.value symbols)) := by
  simp [state, State.bindCell, cell]

theorem bindLocal (symbols : Core.Relocation.Symbols) (before : State) (id : VarId) (v : Value) :
    state symbols (before.bindLocal id v) =
      (state symbols before).bindLocal id (Core.Relocation.value symbols v) :=
  bindCell symbols before id (some v)

@[simp] theorem cell_identity (entry : Cell) : cell Core.Relocation.Symbols.identity entry = entry := by
  cases entry with
  | mk id value => cases value <;> simp [cell]

@[simp] theorem state_identity (before : State) : state Core.Relocation.Symbols.identity before = before := by
  have cells : cell Core.Relocation.Symbols.identity = id := funext cell_identity
  simp [state, cells]

theorem cell_leftInverse (outer inner : Core.Relocation.Symbols)
    (inverse : Function.LeftInverse outer.typeId inner.typeId) (entry : Cell) :
    cell outer (cell inner entry) = entry := by
  cases entry with
  | mk id value => cases value <;> simp [cell, Core.Relocation.value_leftInverse outer inner inverse]

theorem state_leftInverse (outer inner : Core.Relocation.Symbols)
    (inverse : Function.LeftInverse outer.typeId inner.typeId) (before : State) :
    state outer (state inner before) = before := by
  simp [state, List.map_map, Function.comp_def, cell_leftInverse outer inner inverse]

theorem state_wellFormed (symbols : Core.Relocation.Symbols)
    (wellFormed : Properties.StateWellFormed before) :
    Properties.StateWellFormed (state symbols before) := by
  constructor
  · exact wellFormed.heapWellFormed
  · intro left leftMember right rightMember sameId
    obtain ⟨oldLeft, oldLeftMember, rfl⟩ := List.mem_map.mp leftMember
    obtain ⟨oldRight, oldRightMember, rfl⟩ := List.mem_map.mp rightMember
    have same := wellFormed.cellIdsUnique oldLeft oldLeftMember oldRight oldRightMember sameId
    rw [same]
  · intro entry member
    obtain ⟨old, oldMember, rfl⟩ := List.mem_map.mp member
    exact wellFormed.cellIdsBelowNext old oldMember
  · intro binding member
    obtain ⟨old, oldMember, same⟩ := wellFormed.localsReferenceCells binding member
    exact ⟨cell symbols old, List.mem_map.mpr ⟨old, oldMember, rfl⟩, same⟩

theorem projectedValue (symbols : Core.Relocation.Symbols) (v : Value) (path : List ValueProjection) :
    Semantics.projectedValue (Core.Relocation.value symbols v) path =
      (Semantics.projectedValue v path).map (Core.Relocation.value symbols) := by
  induction path generalizing v with
  | nil => rfl
  | cons projection rest induction =>
      cases projection <;> cases v <;>
        simp only [Core.Relocation.value, Semantics.projectedValue,
          Core.Relocation.values_eq_map, List.getElem?_map, Except.map]
      all_goals first
        | rfl
        | split <;> simp_all
      all_goals
        rename_i selected
        obtain ⟨original, found, rfl⟩ := selected
        simp only [found]
        exact induction original

theorem readCellProjection (symbols : Core.Relocation.Symbols) (before : State)
    (id : CellId) (path : List ValueProjection) :
    Semantics.readCellProjection (state symbols before) id path =
      (Semantics.readCellProjection before id path).map (Core.Relocation.value symbols) := by
  simp only [Semantics.readCellProjection, cellEntry]
  cases before.cellEntry? id with
  | none => rfl
  | some entry =>
      cases entry with
      | mk id value => cases value <;> simp [cell, projectedValue, Except.map]

end Lanius.Semantics.Relocation
