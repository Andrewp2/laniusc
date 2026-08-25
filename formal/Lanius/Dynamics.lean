import Lanius.Fuel

namespace Lanius.Dynamics

open Lanius
open Lanius.Core
open Lanius.Semantics

/-- Fuel-independent expression evaluation. A witness supplies enough fuel to
    reach a genuine language observation; `outOfFuel` is not one. -/
def ExprEvaluatesTo
    (program : Program) (state : State) (expression : Expr)
    (result : Outcome Value) : Prop :=
  Fuel.Terminal result ∧ ∃ fuel, evalExpr fuel program state expression = result

/-- Fuel-independent statement execution. -/
def StmtExecutesTo
    (program : Program) (state : State) (statement : Stmt)
    (result : Outcome Completion) : Prop :=
  Fuel.Terminal result ∧ ∃ fuel, execStmt fuel program state statement = result

/-- Fuel-independent whole-program termination. Ordinary return, explicit
    process exit, and terminal trap are observations; exhaustion of a chosen
    evaluator bound is not. -/
def ExecutionTerminatesWith
    (executable : Execution.Executable) (initial : State)
    (result : Execution.Result) : Prop :=
  Fuel.ExecutionTerminal result ∧
    ∃ fuel, Execution.run fuel executable initial = result

/-- A program diverges when every finite evaluator approximation exhausts its
    fuel. This is deliberately stronger than observing `outOfFuel` once. -/
def ExecutionDiverges
    (executable : Execution.Executable) (initial : State) : Prop :=
  ∀ fuel, Execution.run fuel executable initial = .outOfFuel

theorem ExprEvaluatesTo.deterministic
    (first : ExprEvaluatesTo program state expression firstResult)
    (second : ExprEvaluatesTo program state expression secondResult) :
    firstResult = secondResult := by
  rcases first with ⟨firstTerminal, firstFuel, firstEvaluated⟩
  rcases second with ⟨secondTerminal, secondFuel, secondEvaluated⟩
  have firstActualTerminal :
      Fuel.Terminal (evalExpr firstFuel program state expression) := by
    simpa [firstEvaluated] using firstTerminal
  have secondActualTerminal :
      Fuel.Terminal (evalExpr secondFuel program state expression) := by
    simpa [secondEvaluated] using secondTerminal
  have firstStable := Fuel.evalExpr_more_fuel
    (fuel := firstFuel) (extra := secondFuel) firstActualTerminal
  have secondStable := Fuel.evalExpr_more_fuel
    (fuel := secondFuel) (extra := firstFuel) secondActualTerminal
  calc
    firstResult = evalExpr firstFuel program state expression := firstEvaluated.symm
    _ = evalExpr (secondFuel + firstFuel) program state expression := firstStable.symm
    _ = evalExpr (firstFuel + secondFuel) program state expression := by
      rw [Nat.add_comm]
    _ = evalExpr secondFuel program state expression := secondStable
    _ = secondResult := secondEvaluated

theorem StmtExecutesTo.deterministic
    (first : StmtExecutesTo program state statement firstResult)
    (second : StmtExecutesTo program state statement secondResult) :
    firstResult = secondResult := by
  rcases first with ⟨firstTerminal, firstFuel, firstExecuted⟩
  rcases second with ⟨secondTerminal, secondFuel, secondExecuted⟩
  have firstActualTerminal :
      Fuel.Terminal (execStmt firstFuel program state statement) := by
    simpa [firstExecuted] using firstTerminal
  have secondActualTerminal :
      Fuel.Terminal (execStmt secondFuel program state statement) := by
    simpa [secondExecuted] using secondTerminal
  have firstStable := Fuel.execStmt_more_fuel
    (fuel := firstFuel) (extra := secondFuel) firstActualTerminal
  have secondStable := Fuel.execStmt_more_fuel
    (fuel := secondFuel) (extra := firstFuel) secondActualTerminal
  calc
    firstResult = execStmt firstFuel program state statement := firstExecuted.symm
    _ = execStmt (secondFuel + firstFuel) program state statement := firstStable.symm
    _ = execStmt (firstFuel + secondFuel) program state statement := by
      rw [Nat.add_comm]
    _ = execStmt secondFuel program state statement := secondStable
    _ = secondResult := secondExecuted

theorem ExecutionTerminatesWith.deterministic
    (first : ExecutionTerminatesWith executable initial firstResult)
    (second : ExecutionTerminatesWith executable initial secondResult) :
    firstResult = secondResult := by
  rcases first with ⟨firstTerminal, firstFuel, firstExecuted⟩
  rcases second with ⟨secondTerminal, secondFuel, secondExecuted⟩
  have firstActualTerminal :
      Fuel.ExecutionTerminal (Execution.run firstFuel executable initial) := by
    simpa [firstExecuted] using firstTerminal
  have secondActualTerminal :
      Fuel.ExecutionTerminal (Execution.run secondFuel executable initial) := by
    simpa [secondExecuted] using secondTerminal
  have firstStable := Fuel.execution_more_fuel
    (fuel := firstFuel) (extra := secondFuel) firstActualTerminal
  have secondStable := Fuel.execution_more_fuel
    (fuel := secondFuel) (extra := firstFuel) secondActualTerminal
  calc
    firstResult = Execution.run firstFuel executable initial := firstExecuted.symm
    _ = Execution.run (secondFuel + firstFuel) executable initial := firstStable.symm
    _ = Execution.run (firstFuel + secondFuel) executable initial := by
      rw [Nat.add_comm]
    _ = Execution.run secondFuel executable initial := secondStable
    _ = secondResult := secondExecuted

theorem ExecutionTerminatesWith.not_diverges
    (terminates : ExecutionTerminatesWith executable initial result) :
    ¬ ExecutionDiverges executable initial := by
  rintro diverges
  rcases terminates with ⟨terminal, fuel, evaluated⟩
  have exhausted := diverges fuel
  rw [evaluated] at exhausted
  cases result <;> simp [Fuel.ExecutionTerminal] at terminal exhausted

end Lanius.Dynamics
