import Lanius.ContextualFunctionality

namespace Lanius.ProgramElaboration

open Lanius

private theorem contextualVariantResults_unique_of_functional
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (leftSelected : SelectsSymbolicVariantConstructor symbolic path
      leftConstructor)
    (rightSelected : SelectsSymbolicVariantConstructor symbolic path
      rightConstructor)
    (leftExpected : expectedType = Static.Ty.nominal leftConstructor.sourceType
      leftTypeArguments leftConstArguments)
    (rightExpected : expectedType = Static.Ty.nominal rightConstructor.sourceType
      rightTypeArguments rightConstArguments)
    (leftArguments : Static.SymbolicArgumentsBound leftInner
      leftConstructor.genericParameters leftTypeArguments leftConstArguments)
    (rightArguments : Static.SymbolicArgumentsBound rightInner
      rightConstructor.genericParameters rightTypeArguments rightConstArguments)
    (leftTypeArgumentsGround : Static.instantiateTypes outer leftTypeArguments =
      some leftGroundTypeArguments)
    (rightTypeArgumentsGround : Static.instantiateTypes outer
      rightTypeArguments = some rightGroundTypeArguments)
    (leftConstArgumentsGround : Static.instantiateConstants outer
      leftConstArguments = some leftGroundConstArguments)
    (rightConstArgumentsGround : Static.instantiateConstants outer
      rightConstArguments = some rightGroundConstArguments)
    (leftArtifact : NominalArtifactDemand concrete
      leftConstructor.nominalDeclaration leftConstructor.sourceType .enumeration
      leftGroundTypeArguments leftGroundConstArguments leftResolved)
    (rightArtifact : NominalArtifactDemand concrete
      rightConstructor.nominalDeclaration rightConstructor.sourceType
      .enumeration rightGroundTypeArguments rightGroundConstArguments
      rightResolved)
    (leftPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner
      surfaceArguments leftConstructor.payload leftCoreArguments)
    (rightPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner
      surfaceArguments rightConstructor.payload rightCoreArguments) :
    leftConstructor = rightConstructor ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have constructorEquality := complete.symbolicVariantConstructor_unique
    leftSelected rightSelected
  cases constructorEquality
  have expectedEquality := leftExpected.symm.trans rightExpected
  injection expectedEquality with sourceTypeEquality typeArgumentsEquality
    constArgumentsEquality
  cases sourceTypeEquality
  cases typeArgumentsEquality
  cases constArgumentsEquality
  have groundTypeArgumentsEquality := Option.some.inj
    (leftTypeArgumentsGround.symm.trans rightTypeArgumentsGround)
  have groundConstArgumentsEquality := Option.some.inj
    (leftConstArgumentsGround.symm.trans rightConstArgumentsGround)
  have artifactEquality := complete.concreteNominalArtifact_unique contexts
    leftArtifact rightArtifact groundTypeArgumentsEquality
    groundConstArgumentsEquality
  obtain ⟨leftExpectedTypes, leftSubstituted⟩ := leftPayload.substitutedTypes
  obtain ⟨rightExpectedTypes, rightSubstituted⟩ :=
    rightPayload.substitutedTypes
  have expectedTypesEquality := complete.variantPayloadSubstitute_unique
    leftSelected.2.member leftArguments rightArguments leftSubstituted
    rightSubstituted
  have substitutionsAgree : Static.substituteTypes leftInner
      leftConstructor.payload =
      Static.substituteTypes rightInner leftConstructor.payload := by
    rw [leftSubstituted, rightSubstituted, expectedTypesEquality]
  have payloadEquality :=
    leftPayload.unique_of_functional_and_substitution argumentsFunctional
      complete rightPayload substitutionsAgree
  exact ⟨rfl, rfl, rfl, artifactEquality, payloadEquality⟩

