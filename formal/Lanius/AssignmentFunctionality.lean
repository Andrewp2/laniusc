import Lanius.ContextualFunctionality

namespace Lanius.ProgramElaboration

open Lanius

/-- Assignment specialization is determined by the writable-place
    specialization of its left child and contextual checking of its value. -/
theorem ExprInferenceSpecializationFunctional.assign
    (placeFunctional : ExprSpecializationFunctional surfacePlace)
    (valueFunctional : ExprSpecializationFunctional surfaceValue) :
    ExprInferenceSpecializationFunctional
      (.assign op surfacePlace surfaceValue) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore complete left right
  cases left with
  | assign leftPlace leftValue _leftCoreGrounds _leftTyped =>
      cases right with
      | assign rightPlace rightValue _rightCoreGrounds _rightTyped =>
          rcases placeFunctional.place complete leftPlace rightPlace with
            ⟨rfl, rfl, rfl⟩
          obtain ⟨_groundValueEquality, coreValueEquality⟩ :=
            valueFunctional.checking complete leftValue rightValue
          cases coreValueEquality
          exact ⟨rfl, rfl, rfl⟩

theorem ExprSpecializationFunctional.assign
    (placeFunctional : ExprSpecializationFunctional surfacePlace)
    (valueFunctional : ExprSpecializationFunctional surfaceValue) :
    ExprSpecializationFunctional (.assign op surfacePlace surfaceValue) := by
  have inference : ExprInferenceSpecializationFunctional
      (.assign op surfacePlace surfaceValue) :=
    ExprInferenceSpecializationFunctional.assign placeFunctional valueFunctional
  exact ⟨inference,
    ExprCheckingSpecializationFunctional.of_inference inference
      (by intro direct; cases direct),
    by
      intro pack catalog imports program externalBindings outer
        groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
        leftCore rightSymbolic rightGround rightCore _complete left _right
      cases left⟩

end Lanius.ProgramElaboration
