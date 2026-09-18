import Lanius.Semantics.Capacity.Fragment
import Lanius.Semantics.Capacity.Slice
import Lanius.Semantics.Capacity.Scalar
import Lanius.Semantics.Capacity.Borrowed

namespace Lanius.Semantics.Capacity.Execution
open Lanius.Core

/-- Fuel induction premise, not an assumption exposed by the eventual public
frontend call theorem. Successful execution retains the reachable-root
invariant for the next computation. -/
structure Step (fuel : Nat) (config : Config) (allowed : FunctionId → Bool) (program : Program) : Prop where
  expression : ∀ {before input result after}, Ready config before → Fragment.expression allowed input = true →
    evalExpr fuel program before input = .done result after →
    evalExpr fuel program (state config before) input = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true
  expressions : ∀ {before input result after}, Ready config before → Fragment.expressions allowed input = true →
    evalExprs fuel program before input = .done result after →
    evalExprs fuel program (state config before) input = .done (values config result) (state config after) ∧
      Ready config after ∧ closeds config result = true
  place : ∀ {before input result after}, Ready config before → Fragment.place allowed input = true →
    evalPlace fuel program before input = .done result after →
    evalPlace fuel program (state config before) input = .done (resolvedPlace config result) (state config after) ∧
      Ready config after ∧ PlaceReady config result
  forRange : ∀ {before id current stop inclusive body result after}, Ready config before → Fragment.statement allowed body = true →
    execForRange fuel program before id current stop inclusive body = .done result after →
    execForRange fuel program (state config before) id current stop inclusive body = .done (completion config result) (state config after) ∧
      Ready config after ∧ completionClosed config result
  statement : ∀ {before input result after}, Ready config before → Fragment.statement allowed input = true →
    execStmt fuel program before input = .done result after →
    execStmt fuel program (state config before) input = .done (completion config result) (state config after) ∧
      Ready config after ∧ completionClosed config result

theorem zero (config : Config) (allowed : FunctionId → Bool) (program : Program) : Step 0 config allowed program := by
  constructor <;> intros <;> simp [evalExpr, evalExprs, evalPlace, execForRange, execStmt] at *

theorem restoredStatement (step : Step fuel config allowed program) (callerReady : Ready config caller)
    (ready : Ready config before) (supported : Fragment.statement allowed body = true)
    (executed : restoreOutcomeLocals caller (execStmt fuel program before body) = .done result after) :
    restoreOutcomeLocals (state config caller) (execStmt fuel program (state config before) body) =
        .done (completion config result) (state config after) ∧ Ready config after ∧ completionClosed config result := by
  cases run : execStmt fuel program before body with
  | done returned completed =>
    obtain ⟨transport, nextReady, resultClosed⟩ := step.statement ready supported run
    rw [transport]
    simp only [run, restoreOutcomeLocals, Outcome.done.injEq] at executed
    obtain ⟨rfl, rfl⟩ := executed
    exact ⟨rfl, nextReady.restoreLocals callerReady, resultClosed⟩
  | _ => simp [run, restoreOutcomeLocals] at executed

end Lanius.Semantics.Capacity.Execution
