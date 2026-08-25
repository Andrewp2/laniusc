import Lanius.ElaborationFunctionality

namespace Lanius.ProgramElaboration

open Lanius

inductive DirectContextualForm : Surface.Expr → Prop where
  | literal : DirectContextualForm (.literal literal)
  | signedMinimum : DirectContextualForm
      (.unary .negative (.literal (.integer text)))
  | unaryLiteral : DirectContextualForm (.unary op (.literal literal))
  | array : DirectContextualForm (.array elements)
  | structValue : DirectContextualForm (.structValue path fields)
  | variantCall : DirectContextualForm
      (.call (.path path) surfaceArguments)

theorem ExprCheckingSpecializationFunctional.of_inference
    (inferenceFunctional : ExprInferenceSpecializationFunctional surface)
    (notDirect : ¬ DirectContextualForm surface) :
    ExprCheckingSpecializationFunctional surface := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts expected leftGround
    leftCore rightGround rightCore complete left right
  cases left with
  | exact leftInferred _leftSymbolic _leftGrounds _leftConcrete =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          exact (inferenceFunctional complete leftInferred rightInferred).2
      | literal _rightLowered => exact (notDirect .literal).elim
      | signedMinimumLiteral _rightLowered =>
          exact (notDirect .signedMinimum).elim
      | unaryLiteral _rightLowered _rightTyped =>
          exact (notDirect .unaryLiteral).elim
      | array _rightElements _rightElementGrounds _rightElementCore =>
          exact (notDirect .array).elim
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
      | structValue _selected _expected _arguments _typeArgumentsGround
          _constArgumentsGround _pathArguments _requirements _artifact _fields
          _symbolicFields _concreteFields =>
          exact (notDirect .structValue).elim
      | variantCall _selected _notIntrinsic _expected _arguments
          _typeArgumentsGround _constArgumentsGround _pathArguments
          _requirements _artifact _payload _symbolicPayload _concretePayload =>
          exact (notDirect .variantCall).elim
  | literal _leftLowered => exact (notDirect .literal).elim
  | signedMinimumLiteral _leftLowered =>
      exact (notDirect .signedMinimum).elim
  | unaryLiteral _leftLowered _leftTyped =>
      exact (notDirect .unaryLiteral).elim
  | array _leftElements _leftElementGrounds _leftElementCore =>
      exact (notDirect .array).elim
  | scalarCast leftInferred _leftSymbolic _leftConcrete _leftNotContextual
      leftDifferent _leftConversion =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          rcases inferenceFunctional complete leftInferred rightInferred with
            ⟨typeEquality, _, _⟩
          injection typeEquality with scalarEquality
          exact (leftDifferent scalarEquality).elim
      | literal _rightLowered => exact (notDirect .literal).elim
      | signedMinimumLiteral _rightLowered =>
          exact (notDirect .signedMinimum).elim
      | unaryLiteral _rightLowered _rightTyped =>
          exact (notDirect .unaryLiteral).elim
      | scalarCast rightInferred _rightSymbolic _rightConcrete
          _rightNotContextual _rightDifferent _rightConversion =>
          rcases inferenceFunctional complete leftInferred rightInferred with
            ⟨typeEquality, _groundEquality, coreEquality⟩
          injection typeEquality with scalarEquality
          cases scalarEquality
          cases coreEquality
          exact ⟨rfl, rfl⟩
      | structValue _selected _expected _arguments _typeArgumentsGround
          _constArgumentsGround _pathArguments _requirements _artifact _fields
          _symbolicFields _concreteFields =>
          exact (notDirect .structValue).elim
      | variantCall _selected _notIntrinsic _expected _arguments
          _typeArgumentsGround _constArgumentsGround _pathArguments
          _requirements _artifact _payload _symbolicPayload _concretePayload =>
          exact (notDirect .variantCall).elim
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
      | structValue _selected _expected _arguments _typeArgumentsGround
          _constArgumentsGround _pathArguments _requirements _artifact _fields
          _symbolicFields _concreteFields =>
          exact (notDirect .structValue).elim
      | variantCall _selected _notIntrinsic _expected _arguments
          _typeArgumentsGround _constArgumentsGround _pathArguments
          _requirements _artifact _payload _symbolicPayload _concretePayload =>
          exact (notDirect .variantCall).elim
  | structValue _selected _expected _arguments _typeArgumentsGround
      _constArgumentsGround _pathArguments _requirements _artifact _fields
      _symbolicFields _concreteFields =>
      exact (notDirect .structValue).elim
  | variantCall _selected _notIntrinsic _expected _arguments
      _typeArgumentsGround _constArgumentsGround _pathArguments _requirements
      _artifact _payload _symbolicPayload _concretePayload =>
      exact (notDirect .variantCall).elim

