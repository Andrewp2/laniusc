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
      (.binary operation left right) result after := by
  refine ⟨?_, leftRun.frame.trans rightRun.frame⟩
  intro fuel enough
  have leftEval := leftRun.run (fuel - 1) (by omega)
  have rightEval := rightRun.run (fuel - 1) (by omega)
  simpa [show fuel - 1 + 1 = fuel by omega] using
    (evalExpr_binary_done (fuel := fuel - 1) program before operation left right
      leftValue rightValue result middle after leftEval rightEval operationIsEager
      operationEvaluates)

end Lanius.Semantics
