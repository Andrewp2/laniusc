import Lanius.ProgramElaboration

namespace Lanius.ProgramElaboration

open Lanius

/-- Exact specialization is functional at one surface expression when every
    pair of derivations in any complete-program body context agrees on its
    symbolic type, ground type, and emitted Core expression. Quantifying over
    contexts makes the predicate reusable beneath match-arm bindings. -/
def ExprInferenceSpecializationFunctional (surface : Surface.Expr) : Prop :=
  ∀ {pack catalog imports program externalBindings outer
      groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
      leftCore rightSymbolic rightGround rightCore},
    CompleteProgramElaboration pack catalog imports program symbolic.globals
        externalBindings →
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
            concrete contexts surface rightSymbolic rightGround rightCore →
          leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
            leftCore = rightCore

/-- Contextual specialization is functional at one surface expression and one
    expected symbolic type. -/
def ExprCheckingSpecializationFunctional (surface : Surface.Expr) : Prop :=
  ∀ {pack catalog imports program externalBindings outer
      groundEnclosingReturn symbolic concrete contexts expected leftGround
      leftCore rightGround rightCore},
    CompleteProgramElaboration pack catalog imports program symbolic.globals
        externalBindings →
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
            concrete contexts surface expected rightGround rightCore →
          leftGround = rightGround ∧ leftCore = rightCore

/-- Place specialization is functional at one surface expression. Most
    expression forms cannot denote places; path, member, and index forms prove
    this property recursively alongside ordinary expression elaboration. -/
def PlaceSpecializationFunctional (surface : Surface.Expr) : Prop :=
  ∀ {pack catalog imports program externalBindings outer
      groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
      leftCore rightSymbolic rightGround rightCore},
    CompleteProgramElaboration pack catalog imports program symbolic.globals
        externalBindings →
      PlaceDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts surface leftSymbolic leftGround leftCore →
        PlaceDerivationSpecializes outer groundEnclosingReturn symbolic concrete
            contexts surface rightSymbolic rightGround rightCore →
          leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
            leftCore = rightCore

/-- The paired property proved by structural induction over surface syntax.
    Checking may reuse inference at the same node, while inference recursively
    uses both properties only at proper child expressions. -/
structure ExprSpecializationFunctional (surface : Surface.Expr) : Prop where
  inference : ExprInferenceSpecializationFunctional surface
  checking : ExprCheckingSpecializationFunctional surface
  place : PlaceSpecializationFunctional surface

/-- Every expression in a recursively represented source list has both
    functionality properties. -/
abbrev ExprListSpecializationFunctional (surfaces : List Surface.Expr) : Prop :=
  ∀ surface, surface ∈ surfaces → ExprSpecializationFunctional surface

theorem ExprListInferenceDerivationSpecializes.unique_of_functional
    (functional : ExprListSpecializationFunctional surfaces)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : ExprListInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaces leftSymbolic leftGround leftCore)
    (right : ExprListInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaces rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  induction surfaces generalizing leftSymbolic leftGround leftCore
      rightSymbolic rightGround rightCore with
  | nil =>
      cases left
      cases right
      exact ⟨rfl, rfl, rfl⟩
  | cons head tail induction =>
      cases left with
      | cons leftHead leftTail =>
          cases right with
          | cons rightHead rightTail =>
              rcases (functional head (by simp)).inference complete leftHead
                  rightHead with
                ⟨rfl, rfl, rfl⟩
              rcases induction (fun surface member =>
                  functional surface (by simp [member])) leftTail rightTail with
                ⟨rfl, rfl, rfl⟩
              exact ⟨rfl, rfl, rfl⟩

theorem ExprListCheckingDerivationSpecializes.unique_of_functional
    (functional : ExprListSpecializationFunctional surfaces)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : ExprListCheckingDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaces expectedTypes leftGround leftCore)
    (right : ExprListCheckingDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaces expectedTypes rightGround rightCore) :
    leftGround = rightGround ∧ leftCore = rightCore := by
  induction surfaces generalizing expectedTypes leftGround leftCore
      rightGround rightCore with
  | nil =>
      cases left
      cases right
      exact ⟨rfl, rfl⟩
  | cons head tail induction =>
      cases left with
      | cons leftHead leftTail =>
          cases right with
          | cons rightHead rightTail =>
              rcases (functional head (by simp)).checking complete leftHead
                  rightHead with
                ⟨rfl, rfl⟩
              rcases induction (fun surface member =>
                  functional surface (by simp [member])) leftTail rightTail with
                ⟨rfl, rfl⟩
              exact ⟨rfl, rfl⟩

/-- Substituted checking is functional when each source argument is
    functional and both substitutions produce the same expected-type list. -/
