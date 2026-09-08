import Lanius.Semantics.CellRenaming.Syntax
import Lanius.Semantics.CellRenaming.Pointers
import Lanius.Semantics.CellRenaming.Pattern
import Lanius.ProgramSemanticsAgreement

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

/-- Fuel induction hypothesis. Every successful subcomputation also preserves
the allocation boundary, allowing the next subcomputation to use the same
permutation. This is a premise, not an assertion of full execution transport. -/
structure Step (fuel : Nat) (rename : Permutation boundary) (program : Program) : Prop where
  expression : ∀ {before input result after}, boundary ≤ before.nextCell →
    evalExpr fuel program before input = .done result after →
    evalExpr fuel program (state rename.forward before) (CellRenaming.expression rename.forward input) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell
  expressions : ∀ {before input result after}, boundary ≤ before.nextCell →
    evalExprs fuel program before input = .done result after →
    evalExprs fuel program (state rename.forward before) (CellRenaming.expressions rename.forward input) =
      .done (values rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell
  arms : ∀ {before input branches result after}, boundary ≤ before.nextCell →
    evalMatchArms fuel program before input branches = .done result after →
    evalMatchArms fuel program (state rename.forward before) (value rename.forward input)
        (CellRenaming.arms rename.forward branches) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell
  place : ∀ {before input result after}, boundary ≤ before.nextCell →
    evalPlace fuel program before input = .done result after →
    evalPlace fuel program (state rename.forward before) (CellRenaming.place rename.forward input) =
      .done (resolvedPlace rename result) (state rename.forward after) ∧ boundary ≤ after.nextCell
  forValues : ∀ {before id input body result after}, boundary ≤ before.nextCell →
    execForValues fuel program before id input body = .done result after →
    execForValues fuel program (state rename.forward before) id (values rename.forward input)
        (CellRenaming.statement rename.forward body) =
      .done (completion rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell
  forRange : ∀ {before id current stop inclusive body result after}, boundary ≤ before.nextCell →
    execForRange fuel program before id current stop inclusive body = .done result after →
    execForRange fuel program (state rename.forward before) id current stop inclusive
        (CellRenaming.statement rename.forward body) =
      .done (completion rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell
  statement : ∀ {before input result after}, boundary ≤ before.nextCell →
    execStmt fuel program before input = .done result after →
    execStmt fuel program (state rename.forward before) (CellRenaming.statement rename.forward input) =
      .done (completion rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell

theorem zero (rename : Permutation boundary) (program : Program) : Step 0 rename program := by
  constructor <;> intros <;>
    simp [evalExpr, evalExprs, evalMatchArms, evalPlace, execForValues, execForRange, execStmt] at *

theorem restoredStatement {rename : Permutation boundary} (step : Step fuel rename program)
    (caller before : State) (body : Stmt) (result : Completion) (after : State)
    (ready : boundary ≤ before.nextCell)
    (executed : Semantics.restoreOutcomeLocals caller (execStmt fuel program before body) = .done result after) :
    Semantics.restoreOutcomeLocals (state rename.forward caller)
      (execStmt fuel program (state rename.forward before) (CellRenaming.statement rename.forward body)) =
        .done (completion rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  cases run : execStmt fuel program before body with
  | done result completed =>
      obtain ⟨transport, nextReady⟩ := step.statement ready run
      rw [transport]
      simp only [run, Semantics.restoreOutcomeLocals, Outcome.done.injEq] at executed
      obtain ⟨rfl, rfl⟩ := executed
      exact ⟨rfl, nextReady⟩
  | _ => simp [run, Semantics.restoreOutcomeLocals] at executed

end Lanius.Semantics.CellRenaming.Execution
