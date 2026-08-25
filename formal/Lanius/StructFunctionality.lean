import Lanius.CallFunctionality

namespace Lanius.ProgramElaboration

open Lanius

/-- Every value expression named in a struct literal has compositional
    elaboration functionality. Names matter only for constructor-field
    selection; the proof obligation belongs to the selected expression. -/
abbrev NamedExprListSpecializationFunctional
    (fields : List (Surface.Name × Surface.Expr)) : Prop :=
  ∀ name expression, (name, expression) ∈ fields →
    ExprSpecializationFunctional expression

private theorem StructInferenceEvidence.results_unique_of_contextual
    (fieldsFunctional : NamedExprListSpecializationFunctional surfaceFields)
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferred : StructInferenceEvidence outer concrete symbolic path
      inferredConstructor inferredInner inferredTypeArguments
      inferredConstArguments inferredResolved)
    (contextualSelected : SurfaceElaboration.SelectsStructConstructor
      symbolic.globals path contextualConstructor)
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
      contextualConstructor.declaration contextualConstructor.sourceType
      .structure contextualGroundTypeArguments contextualGroundConstArguments
      contextualResolved)
    (inferredFields : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inferredInner
      inferredConstructor.fields surfaceFields inferredCoreFields)
    (contextualFields : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts contextualInner
      contextualConstructor.fields surfaceFields contextualCoreFields) :
    inferredConstructor = contextualConstructor ∧
      inferredTypeArguments = contextualTypeArguments ∧
      inferredConstArguments = contextualConstArguments ∧
      inferredResolved = contextualResolved ∧
      inferredCoreFields = contextualCoreFields := by
  have constructorEquality := complete.structConstructor_unique
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
  have fieldsEquality :=
    inferredFields.core_unique_of_expr_and_checked complete
      (fun member => (fieldsFunctional _ _ member).checking complete)
      inferred.selected.member (fun _ member => member)
      inferred.nominal.arguments contextualArguments contextualFields
  exact ⟨rfl, rfl, rfl, artifactEquality, fieldsEquality⟩

theorem ExprInferenceSpecializationFunctional.structValue
    {path : Surface.Path}
    {surfaceFields : List (Surface.Name × Surface.Expr)}
    (fieldsFunctional : NamedExprListSpecializationFunctional surfaceFields) :
    ExprInferenceSpecializationFunctional
      (.structValue path surfaceFields) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore complete left right
  cases left with
  | structExplicit leftEvidence leftFields =>
      cases right with
      | structExplicit rightEvidence rightFields =>
          rcases leftEvidence.results_unique_of_fields complete
              (fun member => (fieldsFunctional _ _ member).checking complete)
              rightEvidence leftFields rightFields with
            ⟨rfl, rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | structInferred rightEvidence _rightFields =>
          exact (leftEvidence.explicitArguments.excludesNoGenericArguments
            rightEvidence.implicitArguments).elim
      | structNongeneric rightEvidence _rightFields =>
          exact (leftEvidence.explicitArguments.excludesNoGenericArguments
            rightEvidence.implicitArguments).elim
  | structInferred leftEvidence leftFields =>
      cases right with
      | structExplicit rightEvidence _rightFields =>
          exact (rightEvidence.explicitArguments.excludesNoGenericArguments
            leftEvidence.implicitArguments).elim
      | structInferred rightEvidence rightFields =>
          rcases leftEvidence.results_unique_of_fields complete
              (fun member => (fieldsFunctional _ _ member).inference complete)
              rightEvidence leftFields rightFields with
            ⟨rfl, rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | structNongeneric rightEvidence _rightFields =>
          have constructorEquality := complete.structConstructor_unique
            leftEvidence.selected rightEvidence.selected
          cases constructorEquality
          exact (leftEvidence.generic rightEvidence.nongeneric).elim
  | structNongeneric leftEvidence leftFields =>
      cases right with
      | structExplicit rightEvidence _rightFields =>
          exact (rightEvidence.explicitArguments.excludesNoGenericArguments
            leftEvidence.implicitArguments).elim
      | structInferred rightEvidence _rightFields =>
          have constructorEquality := complete.structConstructor_unique
            leftEvidence.selected rightEvidence.selected
          cases constructorEquality
          exact (rightEvidence.generic leftEvidence.nongeneric).elim
      | structNongeneric rightEvidence rightFields =>
          rcases leftEvidence.results_unique_of_fields complete
              (fun member => (fieldsFunctional _ _ member).checking complete)
              rightEvidence leftFields rightFields with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩

theorem ExprCheckingSpecializationFunctional.structValue
    {path : Surface.Path}
    {surfaceFields : List (Surface.Name × Surface.Expr)}
    (fieldsFunctional : NamedExprListSpecializationFunctional surfaceFields) :
    ExprCheckingSpecializationFunctional
      (.structValue path surfaceFields) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts expected leftGround
    leftCore rightGround rightCore complete left right
  cases left with
  | exact leftInferred _leftSymbolic _leftGrounds _leftConcrete =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          exact (ExprInferenceSpecializationFunctional.structValue
            fieldsFunctional complete leftInferred rightInferred).2
      | scalarCast rightInferred _rightSymbolic _rightConcrete
          _rightNotContextual _rightDifferent _rightConversion =>
          cases rightInferred
      | arrayToSlice rightInferred _rightSymbolic _rightConcrete
          _rightElementGrounds _rightElementCore =>
          cases rightInferred
      | structValue rightSelected rightExpected rightArguments
          rightTypeArgumentsGround rightConstArgumentsGround _rightPathArguments
          _rightRequirements rightArtifact rightFields _rightSymbolicFields
          _rightConcreteFields =>
          cases leftInferred with
          | structExplicit leftEvidence leftFields =>
              rcases contextualStructResults_unique complete
                  (fun member =>
                    (fieldsFunctional _ _ member).checking complete)
                  leftEvidence.selected rightSelected rfl rightExpected
                  leftEvidence.nominal.arguments rightArguments
                  leftEvidence.nominal.typeArgumentsGround
                  rightTypeArgumentsGround
                  leftEvidence.nominal.constArgumentsGround
                  rightConstArgumentsGround leftEvidence.nominal.artifact
                  rightArtifact leftFields rightFields with
                ⟨rfl, rfl, rfl, rfl, rfl⟩
              exact ⟨rfl, rfl⟩
          | structInferred leftEvidence leftFields =>
              rcases leftEvidence.results_unique_of_contextual fieldsFunctional
                  complete rightSelected rightExpected rightArguments
                  rightTypeArgumentsGround rightConstArgumentsGround
                  rightArtifact leftFields rightFields with
                ⟨rfl, rfl, rfl, rfl, rfl⟩
              exact ⟨rfl, rfl⟩
          | structNongeneric leftEvidence leftFields =>
              rcases contextualStructResults_unique complete
                  (fun member =>
                    (fieldsFunctional _ _ member).checking complete)
                  leftEvidence.selected rightSelected rfl rightExpected
                  leftEvidence.nominal.arguments rightArguments
                  leftEvidence.nominal.typeArgumentsGround
                  rightTypeArgumentsGround
                  leftEvidence.nominal.constArgumentsGround
                  rightConstArgumentsGround leftEvidence.nominal.artifact
                  rightArtifact leftFields rightFields with
                ⟨rfl, rfl, rfl, rfl, rfl⟩
              exact ⟨rfl, rfl⟩
  | scalarCast leftInferred _leftSymbolic _leftConcrete _leftNotContextual
      _leftDifferent _leftConversion =>
      cases leftInferred
  | arrayToSlice leftInferred _leftSymbolic _leftConcrete _leftElementGrounds
      _leftElementCore =>
      cases leftInferred
  | structValue leftSelected leftExpected leftArguments leftTypeArgumentsGround
      leftConstArgumentsGround _leftPathArguments _leftRequirements leftArtifact
      leftFields _leftSymbolicFields _leftConcreteFields =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          cases rightInferred with
          | structExplicit rightEvidence rightFields =>
              rcases contextualStructResults_unique complete
                  (fun member =>
                    (fieldsFunctional _ _ member).checking complete)
                  leftSelected rightEvidence.selected leftExpected rfl
                  leftArguments rightEvidence.nominal.arguments
                  leftTypeArgumentsGround
                  rightEvidence.nominal.typeArgumentsGround
                  leftConstArgumentsGround
                  rightEvidence.nominal.constArgumentsGround leftArtifact
                  rightEvidence.nominal.artifact leftFields rightFields with
                ⟨rfl, rfl, rfl, rfl, rfl⟩
              exact ⟨rfl, rfl⟩
          | structInferred rightEvidence rightFields =>
              rcases rightEvidence.results_unique_of_contextual fieldsFunctional
                  complete leftSelected leftExpected leftArguments
                  leftTypeArgumentsGround leftConstArgumentsGround leftArtifact
                  rightFields leftFields with ⟨rfl, rfl, rfl, rfl, rfl⟩
              exact ⟨rfl, rfl⟩
          | structNongeneric rightEvidence rightFields =>
              rcases contextualStructResults_unique complete
                  (fun member =>
                    (fieldsFunctional _ _ member).checking complete)
                  leftSelected rightEvidence.selected leftExpected rfl
                  leftArguments rightEvidence.nominal.arguments
                  leftTypeArgumentsGround
                  rightEvidence.nominal.typeArgumentsGround
                  leftConstArgumentsGround
                  rightEvidence.nominal.constArgumentsGround leftArtifact
                  rightEvidence.nominal.artifact leftFields rightFields with
                ⟨rfl, rfl, rfl, rfl, rfl⟩
              exact ⟨rfl, rfl⟩
      | scalarCast rightInferred _rightSymbolic _rightConcrete
          _rightNotContextual _rightDifferent _rightConversion =>
          cases rightInferred
      | arrayToSlice rightInferred _rightSymbolic _rightConcrete
          _rightElementGrounds _rightElementCore =>
          cases rightInferred
      | structValue rightSelected rightExpected rightArguments
          rightTypeArgumentsGround rightConstArgumentsGround _rightPathArguments
          _rightRequirements rightArtifact rightFields _rightSymbolicFields
          _rightConcreteFields =>
          rcases contextualStructResults_unique complete
              (fun member =>
                (fieldsFunctional _ _ member).checking complete)
              leftSelected rightSelected leftExpected rightExpected leftArguments
              rightArguments leftTypeArgumentsGround rightTypeArgumentsGround
              leftConstArgumentsGround rightConstArgumentsGround leftArtifact
              rightArtifact leftFields rightFields with
            ⟨rfl, rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl⟩

theorem ExprSpecializationFunctional.structValue
    {path : Surface.Path}
    {surfaceFields : List (Surface.Name × Surface.Expr)}
    (fieldsFunctional : NamedExprListSpecializationFunctional surfaceFields) :
    ExprSpecializationFunctional (.structValue path surfaceFields) :=
  ⟨ExprInferenceSpecializationFunctional.structValue fieldsFunctional,
    ExprCheckingSpecializationFunctional.structValue fieldsFunctional,
    by
      intro pack catalog imports program externalBindings outer
        groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
        leftCore rightSymbolic rightGround rightCore _complete left _right
      cases left⟩

end Lanius.ProgramElaboration