theorem ExprListSubstitutedCheckingDerivationSpecializes.unique_of_functional_and_substitution
    (functional : ExprListSpecializationFunctional surfaces)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner surfaces
      originalTypes leftCore)
    (right : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner surfaces
      originalTypes rightCore)
    (substitutionsAgree : Static.substituteTypes leftInner originalTypes =
      Static.substituteTypes rightInner originalTypes) :
    leftCore = rightCore := by
  induction originalTypes generalizing surfaces leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons originalHead originalTail induction =>
      cases left with
      | cons leftSubstituted leftHead leftTail _leftSymbolic _leftConcrete =>
          cases right with
          | cons rightSubstituted rightHead rightTail _rightSymbolic
              _rightConcrete =>
              rename_i leftExpectedHead surfaceHead leftGroundHead leftCoreHead
                surfaceTail leftCoreTail rightExpectedHead rightGroundHead
                rightCoreHead rightCoreTail
              obtain ⟨leftTailTypes, leftTailSubstituted⟩ :=
                leftTail.substitutedTypes
              obtain ⟨rightTailTypes, rightTailSubstituted⟩ :=
                rightTail.substitutedTypes
              have expectedListsEquality :
                  leftExpectedHead :: leftTailTypes =
                    rightExpectedHead :: rightTailTypes := by
                have sameSome : some (leftExpectedHead :: leftTailTypes) =
                    some (rightExpectedHead :: rightTailTypes) := by
                  simpa [Static.substituteTypes, leftSubstituted,
                    rightSubstituted, leftTailSubstituted,
                    rightTailSubstituted] using substitutionsAgree
                exact Option.some.inj sameSome
              injection expectedListsEquality with headEquality tailEquality
              cases headEquality
              cases tailEquality
              rcases (functional surfaceHead (by simp)).checking complete
                  leftHead rightHead with ⟨rfl, rfl⟩
              have tailSubstitutionsAgree :
                  Static.substituteTypes leftInner originalTail =
                    Static.substituteTypes rightInner originalTail :=
                leftTailSubstituted.trans rightTailSubstituted.symm
              cases induction (fun surface member =>
                  functional surface (by simp [member])) leftTail rightTail
                    tailSubstitutionsAgree
              rfl

/-- An inferred argument list and a substituted contextual argument list emit
    the same Core expressions when substitution produces the inferred types. -/
theorem ExprListInferenceDerivationSpecializes.core_unique_of_functional_and_substituted
    (functional : ExprListSpecializationFunctional surfaces)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferred : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaces observedTypes
      inferredGround inferredCore)
    (contextual : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner surfaces
      originalTypes contextualCore)
    (substituted : Static.substituteTypes inner originalTypes =
      some observedTypes) : inferredCore = contextualCore := by
  induction originalTypes generalizing surfaces observedTypes inferredGround
      inferredCore contextualCore with
  | nil =>
      cases contextual
      cases inferred
      rfl
  | cons originalHead originalTail induction =>
      cases contextual with
      | cons contextualHeadSubstituted contextualHead contextualTail
          _contextualSymbolic _contextualConcrete =>
          cases inferred with
          | cons inferredHead inferredTail =>
              rename_i expectedHead surfaceHead contextualGroundHead
                contextualCoreHead surfaceTail contextualCoreTail observedHead
                inferredGroundHead inferredCoreHead observedTail
                inferredGroundTail inferredCoreTail
              obtain ⟨contextualTailTypes, contextualTailSubstituted⟩ :=
                contextualTail.substitutedTypes
              have expectedListsEquality :
                  expectedHead :: contextualTailTypes =
                    observedHead :: observedTail := by
                have sameSome : some (expectedHead :: contextualTailTypes) =
                    some (observedHead :: observedTail) := by
                  simpa [Static.substituteTypes, contextualHeadSubstituted,
                    contextualTailSubstituted] using substituted
                exact Option.some.inj sameSome
              injection expectedListsEquality with headEquality tailEquality
              cases headEquality
              cases tailEquality
              rcases (functional surfaceHead (by simp)).checking complete
                  inferredHead.asChecking contextualHead with
                ⟨_groundHeadEquality, coreHeadEquality⟩
              cases coreHeadEquality
              have tailSubstituted :
                  Static.substituteTypes inner originalTail =
                    some observedTail := contextualTailSubstituted
              cases induction (fun surface member =>
                  functional surface (by simp [member])) inferredTail
                    contextualTail tailSubstituted
              rfl

theorem ExprInferenceSpecializationFunctional.literal
    {literal : Surface.Literal} :
    ExprInferenceSpecializationFunctional (.literal literal) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore _complete left right
  exact left.literal_unique right

