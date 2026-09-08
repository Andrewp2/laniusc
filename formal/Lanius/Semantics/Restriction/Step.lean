import Lanius.Semantics.Restriction.Agreement
import Lanius.ProgramSemanticsAgreement
import Lanius.Fuel

namespace Lanius.Semantics.Restriction

open Lanius.Core

theorem expressionPlace_closed (code : Expr) (location : Place)
    (found : expressionPlace? code = some location) (closed : Dependencies.expression allowed code = true) :
    Dependencies.place allowed location = true := by
  cases code with
  | «local» id => cases found; rfl
  | field base field =>
      cases mapped : expressionPlace? base with
      | none => simp [expressionPlace?, mapped] at found
      | some basePlace =>
          have same : location = .field basePlace field := by simpa [expressionPlace?, mapped] using found.symm
          subst location
          exact expressionPlace_closed base basePlace mapped closed
  | index base index =>
      cases mapped : expressionPlace? base with
      | none => simp [expressionPlace?, mapped] at found
      | some basePlace =>
          have same : location = .index basePlace index := by simpa [expressionPlace?, mapped] using found.symm
          subst location
          obtain ⟨baseClosed, indexClosed⟩ := Bool.and_eq_true_iff.mp closed
          exact Bool.and_eq_true_iff.mpr ⟨expressionPlace_closed base basePlace mapped baseClosed, indexClosed⟩
  | _ => simp [expressionPlace?] at found

/-- The induction hypothesis for one fuel layer, restricted to syntax whose
direct calls lie inside the retained dependency set. -/
structure Step (fuel : Nat) (allowed : FunctionId → Bool) (original restricted : Program) : Prop where
  expression : ∀ {before code value after}, evalExpr fuel original before code = .done value after →
    Dependencies.expression allowed code = true → evalExpr fuel restricted before code = .done value after
  expressions : ∀ {before code values after}, evalExprs fuel original before code = .done values after →
    Dependencies.expressions allowed code = true → evalExprs fuel restricted before code = .done values after
  arms : ∀ {before value code result after}, evalMatchArms fuel original before value code = .done result after →
    Dependencies.arms allowed code = true → evalMatchArms fuel restricted before value code = .done result after
  place : ∀ {before code result after}, evalPlace fuel original before code = .done result after →
    Dependencies.place allowed code = true → evalPlace fuel restricted before code = .done result after
  forValues : ∀ {before id values body result after}, execForValues fuel original before id values body = .done result after →
    Dependencies.statement allowed body = true → execForValues fuel restricted before id values body = .done result after
  forRange : ∀ {before id current stop inclusive body result after},
    execForRange fuel original before id current stop inclusive body = .done result after →
    Dependencies.statement allowed body = true →
    execForRange fuel restricted before id current stop inclusive body = .done result after
  statement : ∀ {before code result after}, execStmt fuel original before code = .done result after →
    Dependencies.statement allowed code = true → execStmt fuel restricted before code = .done result after

theorem zero (allowed : FunctionId → Bool) (original restricted : Program) : Step 0 allowed original restricted := by
  constructor <;> intros <;> simp [evalExpr, evalExprs, evalMatchArms, evalPlace, execForValues, execForRange, execStmt] at *

theorem restoredStatement (step : Step fuel allowed original restricted)
    (caller before : State) (body : Stmt) (result : Completion) (after : State)
    (executed : restoreOutcomeLocals caller (execStmt fuel original before body) = .done result after)
    (closed : Dependencies.statement allowed body = true) :
    restoreOutcomeLocals caller (execStmt fuel restricted before body) = .done result after := by
  cases run : execStmt fuel original before body with
  | done value completed =>
      rw [step.statement run closed]
      simpa only [run, restoreOutcomeLocals] using executed
  | _ => simp [run, restoreOutcomeLocals] at executed

end Lanius.Semantics.Restriction
