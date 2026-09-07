import Lanius.Semantics.Relocation.State

namespace Lanius.Semantics.Relocation

open Lanius.Core

theorem expressionPlace (symbols : Core.Relocation.Symbols) (expression : Expr) :
    expressionPlace? (Core.Relocation.expression symbols expression) =
      (expressionPlace? expression).map (Core.Relocation.place symbols) := by
  cases expression <;> simp only [Core.Relocation.expression, expressionPlace?]
  all_goals try rfl
  case field base field =>
    rw [expressionPlace symbols base]
    cases expressionPlace? base <;> rfl
  case index base index =>
    rw [expressionPlace symbols base]
    cases expressionPlace? base <;> rfl
termination_by sizeOf expression

theorem sliceValues (symbols : Core.Relocation.Symbols) (before : State)
    (id : CellId) (path : List ValueProjection) (start length : Nat) :
    Semantics.sliceValues (state symbols before) id path start length =
      (Semantics.sliceValues before id path start length).map (Core.Relocation.values symbols) := by
  simp only [Semantics.sliceValues, readCellProjection]
  cases Semantics.readCellProjection before id path with
  | error reason => rfl
  | ok v =>
      cases v <;> simp only [Except.map, Core.Relocation.value]
      all_goals try rfl
      simp only [Core.Relocation.values_eq_map, List.length_map]
      split <;> simp [List.map_take, List.map_drop, Except.map]

theorem dereferenceValue (symbols : Core.Relocation.Symbols) (before : State) (v : Value) :
    Semantics.dereferenceValue (state symbols before) (Core.Relocation.value symbols v) =
      (Semantics.dereferenceValue before v).map (Core.Relocation.value symbols) := by
  cases v <;> simp only [Semantics.dereferenceValue, Core.Relocation.value, readCellProjection] <;> rfl

end Lanius.Semantics.Relocation