theorem ExprCheckingSpecializationFunctional.literal
    {literal : Surface.Literal} :
    ExprCheckingSpecializationFunctional (.literal literal) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts expected leftGround
    leftCore rightGround rightCore complete left right
  cases left with
  | exact leftInferred _leftSymbolic _leftGrounds _leftConcrete =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          exact (ExprInferenceSpecializationFunctional.literal complete
            leftInferred rightInferred).2
      | literal rightLowered =>
          cases leftInferred with
          | literal leftLowered =>
              rw [literalDefaultType_eq_scalar] at leftLowered
              cases leftLowered.core_unique rightLowered
              exact ⟨rfl, rfl⟩
      | scalarCast rightInferred _rightSymbolic _rightConcrete
          _rightNotContextual rightDifferent _rightConversion =>
          rcases ExprInferenceSpecializationFunctional.literal complete
              leftInferred rightInferred with ⟨typeEquality, _, _⟩
          injection typeEquality with scalarEquality
          exact (rightDifferent scalarEquality.symm).elim
      | arrayToSlice rightArray _rightSymbolic _rightConcrete
          _rightElementGrounds _rightElementCore =>
          cases rightArray
  | literal leftLowered =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          cases rightInferred with
          | literal rightLowered =>
              rw [literalDefaultType_eq_scalar] at rightLowered
              cases leftLowered.core_unique rightLowered
              exact ⟨rfl, rfl⟩
      | literal rightLowered =>
          cases leftLowered.core_unique rightLowered
          exact ⟨rfl, rfl⟩
      | scalarCast _rightInferred _rightSymbolic _rightConcrete
          rightNotContextual _rightDifferent _rightConversion =>
          exact (rightNotContextual ⟨_, leftLowered⟩).elim
  | scalarCast leftInferred _leftSymbolic _leftConcrete leftNotContextual
      leftDifferent _leftConversion =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          rcases ExprInferenceSpecializationFunctional.literal complete
              leftInferred rightInferred with ⟨typeEquality, _, _⟩
          injection typeEquality with scalarEquality
          exact (leftDifferent scalarEquality).elim
      | literal rightLowered =>
          exact (leftNotContextual ⟨_, rightLowered⟩).elim
      | scalarCast rightInferred _rightSymbolic _rightConcrete
          _rightNotContextual _rightDifferent _rightConversion =>
          rcases ExprInferenceSpecializationFunctional.literal complete
              leftInferred rightInferred with
            ⟨typeEquality, _groundEquality, coreEquality⟩
          injection typeEquality with scalarEquality
          cases scalarEquality
          cases coreEquality
          exact ⟨rfl, rfl⟩
  | arrayToSlice leftArray _leftSymbolic _leftConcrete _leftElementGrounds
      _leftElementCore =>
      cases leftArray

theorem ExprSpecializationFunctional.literal
    {literal : Surface.Literal} :
    ExprSpecializationFunctional (.literal literal) :=
  ⟨ExprInferenceSpecializationFunctional.literal,
    ExprCheckingSpecializationFunctional.literal,
    by
      intro pack catalog imports program externalBindings outer
        groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
        leftCore rightSymbolic rightGround rightCore _complete left _right
      cases left⟩

theorem ExprInferenceSpecializationFunctional.path
    {path : Surface.Path} :
    ExprInferenceSpecializationFunctional (.path path) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore _complete left right
  exact CompleteProgramElaboration.pathInference_unique left right

theorem ExprInferenceSpecializationFunctional.selfValue :
    ExprInferenceSpecializationFunctional .selfValue := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore _complete left right
  exact left.selfValue_unique right

theorem ExprInferenceSpecializationFunctional.array
    (elementsFunctional : ExprListSpecializationFunctional elements) :
    ExprInferenceSpecializationFunctional (.array elements) := by
  cases elements with
  | nil =>
      intro pack catalog imports program externalBindings outer
        groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
        leftCore rightSymbolic rightGround rightCore complete left right
      cases left
  | cons head tail =>
      intro pack catalog imports program externalBindings outer
        groundEnclosingReturn symbolic concrete contexts leftSymbolic
        leftGround leftCore rightSymbolic rightGround rightCore complete
        left right
      cases left with
      | array leftHead leftTail leftElementCore =>
          cases right with
          | array rightHead rightTail rightElementCore =>
              rcases (elementsFunctional head (by simp)).inference complete
                  leftHead rightHead with ⟨rfl, rfl, rfl⟩
              have tailFunctional : ExprListSpecializationFunctional tail :=
                fun surface member =>
                  elementsFunctional surface (by simp [member])
              obtain ⟨_groundTailEquality, coreTailEquality⟩ :=
                rightTail.unique_of_functional tailFunctional complete leftTail
              cases coreTailEquality
              have coreElementEquality := Option.some.inj
                (leftElementCore.symm.trans rightElementCore)
              cases coreElementEquality
              exact ⟨rfl, rfl, rfl⟩

