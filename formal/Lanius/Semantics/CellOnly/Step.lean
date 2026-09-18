import Lanius.Semantics.CellOnly.Syntax
import Lanius.Separation.HeapFrame

namespace Lanius.Semantics.CellOnly

open Lanius.Core Lanius.Separation Lanius.Properties

/-- Induction on evaluator fuel, shared by expressions, places, and loops.
This is discharged once for the language fragment, not by each source proof. -/
structure Step (fuel : Nat) (program : Program) (allowed : FunctionId → Bool) : Prop where
  expression : ∀ {before input result after}, expression allowed input = true →
    evalExpr fuel program before input = .done result after → HeapFrame before after
  expressions : ∀ {before input result after}, expressions allowed input = true →
    evalExprs fuel program before input = .done result after → HeapFrame before after
  place : ∀ {before input result after}, place allowed input = true →
    evalPlace fuel program before input = .done result after → HeapFrame before after
  forRange : ∀ {before id current stop inclusive body result after}, statement allowed body = true →
    execForRange fuel program before id current stop inclusive body = .done result after → HeapFrame before after
  statement : ∀ {before input result after}, statement allowed input = true →
    execStmt fuel program before input = .done result after → HeapFrame before after

theorem zero (program : Program) (allowed : FunctionId → Bool) : Step 0 program allowed := by
  constructor <;> intros <;> simp [evalExpr, evalExprs, evalPlace, execForRange, execStmt] at *

theorem restoredStatement (step : Step fuel program allowed)
    (supported : statement allowed body = true)
    (executed : restoreOutcomeLocals caller (execStmt fuel program before body) = .done result after) :
    HeapFrame before after := by
  cases run : execStmt fuel program before body with
  | done returned completed =>
    have frame := step.statement supported run
    simp only [run, restoreOutcomeLocals, Outcome.done.injEq] at executed
    obtain ⟨rfl, rfl⟩ := executed
    exact ⟨frame.heap, frame.views⟩
  | _ => simp [run, restoreOutcomeLocals] at executed

end Lanius.Semantics.CellOnly