private theorem VariantInferenceEvidence.results_unique_of_contextual
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferred : VariantInferenceEvidence outer concrete symbolic path
      inferredConstructor inferredInner observedTypes inferredTypeArguments
      inferredConstArguments inferredResolved)
    (contextualSelected : SelectsSymbolicVariantConstructor symbolic path
      contextualConstructor)
    (expectedEquality :
      Static.Ty.nominal inferredConstructor.sourceType inferredTypeArguments
          inferredConstArguments =
        Static.Ty.nominal contextualConstructor.sourceType
          contextualTypeArguments contextualConstArguments)
    (contextualArguments : Static.SymbolicArgumentsBound contextualInner
      contextualConstructor.genericParameters contextualTypeArguments
      contextualConstArguments)
    (contextualTypeArgumentsGround : Static.instantiateTypes outer
      contextualTypeArguments = some contextualGroundTypeArguments)
    (contextualConstArgumentsGround : Static.instantiateConstants outer
      contextualConstArguments = some contextualGroundConstArguments)
    (contextualArtifact : NominalArtifactDemand concrete
      contextualConstructor.nominalDeclaration contextualConstructor.sourceType
      .enumeration contextualGroundTypeArguments contextualGroundConstArguments
      contextualResolved)
    (inferredPayload : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      observedTypes inferredGroundPayload inferredCoreArguments)
    (contextualPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts contextualInner
      surfaceArguments contextualConstructor.payload contextualCoreArguments) :
    inferredConstructor = contextualConstructor ∧
      inferredTypeArguments = contextualTypeArguments ∧
      inferredConstArguments = contextualConstArguments ∧
      inferredResolved = contextualResolved ∧
      inferredCoreArguments = contextualCoreArguments := by
  have constructorEquality := complete.symbolicVariantConstructor_unique
    inferred.selected contextualSelected
  cases constructorEquality
  injection expectedEquality with sourceTypeEquality typeArgumentsEquality
    constArgumentsEquality
  cases sourceTypeEquality
  cases typeArgumentsEquality
  cases constArgumentsEquality
  have groundTypeArgumentsEquality := Option.some.inj
    (inferred.nominal.typeArgumentsGround.symm.trans
      contextualTypeArgumentsGround)
  have groundConstArgumentsEquality := Option.some.inj
    (inferred.nominal.constArgumentsGround.symm.trans
      contextualConstArgumentsGround)
  have artifactEquality := complete.concreteNominalArtifact_unique contexts
    inferred.nominal.artifact contextualArtifact groundTypeArgumentsEquality
    groundConstArgumentsEquality
  obtain ⟨contextualExpectedTypes, contextualSubstituted⟩ :=
    contextualPayload.substitutedTypes
  have expectedTypesEquality := complete.variantPayloadSubstitute_unique
    inferred.selected.2.member inferred.nominal.arguments contextualArguments
    inferred.typeMatches.substitutes contextualSubstituted
  have contextualSubstitutesObserved :
      Static.substituteTypes contextualInner inferredConstructor.payload =
        some observedTypes := by
    rw [contextualSubstituted, ← expectedTypesEquality]
  have payloadEquality :=
    inferredPayload.core_unique_of_functional_and_substituted
      argumentsFunctional complete contextualPayload
      contextualSubstitutesObserved
  exact ⟨rfl, rfl, rfl, artifactEquality, payloadEquality⟩

theorem VariantInferenceEvidence.results_unique_of_functional
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : VariantInferenceEvidence outer concrete symbolic path leftConstructor
      leftInner leftObservedTypes leftTypeArguments leftConstArguments
      leftResolved)
    (right : VariantInferenceEvidence outer concrete symbolic path
      rightConstructor rightInner rightObservedTypes rightTypeArguments
      rightConstArguments rightResolved)
    (leftPayload : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftObservedTypes leftGroundPayload leftCoreArguments)
    (rightPayload : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightObservedTypes rightGroundPayload rightCoreArguments) :
    leftConstructor = rightConstructor ∧
      leftObservedTypes = rightObservedTypes ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧
      leftGroundPayload = rightGroundPayload ∧
      leftCoreArguments = rightCoreArguments := by
  have constructorEquality :=
    complete.symbolicVariantConstructor_unique left.selected right.selected
  cases constructorEquality
  obtain ⟨observedTypesEquality, groundPayloadEquality,
      coreArgumentsEquality⟩ :=
    ExprListInferenceDerivationSpecializes.unique_of_functional
      argumentsFunctional complete leftPayload rightPayload
  have typeMatchesRight : Static.TypesSymbolicallyMatch rightInner
      leftConstructor.payload leftObservedTypes := by
    rw [observedTypesEquality]
    exact right.typeMatches
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      left.determined left.typeMatches typeMatchesRight
      left.nominal.arguments right.nominal.arguments
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal typeArgumentsEquality constArgumentsEquality
  exact ⟨rfl, observedTypesEquality, typeArgumentsEquality,
    constArgumentsEquality, artifactEquality, groundPayloadEquality,
    coreArgumentsEquality⟩

theorem VariantExplicitEvidence.results_unique_of_functional
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : VariantExplicitEvidence outer concrete symbolic path leftConstructor
      leftInner leftTypeArguments leftConstArguments leftResolved)
    (right : VariantExplicitEvidence outer concrete symbolic path
      rightConstructor rightInner rightTypeArguments rightConstArguments
      rightResolved)
    (leftPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner
      surfaceArguments leftConstructor.payload leftCoreArguments)
    (rightPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner
      surfaceArguments rightConstructor.payload rightCoreArguments) :
    leftConstructor = rightConstructor ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have constructorEquality :=
    complete.symbolicVariantConstructor_unique left.selected right.selected
  cases constructorEquality
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    left.explicitArguments.orderedArguments_unique complete.metadataUnique
      right.explicitArguments left.nominal.arguments right.nominal.arguments
  cases typeArgumentsEquality
  cases constArgumentsEquality
  obtain ⟨leftExpectedTypes, leftSubstituted⟩ := leftPayload.substitutedTypes
  obtain ⟨rightExpectedTypes, rightSubstituted⟩ :=
    rightPayload.substitutedTypes
  have expectedTypesEquality := complete.variantPayloadSubstitute_unique
    left.selected.2.member left.nominal.arguments right.nominal.arguments
    leftSubstituted rightSubstituted
  have substitutionsAgree : Static.substituteTypes leftInner
      leftConstructor.payload =
      Static.substituteTypes rightInner leftConstructor.payload := by
    rw [leftSubstituted, rightSubstituted, expectedTypesEquality]
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal rfl rfl
  have payloadEquality :=
    leftPayload.unique_of_functional_and_substitution argumentsFunctional
      complete rightPayload substitutionsAgree
  exact ⟨rfl, rfl, rfl, artifactEquality, payloadEquality⟩