/-- Contextual array checking is functional using only the paired properties
    of its elements. An exact inferred array is converted into an element
    checking list, avoiding recursion at the same array node. -/
theorem ExprCheckingSpecializationFunctional.array
    (elementsFunctional : ExprListSpecializationFunctional elements) :
    ExprCheckingSpecializationFunctional (.array elements) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts expected leftGround
    leftCore rightGround rightCore complete left right
  cases left with
  | exact leftInferred _leftSymbolic _leftGrounds _leftConcrete =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          exact (ExprInferenceSpecializationFunctional.array
            elementsFunctional complete leftInferred rightInferred).2
      | array rightElements rightElementGrounds rightElementCore =>
          cases leftInferred with
          | array leftHead leftTail leftElementCore =>
              have leftElements := ExprListCheckingDerivationSpecializes.cons
                leftHead.asChecking leftTail
              obtain ⟨groundElementsEquality, coreElementsEquality⟩ :=
                rightElements.unique_of_functional elementsFunctional complete
                  leftElements
              cases groundElementsEquality
              cases coreElementsEquality
              have coreElementEquality := Option.some.inj
                (leftElementCore.symm.trans rightElementCore)
              cases coreElementEquality
              exact ⟨rfl, rfl⟩
      | scalarCast _rightInferred _rightSymbolic _rightConcrete
          _rightNotContextual _rightDifferent _rightConversion =>
          cases leftInferred
      | arrayToSlice _rightArray _rightSymbolic _rightConcrete
          _rightElementGrounds _rightElementCore =>
          cases leftInferred
  | array leftElements leftElementGrounds leftElementCore =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          cases rightInferred with
          | array rightHead rightTail rightElementCore =>
              have rightElements := ExprListCheckingDerivationSpecializes.cons
                rightHead.asChecking rightTail
              obtain ⟨groundElementsEquality, coreElementsEquality⟩ :=
                leftElements.unique_of_functional elementsFunctional complete
                  rightElements
              cases groundElementsEquality
              cases coreElementsEquality
              have coreElementEquality := Option.some.inj
                (leftElementCore.symm.trans rightElementCore)
              cases coreElementEquality
              exact ⟨rfl, rfl⟩
      | array rightElements rightElementGrounds rightElementCore =>
          have groundElementEquality := Option.some.inj
            (leftElementGrounds.symm.trans rightElementGrounds)
          cases groundElementEquality
          obtain ⟨_groundElementsEquality, coreElementsEquality⟩ :=
            leftElements.unique_of_functional elementsFunctional complete
              rightElements
          cases coreElementsEquality
          have coreElementEquality := Option.some.inj
            (leftElementCore.symm.trans rightElementCore)
          cases coreElementEquality
          exact ⟨rfl, rfl⟩

  | scalarCast leftInferred _leftSymbolic _leftConcrete _leftNotContextual
      _leftDifferent _leftConversion =>
      cases leftInferred
  | arrayToSlice leftArray _leftSymbolic _leftConcrete leftElementGrounds
      leftElementCore =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          cases rightInferred
      | arrayToSlice rightArray _rightSymbolic _rightConcrete
          rightElementGrounds rightElementCore =>
          rcases ExprInferenceSpecializationFunctional.array elementsFunctional
              complete leftArray rightArray with
            ⟨symbolicEquality, groundEquality, coreArrayEquality⟩
          injection symbolicEquality with elementEquality lengthEquality
          injection groundEquality with groundElementEquality
            groundLengthEquality
          cases elementEquality
          cases lengthEquality
          cases groundElementEquality
          cases groundLengthEquality
          cases coreArrayEquality
          have coreElementEquality := Option.some.inj
            (leftElementCore.symm.trans rightElementCore)
          cases coreElementEquality
          exact ⟨rfl, rfl⟩

theorem ExprSpecializationFunctional.array
    (elementsFunctional : ExprListSpecializationFunctional elements) :
    ExprSpecializationFunctional (.array elements) :=
  ⟨ExprInferenceSpecializationFunctional.array elementsFunctional,
    ExprCheckingSpecializationFunctional.array elementsFunctional,
    by
      intro pack catalog imports program externalBindings outer
        groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
        leftCore rightSymbolic rightGround rightCore _complete left _right
      cases left⟩

theorem ExprInferenceSpecializationFunctional.unary
    (operandFunctional : ExprInferenceSpecializationFunctional operand) :
    ExprInferenceSpecializationFunctional (.unary op operand) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore complete left right
  apply left.unary_unique_of_expr _ right
  exact operandFunctional complete

theorem ExprInferenceSpecializationFunctional.binary
    (leftFunctional : ExprInferenceSpecializationFunctional surfaceLeft)
    (rightFunctional : ExprInferenceSpecializationFunctional surfaceRight) :
    ExprInferenceSpecializationFunctional
      (.binary op surfaceLeft surfaceRight) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore complete left right
  apply left.binary_unique_of_expr _ _ right
  · exact leftFunctional complete
  · exact rightFunctional complete

