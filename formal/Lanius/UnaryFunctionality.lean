import Lanius.ContextualFunctionality

namespace Lanius.ProgramElaboration

open Lanius

private theorem contextualScalarLiteralApplies_of_unaryLiteral
    (lowered : Elaboration.LiteralElaborates target literal
      (.scalar scalarType) coreOperand)
    (typed : Typing.UnaryOpHasType (SurfaceElaboration.lowerUnaryOp op)
      (.scalar scalarType) (.scalar scalarType)) :
    SurfaceElaboration.ContextualScalarLiteralApplies target
      (.unary op (.literal literal)) scalarType := by
  cases op <;> cases literal <;>
    simp only [SurfaceElaboration.ContextualScalarLiteralApplies]
  all_goals first
    | exact ⟨_, lowered, typed⟩
    | exact Or.inl ⟨_, lowered, typed⟩

theorem ExprCheckingSpecializationFunctional.unaryLiteral
    {op : Surface.UnaryOp} {literal : Surface.Literal} :
    ExprCheckingSpecializationFunctional (.unary op (.literal literal)) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts expected leftGround
    leftCore rightGround rightCore complete left right
  have inferenceFunctional : ExprInferenceSpecializationFunctional
      (.unary op (.literal literal)) :=
    ExprInferenceSpecializationFunctional.unary
      ExprInferenceSpecializationFunctional.literal
  cases left with
  | exact leftInferred _leftSymbolic _leftGrounds _leftConcrete =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          exact (inferenceFunctional complete leftInferred rightInferred).2
      | signedMinimumLiteral rightMinimum =>
          cases leftInferred with
          | signedMinimumLiteral leftMinimum =>
              cases leftMinimum.core_unique rightMinimum
              exact ⟨rfl, rfl⟩
          | unaryScalar leftOperand leftTyped =>
              cases leftOperand with
              | literal leftPositive =>
                  have typeEquality := leftTyped.input_eq_output
                  injection typeEquality with scalarEquality
                  cases scalarEquality
                  exact (rightMinimum.not_positive_literal leftPositive).elim
      | unaryLiteral rightLowered rightTyped =>
          cases leftInferred with
          | signedMinimumLiteral leftMinimum =>
              cases rightTyped
              exact (leftMinimum.not_positive_literal rightLowered).elim
          | unaryScalar leftOperand leftTyped =>
              cases leftOperand with
              | literal leftLowered =>
                  have typeEquality := leftTyped.input_eq_output
                  injection typeEquality with scalarEquality
                  cases scalarEquality
                  rw [literalDefaultType_eq_scalar] at leftLowered
                  cases leftLowered.core_unique rightLowered
                  exact ⟨rfl, rfl⟩
      | scalarCast rightInferred _rightSymbolic _rightConcrete
          _rightNotContextual rightDifferent _rightConversion =>
          rcases inferenceFunctional complete leftInferred rightInferred with
            ⟨typeEquality, _, _⟩
          injection typeEquality with scalarEquality
          exact (rightDifferent scalarEquality.symm).elim
      | arrayToSlice rightArray _rightSymbolic _rightConcrete
          _rightElementGrounds _rightElementCore =>
          cases rightArray
  | signedMinimumLiteral leftMinimum =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          cases rightInferred with
          | signedMinimumLiteral rightMinimum =>
              cases leftMinimum.core_unique rightMinimum
              exact ⟨rfl, rfl⟩
          | unaryScalar rightOperand rightTyped =>
              cases rightOperand with
              | literal rightPositive =>
                  have typeEquality := rightTyped.input_eq_output
                  injection typeEquality with scalarEquality
                  cases scalarEquality
                  exact (leftMinimum.not_positive_literal rightPositive).elim
      | signedMinimumLiteral rightMinimum =>
          cases leftMinimum.core_unique rightMinimum
          exact ⟨rfl, rfl⟩
      | unaryLiteral rightLowered rightTyped =>
          cases rightTyped
          exact (leftMinimum.not_positive_literal rightLowered).elim
      | scalarCast _rightInferred _rightSymbolic _rightConcrete
          rightNotContextual _rightDifferent _rightConversion =>
          exact (rightNotContextual (by
            simp only [SurfaceElaboration.ContextualScalarLiteralApplies]
            exact Or.inr ⟨_, _, rfl, leftMinimum⟩)).elim
  | unaryLiteral leftLowered leftTyped =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          cases rightInferred with
          | signedMinimumLiteral rightMinimum =>
              cases leftTyped
              exact (rightMinimum.not_positive_literal leftLowered).elim
          | unaryScalar rightOperand rightTyped =>
              cases rightOperand with
              | literal rightLowered =>
                  have typeEquality := rightTyped.input_eq_output
                  injection typeEquality with scalarEquality
                  cases scalarEquality
                  rw [literalDefaultType_eq_scalar] at rightLowered
                  cases leftLowered.core_unique rightLowered
                  exact ⟨rfl, rfl⟩
      | signedMinimumLiteral rightMinimum =>
          cases leftTyped
          exact (rightMinimum.not_positive_literal leftLowered).elim
      | unaryLiteral rightLowered rightTyped =>
          cases leftLowered.core_unique rightLowered
          exact ⟨rfl, rfl⟩
      | scalarCast _rightInferred _rightSymbolic _rightConcrete
          rightNotContextual _rightDifferent _rightConversion =>
          exact (rightNotContextual
            (contextualScalarLiteralApplies_of_unaryLiteral leftLowered
              leftTyped)).elim
  | scalarCast leftInferred _leftSymbolic _leftConcrete leftNotContextual
      leftDifferent _leftConversion =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          rcases inferenceFunctional complete leftInferred rightInferred with
            ⟨typeEquality, _, _⟩
          injection typeEquality with scalarEquality
          exact (leftDifferent scalarEquality).elim
      | signedMinimumLiteral rightMinimum =>
          exact (leftNotContextual (by
            simp only [SurfaceElaboration.ContextualScalarLiteralApplies]
            exact Or.inr ⟨_, _, rfl, rightMinimum⟩)).elim
      | unaryLiteral rightLowered rightTyped =>
          exact (leftNotContextual
            (contextualScalarLiteralApplies_of_unaryLiteral rightLowered
              rightTyped)).elim
      | scalarCast rightInferred _rightSymbolic _rightConcrete
          _rightNotContextual _rightDifferent _rightConversion =>
          rcases inferenceFunctional complete leftInferred rightInferred with
            ⟨typeEquality, _groundEquality, coreEquality⟩
          injection typeEquality with scalarEquality
          cases scalarEquality
          cases coreEquality
          exact ⟨rfl, rfl⟩
  | arrayToSlice leftArray _leftSymbolic _leftConcrete _leftElementGrounds
      _leftElementCore =>
      cases leftArray

theorem ExprSpecializationFunctional.unary
    (operandFunctional : ExprSpecializationFunctional operand) :
    ExprSpecializationFunctional (.unary op operand) := by
  cases operand <;>
    first
    | exact ⟨ExprInferenceSpecializationFunctional.unary
          operandFunctional.inference,
        ExprCheckingSpecializationFunctional.unaryLiteral,
        by
          intro pack catalog imports program externalBindings outer
            groundEnclosingReturn symbolic concrete contexts leftSymbolic
            leftGround leftCore rightSymbolic rightGround rightCore _complete
            left _right
          cases left⟩
    | (have inference : ExprInferenceSpecializationFunctional
          (.unary op _) := ExprInferenceSpecializationFunctional.unary
            operandFunctional.inference
       exact ⟨inference, ExprCheckingSpecializationFunctional.of_inference
          inference (by intro direct; cases direct),
          by
            intro pack catalog imports program externalBindings outer
              groundEnclosingReturn symbolic concrete contexts leftSymbolic
              leftGround leftCore rightSymbolic rightGround rightCore _complete
              left _right
            cases left⟩)

end Lanius.ProgramElaboration