theorem VariantNongenericEvidence.results_unique_of_functional
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : VariantNongenericEvidence outer concrete symbolic path
      leftConstructor leftInner leftResolved)
    (right : VariantNongenericEvidence outer concrete symbolic path
      rightConstructor rightInner rightResolved)
    (leftPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner
      surfaceArguments leftConstructor.payload leftCoreArguments)
    (rightPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner
      surfaceArguments rightConstructor.payload rightCoreArguments) :
    leftConstructor = rightConstructor ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have constructorEquality :=
    complete.symbolicVariantConstructor_unique left.selected right.selected
  cases constructorEquality
  obtain ⟨leftExpectedTypes, leftSubstituted⟩ := leftPayload.substitutedTypes
  obtain ⟨rightExpectedTypes, rightSubstituted⟩ :=
    rightPayload.substitutedTypes
  have expectedTypesEquality := complete.variantPayloadSubstitute_unique
    left.selected.2.member left.nominal.arguments right.nominal.arguments
    leftSubstituted rightSubstituted
  have substitutionsAgree : Static.substituteTypes leftInner
      leftConstructor.payload =
      Static.substituteTypes rightInner leftConstructor.payload := by
    rw [leftSubstituted, rightSubstituted, expectedTypesEquality]
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal rfl rfl
  have payloadEquality :=
    leftPayload.unique_of_functional_and_substitution argumentsFunctional
      complete rightPayload substitutionsAgree
  exact ⟨rfl, artifactEquality, payloadEquality⟩

theorem DirectCallInferenceEvidence.results_unique_of_functional
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : DirectCallInferenceEvidence outer concrete symbolic path
      leftObservedTypes leftReturnType leftScheme leftInner leftResolved)
    (right : DirectCallInferenceEvidence outer concrete symbolic path
      rightObservedTypes rightReturnType rightScheme rightInner rightResolved)
    (leftArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftObservedTypes leftResolved.parameterTypes leftCoreArguments)
    (rightArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightObservedTypes rightResolved.parameterTypes rightCoreArguments) :
    leftScheme = rightScheme ∧ leftObservedTypes = rightObservedTypes ∧
      leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have schemeEquality := left.selected.unique right.selected
  cases schemeEquality
  obtain ⟨observedTypesEquality, _parameterGroundsEquality,
      coreArgumentsEquality⟩ :=
    ExprListInferenceDerivationSpecializes.unique_of_functional
      argumentsFunctional complete leftArguments rightArguments
  cases observedTypesEquality
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      left.determined left.argumentMatches right.argumentMatches
      left.genericArguments right.genericArguments
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨_parameterTypesEquality, returnTypeEquality⟩ :=
    complete.functionSignatureSubstitute_unique left.selected.member
      left.genericArguments rightGenericArguments
      left.argumentMatches.substitutes right.argumentMatches.substitutes
      left.returnSubstitute right.returnSubstitute
  cases returnTypeEquality
  have groundTypeArgumentsEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        right.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans right.constArgumentsGround))
  have artifactEquality := complete.concreteFunctionArtifact_unique contexts
    left.artifact right.artifact groundTypeArgumentsEquality
    groundConstArgumentsEquality
  cases artifactEquality
  exact ⟨rfl, rfl, rfl, rfl, coreArgumentsEquality⟩