theorem ExprInferenceSpecializationFunctional.index
    (baseFunctional : ExprInferenceSpecializationFunctional surfaceBase)
    (indexFunctional : ExprInferenceSpecializationFunctional surfaceIndex) :
    ExprInferenceSpecializationFunctional
      (.index surfaceBase surfaceIndex) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore complete left right
  apply left.index_unique_of_expr _ _ right
  · exact baseFunctional complete
  · exact indexFunctional complete

theorem ExprInferenceSpecializationFunctional.field
    (baseFunctional : ExprInferenceSpecializationFunctional surfaceBase) :
    ExprInferenceSpecializationFunctional (.member surfaceBase name) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore complete left right
  apply left.field_unique_of_expr complete _ right
  exact baseFunctional complete

theorem ExprInferenceDerivationSpecializes.variantPathCall_unique_of_expr
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (resolved : PathCallResolvesAs symbolic path .variant)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases resolved with
  | variant selected notIntrinsic =>
      cases left with
      | printI32 builtin _argument =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none builtin
            notIntrinsic).elim
      | assert builtin _argument =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none builtin
            notIntrinsic).elim
      | i32ArrayDataPtr builtin _argument =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none builtin
            notIntrinsic).elim
      | directCallInferred evidence _arguments =>
          exact (complete.function_excludes_symbolicVariantConstructor
            evidence.selected selected).elim
      | directCallExplicit evidence _arguments =>
          exact (complete.function_excludes_symbolicVariantConstructor
            evidence.selected selected).elim
      | directCallNongeneric evidence _arguments =>
          exact (complete.function_excludes_symbolicVariantConstructor
            evidence.selected selected).elim
      | associatedCallInferred evidence _arguments =>
          exact (evidence.notVariant ⟨_, selected⟩).elim
      | associatedCallContextual evidence _arguments =>
          exact (evidence.notVariant ⟨_, selected⟩).elim
      | variantExplicit leftEvidence leftPayload =>
          cases right with
          | printI32 builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | assert builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | i32ArrayDataPtr builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | directCallInferred evidence _arguments =>
              exact (complete.function_excludes_symbolicVariantConstructor
                evidence.selected selected).elim
          | directCallExplicit evidence _arguments =>
              exact (complete.function_excludes_symbolicVariantConstructor
                evidence.selected selected).elim
          | directCallNongeneric evidence _arguments =>
              exact (complete.function_excludes_symbolicVariantConstructor
                evidence.selected selected).elim
          | associatedCallInferred evidence _arguments =>
              exact (evidence.notVariant ⟨_, selected⟩).elim
          | associatedCallContextual evidence _arguments =>
              exact (evidence.notVariant ⟨_, selected⟩).elim
          | variantExplicit rightEvidence rightPayload =>
              rcases leftEvidence.results_unique_of_payload complete checkUnique
                  rightEvidence leftPayload rightPayload with
                ⟨rfl, rfl, rfl, rfl, rfl⟩
              exact ⟨rfl, rfl, rfl⟩
          | variantInferred rightEvidence _rightPayload =>
              exact (leftEvidence.excludesInference rightEvidence).elim
          | variantNongeneric rightEvidence _rightPayload =>
              exact (leftEvidence.excludesNongeneric rightEvidence).elim
      | variantInferred leftEvidence leftPayload =>
          cases right with
          | printI32 builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | assert builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | i32ArrayDataPtr builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | directCallInferred evidence _arguments =>
              exact (complete.function_excludes_symbolicVariantConstructor
                evidence.selected selected).elim
          | directCallExplicit evidence _arguments =>
              exact (complete.function_excludes_symbolicVariantConstructor
                evidence.selected selected).elim
          | directCallNongeneric evidence _arguments =>
              exact (complete.function_excludes_symbolicVariantConstructor
                evidence.selected selected).elim
          | associatedCallInferred evidence _arguments =>
              exact (evidence.notVariant ⟨_, selected⟩).elim
          | associatedCallContextual evidence _arguments =>
              exact (evidence.notVariant ⟨_, selected⟩).elim
          | variantExplicit rightEvidence _rightPayload =>
              exact (rightEvidence.excludesInference leftEvidence).elim
          | variantInferred rightEvidence rightPayload =>
              rcases leftEvidence.results_unique_of_payload complete inferUnique
                  rightEvidence leftPayload rightPayload with
                ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
              exact ⟨rfl, rfl, rfl⟩
          | variantNongeneric rightEvidence _rightPayload =>
              exact (leftEvidence.excludesNongeneric complete
                rightEvidence).elim
      | variantNongeneric leftEvidence leftPayload =>
          cases right with
          | printI32 builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | assert builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | i32ArrayDataPtr builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | directCallInferred evidence _arguments =>
              exact (complete.function_excludes_symbolicVariantConstructor
                evidence.selected selected).elim
          | directCallExplicit evidence _arguments =>
              exact (complete.function_excludes_symbolicVariantConstructor
                evidence.selected selected).elim
          | directCallNongeneric evidence _arguments =>
              exact (complete.function_excludes_symbolicVariantConstructor
                evidence.selected selected).elim
          | associatedCallInferred evidence _arguments =>
              exact (evidence.notVariant ⟨_, selected⟩).elim
          | associatedCallContextual evidence _arguments =>
              exact (evidence.notVariant ⟨_, selected⟩).elim
          | variantExplicit rightEvidence _rightPayload =>
              exact (rightEvidence.excludesNongeneric leftEvidence).elim
          | variantInferred rightEvidence _rightPayload =>
              exact (rightEvidence.excludesNongeneric complete
                leftEvidence).elim
          | variantNongeneric rightEvidence rightPayload =>
              rcases leftEvidence.results_unique_of_payload complete checkUnique
                  rightEvidence leftPayload rightPayload with ⟨rfl, rfl, rfl⟩
              exact ⟨rfl, rfl, rfl⟩

