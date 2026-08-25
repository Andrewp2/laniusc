import Lanius.StructFunctionality

namespace Lanius.ProgramElaboration

open Lanius

/-- Every body expression in a source match-arm list has compositional
    elaboration functionality. Pattern functionality is supplied separately
    by complete-program declaration and allocation uniqueness. -/
abbrev MatchArmListSpecializationFunctional
    (arms : List (Surface.Pattern × Surface.Expr)) : Prop :=
  ∀ pattern body, (pattern, body) ∈ arms →
    ExprSpecializationFunctional body

theorem MatchArmsDerivationSpecializes.core_unique_of_functional
    (armsFunctional : MatchArmListSpecializationFunctional surfaceArms)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : MatchArmsDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts next symbolicScrutinee symbolicResult groundScrutinee
      groundResult surfaceArms leftCore)
    (right : MatchArmsDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts next symbolicScrutinee symbolicResult groundScrutinee
      groundResult surfaceArms rightCore) :
    leftCore = rightCore := by
  induction surfaceArms generalizing leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons surfaceArm surfaceTail induction =>
      cases left with
      | @cons symbolicCase concreteCase contextsCase nextCase surfacePatternCase
          symbolicScrutineeCase groundScrutineeCase corePatternCase
          symbolicBindingsCase concreteBindingsCase patternFinalCase
          surfaceBodyCase symbolicResultCase groundResultCase coreBodyCase
          surfaceTailCase coreTailCase leftPattern leftBody leftTail =>
          cases right with
          | cons rightPattern rightBody rightTail =>
              rcases complete.patternSpecialization_unique leftPattern
                  rightPattern with
                ⟨_groundEquality, corePatternEquality,
                  symbolicBindingsEquality, concreteBindingsEquality,
                  finalEquality⟩
              cases corePatternEquality
              cases symbolicBindingsEquality
              cases concreteBindingsEquality
              cases finalEquality
              have bodyContextsEquality : leftPattern.boundContexts =
                  rightPattern.boundContexts := Subsingleton.elim _ _
              cases bodyContextsEquality
              have bodyComplete : CompleteProgramElaboration pack catalog imports
                  program (symbolic.bindMany symbolicBindingsCase).globals
                  externalBindings := by
                simpa [SymbolicBodyContext.bindMany_eq] using complete
              obtain ⟨_groundBodyEquality, coreBodyEquality⟩ :=
                (armsFunctional surfacePatternCase surfaceBodyCase (by simp))
                  |>.checking bodyComplete leftBody rightBody
              cases coreBodyEquality
              cases induction
                (fun pattern body member =>
                  armsFunctional pattern body (by simp [member]))
                leftTail rightTail
              rfl

theorem MatchArmsInferenceDerivationSpecializes.results_unique_of_functional
    (armsFunctional : MatchArmListSpecializationFunctional surfaceArms)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : MatchArmsInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next symbolicScrutinee leftSymbolicResult
      groundScrutinee leftGroundResult surfaceArms leftCore)
    (right : MatchArmsInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next symbolicScrutinee rightSymbolicResult
      groundScrutinee rightGroundResult surfaceArms rightCore) :
    leftSymbolicResult = rightSymbolicResult ∧
      leftGroundResult = rightGroundResult ∧ leftCore = rightCore := by
  cases left with
  | @cons symbolicCase concreteCase contextsCase nextCase surfacePatternCase
      symbolicScrutineeCase groundScrutineeCase corePatternCase
      symbolicBindingsCase concreteBindingsCase patternFinalCase surfaceBodyCase
      leftSymbolicResultCase leftGroundResultCase leftCoreBody surfaceTailCase
      leftCoreTail leftPattern leftBody leftTail =>
      cases right with
      | cons rightPattern rightBody rightTail =>
          rcases complete.patternSpecialization_unique leftPattern rightPattern with
            ⟨_groundEquality, corePatternEquality, symbolicBindingsEquality,
              concreteBindingsEquality, finalEquality⟩
          cases corePatternEquality
          cases symbolicBindingsEquality
          cases concreteBindingsEquality
          cases finalEquality
          have bodyContextsEquality : leftPattern.boundContexts =
              rightPattern.boundContexts := Subsingleton.elim _ _
          cases bodyContextsEquality
          have bodyComplete : CompleteProgramElaboration pack catalog imports
              program (symbolic.bindMany symbolicBindingsCase).globals
              externalBindings := by
            simpa [SymbolicBodyContext.bindMany_eq] using complete
          rcases (armsFunctional surfacePatternCase surfaceBodyCase (by simp))
              |>.inference bodyComplete leftBody rightBody with
            ⟨symbolicResultEquality, groundResultEquality, coreBodyEquality⟩
          cases symbolicResultEquality
          cases groundResultEquality
          cases coreBodyEquality
          have tailFunctional : MatchArmListSpecializationFunctional
              surfaceTailCase := by
            intro pattern body member
            exact armsFunctional pattern body (by simp [member])
          cases leftTail.core_unique_of_functional tailFunctional complete
            rightTail
          exact ⟨rfl, rfl, rfl⟩

theorem ExprInferenceSpecializationFunctional.matchValue
    (scrutineeFunctional : ExprSpecializationFunctional surfaceScrutinee)
    (armsFunctional : MatchArmListSpecializationFunctional surfaceArms) :
    ExprInferenceSpecializationFunctional
      (.matchValue surfaceScrutinee surfaceArms) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore complete left right
  cases left with
  | matchValue leftScrutinee _leftResultGrounds leftArms =>
      cases right with
      | matchValue rightScrutinee _rightResultGrounds rightArms =>
          rcases scrutineeFunctional.inference complete leftScrutinee
              rightScrutinee with ⟨rfl, rfl, rfl⟩
          rcases leftArms.results_unique_of_functional armsFunctional complete
              rightArms with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩

theorem ExprSpecializationFunctional.matchValue
    (scrutineeFunctional : ExprSpecializationFunctional surfaceScrutinee)
    (armsFunctional : MatchArmListSpecializationFunctional surfaceArms) :
    ExprSpecializationFunctional
      (.matchValue surfaceScrutinee surfaceArms) := by
  have inference : ExprInferenceSpecializationFunctional
      (.matchValue surfaceScrutinee surfaceArms) :=
    ExprInferenceSpecializationFunctional.matchValue
      scrutineeFunctional armsFunctional
  exact ⟨inference,
    ExprCheckingSpecializationFunctional.of_inference inference
      (by intro direct; cases direct),
    by
      intro pack catalog imports program externalBindings outer
        groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
        leftCore rightSymbolic rightGround rightCore _complete left _right
      cases left⟩

end Lanius.ProgramElaboration