theorem DirectCallExplicitEvidence.results_unique_of_functional
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : DirectCallExplicitEvidence outer concrete symbolic path
      leftParameterTypes leftReturnType leftScheme leftInner leftResolved)
    (right : DirectCallExplicitEvidence outer concrete symbolic path
      rightParameterTypes rightReturnType rightScheme rightInner rightResolved)
    (leftArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftParameterTypes leftResolved.parameterTypes leftCoreArguments)
    (rightArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightParameterTypes rightResolved.parameterTypes rightCoreArguments) :
    leftScheme = rightScheme ∧ leftParameterTypes = rightParameterTypes ∧
      leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have schemeEquality := left.selected.unique right.selected
  cases schemeEquality
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    left.explicitArguments.orderedArguments_unique complete.metadataUnique
      right.explicitArguments left.genericArguments right.genericArguments
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨parameterTypesEquality, returnTypeEquality⟩ :=
    complete.functionSignatureSubstitute_unique left.selected.member
      left.genericArguments rightGenericArguments left.parametersSubstitute
      right.parametersSubstitute left.returnSubstitute right.returnSubstitute
  cases parameterTypesEquality
  cases returnTypeEquality
  have groundTypeArgumentsEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        right.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans right.constArgumentsGround))
  have artifactEquality := complete.concreteFunctionArtifact_unique contexts
    left.artifact right.artifact groundTypeArgumentsEquality
    groundConstArgumentsEquality
  cases artifactEquality
  obtain ⟨_parameterGroundsEquality, coreArgumentsEquality⟩ :=
    ExprListCheckingDerivationSpecializes.unique_of_functional
      argumentsFunctional complete leftArguments rightArguments
  exact ⟨rfl, rfl, rfl, rfl, coreArgumentsEquality⟩

theorem DirectCallNongenericEvidence.results_unique_of_functional
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : DirectCallNongenericEvidence outer concrete symbolic path
      leftScheme leftResolved)
    (right : DirectCallNongenericEvidence outer concrete symbolic path
      rightScheme rightResolved)
    (leftArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftScheme.parameterTypes leftResolved.parameterTypes leftCoreArguments)
    (rightArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightScheme.parameterTypes rightResolved.parameterTypes rightCoreArguments) :
    leftScheme = rightScheme ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have schemeEquality := left.selected.unique right.selected
  cases schemeEquality
  have artifactEquality := complete.concreteFunctionArtifact_unique contexts
    left.artifact right.artifact rfl rfl
  cases artifactEquality
  obtain ⟨_parameterGroundsEquality, coreArgumentsEquality⟩ :=
    ExprListCheckingDerivationSpecializes.unique_of_functional
      argumentsFunctional complete leftArguments rightArguments
  exact ⟨rfl, rfl, coreArgumentsEquality⟩

theorem ExprInferenceDerivationSpecializes.functionPathCall_unique_of_functional
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (resolved : PathCallResolvesAs symbolic path .function)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases path_call_view complete resolved left with
  | directInferred leftEvidence leftArguments =>
      cases path_call_view complete resolved right with
      | directInferred rightEvidence rightArguments =>
          rcases leftEvidence.results_unique_of_functional
              argumentsFunctional complete rightEvidence leftArguments
              rightArguments with ⟨rfl, rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | directExplicit rightEvidence _rightArguments =>
          exact (rightEvidence.excludesInference leftEvidence).elim
      | directNongeneric rightEvidence _rightArguments =>
          exact (leftEvidence.excludesNongeneric rightEvidence).elim
  | directExplicit leftEvidence leftArguments =>
      cases path_call_view complete resolved right with
      | directInferred rightEvidence _rightArguments =>
          exact (leftEvidence.excludesInference rightEvidence).elim
      | directExplicit rightEvidence rightArguments =>
          rcases leftEvidence.results_unique_of_functional
              argumentsFunctional complete rightEvidence leftArguments
              rightArguments with ⟨rfl, rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | directNongeneric rightEvidence _rightArguments =>
          exact (leftEvidence.excludesNongeneric rightEvidence).elim
  | directNongeneric leftEvidence leftArguments =>
      cases path_call_view complete resolved right with
      | directInferred rightEvidence _rightArguments =>
          exact (rightEvidence.excludesNongeneric leftEvidence).elim
      | directExplicit rightEvidence _rightArguments =>
          exact (rightEvidence.excludesNongeneric leftEvidence).elim
      | directNongeneric rightEvidence rightArguments =>
          rcases leftEvidence.results_unique_of_functional
              argumentsFunctional complete rightEvidence leftArguments
              rightArguments with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩

theorem ExprInferenceDerivationSpecializes.variantPathCall_unique_of_functional
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (resolved : PathCallResolvesAs symbolic path .variant)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases path_call_view complete resolved left with
  | variantExplicit leftEvidence leftPayload =>
      cases path_call_view complete resolved right with
      | variantExplicit rightEvidence rightPayload =>
          rcases leftEvidence.results_unique_of_functional
              argumentsFunctional complete rightEvidence leftPayload
              rightPayload with ⟨rfl, rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | variantInferred rightEvidence _rightPayload =>
          exact (leftEvidence.excludesInference rightEvidence).elim
      | variantNongeneric rightEvidence _rightPayload =>
          exact (leftEvidence.excludesNongeneric rightEvidence).elim
  | variantInferred leftEvidence leftPayload =>
      cases path_call_view complete resolved right with
      | variantExplicit rightEvidence _rightPayload =>
          exact (rightEvidence.excludesInference leftEvidence).elim
      | variantInferred rightEvidence rightPayload =>
          rcases leftEvidence.results_unique_of_functional
              argumentsFunctional complete rightEvidence leftPayload
              rightPayload with ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | variantNongeneric rightEvidence _rightPayload =>
          exact (leftEvidence.excludesNongeneric complete rightEvidence).elim
  | variantNongeneric leftEvidence leftPayload =>
      cases path_call_view complete resolved right with
      | variantExplicit rightEvidence _rightPayload =>
          exact (rightEvidence.excludesNongeneric leftEvidence).elim
      | variantInferred rightEvidence _rightPayload =>
          exact (rightEvidence.excludesNongeneric complete leftEvidence).elim
      | variantNongeneric rightEvidence rightPayload =>
          rcases leftEvidence.results_unique_of_functional
              argumentsFunctional complete rightEvidence leftPayload
              rightPayload with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩

theorem ExprInferenceDerivationSpecializes.intrinsicPathCall_unique_of_functional
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments)
    (resolved : PathCallResolvesAs symbolic path .intrinsic)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases path_call_view complete resolved left with
  | printI32 leftBuiltin leftArgument =>
      cases path_call_view complete resolved right with
      | printI32 _rightBuiltin rightArgument =>
          obtain ⟨_groundEquality, coreEquality⟩ :=
            (argumentsFunctional _ (by simp)).checking complete
              leftArgument rightArgument
          exact ⟨rfl, rfl, congrArg
            (fun argument => Core.Expr.intrinsic .printI32 argument)
            coreEquality⟩
      | assert rightBuiltin _rightArgument =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | i32ArrayDataPtr rightBuiltin _rightArgument =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | i32SliceDataPtr rightBuiltin _rightSlice =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | stringDataPtr rightBuiltin _rightString =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
  | assert leftBuiltin leftArgument =>
      cases path_call_view complete resolved right with
      | printI32 rightBuiltin _rightArgument =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | assert _rightBuiltin rightArgument =>
          obtain ⟨_groundEquality, coreEquality⟩ :=
            (argumentsFunctional _ (by simp)).checking complete
              leftArgument rightArgument
          exact ⟨rfl, rfl, congrArg
            (fun argument => Core.Expr.intrinsic .assert argument)
            coreEquality⟩
      | i32ArrayDataPtr rightBuiltin _rightArgument =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | i32SliceDataPtr rightBuiltin _rightSlice =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | stringDataPtr rightBuiltin _rightString =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
  | i32ArrayDataPtr leftBuiltin leftArgument =>
      cases path_call_view complete resolved right with
      | printI32 rightBuiltin _rightArgument =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | assert rightBuiltin _rightArgument =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | i32ArrayDataPtr _rightBuiltin rightArgument =>
          obtain ⟨_lengthEquality, _groundEquality, coreEquality⟩ :=
            ExprCheckingDerivationSpecializes.array_unique_of_expr
              ((argumentsFunctional _ (by simp)).inference complete)
              ((argumentsFunctional _ (by simp)).checking complete)
              leftArgument rightArgument
          exact ⟨rfl, rfl, congrArg Core.Expr.i32ArrayDataPtr coreEquality⟩
      | i32SliceDataPtr rightBuiltin _rightSlice =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | stringDataPtr rightBuiltin _rightString =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
  | i32SliceFromRawParts leftBuiltin leftPointer leftLength =>
      cases path_call_view complete resolved right with
      | i32SliceFromRawParts _rightBuiltin rightPointer rightLength =>
          obtain ⟨_pointerGroundEquality, pointerCoreEquality⟩ :=
            (argumentsFunctional _ (by simp)).checking complete
              leftPointer rightPointer
          obtain ⟨_lengthGroundEquality, lengthCoreEquality⟩ :=
            (argumentsFunctional _ (by simp)).checking complete
              leftLength rightLength
          cases pointerCoreEquality
          cases lengthCoreEquality
          exact ⟨rfl, rfl, rfl⟩
  | i32SliceDataPtr leftBuiltin leftSlice =>
      cases path_call_view complete resolved right with
      | printI32 rightBuiltin _rightArgument =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | assert rightBuiltin _rightArgument =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | i32ArrayDataPtr rightBuiltin _rightArgument =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | i32SliceDataPtr _rightBuiltin rightSlice =>
          obtain ⟨_groundEquality, coreEquality⟩ :=
            (argumentsFunctional _ (by simp)).checking complete
              leftSlice rightSlice
          exact ⟨rfl, rfl, congrArg Core.Expr.i32SliceDataPtr coreEquality⟩
      | stringDataPtr rightBuiltin _rightString =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
  | stringDataPtr leftBuiltin leftString =>
      cases path_call_view complete resolved right with
      | printI32 rightBuiltin _rightArgument =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | assert rightBuiltin _rightArgument =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | i32ArrayDataPtr rightBuiltin _rightArgument =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | i32SliceDataPtr rightBuiltin _rightSlice =>
          cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
      | stringDataPtr _rightBuiltin rightString =>
          obtain ⟨_groundEquality, coreEquality⟩ :=
            (argumentsFunctional _ (by simp)).checking complete
              leftString rightString
          exact ⟨rfl, rfl, congrArg Core.Expr.stringDataPtr coreEquality⟩

