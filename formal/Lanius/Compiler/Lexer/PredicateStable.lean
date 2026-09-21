import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.Predicate
import Lanius.Compiler.Lexer.Composition

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

/-! A byte predicate remains valid at every fuel value above its threshold,
    with the evaluator's exact post-call frame made explicit existentially. -/
def ThresholdBytePredicate (threshold : Nat) (functionId : FunctionId)
    (spec : Byte → Bool) : Prop :=
  ∀ byte before, before.CellsWellFormed →
    ∃ after, ThresholdPure threshold Artifact.lexerProgram before
      (unaryI32PredicateCall functionId (Int.ofNat byte.val))
      (.boolean (spec byte)) after

theorem thresholdUnaryI32ValueCall
    (program : Program) (caller : State)
    (functionId parameter : Nat) (predicate : UnaryI32Predicate) (input : Int)
    (found : program.function? functionId =
      some (unaryI32PredicateFunction functionId parameter predicate))
    (formed : caller.CellsWellFormed) :
    ThresholdPure (predicate.exprFuel + 3) program caller
      (.call functionId [.value (.signed .i32 input)])
      (.boolean (predicate.accepts input))
      (restoreLocals caller
        (({ caller with locals := [] }).bindLocal parameter
          (.signed .i32 input))) := by
  let value : Value := .signed .i32 input
  let callee : State := ({ caller with locals := [] }).bindLocal parameter value
  let after : State := restoreLocals caller callee
  refine ⟨?_, ?_⟩
  · intro fuel enough
    apply evalExpr_unaryI32PredicateCall_of_fuel fuel program caller
      functionId parameter predicate (.value value) input found formed enough
    simpa [show fuel - 3 + 1 = fuel - 2 by omega, value] using
      (evalExpr_value (fuel - 3) program caller value)
  · exact ⟨formed, (FreshCellFrame.bindLocal caller parameter value).restoreLocals,
      rfl, rfl, rfl, rfl⟩

theorem whitespace_threshold_stable :
    ThresholdBytePredicate (Artifact.whitespacePredicate.exprFuel + 3)
      Artifact.whitespaceFunction.id isWhitespace := by
  intro byte before formed
  have contract := thresholdUnaryI32ValueCall Artifact.lexerProgram before
    3 0 Artifact.whitespacePredicate (Int.ofNat byte.val)
    (by simpa [Artifact.whitespaceFunction, unaryI32PredicateFunction] using
      Artifact.whitespaceFunction_found) formed
  refine ⟨restoreLocals before
      (({ before with locals := [] }).bindLocal 0
        (.signed .i32 (Int.ofNat byte.val))), ?_⟩
  rw [← whitespacePredicate_accepts byte]
  simpa [Artifact.whitespaceFunction, unaryI32PredicateFunction,
    unaryI32PredicateCall] using contract

theorem identifierContinue_threshold_stable :
    ThresholdBytePredicate 13 Artifact.identifierContinueFunction.id
      isIdentifierContinue := by
  intro byte before formed
  change ∃ after, ThresholdPure 13 Artifact.lexerProgram before
    (unaryI32PredicateCall Artifact.identifierContinueFunction.id
      (Int.ofNat byte.val))
    (.boolean (isIdentifierStart byte || isDecimalDigit byte)) after
  rw [← identifierStartPredicate_accepts byte, ← decimalPredicate_accepts byte]
  rcases thresholdUnaryPredicateOr Artifact.lexerProgram before 0 0 2
    Artifact.identifierStartPredicate Artifact.decimalPredicate (Int.ofNat byte.val)
    (by simpa [Artifact.identifierStartFunction, unaryI32PredicateFunction] using
      Artifact.identifierStartFunction_found)
    (by simpa [Artifact.decimalFunction, unaryI32PredicateFunction] using
      Artifact.decimalFunction_found)
    formed with ⟨after, body⟩
  refine ⟨restoreLocals before after, ?_⟩
  exact thresholdOneParameterCall Artifact.lexerProgram before 1 0
    (.binary .logicalOr (.call 0 [.local 0]) (.call 2 [.local 0]))
    (Int.ofNat byte.val)
    (by simpa [Artifact.identifierContinueFunction, oneParameterBooleanFunction] using
      Artifact.identifierContinueFunction_found)
    formed (by simpa [Artifact.identifierStartPredicate, Artifact.decimalPredicate,
      UnaryI32Predicate.exprFuel] using body)

end Lanius.Compiler.Lexer
