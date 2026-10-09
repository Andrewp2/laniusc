import Lanius.Semantics.Loop
import Lanius.Semantics.Stable

namespace Lanius.Semantics

open Lanius
open Lanius.Core

theorem execStmt_ifThenElse
    (fuel : Nat) (program : Program) (state : State) (condition : Expr)
    (thenBranch elseBranch : Stmt) (conditionValue : Bool)
    (completion : Completion) (conditionAfter after : State)
    (conditionEvaluates : evalExpr fuel program state condition =
      .done (.boolean conditionValue) conditionAfter)
    (selectedExecutes :
      execStmt fuel program conditionAfter
        (if conditionValue then thenBranch else elseBranch) = .done completion after) :
    execStmt fuel.succ program state (.ifThenElse condition thenBranch elseBranch) =
      .done completion after := by
  rw [execStmt.eq_def]
  cases conditionValue
  · simp only [conditionEvaluates]
    simpa using selectedExecutes
  · simp only [conditionEvaluates]
    simpa using selectedExecutes

namespace StableStmt

theorem returnValue (run : StableExpr threshold program state argument value after) :
    StableStmt (threshold + 1) program state (.returnValue (some argument))
      (.returned (some value)) after := by
  intro fuel enough
  simpa [show fuel - 1 + 1 = fuel by omega] using
    execStmt_return (fuel - 1) program state argument value after (run (fuel - 1) (by omega))

theorem sequence_next
    {firstFuel secondFuel : Nat} {program : Program}
    {state middle after : State} {first second : Stmt} {completion : Completion}
    (firstContract : StableStmt firstFuel program state first .next middle)
    (secondContract : StableStmt secondFuel program middle second completion after) :
    StableStmt (max firstFuel secondFuel + 1) program state
      (.sequence first second) completion after := by
  intro fuel enough
  have firstEval := firstContract (fuel - 1) (by omega)
  have secondEval := secondContract (fuel - 1) (by omega)
  simpa [show fuel - 1 + 1 = fuel by omega] using
    (execStmt_sequence_next (fuel := fuel - 1) program state first second
      completion middle after firstEval secondEval)

theorem sequence_completed
    {firstFuel : Nat} {program : Program} {state after : State}
    {first second : Stmt} {completion : Completion}
    (firstContract : StableStmt firstFuel program state first completion after)
    (notNext : completion ≠ .next) :
    StableStmt (firstFuel + 1) program state
      (.sequence first second) completion after := by
  intro fuel enough
  have firstEval := firstContract (fuel - 1) (by omega)
  simpa [show fuel - 1 + 1 = fuel by omega] using
    (execStmt_sequence_completed (fuel := fuel - 1) program state first second
      completion after firstEval notNext)

theorem ifThenElse_true
    {conditionFuel branchFuel : Nat} {program : Program} {state conditionAfter after : State}
    {condition : Expr} {thenBranch elseBranch : Stmt} {completion : Completion}
    (conditionRun : ∀ fuel, conditionFuel ≤ fuel →
      evalExpr fuel program state condition = .done (.boolean true) conditionAfter)
    (thenContract : StableStmt branchFuel program conditionAfter thenBranch completion after) :
    StableStmt (max conditionFuel branchFuel + 1) program state
      (.ifThenElse condition thenBranch elseBranch) completion after := by
  intro fuel enough
  have conditionEval := conditionRun (fuel - 1) (by omega)
  have thenEval := thenContract (fuel - 1) (by omega)
  simpa [show fuel - 1 + 1 = fuel by omega] using
    (execStmt_ifThenElse (fuel := fuel - 1) program state condition
      thenBranch elseBranch true completion conditionAfter after conditionEval thenEval)

theorem ifThenElse_false
    {conditionFuel branchFuel : Nat} {program : Program} {state : State}
    {conditionAfter after : State} {condition : Expr} {thenBranch elseBranch : Stmt}
    {completion : Completion}
    (conditionRun : ∀ fuel, conditionFuel ≤ fuel →
      evalExpr fuel program state condition = .done (.boolean false) conditionAfter)
    (elseContract : StableStmt branchFuel program conditionAfter elseBranch completion after) :
    StableStmt (max conditionFuel branchFuel + 1) program state
      (.ifThenElse condition thenBranch elseBranch) completion after := by
  intro fuel enough
  have conditionEval := conditionRun (fuel - 1) (by omega)
  have elseEval := elseContract (fuel - 1) (by omega)
  simpa [show fuel - 1 + 1 = fuel by omega] using
    (execStmt_ifThenElse (fuel := fuel - 1) program state condition
      thenBranch elseBranch false completion conditionAfter after conditionEval elseEval)

end StableStmt

/-! A stable expression result lifted through Core's return/skip sequence. -/
theorem StableStmt.returnValueSequence
    (program : Program) (state : State) (argument : Expr) (result : Value)
    {fuel : Nat} {after : State}
    (run : StableExpr fuel program state argument result after) :
    StableStmt (fuel + 2) program state
      (.sequence (.returnValue (some argument)) .skip)
      (.returned (some result)) after :=
  StableStmt.sequence_completed (StableStmt.returnValue run) (by simp)

end Lanius.Semantics
