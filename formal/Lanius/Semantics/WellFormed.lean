import Lanius.Semantics

namespace Lanius.Semantics

open Lanius
open Lanius.Core

/-! The cell frontier is the only allocation invariant needed by the
    first executable-state proofs: every stored cell has an id below the
    next id, so the frontier is fresh. -/

def State.CellsWellFormed (state : State) : Prop :=
  ∀ cell ∈ state.cells, cell.id < state.nextCell

theorem State.CellsWellFormed.cellEntry_nextCell
    {state : State} (formed : state.CellsWellFormed) :
    state.cellEntry? state.nextCell = none := by
  unfold State.cellEntry?
  apply List.find?_eq_none.mpr
  intro cell member
  simp [Nat.ne_of_lt (formed cell member)]

theorem State.CellsWellFormed.bindLocal_local
    {state : State} (formed : state.CellsWellFormed)
    (id : VarId) (value : Value) :
    (state.bindLocal id value).local? id = some value := by
  have oldFind :
      state.cells.find? (fun cell => cell.id == state.nextCell) = none := by
    exact formed.cellEntry_nextCell
  simp [State.local?, State.cellId?, State.cell?, State.cellEntry?,
    State.bindLocal, State.bindCell, oldFind]

theorem State.CellsWellFormed.bindCell
    {state : State} (formed : state.CellsWellFormed)
    (id : VarId) (value : Option Value) :
    (state.bindCell id value).CellsWellFormed := by
  intro cell member
  change cell.id < state.nextCell + 1 at *
  simp only [State.bindCell] at member
  rcases List.mem_append.mp member with old | last
  · exact Nat.lt_succ_of_lt (formed cell old)
  · simp only [List.mem_singleton] at last
    subst cell
    exact Nat.lt_succ_self _

theorem State.CellsWellFormed.allocateTemporary
    {state : State} (formed : state.CellsWellFormed) (value : Value) :
    (state.allocateTemporary value).2.CellsWellFormed := by
  intro cell member
  change cell.id < state.nextCell + 1 at *
  simp only [State.allocateTemporary] at member
  rcases List.mem_append.mp member with old | last
  · exact Nat.lt_succ_of_lt (formed cell old)
  · simp only [List.mem_singleton] at last
    subst cell
    exact Nat.lt_succ_self _

theorem State.CellsWellFormed.bindLocal
    {state : State} (formed : state.CellsWellFormed)
    (id : VarId) (value : Value) :
    (state.bindLocal id value).CellsWellFormed := by
  exact formed.bindCell id (some value)

theorem State.CellsWellFormed.bindLocals
    {state : State} (formed : state.CellsWellFormed)
    (bindings : List (VarId × Value)) :
    (state.bindLocals bindings).CellsWellFormed := by
  induction bindings generalizing state with
  | nil => simpa [State.bindLocals]
  | cons binding rest inductionHypothesis =>
      simp only [State.bindLocals, List.foldl_cons]
      exact inductionHypothesis (formed.bindLocal binding.1 binding.2)

end Lanius.Semantics
