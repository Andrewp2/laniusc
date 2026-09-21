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
      (.returned (some result)) after := by
  intro enoughFuel bound
  have returned := execStmt_return (fuel := enoughFuel - 2) program state argument result after
    (run (enoughFuel - 2) (by omega))
  have returned' : execStmt (enoughFuel - 1) program state
      (.returnValue (some argument)) = .done (.returned (some result)) after := by
    simpa [show enoughFuel - 2 + 1 = enoughFuel - 1 by omega] using returned
  have sequence := execStmt_sequence_completed (fuel := enoughFuel - 1) program state
    (.returnValue (some argument)) .skip (.returned (some result)) after returned' (by simp)
  simpa [show enoughFuel - 1 + 1 = enoughFuel by omega] using sequence

end Lanius.Semantics