theorem ExprInferenceDerivationSpecializes.associatedPathCall_unique_of_functional
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (resolved : PathCallResolvesAs symbolic path .associated)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases path_call_view complete resolved left with
  | associatedInferred leftEvidence leftArguments =>
      cases path_call_view complete resolved right with
      | associatedInferred rightEvidence rightArguments =>
          rcases leftEvidence.results_unique_of_arguments complete
              (ExprListInferenceDerivationSpecializes.unique_of_functional
                argumentsFunctional complete)
              rightEvidence leftArguments rightArguments with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | associatedContextual rightEvidence rightArguments =>
          rcases leftEvidence.results_unique_of_contextual complete
              (ExprListCheckingDerivationSpecializes.unique_of_functional
                argumentsFunctional complete)
              rightEvidence leftArguments rightArguments with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
  | associatedContextual leftEvidence leftArguments =>
      cases path_call_view complete resolved right with
      | associatedInferred rightEvidence rightArguments =>
          rcases rightEvidence.results_unique_of_contextual complete
              (ExprListCheckingDerivationSpecializes.unique_of_functional
                argumentsFunctional complete)
              leftEvidence rightArguments leftArguments with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | associatedContextual rightEvidence rightArguments =>
          rcases leftEvidence.results_unique_of_arguments complete
              (ExprListCheckingDerivationSpecializes.unique_of_functional
                argumentsFunctional complete)
              rightEvidence leftArguments rightArguments with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩

theorem ExprInferenceSpecializationFunctional.pathCall
    {path : Surface.Path} {surfaceArguments : List Surface.Expr}
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments) :
    ExprInferenceSpecializationFunctional
      (.call (.path path) surfaceArguments) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore complete left right
  obtain ⟨kind, resolved⟩ := left.pathCallResolution
  cases kind with
  | intrinsic =>
      exact left.intrinsicPathCall_unique_of_functional argumentsFunctional
        resolved complete right
  | function =>
      exact left.functionPathCall_unique_of_functional argumentsFunctional
        complete resolved right
  | variant =>
      exact left.variantPathCall_unique_of_functional argumentsFunctional
        complete resolved right
  | associated =>
      exact left.associatedPathCall_unique_of_functional argumentsFunctional
        complete resolved right