theorem ExprCheckingSpecializationFunctional.path
    {path : Surface.Path} :
    ExprCheckingSpecializationFunctional (.path path) :=
  ExprCheckingSpecializationFunctional.of_inference
    ExprInferenceSpecializationFunctional.path (by
      intro direct
      cases direct)

theorem PlaceSpecializationFunctional.path
    {path : Surface.Path} : PlaceSpecializationFunctional (.path path) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore _complete left right
  cases left with
  | «local» leftSingle leftSymbolicResolved leftConcreteResolved
      _leftTypeGrounds =>
      cases right with
      | «local» rightSingle rightSymbolicResolved rightConcreteResolved
          _rightTypeGrounds =>
          have nameEquality := Option.some.inj
            (leftSingle.symm.trans rightSingle)
          cases nameEquality
          cases leftSymbolicResolved.unique rightSymbolicResolved
          cases leftConcreteResolved.unique rightConcreteResolved
          exact ⟨rfl, rfl, rfl⟩

theorem ExprSpecializationFunctional.path
    {path : Surface.Path} : ExprSpecializationFunctional (.path path) :=
  ⟨ExprInferenceSpecializationFunctional.path,
    ExprCheckingSpecializationFunctional.path,
    PlaceSpecializationFunctional.path⟩

theorem ExprCheckingSpecializationFunctional.selfValue :
    ExprCheckingSpecializationFunctional .selfValue :=
  ExprCheckingSpecializationFunctional.of_inference
    ExprInferenceSpecializationFunctional.selfValue (by
      intro direct
      cases direct)

theorem PlaceSpecializationFunctional.selfValue :
    PlaceSpecializationFunctional .selfValue := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore _complete left right
  cases left with
  | selfValue leftSymbolicResolved leftConcreteResolved _leftTypeGrounds =>
      cases right with
      | selfValue rightSymbolicResolved rightConcreteResolved
          _rightTypeGrounds =>
          cases leftSymbolicResolved.unique rightSymbolicResolved
          cases leftConcreteResolved.unique rightConcreteResolved
          exact ⟨rfl, rfl, rfl⟩

theorem ExprSpecializationFunctional.selfValue :
    ExprSpecializationFunctional .selfValue :=
  ⟨ExprInferenceSpecializationFunctional.selfValue,
    ExprCheckingSpecializationFunctional.selfValue,
    PlaceSpecializationFunctional.selfValue⟩

theorem ExprSpecializationFunctional.binary
    (leftFunctional : ExprSpecializationFunctional surfaceLeft)
    (rightFunctional : ExprSpecializationFunctional surfaceRight) :
    ExprSpecializationFunctional (.binary op surfaceLeft surfaceRight) := by
  have inference : ExprInferenceSpecializationFunctional
      (.binary op surfaceLeft surfaceRight) :=
    ExprInferenceSpecializationFunctional.binary
    leftFunctional.inference rightFunctional.inference
  exact ⟨inference, ExprCheckingSpecializationFunctional.of_inference inference
    (by intro direct; cases direct), by
      intro pack catalog imports program externalBindings outer
        groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
        leftCore rightSymbolic rightGround rightCore _complete left _right
      cases left⟩

