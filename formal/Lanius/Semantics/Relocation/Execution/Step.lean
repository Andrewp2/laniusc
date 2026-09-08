import Lanius.Semantics.Relocation.Pointers
import Lanius.Semantics.Relocation.Pattern
import Lanius.Semantics.Relocation.Access
-- Reuse canonical generated evaluator congruences across semantic proofs.
import Lanius.ProgramSemanticsAgreement

namespace Lanius.Semantics.Relocation.Execution

open Lanius.Core

/-- Induction interface for one fuel layer. This is an explicit premise of
the step lemmas, not an axiom or an assertion that transport is established. -/
structure Step (fuel : Nat) (symbols : Core.Relocation.Symbols) (smaller larger : Program) : Prop where
  expression : ∀ {before expression value after},
    evalExpr fuel smaller before expression = .done value after →
    evalExpr fuel larger (state symbols before) (Core.Relocation.expression symbols expression) =
      .done (Core.Relocation.value symbols value) (state symbols after)
  expressions : ∀ {before expressions values after},
    evalExprs fuel smaller before expressions = .done values after →
    evalExprs fuel larger (state symbols before) (Core.Relocation.expressions symbols expressions) =
      .done (Core.Relocation.values symbols values) (state symbols after)
  arms : ∀ {before value arms result after},
    evalMatchArms fuel smaller before value arms = .done result after →
    evalMatchArms fuel larger (state symbols before) (Core.Relocation.value symbols value)
        (Core.Relocation.arms symbols arms) =
      .done (Core.Relocation.value symbols result) (state symbols after)
  place : ∀ {before place result after},
    evalPlace fuel smaller before place = .done result after →
    evalPlace fuel larger (state symbols before) (Core.Relocation.place symbols place) =
      .done (resolvedPlace symbols result) (state symbols after)
  forValues : ∀ {before id values body result after},
    execForValues fuel smaller before id values body = .done result after →
    execForValues fuel larger (state symbols before) id (Core.Relocation.values symbols values)
        (Core.Relocation.statement symbols body) =
      .done (completion symbols result) (state symbols after)
  forRange : ∀ {before id current stop inclusive body result after},
    execForRange fuel smaller before id current stop inclusive body = .done result after →
    execForRange fuel larger (state symbols before) id current stop inclusive
        (Core.Relocation.statement symbols body) =
      .done (completion symbols result) (state symbols after)
  statement : ∀ {before statement result after},
    execStmt fuel smaller before statement = .done result after →
    execStmt fuel larger (state symbols before) (Core.Relocation.statement symbols statement) =
      .done (completion symbols result) (state symbols after)

theorem zero (symbols : Core.Relocation.Symbols) (smaller larger : Program) :
    Step 0 symbols smaller larger := by
  constructor <;> intros <;>
    simp [evalExpr, evalExprs, evalMatchArms, evalPlace, execForValues, execForRange, execStmt] at *

theorem restoredStatement (step : Step fuel symbols smaller larger)
    (caller before : State) (body : Stmt) (result : Completion) (after : State)
    (executed : Semantics.restoreOutcomeLocals caller (execStmt fuel smaller before body) = .done result after) :
    Semantics.restoreOutcomeLocals (state symbols caller)
      (execStmt fuel larger (state symbols before) (Core.Relocation.statement symbols body)) =
        .done (completion symbols result) (state symbols after) := by
  cases run : execStmt fuel smaller before body with
  | done value completed =>
      rw [step.statement run]
      simp only [run, Semantics.restoreOutcomeLocals, Outcome.done.injEq] at executed
      obtain ⟨rfl, rfl⟩ := executed
      rfl
  | _ => simp [run, Semantics.restoreOutcomeLocals] at executed

end Lanius.Semantics.Relocation.Execution
