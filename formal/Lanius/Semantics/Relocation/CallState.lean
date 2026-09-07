import Lanius.Semantics.Relocation.State

namespace Lanius.Semantics.Relocation

open Lanius.Core

def bindings (symbols : Core.Relocation.Symbols) (entries : List (VarId × Value)) :=
  entries.map fun entry => (entry.1, Core.Relocation.value symbols entry.2)

theorem bindLocals (symbols : Core.Relocation.Symbols) (before : State)
    (entries : List (VarId × Value)) :
    state symbols (before.bindLocals entries) =
      (state symbols before).bindLocals (bindings symbols entries) := by
  induction entries generalizing before with
  | nil => rfl
  | cons first rest induction =>
      simp only [State.bindLocals, bindings, List.map_cons, List.foldl_cons]
      rw [← bindLocal]
      exact induction (before.bindLocal first.1 first.2)

theorem unbindLocal (symbols : Core.Relocation.Symbols) (before : State) (id : VarId) :
    state symbols (before.unbindLocal id) = (state symbols before).unbindLocal id := rfl

theorem unbindLocals (symbols : Core.Relocation.Symbols) (before : State)
    (entries : List (VarId × Value)) :
    state symbols (before.unbindLocals entries) =
      (state symbols before).unbindLocals (bindings symbols entries) := by
  induction entries generalizing before with
  | nil => rfl
  | cons first rest induction =>
      simp only [State.unbindLocals, bindings, List.map_cons, List.foldl_cons]
      exact induction (before.unbindLocal first.1)

theorem allocateTemporary (symbols : Core.Relocation.Symbols) (before : State) (v : Value) :
    (state symbols before).allocateTemporary (Core.Relocation.value symbols v) =
      let allocated := before.allocateTemporary v
      (allocated.1, state symbols allocated.2) := by
  simp [State.allocateTemporary, state, cell]

theorem restoreLocals (symbols : Core.Relocation.Symbols) (caller completed : State) :
    state symbols (Semantics.restoreLocals caller completed) =
      Semantics.restoreLocals (state symbols caller) (state symbols completed) := rfl

private theorem zipParameters (symbols : Core.Relocation.Symbols)
    (parameters : List (VarId × Ty)) (arguments : List Value) :
    ((parameters.map fun p => (p.1, Core.Relocation.ty symbols p.2)).zip
        (arguments.map (Core.Relocation.value symbols))).map (fun pair => (pair.1.1, pair.2)) =
      bindings symbols ((parameters.zip arguments).map fun pair => (pair.1.1, pair.2)) := by
  induction parameters generalizing arguments with
  | nil => rfl
  | cons first rest induction =>
      cases arguments with
      | nil => rfl
      | cons argument arguments =>
          simp [List.zip_cons_cons, bindings, induction]

theorem bindParameters (symbols : Core.Relocation.Symbols)
    (parameters : List (VarId × Ty)) (arguments : List Value) :
    Semantics.bindParameters (parameters.map fun p => (p.1, Core.Relocation.ty symbols p.2))
        (Core.Relocation.values symbols arguments) =
      (Semantics.bindParameters parameters arguments).map (bindings symbols) := by
  simp only [Semantics.bindParameters, Core.Relocation.values_eq_map, List.length_map]
  split <;> simp [zipParameters]

end Lanius.Semantics.Relocation