theorem ExprInferenceDerivationSpecializes.functionPathCall_unique_of_expr
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (resolved : PathCallResolvesAs symbolic path .function)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases resolved with
  | function selected notIntrinsic =>
      cases left with
      | printI32 builtin _argument =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none builtin
            notIntrinsic).elim
      | assert builtin _argument =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none builtin
            notIntrinsic).elim
      | i32ArrayDataPtr builtin _argument =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none builtin
            notIntrinsic).elim
      | variantExplicit evidence _payload =>
          exact (complete.function_excludes_symbolicVariantConstructor selected
            evidence.selected).elim
      | variantInferred evidence _payload =>
          exact (complete.function_excludes_symbolicVariantConstructor selected
            evidence.selected).elim
      | variantNongeneric evidence _payload =>
          exact (complete.function_excludes_symbolicVariantConstructor selected
            evidence.selected).elim
      | associatedCallInferred evidence _arguments =>
          exact (evidence.notFunction ⟨_, selected⟩).elim
      | associatedCallContextual evidence _arguments =>
          exact (evidence.notFunction ⟨_, selected⟩).elim
      | directCallInferred leftEvidence leftArguments =>
          cases right with
          | printI32 builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | assert builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | i32ArrayDataPtr builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | variantExplicit evidence _payload =>
              exact (complete.function_excludes_symbolicVariantConstructor
                selected evidence.selected).elim
          | variantInferred evidence _payload =>
              exact (complete.function_excludes_symbolicVariantConstructor
                selected evidence.selected).elim
          | variantNongeneric evidence _payload =>
              exact (complete.function_excludes_symbolicVariantConstructor
                selected evidence.selected).elim
          | associatedCallInferred evidence _arguments =>
              exact (evidence.notFunction ⟨_, selected⟩).elim
          | associatedCallContextual evidence _arguments =>
              exact (evidence.notFunction ⟨_, selected⟩).elim
          | directCallInferred rightEvidence rightArguments =>
              rcases leftEvidence.results_unique_of_arguments complete
                  inferUnique rightEvidence leftArguments rightArguments with
                ⟨rfl, rfl, rfl, rfl, rfl⟩
              exact ⟨rfl, rfl, rfl⟩
          | directCallExplicit rightEvidence _rightArguments =>
              exact (rightEvidence.excludesInference leftEvidence).elim
          | directCallNongeneric rightEvidence _rightArguments =>
              exact (leftEvidence.excludesNongeneric rightEvidence).elim
      | directCallExplicit leftEvidence leftArguments =>
          cases right with
          | printI32 builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | assert builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | i32ArrayDataPtr builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | variantExplicit evidence _payload =>
              exact (complete.function_excludes_symbolicVariantConstructor
                selected evidence.selected).elim
          | variantInferred evidence _payload =>
              exact (complete.function_excludes_symbolicVariantConstructor
                selected evidence.selected).elim
          | variantNongeneric evidence _payload =>
              exact (complete.function_excludes_symbolicVariantConstructor
                selected evidence.selected).elim
          | associatedCallInferred evidence _arguments =>
              exact (evidence.notFunction ⟨_, selected⟩).elim
          | associatedCallContextual evidence _arguments =>
              exact (evidence.notFunction ⟨_, selected⟩).elim
          | directCallInferred rightEvidence _rightArguments =>
              exact (leftEvidence.excludesInference rightEvidence).elim
          | directCallExplicit rightEvidence rightArguments =>
              rcases leftEvidence.results_unique_of_arguments complete
                  checkUnique rightEvidence leftArguments rightArguments with
                ⟨rfl, rfl, rfl, rfl, rfl⟩
              exact ⟨rfl, rfl, rfl⟩
          | directCallNongeneric rightEvidence _rightArguments =>
              exact (leftEvidence.excludesNongeneric rightEvidence).elim
      | directCallNongeneric leftEvidence leftArguments =>
          cases right with
          | printI32 builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | assert builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | i32ArrayDataPtr builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | variantExplicit evidence _payload =>
              exact (complete.function_excludes_symbolicVariantConstructor
                selected evidence.selected).elim
          | variantInferred evidence _payload =>
              exact (complete.function_excludes_symbolicVariantConstructor
                selected evidence.selected).elim
          | variantNongeneric evidence _payload =>
              exact (complete.function_excludes_symbolicVariantConstructor
                selected evidence.selected).elim
          | associatedCallInferred evidence _arguments =>
              exact (evidence.notFunction ⟨_, selected⟩).elim
          | associatedCallContextual evidence _arguments =>
              exact (evidence.notFunction ⟨_, selected⟩).elim
          | directCallInferred rightEvidence _rightArguments =>
              exact (rightEvidence.excludesNongeneric leftEvidence).elim
          | directCallExplicit rightEvidence _rightArguments =>
              exact (rightEvidence.excludesNongeneric leftEvidence).elim
          | directCallNongeneric rightEvidence rightArguments =>
              rcases leftEvidence.results_unique_of_arguments complete
                  checkUnique rightEvidence leftArguments rightArguments with
                ⟨rfl, rfl, rfl⟩
              exact ⟨rfl, rfl, rfl⟩

