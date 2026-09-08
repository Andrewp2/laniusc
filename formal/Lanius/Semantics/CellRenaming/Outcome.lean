import Lanius.Semantics.CellRenaming.CallState

namespace Lanius.Semantics.CellRenaming

open Lanius.Core

def completion (rename : CellId → CellId) : Completion → Completion
  | .next => .next
  | .returned contents => .returned (contents.map (value rename))
  | .breakLoop => .breakLoop
  | .continueLoop => .continueLoop

def outcome (rename : CellId → CellId) (mapValue : α → β) : Outcome α → Outcome β
  | .done value after => .done (mapValue value) (state rename after)
  | .trapped reason after => .trapped reason (state rename after)
  | .exited code after => .exited code (state rename after)
  | .outOfFuel => .outOfFuel

theorem restoreOutcomeLocals (rename : CellId → CellId) (mapValue : α → β)
    (caller : State) (result : Outcome α) :
    Semantics.restoreOutcomeLocals (state rename caller) (outcome rename mapValue result) =
      outcome rename mapValue (Semantics.restoreOutcomeLocals caller result) := by
  cases result <;> rfl

theorem completion_leftInverse (outer inner : CellId → CellId)
    (inverse : Function.LeftInverse outer inner) (result : Completion) :
    completion outer (completion inner result) = result := by
  cases result with
  | returned value =>
      cases value <;> simp [completion, value_leftInverse outer inner inverse]
  | _ => rfl

theorem outcome_leftInverse (outer inner : CellId → CellId)
    (inverse : Function.LeftInverse outer inner) (mapInner : α → β) (mapOuter : β → α)
    (valueInverse : Function.LeftInverse mapOuter mapInner) (result : Outcome α) :
    outcome outer mapOuter (outcome inner mapInner result) = result := by
  have values : ∀ v, mapOuter (mapInner v) = v := valueInverse
  cases result <;> simp [outcome, state_leftInverse outer inner inverse, values]

end Lanius.Semantics.CellRenaming
