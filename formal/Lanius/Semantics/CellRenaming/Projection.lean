import Lanius.Semantics.CellRenaming.Assignment
import Lanius.Semantics.CellRenaming.Syntax

namespace Lanius.Semantics.CellRenaming

open Lanius.Core

theorem expressionPlace (rename : Permutation boundary) (expression : Expr) :
    expressionPlace? (CellRenaming.expression rename.forward expression) =
      (expressionPlace? expression).map (CellRenaming.place rename.forward) := by
  cases expression <;> simp only [CellRenaming.expression, expressionPlace?]
  all_goals try rfl
  case field base field =>
    rw [expressionPlace rename base]
    cases expressionPlace? base <;> rfl
  case index base index =>
    rw [expressionPlace rename base]
    cases expressionPlace? base <;> rfl
termination_by sizeOf expression

theorem sliceValues (rename : Permutation boundary) (before : State)
    (id : CellId) (path : List ValueProjection) (start length : Nat) :
    Semantics.sliceValues (state rename.forward before) (rename.forward id) path start length =
      (Semantics.sliceValues before id path start length).map (CellRenaming.values rename.forward) := by
  simp only [Semantics.sliceValues, readCellProjection]
  cases Semantics.readCellProjection before id path with
  | error reason => rfl
  | ok v =>
      cases v <;> simp only [Except.map, CellRenaming.value]
      all_goals try rfl
      simp only [CellRenaming.values_eq_map, List.length_map]
      split <;> simp [List.map_take, List.map_drop, Except.map]

theorem dereferenceValue (rename : Permutation boundary) (before : State) (v : Value) :
    Semantics.dereferenceValue (state rename.forward before) (CellRenaming.value rename.forward v) =
      (Semantics.dereferenceValue before v).map (CellRenaming.value rename.forward) := by
  cases v <;> simp only [Semantics.dereferenceValue, CellRenaming.value, readCellProjection] <;> rfl

end Lanius.Semantics.CellRenaming