private theorem inferred_variant_unique_of_functional
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      leftSymbolic leftGround leftCore)
    (leftExpected : expectedType = leftSymbolic)
    (rightSelected : SelectsSymbolicVariantConstructor symbolic path
      rightConstructor)
    (rightNotIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
    (rightExpected : expectedType = Static.Ty.nominal
      rightConstructor.sourceType rightTypeArguments rightConstArguments)
    (rightArguments : Static.SymbolicArgumentsBound rightInner
      rightConstructor.genericParameters rightTypeArguments rightConstArguments)
    (rightTypeArgumentsGround : Static.instantiateTypes outer
      rightTypeArguments = some rightGroundTypeArguments)
    (rightConstArgumentsGround : Static.instantiateConstants outer
      rightConstArguments = some rightGroundConstArguments)
    (rightArtifact : NominalArtifactDemand concrete
      rightConstructor.nominalDeclaration rightConstructor.sourceType
      .enumeration rightGroundTypeArguments rightGroundConstArguments
      rightResolved)
    (rightPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner surfaceArguments
      rightConstructor.payload rightCoreArguments)
    : leftGround = Static.GroundTy.nominal rightConstructor.sourceType
        rightResolved.typeArguments rightResolved.constArguments ∧
      leftCore = Core.Expr.enumValue rightResolved.coreType
        rightConstructor.variant rightCoreArguments := by
  cases path_call_view complete
      (.variant rightSelected rightNotIntrinsic) left with
  | variantExplicit leftEvidence leftPayload =>
      rcases contextualVariantResults_unique_of_functional
          argumentsFunctional complete leftEvidence.selected rightSelected
          leftExpected rightExpected leftEvidence.nominal.arguments
          rightArguments
          leftEvidence.nominal.typeArgumentsGround rightTypeArgumentsGround
          leftEvidence.nominal.constArgumentsGround
          rightConstArgumentsGround leftEvidence.nominal.artifact rightArtifact
          leftPayload rightPayload with ⟨rfl, rfl, rfl, rfl, rfl⟩
      exact ⟨rfl, rfl⟩
  | variantInferred leftEvidence leftPayload =>
      rcases leftEvidence.results_unique_of_contextual
          argumentsFunctional complete rightSelected
          (leftExpected.symm.trans rightExpected) rightArguments
          rightTypeArgumentsGround rightConstArgumentsGround rightArtifact
          leftPayload rightPayload with ⟨rfl, rfl, rfl, rfl, rfl⟩
      exact ⟨rfl, rfl⟩
  | variantNongeneric leftEvidence leftPayload =>
      rcases contextualVariantResults_unique_of_functional
          argumentsFunctional complete leftEvidence.selected rightSelected
          leftExpected rightExpected leftEvidence.nominal.arguments rightArguments
          leftEvidence.nominal.typeArgumentsGround rightTypeArgumentsGround
          leftEvidence.nominal.constArgumentsGround
          rightConstArgumentsGround leftEvidence.nominal.artifact rightArtifact
          leftPayload rightPayload with ⟨rfl, rfl, rfl, rfl, rfl⟩
      exact ⟨rfl, rfl⟩

theorem ExprCheckingSpecializationFunctional.pathCall
    {path : Surface.Path} {surfaceArguments : List Surface.Expr}
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments) :
    ExprCheckingSpecializationFunctional
      (.call (.path path) surfaceArguments) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts expected leftGround
    leftCore rightGround rightCore complete left right
  have inferenceFunctional : ExprInferenceSpecializationFunctional
      (.call (.path path) surfaceArguments) :=
    ExprInferenceSpecializationFunctional.pathCall argumentsFunctional
  cases left with
  | exact leftInferred _leftSymbolic _leftGrounds _leftConcrete =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          exact (inferenceFunctional complete leftInferred rightInferred).2
      | scalarCast rightInferred _rightSymbolic _rightConcrete
          _rightNotContextual rightDifferent _rightConversion =>
          rcases inferenceFunctional complete leftInferred rightInferred with
            ⟨typeEquality, _, _⟩
          injection typeEquality with scalarEquality
          exact (rightDifferent scalarEquality.symm).elim
      | arrayToSlice rightArray _rightSymbolic _rightConcrete
          _rightElementGrounds _rightElementCore =>
          rcases inferenceFunctional complete leftInferred rightArray with
            ⟨typeEquality, _, _⟩
          cases typeEquality
      | variantCall rightSelected rightNotIntrinsic rightExpected
          rightArguments rightTypeArgumentsGround rightConstArgumentsGround
          _rightPathArguments _rightRequirements rightArtifact rightPayload
          _rightSymbolicPayload _rightConcretePayload =>
          exact inferred_variant_unique_of_functional argumentsFunctional
            complete leftInferred rfl rightSelected rightNotIntrinsic rightExpected
            rightArguments rightTypeArgumentsGround rightConstArgumentsGround
            rightArtifact rightPayload
  | scalarCast leftInferred _leftSymbolic _leftConcrete _leftNotContextual
      leftDifferent _leftConversion =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          rcases inferenceFunctional complete leftInferred rightInferred with
            ⟨typeEquality, _, _⟩
          injection typeEquality with scalarEquality
          exact (leftDifferent scalarEquality).elim
      | scalarCast rightInferred _rightSymbolic _rightConcrete
          _rightNotContextual _rightDifferent _rightConversion =>
          rcases inferenceFunctional complete leftInferred rightInferred with
            ⟨typeEquality, _groundEquality, coreEquality⟩
          injection typeEquality with scalarEquality
          cases scalarEquality
          cases coreEquality
          exact ⟨rfl, rfl⟩
      | variantCall _rightSelected _rightNotIntrinsic rightExpected
          _rightArguments _rightTypeArgumentsGround _rightConstArgumentsGround
          _rightPathArguments _rightRequirements _rightArtifact _rightPayload
          _rightSymbolicPayload _rightConcretePayload =>
          cases rightExpected
  | arrayToSlice leftArray _leftSymbolic _leftConcrete leftElementGrounds
      leftElementCore =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          rcases inferenceFunctional complete leftArray rightInferred with
            ⟨typeEquality, _, _⟩
          cases typeEquality
      | arrayToSlice rightArray _rightSymbolic _rightConcrete
          rightElementGrounds rightElementCore =>
          rcases inferenceFunctional complete leftArray rightArray with
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
      | variantCall _rightSelected _rightNotIntrinsic rightExpected
          _rightArguments _rightTypeArgumentsGround _rightConstArgumentsGround
          _rightPathArguments _rightRequirements _rightArtifact _rightPayload
          _rightSymbolicPayload _rightConcretePayload =>
          cases rightExpected
  | variantCall leftSelected leftNotIntrinsic leftExpected leftArguments
      leftTypeArgumentsGround leftConstArgumentsGround _leftPathArguments
      _leftRequirements leftArtifact leftPayload _leftSymbolicPayload
      _leftConcretePayload =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          exact (inferred_variant_unique_of_functional argumentsFunctional
            complete rightInferred rfl leftSelected leftNotIntrinsic leftExpected
            leftArguments leftTypeArgumentsGround leftConstArgumentsGround
            leftArtifact leftPayload).imp Eq.symm Eq.symm
      | scalarCast _rightInferred _rightSymbolic _rightConcrete
          _rightNotContextual _rightDifferent _rightConversion =>
          cases leftExpected
      | arrayToSlice _rightArray _rightSymbolic _rightConcrete
          _rightElementGrounds _rightElementCore =>
          cases leftExpected
      | variantCall rightSelected _rightNotIntrinsic rightExpected
          rightArguments rightTypeArgumentsGround rightConstArgumentsGround
          _rightPathArguments _rightRequirements rightArtifact rightPayload
          _rightSymbolicPayload _rightConcretePayload =>
          rcases contextualVariantResults_unique_of_functional
              argumentsFunctional complete leftSelected rightSelected
              leftExpected rightExpected leftArguments rightArguments
              leftTypeArgumentsGround rightTypeArgumentsGround
              leftConstArgumentsGround rightConstArgumentsGround leftArtifact
              rightArtifact leftPayload rightPayload with
            ⟨rfl, rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl⟩