/-- Type-qualified associated calls are functional across both argument
    inference and owner-driven contextual checking.  The path category excludes
    intrinsics, global functions, and enum variants before the two associated
    rules are compared. -/
theorem ExprInferenceDerivationSpecializes.associatedPathCall_unique_of_expr
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (resolved : PathCallResolvesAs symbolic path .associated)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases resolved with
  | associated notIntrinsic notFunction notVariant =>
      cases left with
      | printI32 builtin _argument =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none builtin
            notIntrinsic).elim
      | assert builtin _argument =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none builtin
            notIntrinsic).elim
      | i32ArrayDataPtr builtin _argument =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none builtin
            notIntrinsic).elim
      | directCallInferred evidence _arguments =>
          exact (notFunction ⟨_, evidence.selected⟩).elim
      | directCallExplicit evidence _arguments =>
          exact (notFunction ⟨_, evidence.selected⟩).elim
      | directCallNongeneric evidence _arguments =>
          exact (notFunction ⟨_, evidence.selected⟩).elim
      | variantExplicit evidence _payload =>
          exact (notVariant ⟨_, evidence.selected⟩).elim
      | variantInferred evidence _payload =>
          exact (notVariant ⟨_, evidence.selected⟩).elim
      | variantNongeneric evidence _payload =>
          exact (notVariant ⟨_, evidence.selected⟩).elim
      | associatedCallInferred leftEvidence leftArguments =>
          cases right with
          | printI32 builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | assert builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | i32ArrayDataPtr builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | directCallInferred evidence _arguments =>
              exact (notFunction ⟨_, evidence.selected⟩).elim
          | directCallExplicit evidence _arguments =>
              exact (notFunction ⟨_, evidence.selected⟩).elim
          | directCallNongeneric evidence _arguments =>
              exact (notFunction ⟨_, evidence.selected⟩).elim
          | variantExplicit evidence _payload =>
              exact (notVariant ⟨_, evidence.selected⟩).elim
          | variantInferred evidence _payload =>
              exact (notVariant ⟨_, evidence.selected⟩).elim
          | variantNongeneric evidence _payload =>
              exact (notVariant ⟨_, evidence.selected⟩).elim
          | associatedCallInferred rightEvidence rightArguments =>
              rcases leftEvidence.results_unique_of_arguments complete
                  (ExprListInferenceDerivationSpecializes.unique_of_expr
                    inferUnique)
                  rightEvidence leftArguments rightArguments with ⟨rfl, rfl, rfl⟩
              exact ⟨rfl, rfl, rfl⟩
          | associatedCallContextual rightEvidence rightArguments =>
              rcases leftEvidence.results_unique_of_contextual complete
                  (ExprListCheckingDerivationSpecializes.unique_of_expr
                    checkUnique)
                  rightEvidence leftArguments rightArguments with ⟨rfl, rfl, rfl⟩
              exact ⟨rfl, rfl, rfl⟩
      | associatedCallContextual leftEvidence leftArguments =>
          cases right with
          | printI32 builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | assert builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | i32ArrayDataPtr builtin _argument =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                builtin notIntrinsic).elim
          | directCallInferred evidence _arguments =>
              exact (notFunction ⟨_, evidence.selected⟩).elim
          | directCallExplicit evidence _arguments =>
              exact (notFunction ⟨_, evidence.selected⟩).elim
          | directCallNongeneric evidence _arguments =>
              exact (notFunction ⟨_, evidence.selected⟩).elim
          | variantExplicit evidence _payload =>
              exact (notVariant ⟨_, evidence.selected⟩).elim
          | variantInferred evidence _payload =>
              exact (notVariant ⟨_, evidence.selected⟩).elim
          | variantNongeneric evidence _payload =>
              exact (notVariant ⟨_, evidence.selected⟩).elim
          | associatedCallInferred rightEvidence rightArguments =>
              rcases rightEvidence.results_unique_of_contextual complete
                  (ExprListCheckingDerivationSpecializes.unique_of_expr
                    checkUnique)
                  leftEvidence rightArguments leftArguments with ⟨rfl, rfl, rfl⟩
              exact ⟨rfl, rfl, rfl⟩
          | associatedCallContextual rightEvidence rightArguments =>
              rcases leftEvidence.results_unique_of_arguments complete
                  (ExprListCheckingDerivationSpecializes.unique_of_expr
                    checkUnique)
                  rightEvidence leftArguments rightArguments with ⟨rfl, rfl, rfl⟩
              exact ⟨rfl, rfl, rfl⟩

