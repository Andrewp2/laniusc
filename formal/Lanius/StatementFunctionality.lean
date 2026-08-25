import Lanius.ExpressionFunctionality

namespace Lanius.ProgramElaboration

open Lanius

theorem RangeBoundSpecializes.core_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : RangeBoundSpecializes substitution groundReturnType symbolic
      concrete contexts surface leftCore)
    (right : RangeBoundSpecializes substitution groundReturnType symbolic
      concrete contexts surface rightCore) :
    leftCore = rightCore := by
  cases left with
  | integer leftChecked =>
      cases right with
      | integer rightChecked =>
          exact ((exprSpecializationFunctional _).checking complete leftChecked
            rightChecked).2
  | «postfix» leftFormed leftChecked =>
      cases right with
      | «postfix» rightFormed rightChecked =>
          exact ((exprSpecializationFunctional _).checking complete leftChecked
            rightChecked).2

theorem RangeSpecializes.results_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : RangeSpecializes substitution groundReturnType symbolic concrete
      contexts kind start stop leftStart leftStop leftInclusive)
    (right : RangeSpecializes substitution groundReturnType symbolic concrete
      contexts kind start stop rightStart rightStop rightInclusive) :
    leftStart = rightStart ∧ leftStop = rightStop ∧
      leftInclusive = rightInclusive := by
  cases left with
  | full =>
      cases right
      exact ⟨rfl, rfl, rfl⟩
  | «from» leftStartBound =>
      cases right with
      | «from» rightStartBound =>
          cases leftStartBound.core_unique complete rightStartBound
          exact ⟨rfl, rfl, rfl⟩
  | toExclusive leftStopBound =>
      cases right with
      | toExclusive rightStopBound =>
          cases leftStopBound.core_unique complete rightStopBound
          exact ⟨rfl, rfl, rfl⟩
  | toInclusive leftStopBound =>
      cases right with
      | toInclusive rightStopBound =>
          cases leftStopBound.core_unique complete rightStopBound
          exact ⟨rfl, rfl, rfl⟩
  | exclusive leftStartBound leftStopBound =>
      cases right with
      | exclusive rightStartBound rightStopBound =>
          cases leftStartBound.core_unique complete rightStartBound
          cases leftStopBound.core_unique complete rightStopBound
          exact ⟨rfl, rfl, rfl⟩
  | inclusive leftStartBound leftStopBound =>
      cases right with
      | inclusive rightStartBound rightStopBound =>
          cases leftStartBound.core_unique complete rightStartBound
          cases leftStopBound.core_unique complete rightStopBound
          exact ⟨rfl, rfl, rfl⟩

theorem NamedRangeSpecializes.results_unique
    {symbolic : SymbolicBodyContext}
    {contexts : symbolic.Specializes substitution groundReturnType concrete}
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : NamedRangeSpecializes substitution groundReturnType symbolic concrete
      contexts path leftStart leftStop leftInclusive)
    (right : NamedRangeSpecializes substitution groundReturnType symbolic concrete
      contexts path rightStart rightStop rightInclusive) :
    leftStart = rightStart ∧ leftStop = rightStop ∧
      leftInclusive = rightInclusive := by
  cases left with
  | exclusive leftConstructor leftSelected leftDistinct leftIterable
      leftStartField leftEndField leftStartSelected leftEndSelected leftStartType
      leftEndType =>
      cases right with
      | exclusive rightConstructor rightSelected rightDistinct rightIterable
          rightStartField rightEndField rightStartSelected rightEndSelected
          rightStartType rightEndType =>
          have constructorEquality := complete.structConstructor_unique
            leftSelected rightSelected
          cases constructorEquality
          rcases (exprSpecializationFunctional _).inference complete leftIterable
              rightIterable with ⟨_symbolicEquality, _groundEquality, coreEquality⟩
          cases coreEquality
          have startFieldEquality := leftStartSelected.unique rightStartSelected
          cases startFieldEquality
          have endFieldEquality := leftEndSelected.unique rightEndSelected
          cases endFieldEquality
          exact ⟨rfl, rfl, rfl⟩
      | inclusive rightConstructor rightSelected rightDistinct rightIterable
          rightStartField rightEndField rightStartSelected rightEndSelected
          rightStartType rightEndType =>
          rcases (exprSpecializationFunctional _).inference complete leftIterable
              rightIterable with ⟨typeEquality, _groundEquality, _coreEquality⟩
          injection typeEquality with sourceTypeEquality
          exact (leftDistinct rightConstructor rightSelected
            sourceTypeEquality.symm).elim
  | inclusive leftConstructor leftSelected leftDistinct leftIterable
      leftStartField leftEndField leftStartSelected leftEndSelected leftStartType
      leftEndType =>
      cases right with
      | exclusive rightConstructor rightSelected rightDistinct rightIterable
          rightStartField rightEndField rightStartSelected rightEndSelected
          rightStartType rightEndType =>
          rcases (exprSpecializationFunctional _).inference complete leftIterable
              rightIterable with ⟨typeEquality, _groundEquality, _coreEquality⟩
          injection typeEquality with sourceTypeEquality
          exact (leftDistinct rightConstructor rightSelected
            sourceTypeEquality.symm).elim
      | inclusive rightConstructor rightSelected rightDistinct rightIterable
          rightStartField rightEndField rightStartSelected rightEndSelected
          rightStartType rightEndType =>
          have constructorEquality := complete.structConstructor_unique
            leftSelected rightSelected
          cases constructorEquality
          rcases (exprSpecializationFunctional _).inference complete leftIterable
              rightIterable with ⟨_symbolicEquality, _groundEquality, coreEquality⟩
          cases coreEquality
          have startFieldEquality := leftStartSelected.unique rightStartSelected
          cases startFieldEquality
          have endFieldEquality := leftEndSelected.unique rightEndSelected
          cases endFieldEquality
          exact ⟨rfl, rfl, rfl⟩