theorem PlaceSpecializationFunctional.index
    (baseFunctional : PlaceSpecializationFunctional surfaceBase)
    (indexFunctional : ExprInferenceSpecializationFunctional surfaceIndex) :
    PlaceSpecializationFunctional (.index surfaceBase surfaceIndex) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore complete left right
  cases left with
  | indexArray leftBase _leftElementGrounds _leftLengthGrounds leftIndex
      _leftInteger =>
      cases right with
      | indexArray rightBase _rightElementGrounds _rightLengthGrounds rightIndex
          _rightInteger =>
          rcases baseFunctional complete leftBase rightBase with
            ⟨baseTypeEquality, baseGroundEquality, coreBaseEquality⟩
          injection baseTypeEquality with elementTypeEquality lengthEquality
          injection baseGroundEquality with groundElementEquality
            groundLengthEquality
          cases elementTypeEquality
          cases lengthEquality
          cases groundElementEquality
          cases groundLengthEquality
          cases coreBaseEquality
          rcases indexFunctional complete leftIndex rightIndex with
            ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | indexSlice rightBase _rightElementGrounds _rightIndex _rightInteger =>
          rcases baseFunctional complete leftBase rightBase with
            ⟨baseTypeEquality, _, _⟩
          cases baseTypeEquality
  | indexSlice leftBase _leftElementGrounds leftIndex _leftInteger =>
      cases right with
      | indexArray rightBase _rightElementGrounds _rightLengthGrounds
          _rightIndex _rightInteger =>
          rcases baseFunctional complete leftBase rightBase with
            ⟨baseTypeEquality, _, _⟩
          cases baseTypeEquality
      | indexSlice rightBase _rightElementGrounds rightIndex _rightInteger =>
          rcases baseFunctional complete leftBase rightBase with
            ⟨baseTypeEquality, baseGroundEquality, coreBaseEquality⟩
          injection baseTypeEquality with elementTypeEquality
          injection baseGroundEquality with groundElementEquality
          cases elementTypeEquality
          cases groundElementEquality
          cases coreBaseEquality
          rcases indexFunctional complete leftIndex rightIndex with
            ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩

theorem ExprSpecializationFunctional.index
    (baseFunctional : ExprSpecializationFunctional surfaceBase)
    (indexFunctional : ExprSpecializationFunctional surfaceIndex) :
    ExprSpecializationFunctional (.index surfaceBase surfaceIndex) := by
  have inference : ExprInferenceSpecializationFunctional
      (.index surfaceBase surfaceIndex) :=
    ExprInferenceSpecializationFunctional.index
    baseFunctional.inference indexFunctional.inference
  exact ⟨inference, ExprCheckingSpecializationFunctional.of_inference inference
    (by intro direct; cases direct),
    PlaceSpecializationFunctional.index baseFunctional.place
      indexFunctional.inference⟩

theorem PlaceSpecializationFunctional.field
    (baseFunctional : PlaceSpecializationFunctional surfaceBase) :
    PlaceSpecializationFunctional (.member surfaceBase name) := by
  intro pack catalog imports program externalBindings outer
    groundEnclosingReturn symbolic concrete contexts leftSymbolic leftGround
    leftCore rightSymbolic rightGround rightCore complete left right
  cases left with
  | field leftBase leftSymbolicSelected leftConcreteSelected
      _leftFieldGrounds =>
      cases right with
      | field rightBase rightSymbolicSelected rightConcreteSelected
          _rightFieldGrounds =>
          rcases baseFunctional complete leftBase rightBase with
            ⟨receiverTypeEquality, groundReceiverEquality, coreBaseEquality⟩
          cases receiverTypeEquality
          cases groundReceiverEquality
          cases coreBaseEquality
          cases complete.symbolicFieldResult_unique leftSymbolicSelected
            rightSymbolicSelected
          cases leftConcreteSelected.unique rightConcreteSelected
          exact ⟨rfl, rfl, rfl⟩

theorem ExprSpecializationFunctional.field
    (baseFunctional : ExprSpecializationFunctional surfaceBase) :
    ExprSpecializationFunctional (.member surfaceBase name) := by
  have inference : ExprInferenceSpecializationFunctional
      (.member surfaceBase name) :=
    ExprInferenceSpecializationFunctional.field
    baseFunctional.inference
  exact ⟨inference, ExprCheckingSpecializationFunctional.of_inference inference
    (by intro direct; cases direct),
    PlaceSpecializationFunctional.field baseFunctional.place⟩

end Lanius.ProgramElaboration
