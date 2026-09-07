import Lanius.Semantics.Relocation.CallState

namespace Lanius.Semantics.Relocation

open Lanius.Core

def completion (symbols : Core.Relocation.Symbols) : Completion → Completion
  | .next => .next
  | .returned value => .returned (value.map (Core.Relocation.value symbols))
  | .breakLoop => .breakLoop
  | .continueLoop => .continueLoop

def outcome (symbols : Core.Relocation.Symbols) (mapValue : α → β) : Outcome α → Outcome β
  | .done value after => .done (mapValue value) (state symbols after)
  | .trapped reason after => .trapped reason (state symbols after)
  | .exited code after => .exited code (state symbols after)
  | .outOfFuel => .outOfFuel

theorem restoreOutcomeLocals (symbols : Core.Relocation.Symbols) (mapValue : α → β)
    (caller : State) (result : Outcome α) :
    Semantics.restoreOutcomeLocals (state symbols caller) (outcome symbols mapValue result) =
      outcome symbols mapValue (Semantics.restoreOutcomeLocals caller result) := by
  cases result <;> rfl

theorem completion_leftInverse (outer inner : Core.Relocation.Symbols)
    (inverse : Function.LeftInverse outer.typeId inner.typeId) (result : Completion) :
    completion outer (completion inner result) = result := by
  cases result with
  | returned value =>
      cases value <;> simp [completion, Core.Relocation.value_leftInverse outer inner inverse]
  | _ => rfl

theorem outcome_leftInverse (outer inner : Core.Relocation.Symbols)
    (inverse : Function.LeftInverse outer.typeId inner.typeId) (mapInner : α → β) (mapOuter : β → α)
    (valueInverse : Function.LeftInverse mapOuter mapInner) (result : Outcome α) :
    outcome outer mapOuter (outcome inner mapInner result) = result := by
  have values : ∀ v, mapOuter (mapInner v) = v := valueInverse
  cases result <;> simp [outcome, state_leftInverse outer inner inverse, values]

end Lanius.Semantics.Relocation
