import Lanius.Semantics.StmtList

namespace Lanius.Semantics

open Lanius Lanius.Core

/-! A proof-producing binary-expression rule; it carries evaluator fuel and
    caller-frame composition once for all scalar emitter expressions. -/
theorem ThresholdPure.binary
    {leftFuel rightFuel : Nat} {program : Program} {before middle after : State}
    {operation : BinaryOp} {left right : Expr} {leftValue rightValue result : Value}
    (leftRun : ThresholdPure leftFuel program before left leftValue middle)
    (rightRun : ThresholdPure rightFuel program middle right rightValue after)
    (operationIsEager : operation ≠ .logicalAnd ∧ operation ≠ .logicalOr)
    (operationEvaluates : evalBinaryValue program.target operation
      leftValue rightValue = .ok result) :
    ThresholdPure (max leftFuel rightFuel + 1) program before
      (.binary operation left right) result after :=
  ⟨StableExpr.binary leftRun.run rightRun.run operationIsEager operationEvaluates,
    leftRun.frame.trans rightRun.frame⟩

end Lanius.Semantics
