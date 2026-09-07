import Lanius.Semantics.Relocation.Execution.Step
import Std.Tactic

namespace Lanius.Semantics.Relocation.Execution

open Lanius.Core

private theorem cellId (symbols : Core.Relocation.Symbols) (before : State) (id : VarId) :
    (state symbols before).cellId? id = before.cellId? id := rfl

theorem place (step : Step fuel symbols smaller larger)
    (before : State) (place : Place) (result : ResolvedPlace) (after : State)
    (evaluated : evalPlace (fuel + 1) smaller before place = .done result after) :
    evalPlace (fuel + 1) larger (state symbols before) (Core.Relocation.place symbols place) =
      .done (resolvedPlace symbols result) (state symbols after) := by
  cases place <;> simp only [Core.Relocation.place, evalPlace] at evaluated ⊢
  all_goals
    repeat' first
      | rw [step.expression (by assumption)]
      | rw [step.place (by assumption)]
      | simp_all only [Core.Relocation.value, Core.Relocation.values_eq_map,
          Option.map, Except.map, resolvedPlace, cellId, cellEntry, cell,
          List.getElem?_map, integerIndex, sliceValues]
      | split at evaluated
    all_goals grind only [resolvedPlace, Core.Relocation.value, cell]

end Lanius.Semantics.Relocation.Execution