/-- Statement specialization is functional at a fixed symbolic/concrete body
    context and allocator position. The result includes both emitted Core and
    the final local-ID frontier because enclosing branches compose using that
    frontier. -/
def StmtsSpecializationFunctional (surface : List Surface.Stmt) : Prop :=
  ∀ {pack : Declarations.SourcePack} {catalog : Declarations.Catalog}
      {imports : List Declarations.CollectedImport} {program : Core.Program}
      {externalBindings : List ExternalBinding}
      {substitution : Static.Substitution}
      {groundReturnType : Static.GroundTy}
      {symbolic : SymbolicBodyContext}
      {concrete : SurfaceElaboration.Context} {next : VarId} {inLoop : Bool}
      {leftCore : Core.Stmt} {leftFinal : VarId} {rightCore : Core.Stmt}
      {rightFinal : VarId},
    CompleteProgramElaboration pack catalog imports program symbolic.globals
        externalBindings →
      StmtsSpecialize substitution groundReturnType symbolic concrete next
          inLoop surface leftCore leftFinal →
        StmtsSpecialize substitution groundReturnType symbolic concrete next
            inLoop surface rightCore rightFinal →
          leftCore = rightCore ∧ leftFinal = rightFinal

theorem StmtsSpecialize.results_unique
    {symbolic : SymbolicBodyContext}
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : StmtsSpecialize substitution groundReturnType symbolic concrete next
      inLoop surface leftCore leftFinal)
    (right : StmtsSpecialize substitution groundReturnType symbolic concrete next
      inLoop surface rightCore rightFinal) :
    leftCore = rightCore ∧ leftFinal = rightFinal := by
  induction left generalizing rightCore rightFinal with
  | nil leftContexts leftBounded =>
      cases right
      exact ⟨rfl, rfl⟩
  | expression leftContexts leftBounded leftHead leftTail tailIH =>
      cases right with
      | expression rightContexts rightBounded rightHead rightTail =>
          rcases (exprSpecializationFunctional _).inference complete leftHead
              rightHead with ⟨rfl, rfl, rfl⟩
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
  | letInferred leftContexts leftBounded leftInitializer leftCoreType leftTail
      tailIH =>
      cases right with
      | letInferred rightContexts rightBounded rightInitializer rightCoreType
          rightTail =>
          rcases (exprSpecializationFunctional _).inference complete
              leftInitializer rightInitializer with ⟨rfl, rfl, rfl⟩
          have loweredTypeEquality := Option.some.inj
            (leftCoreType.symm.trans rightCoreType)
          cases loweredTypeEquality
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
  | letAnnotated leftContexts leftBounded leftAnnotation leftInitializer
      leftCoreType leftTail tailIH =>
      cases right with
      | letAnnotated rightContexts rightBounded rightAnnotation rightInitializer
          rightCoreType rightTail =>
          have symbolicTypeEquality := TypeRetains.unique complete.metadataUnique
            leftAnnotation rightAnnotation
          cases symbolicTypeEquality
          rcases (exprSpecializationFunctional _).checking complete
              leftInitializer rightInitializer with ⟨rfl, rfl⟩
          have loweredTypeEquality := Option.some.inj
            (leftCoreType.symm.trans rightCoreType)
          cases loweredTypeEquality
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
  | letUninitialized leftContexts leftBounded leftAnnotation leftGrounds
      leftCoreType leftTail tailIH =>
      cases right with
      | letUninitialized rightContexts rightBounded rightAnnotation rightGrounds
          rightCoreType rightTail =>
          have symbolicTypeEquality := TypeRetains.unique complete.metadataUnique
            leftAnnotation rightAnnotation
          cases symbolicTypeEquality
          have groundTypeEquality := Option.some.inj
            (leftGrounds.symm.trans rightGrounds)
          cases groundTypeEquality
          have loweredTypeEquality := Option.some.inj
            (leftCoreType.symm.trans rightCoreType)
          cases loweredTypeEquality
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
  | returnUnit leftContexts leftBounded leftUnit leftTail tailIH =>
      cases right with
      | returnUnit rightContexts rightBounded rightUnit rightTail =>
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
  | returnValue leftContexts leftBounded leftValue leftTail tailIH =>
      cases right with
      | returnValue rightContexts rightBounded rightValue rightTail =>
          rcases (exprSpecializationFunctional _).checking complete leftValue
              rightValue with ⟨_groundEquality, rfl⟩
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
  | ifThenElse leftContexts leftBounded leftCondition leftThen leftElse leftTail
      thenIH elseIH tailIH =>
      cases right with
      | ifThenElse rightContexts rightBounded rightCondition rightThen rightElse
          rightTail =>
          rcases (exprSpecializationFunctional _).checking complete leftCondition
              rightCondition with ⟨_groundEquality, rfl⟩
          rcases thenIH complete rightThen with ⟨rfl, rfl⟩
          rcases elseIH complete rightElse with ⟨rfl, rfl⟩
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
  | whileLoop leftContexts leftBounded leftCondition leftBody leftTail bodyIH
      tailIH =>
      cases right with
      | whileLoop rightContexts rightBounded rightCondition rightBody rightTail =>
          rcases (exprSpecializationFunctional _).checking complete leftCondition
              rightCondition with ⟨_groundEquality, rfl⟩
          rcases bodyIH complete rightBody with ⟨rfl, rfl⟩
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
  | forArray leftContexts leftBounded leftIterable leftBody leftTail bodyIH
      tailIH =>
      cases right with
      | forArray rightContexts rightBounded rightIterable rightBody rightTail =>
          rcases (exprSpecializationFunctional _).inference complete leftIterable
              rightIterable with
            ⟨symbolicEquality, groundEquality, coreEquality⟩
          injection symbolicEquality with elementEquality lengthEquality
          injection groundEquality with groundElementEquality groundLengthEquality
          cases elementEquality
          cases lengthEquality
          cases groundElementEquality
          cases groundLengthEquality
          cases coreEquality
          rcases bodyIH complete rightBody with ⟨rfl, rfl⟩
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
      | forSlice rightContexts rightBounded rightIterable rightBody rightTail =>
          rcases (exprSpecializationFunctional _).inference complete leftIterable
              rightIterable with ⟨typeEquality, _groundEquality, _coreEquality⟩
          cases typeEquality
      | forNamedRange rightContexts rightBounded rightRange rightBody rightTail =>
          cases rightRange with
          | exclusive constructor selected distinct rightIterable startField endField
              startSelected endSelected startType endType =>
              rcases (exprSpecializationFunctional _).inference complete
                  leftIterable rightIterable with
                ⟨typeEquality, _groundEquality, _coreEquality⟩
              cases typeEquality
          | inclusive constructor selected distinct rightIterable startField endField
              startSelected endSelected startType endType =>
              rcases (exprSpecializationFunctional _).inference complete
                  leftIterable rightIterable with
                ⟨typeEquality, _groundEquality, _coreEquality⟩
              cases typeEquality
  | forSlice leftContexts leftBounded leftIterable leftBody leftTail bodyIH
      tailIH =>
      cases right with
      | forArray rightContexts rightBounded rightIterable rightBody rightTail =>
          rcases (exprSpecializationFunctional _).inference complete leftIterable
              rightIterable with ⟨typeEquality, _groundEquality, _coreEquality⟩
          cases typeEquality
      | forSlice rightContexts rightBounded rightIterable rightBody rightTail =>
          rcases (exprSpecializationFunctional _).inference complete leftIterable
              rightIterable with
            ⟨symbolicEquality, groundEquality, coreEquality⟩
          injection symbolicEquality with elementEquality
          injection groundEquality with groundElementEquality
          cases elementEquality
          cases groundElementEquality
          cases coreEquality
          rcases bodyIH complete rightBody with ⟨rfl, rfl⟩
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
      | forNamedRange rightContexts rightBounded rightRange rightBody rightTail =>
          cases rightRange with
          | exclusive constructor selected distinct rightIterable startField endField
              startSelected endSelected startType endType =>
              rcases (exprSpecializationFunctional _).inference complete
                  leftIterable rightIterable with
                ⟨typeEquality, _groundEquality, _coreEquality⟩
              cases typeEquality
          | inclusive constructor selected distinct rightIterable startField endField
              startSelected endSelected startType endType =>
              rcases (exprSpecializationFunctional _).inference complete
                  leftIterable rightIterable with
                ⟨typeEquality, _groundEquality, _coreEquality⟩
              cases typeEquality
  | forNamedRange leftContexts leftBounded leftRange leftBody leftTail bodyIH
      tailIH =>
      cases right with
      | forArray rightContexts rightBounded rightIterable rightBody rightTail =>
          cases leftRange with
          | exclusive constructor selected distinct leftIterable startField endField
              startSelected endSelected startType endType =>
              rcases (exprSpecializationFunctional _).inference complete
                  leftIterable rightIterable with
                ⟨typeEquality, _groundEquality, _coreEquality⟩
              cases typeEquality
          | inclusive constructor selected distinct leftIterable startField endField
              startSelected endSelected startType endType =>
              rcases (exprSpecializationFunctional _).inference complete
                  leftIterable rightIterable with
                ⟨typeEquality, _groundEquality, _coreEquality⟩
              cases typeEquality
      | forSlice rightContexts rightBounded rightIterable rightBody rightTail =>
          cases leftRange with
          | exclusive constructor selected distinct leftIterable startField endField
              startSelected endSelected startType endType =>
              rcases (exprSpecializationFunctional _).inference complete
                  leftIterable rightIterable with
                ⟨typeEquality, _groundEquality, _coreEquality⟩
              cases typeEquality
          | inclusive constructor selected distinct leftIterable startField endField
              startSelected endSelected startType endType =>
              rcases (exprSpecializationFunctional _).inference complete
                  leftIterable rightIterable with
                ⟨typeEquality, _groundEquality, _coreEquality⟩
              cases typeEquality
      | forNamedRange rightContexts rightBounded rightRange rightBody rightTail =>
          rcases leftRange.results_unique complete rightRange with
            ⟨rfl, rfl, rfl⟩
          rcases bodyIH complete rightBody with ⟨rfl, rfl⟩
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
  | forRange leftContexts leftBounded leftRange leftBody leftTail bodyIH tailIH =>
      cases right with
      | forRange rightContexts rightBounded rightRange rightBody rightTail =>
          rcases leftRange.results_unique complete rightRange with
            ⟨rfl, rfl, rfl⟩
          rcases bodyIH complete rightBody with ⟨rfl, rfl⟩
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
  | breakLoop leftContexts leftBounded leftInside leftTail tailIH =>
      cases right with
      | breakLoop rightContexts rightBounded rightInside rightTail =>
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
  | continueLoop leftContexts leftBounded leftInside leftTail tailIH =>
      cases right with
      | continueLoop rightContexts rightBounded rightInside rightTail =>
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩
  | block leftContexts leftBounded leftBody leftTail bodyIH tailIH =>
      cases right with
      | block rightContexts rightBounded rightBody rightTail =>
          rcases bodyIH complete rightBody with ⟨rfl, rfl⟩
          rcases tailIH complete rightTail with ⟨rfl, rfl⟩
          exact ⟨rfl, rfl⟩

theorem stmtsSpecializationFunctional (surface : List Surface.Stmt) :
    StmtsSpecializationFunctional surface := by
  intro pack catalog imports program externalBindings substitution
    groundReturnType symbolic concrete next inLoop leftCore leftFinal rightCore
    rightFinal complete left right
  exact left.results_unique complete right

end Lanius.ProgramElaboration