theorem ExprSpecializationFunctional.pathCall
    {path : Surface.Path} {surfaceArguments : List Surface.Expr}
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments) :
    ExprSpecializationFunctional (.call (.path path) surfaceArguments) :=
  ⟨ExprInferenceSpecializationFunctional.pathCall argumentsFunctional,
    ExprCheckingSpecializationFunctional.pathCall argumentsFunctional,
    by
      intro pack catalog imports program externalBindings outer
        groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
        leftCore rightSymbolic rightGround rightCore _complete left _right
      cases left⟩

theorem ExprInferenceSpecializationFunctional.methodCall
    (receiverFunctional : ExprSpecializationFunctional surfaceReceiver)
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments) :
    ExprInferenceSpecializationFunctional
      (.call (.member surfaceReceiver name) surfaceArguments) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore complete left right
  cases left with
  | methodCallInferred leftEvidence leftReceiver leftMemberBase
      leftMemberLowers leftArguments leftReceiverArgument =>
      cases right with
      | methodCallInferred rightEvidence rightReceiver rightMemberBase
          rightMemberLowers rightArguments rightReceiverArgument =>
          rcases leftEvidence.results_unique_of_children complete
              (receiverFunctional.inference complete)
              (ExprListInferenceDerivationSpecializes.unique_of_functional
                argumentsFunctional complete)
              rightEvidence leftReceiver rightReceiver
              leftMemberBase rightMemberBase leftMemberLowers rightMemberLowers
              leftArguments rightArguments leftReceiverArgument
              rightReceiverArgument with ⟨rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | methodCallContextual rightEvidence rightReceiver rightMemberBase
          rightMemberLowers rightArguments rightReceiverArgument =>
          rcases leftEvidence.results_unique_of_contextual complete
              (receiverFunctional.inference complete)
              (ExprListCheckingDerivationSpecializes.unique_of_functional
                argumentsFunctional complete)
              rightEvidence leftReceiver
              rightReceiver leftMemberBase rightMemberBase leftMemberLowers
              rightMemberLowers leftArguments rightArguments leftReceiverArgument
              rightReceiverArgument with ⟨rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
  | methodCallContextual leftEvidence leftReceiver leftMemberBase
      leftMemberLowers leftArguments leftReceiverArgument =>
      cases right with
      | methodCallInferred rightEvidence rightReceiver rightMemberBase
          rightMemberLowers rightArguments rightReceiverArgument =>
          rcases rightEvidence.results_unique_of_contextual complete
              (receiverFunctional.inference complete)
              (ExprListCheckingDerivationSpecializes.unique_of_functional
                argumentsFunctional complete)
              leftEvidence rightReceiver
              leftReceiver rightMemberBase leftMemberBase rightMemberLowers
              leftMemberLowers rightArguments leftArguments rightReceiverArgument
              leftReceiverArgument with ⟨rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | methodCallContextual rightEvidence rightReceiver rightMemberBase
          rightMemberLowers rightArguments rightReceiverArgument =>
          rcases leftEvidence.results_unique_of_children complete
              (receiverFunctional.inference complete)
              (ExprListCheckingDerivationSpecializes.unique_of_functional
                argumentsFunctional complete)
              rightEvidence leftReceiver rightReceiver
              leftMemberBase rightMemberBase leftMemberLowers rightMemberLowers
              leftArguments rightArguments leftReceiverArgument
              rightReceiverArgument with ⟨rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩

theorem ExprSpecializationFunctional.methodCall
    (receiverFunctional : ExprSpecializationFunctional surfaceReceiver)
    (argumentsFunctional : ExprListSpecializationFunctional surfaceArguments) :
    ExprSpecializationFunctional
      (.call (.member surfaceReceiver name) surfaceArguments) := by
  have inference : ExprInferenceSpecializationFunctional
      (.call (.member surfaceReceiver name) surfaceArguments) :=
    ExprInferenceSpecializationFunctional.methodCall receiverFunctional
      argumentsFunctional
  exact ⟨inference,
    ExprCheckingSpecializationFunctional.of_inference inference
      (by intro direct; cases direct),
    by
      intro pack catalog imports program externalBindings outer
        groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
        leftCore rightSymbolic rightGround rightCore _complete left _right
      cases left⟩

end Lanius.ProgramElaboration
