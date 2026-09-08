import Lanius.Semantics.CellRenaming.Access

namespace Lanius.Semantics.CellRenaming
open Lanius.Core

def bindings (rename : CellId → CellId) (entries : List (VarId × Value)) : List (VarId × Value) :=
  entries.map fun entry => (entry.1, value rename entry.2)

theorem bindLocals_ready (before : State) (entries : List (VarId × Value))
    (ready : boundary ≤ before.nextCell) : boundary ≤ (before.bindLocals entries).nextCell := by
  induction entries generalizing before with
  | nil => exact ready
  | cons first rest induction =>
      exact induction (before.bindLocal first.1 first.2)
        (Nat.le_trans ready (Nat.le_succ before.nextCell))

theorem bindLocal (rename : Permutation boundary) (before : State)
    (ready : boundary ≤ before.nextCell) (id : VarId) (entry : Value) :
    state rename.forward (before.bindLocal id entry) =
      (state rename.forward before).bindLocal id (value rename.forward entry) :=
  bindCell rename before ready id (some entry)

theorem bindLocals (rename : Permutation boundary) (before : State)
    (ready : boundary ≤ before.nextCell) (entries : List (VarId × Value)) :
    state rename.forward (before.bindLocals entries) =
      (state rename.forward before).bindLocals (bindings rename.forward entries) := by
  induction entries generalizing before with
  | nil => rfl
  | cons first rest induction =>
      simp only [State.bindLocals, bindings, List.map_cons, List.foldl_cons]
      rw [← bindLocal rename before ready]
      exact induction (before.bindLocal first.1 first.2)
        (Nat.le_trans ready (Nat.le_succ before.nextCell))

theorem restoreLocals (rename : CellId → CellId) (caller completed : State) :
    state rename (Semantics.restoreLocals caller completed) =
      Semantics.restoreLocals (state rename caller) (state rename completed) := rfl

private theorem zipParameters (rename : CellId → CellId)
    (parameters : List (VarId × Ty)) (arguments : List Value) :
    (parameters.zip (arguments.map (value rename))).map (fun pair => (pair.1.1, pair.2)) =
      bindings rename ((parameters.zip arguments).map fun pair => (pair.1.1, pair.2)) := by
  induction parameters generalizing arguments with
  | nil => rfl
  | cons first rest induction =>
      cases arguments with
      | nil => rfl
      | cons argument arguments => simp [List.zip_cons_cons, bindings, induction]

theorem bindParameters (rename : CellId → CellId)
    (parameters : List (VarId × Ty)) (arguments : List Value) :
    Semantics.bindParameters parameters (values rename arguments) =
      (Semantics.bindParameters parameters arguments).map (bindings rename) := by
  simp only [Semantics.bindParameters, values_eq_map, List.length_map]
  split <;> simp [zipParameters]

end Lanius.Semantics.CellRenaming