theorem CompleteProgramElaboration.pathCallSpecialization_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  obtain ⟨kind, resolved⟩ := left.pathCallResolution
  cases kind with
  | intrinsic =>
      exact left.intrinsicPathCall_unique_of_expr inferUnique checkUnique
        resolved right
  | function =>
      exact left.functionPathCall_unique_of_expr complete inferUnique
        checkUnique resolved right
  | variant =>
      exact left.variantPathCall_unique_of_expr complete inferUnique checkUnique
        resolved right
  | associated =>
      exact left.associatedPathCall_unique_of_expr complete inferUnique checkUnique
        resolved right

/-- Member-call inference has one specialization regardless of whether generic
    arguments are inferred from all operands or the receiver fixes a
    contextual argument signature. -/
theorem CompleteProgramElaboration.methodCallSpecialization_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts
      (.call (.member surfaceReceiver name) surfaceArguments)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts
      (.call (.member surfaceReceiver name) surfaceArguments)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | methodCallInferred leftEvidence leftReceiver leftMemberBase
      leftMemberLowers leftArguments leftReceiverArgument =>
      cases right with
      | methodCallInferred rightEvidence rightReceiver rightMemberBase
          rightMemberLowers rightArguments rightReceiverArgument =>
          rcases leftEvidence.results_unique_of_children complete inferUnique
              (ExprListInferenceDerivationSpecializes.unique_of_expr inferUnique)
              rightEvidence leftReceiver rightReceiver leftMemberBase
              rightMemberBase leftMemberLowers rightMemberLowers leftArguments
              rightArguments leftReceiverArgument rightReceiverArgument with
            ⟨rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | methodCallContextual rightEvidence rightReceiver rightMemberBase
          rightMemberLowers rightArguments rightReceiverArgument =>
          rcases leftEvidence.results_unique_of_contextual complete inferUnique
              (ExprListCheckingDerivationSpecializes.unique_of_expr checkUnique)
              rightEvidence leftReceiver rightReceiver leftMemberBase
              rightMemberBase leftMemberLowers rightMemberLowers leftArguments
              rightArguments leftReceiverArgument rightReceiverArgument with
            ⟨rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
  | methodCallContextual leftEvidence leftReceiver leftMemberBase
      leftMemberLowers leftArguments leftReceiverArgument =>
      cases right with
      | methodCallInferred rightEvidence rightReceiver rightMemberBase
          rightMemberLowers rightArguments rightReceiverArgument =>
          rcases rightEvidence.results_unique_of_contextual complete inferUnique
              (ExprListCheckingDerivationSpecializes.unique_of_expr checkUnique)
              leftEvidence rightReceiver leftReceiver rightMemberBase
              leftMemberBase rightMemberLowers leftMemberLowers rightArguments
              leftArguments rightReceiverArgument leftReceiverArgument with
            ⟨rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | methodCallContextual rightEvidence rightReceiver rightMemberBase
          rightMemberLowers rightArguments rightReceiverArgument =>
          rcases leftEvidence.results_unique_of_children complete inferUnique
              (ExprListCheckingDerivationSpecializes.unique_of_expr checkUnique)
              rightEvidence leftReceiver rightReceiver leftMemberBase
              rightMemberBase leftMemberLowers rightMemberLowers leftArguments
              rightArguments leftReceiverArgument rightReceiverArgument with
            ⟨rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩

end Lanius.ProgramElaboration
