import Lanius.Extraction.Lexer.Digits
import Lanius.FunctionalViewCoreEffectfulStateful

namespace Lanius.Extraction.Lexer.DigitAccessorContracts

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful

/-! # Checked `DigitScan` accessor contracts

These contracts execute the three accessor bodies decoded from the checked
`digits.lani` artifact.  The shared proof is parameterized only by the field
number; each public theorem supplies the exact artifact function, body, and
function-table lookup from `verifiedFrontendDigitsCore`.
-/

def resultType : Ty := .structure 2

def resultValue (success : Bool) (endOffset errorOffset : Int) : Value :=
  .structure 2 [
    .boolean success,
    .signed .i32 endOffset,
    .signed .i32 errorOffset]

def accessorBody (field : Lanius.FieldId) : Stmt :=
  .sequence (.returnValue (some (.field (.local 0) field))) .skip

theorem digitScanSucceededBody_eq :
    Digits.digitScanSucceededBody = accessorBody 0 := by
  rfl

theorem digitScanEndOffsetBody_eq :
    Digits.digitScanEndOffsetBody = accessorBody 1 := by
  rfl

theorem digitScanErrorOffsetBody_eq :
    Digits.digitScanErrorOffsetBody = accessorBody 2 := by
  rfl

theorem verifiedFrontendDigitsCore_finds_digitScanSucceeded :
    verifiedFrontendDigitsCore.function?
        Digits.digitScanSucceededFunction.id =
      some Digits.digitScanSucceededFunction := by
  rfl

theorem verifiedFrontendDigitsCore_finds_digitScanEndOffset :
    verifiedFrontendDigitsCore.function?
        Digits.digitScanEndOffsetFunction.id =
      some Digits.digitScanEndOffsetFunction := by
  rfl

theorem verifiedFrontendDigitsCore_finds_digitScanErrorOffset :
    verifiedFrontendDigitsCore.function?
        Digits.digitScanErrorOffsetFunction.id =
      some Digits.digitScanErrorOffsetFunction := by
  rfl

theorem digitScanSucceededFunction_parameters :
    Digits.digitScanSucceededFunction.parameters = [(0, resultType)] := by
  rfl

theorem digitScanEndOffsetFunction_parameters :
    Digits.digitScanEndOffsetFunction.parameters = [(0, resultType)] := by
  rfl

theorem digitScanErrorOffsetFunction_parameters :
    Digits.digitScanErrorOffsetFunction.parameters = [(0, resultType)] := by
  rfl

theorem digitScanSucceededFunction_body :
    Digits.digitScanSucceededFunction.body =
      some Digits.digitScanSucceededBody := by
  rfl

theorem digitScanEndOffsetFunction_body :
    Digits.digitScanEndOffsetFunction.body =
      some Digits.digitScanEndOffsetBody := by
  rfl

theorem digitScanErrorOffsetFunction_body :
    Digits.digitScanErrorOffsetFunction.body =
      some Digits.digitScanErrorOffsetBody := by
  rfl

private theorem accessorBody_executes
    (state : State) (fields : List Value) (field : Lanius.FieldId)
    (value : Value)
    (resultLocal : state.local? 0 = some (.structure 2 fields))
    (fieldFound : fields[field]? = some value) :
    Executes verifiedFrontendDigitsCore state (accessorBody field)
      (.returned (some value)) state := by
  have localEvaluation : Evaluates verifiedFrontendDigitsCore state (.local 0)
      (.structure 2 fields) state :=
    ⟨1, evalLocal_of_local 1 verifiedFrontendDigitsCore state 0 _ resultLocal⟩
  have fieldEvaluation : Evaluates verifiedFrontendDigitsCore state
      (.field (.local 0) field) value state :=
    evaluatesStructureField localEvaluation fieldFound
  exact executesSequenceReturned (executesReturnValue fieldEvaluation)

theorem digitScanSucceededBody_executes
    (state : State) (success : Bool) (endOffset errorOffset : Int)
    (resultLocal : state.local? 0 =
      some (resultValue success endOffset errorOffset)) :
    Executes verifiedFrontendDigitsCore state Digits.digitScanSucceededBody
      (.returned (some (.boolean success))) state := by
  rw [digitScanSucceededBody_eq]
  exact accessorBody_executes state _ 0 (.boolean success) resultLocal rfl

theorem digitScanEndOffsetBody_executes
    (state : State) (success : Bool) (endOffset errorOffset : Int)
    (resultLocal : state.local? 0 =
      some (resultValue success endOffset errorOffset)) :
    Executes verifiedFrontendDigitsCore state Digits.digitScanEndOffsetBody
      (.returned (some (.signed .i32 endOffset))) state := by
  rw [digitScanEndOffsetBody_eq]
  exact accessorBody_executes state _ 1 (.signed .i32 endOffset) resultLocal rfl

theorem digitScanErrorOffsetBody_executes
    (state : State) (success : Bool) (endOffset errorOffset : Int)
    (resultLocal : state.local? 0 =
      some (resultValue success endOffset errorOffset)) :
    Executes verifiedFrontendDigitsCore state Digits.digitScanErrorOffsetBody
      (.returned (some (.signed .i32 errorOffset))) state := by
  rw [digitScanErrorOffsetBody_eq]
  exact accessorBody_executes state _ 2 (.signed .i32 errorOffset) resultLocal rfl

def accessorBindings (fields : List Value) : List (VarId × Value) :=
  [(0, .structure 2 fields)]

def accessorCallState (state : State) (fields : List Value) : State :=
  restoreLocals state (enterCall state (accessorBindings fields))

private theorem accessorCall_evaluates
    (function : Function) (body : Stmt) (field : Lanius.FieldId)
    (before afterArguments : State) (arguments : List Expr)
    (fields : List Value) (value : Value)
    (foundFunction : verifiedFrontendDigitsCore.function? function.id =
      some function)
    (parameters : function.parameters = [(0, resultType)])
    (functionBody : function.body = some body)
    (bodyShape : body = accessorBody field)
    (fieldFound : fields[field]? = some value)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendDigitsCore before
      arguments [.structure 2 fields] afterArguments) :
    Evaluates verifiedFrontendDigitsCore before (.call function.id arguments)
      value (accessorCallState afterArguments fields) := by
  let callee := enterCall afterArguments (accessorBindings fields)
  have resultLocal : callee.local? 0 = some (.structure 2 fields) := by
    simpa [callee, accessorBindings] using
      enterCall_local_of_binding afterArguments [] [] 0
        (.structure 2 fields) afterArgumentsWellFormed (by simp)
  have bodyExecution : Executes verifiedFrontendDigitsCore callee body
      (.returned (some value)) callee := by
    rw [bodyShape]
    exact accessorBody_executes callee fields field value resultLocal fieldFound
  apply evaluatesCallReturned argumentsResult foundFunction
  · rw [parameters]
    rfl
  · exact functionBody
  · simpa [callee, accessorCallState, accessorBindings] using bodyExecution

theorem digitScanSucceededCall_evaluates
    (before afterArguments : State) (arguments : List Expr)
    (success : Bool) (endOffset errorOffset : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendDigitsCore before
      arguments [resultValue success endOffset errorOffset] afterArguments) :
    Evaluates verifiedFrontendDigitsCore before
      (.call Digits.digitScanSucceededFunction.id arguments)
      (.boolean success)
      (accessorCallState afterArguments [
        .boolean success, .signed .i32 endOffset, .signed .i32 errorOffset]) := by
  exact accessorCall_evaluates Digits.digitScanSucceededFunction
    Digits.digitScanSucceededBody 0 before afterArguments arguments _ _
    verifiedFrontendDigitsCore_finds_digitScanSucceeded
    digitScanSucceededFunction_parameters digitScanSucceededFunction_body
    digitScanSucceededBody_eq rfl afterArgumentsWellFormed argumentsResult

theorem digitScanEndOffsetCall_evaluates
    (before afterArguments : State) (arguments : List Expr)
    (success : Bool) (endOffset errorOffset : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendDigitsCore before
      arguments [resultValue success endOffset errorOffset] afterArguments) :
    Evaluates verifiedFrontendDigitsCore before
      (.call Digits.digitScanEndOffsetFunction.id arguments)
      (.signed .i32 endOffset)
      (accessorCallState afterArguments [
        .boolean success, .signed .i32 endOffset, .signed .i32 errorOffset]) := by
  exact accessorCall_evaluates Digits.digitScanEndOffsetFunction
    Digits.digitScanEndOffsetBody 1 before afterArguments arguments _ _
    verifiedFrontendDigitsCore_finds_digitScanEndOffset
    digitScanEndOffsetFunction_parameters digitScanEndOffsetFunction_body
    digitScanEndOffsetBody_eq rfl afterArgumentsWellFormed argumentsResult

theorem digitScanErrorOffsetCall_evaluates
    (before afterArguments : State) (arguments : List Expr)
    (success : Bool) (endOffset errorOffset : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendDigitsCore before
      arguments [resultValue success endOffset errorOffset] afterArguments) :
    Evaluates verifiedFrontendDigitsCore before
      (.call Digits.digitScanErrorOffsetFunction.id arguments)
      (.signed .i32 errorOffset)
      (accessorCallState afterArguments [
        .boolean success, .signed .i32 endOffset, .signed .i32 errorOffset]) := by
  exact accessorCall_evaluates Digits.digitScanErrorOffsetFunction
    Digits.digitScanErrorOffsetBody 2 before afterArguments arguments _ _
    verifiedFrontendDigitsCore_finds_digitScanErrorOffset
    digitScanErrorOffsetFunction_parameters digitScanErrorOffsetFunction_body
    digitScanErrorOffsetBody_eq rfl afterArgumentsWellFormed argumentsResult

def callsFor (function : FunctionId) (field : Lanius.FieldId) : CallModel where
  evaluate := fun world candidate values =>
    if candidate = function then
      match values with
      | [.structure 2 fields] =>
          match fields[field]? with
          | some value => .ok (value, world)
          | none => .error .typeMismatch
      | _ => .error .typeMismatch
    else
      .error .invalidPointer

private theorem callsFor_success
    (evaluated : (callsFor expectedFunction field).evaluate world function
      values = .ok (value, afterWorld)) :
    ∃ fields,
      function = expectedFunction ∧
      values = [.structure 2 fields] ∧
      fields[field]? = some value ∧
      afterWorld = world := by
  simp only [callsFor] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next fields =>
      split at evaluated
      next found =>
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨fields, functionEq, rfl, found, rfl⟩
      next => contradiction
    next => contradiction
  next => contradiction

private theorem callSoundnessFor
    (function : Function) (body : Stmt) (field : Lanius.FieldId)
    (foundFunction : verifiedFrontendDigitsCore.function? function.id =
      some function)
    (parameters : function.parameters = [(0, resultType)])
    (functionBody : function.body = some body)
    (bodyShape : body = accessorBody field) :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendDigitsCore (callsFor function.id field) := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld callerEnvironment
      before afterArguments calledFunction arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨fields, functionEq, valuesEq, fieldFound, worldEq⟩ :=
      callsFor_success (expectedFunction := function.id) (field := field)
        evaluated
    subst calledFunction
    subst values
    subst afterWorld
    let callee := enterCall afterArguments (accessorBindings fields)
    let after := accessorCallState afterArguments fields
    have callExecution : Evaluates verifiedFrontendDigitsCore before
        (.call function.id (toCoreExprs layout arguments)) value after := by
      exact accessorCall_evaluates function body field before afterArguments
        (toCoreExprs layout arguments) fields value foundFunction parameters
        functionBody bodyShape fieldFound afterArgumentsWellFormed
        argumentsExecution
    have entered : StoreEffect CellSet.empty afterArguments callee := by
      simpa [callee] using
        enterCall_effect afterArguments (accessorBindings fields)
    have calleeWellFormed : StateWellFormed callee := by
      simpa [callee] using
        (enterCall_preserves_wellFormed
          (bindings := accessorBindings fields) afterArgumentsWellFormed)
    have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
      simpa [after, accessorCallState, callee] using entered.restoreLocals
    have afterWellFormed : StateWellFormed after := by
      simpa [after, accessorCallState, callee] using
        entered.restoreLocals_wellFormed afterArgumentsWellFormed
          calleeWellFormed
    have afterRepresented : Representation layout localCell beforeWorld
        callerEnvironment after := {
      worldOwned := callEffect.empty_preserves_assertion
        afterArgumentsWellFormed (World.owns beforeWorld)
        represented.worldOwned
      localOwned := fun index => callEffect.empty_preserves_assertion
        afterArgumentsWellFormed
        (Assertion.localPointsTo (layout index) (localCell index)
          (some (callerEnvironment index))) (represented.localOwned index)
      localCellsInjective := represented.localCellsInjective
      worldLocalsDisjoint := represented.worldLocalsDisjoint
    }
    exact ⟨after, CellSet.union argumentWrites CellSet.empty, callExecution,
      afterWellFormed, afterRepresented, argumentsEffect.trans callEffect⟩
  · intro beforeWorld afterWorld calledFunction values value evaluated cell
    obtain ⟨fields, functionEq, valuesEq, fieldFound, worldEq⟩ :=
      callsFor_success (expectedFunction := function.id) (field := field)
        evaluated
    exact congrArg (fun currentWorld : World =>
      (currentWorld.i32Slice? cell).map List.length) worldEq

def digitScanSucceededCalls : CallModel :=
  callsFor Digits.digitScanSucceededFunction.id 0

def digitScanEndOffsetCalls : CallModel :=
  callsFor Digits.digitScanEndOffsetFunction.id 1

def digitScanErrorOffsetCalls : CallModel :=
  callsFor Digits.digitScanErrorOffsetFunction.id 2

theorem digitScanSucceededCalls_at_result :
    digitScanSucceededCalls.evaluate worldValue
        Digits.digitScanSucceededFunction.id
        [resultValue success endOffset errorOffset] =
      .ok (.boolean success, worldValue) := by
  rfl

theorem digitScanEndOffsetCalls_at_result :
    digitScanEndOffsetCalls.evaluate worldValue
        Digits.digitScanEndOffsetFunction.id
        [resultValue success endOffset errorOffset] =
      .ok (.signed .i32 endOffset, worldValue) := by
  rfl

theorem digitScanErrorOffsetCalls_at_result :
    digitScanErrorOffsetCalls.evaluate worldValue
        Digits.digitScanErrorOffsetFunction.id
        [resultValue success endOffset errorOffset] =
      .ok (.signed .i32 errorOffset, worldValue) := by
  rfl

theorem digitScanSucceededCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendDigitsCore digitScanSucceededCalls := by
  exact callSoundnessFor Digits.digitScanSucceededFunction
    Digits.digitScanSucceededBody 0
    verifiedFrontendDigitsCore_finds_digitScanSucceeded
    digitScanSucceededFunction_parameters digitScanSucceededFunction_body
    digitScanSucceededBody_eq

theorem digitScanEndOffsetCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendDigitsCore digitScanEndOffsetCalls := by
  exact callSoundnessFor Digits.digitScanEndOffsetFunction
    Digits.digitScanEndOffsetBody 1
    verifiedFrontendDigitsCore_finds_digitScanEndOffset
    digitScanEndOffsetFunction_parameters digitScanEndOffsetFunction_body
    digitScanEndOffsetBody_eq

theorem digitScanErrorOffsetCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendDigitsCore digitScanErrorOffsetCalls := by
  exact callSoundnessFor Digits.digitScanErrorOffsetFunction
    Digits.digitScanErrorOffsetBody 2
    verifiedFrontendDigitsCore_finds_digitScanErrorOffset
    digitScanErrorOffsetFunction_parameters digitScanErrorOffsetFunction_body
    digitScanErrorOffsetBody_eq

end Lanius.Extraction.Lexer.DigitAccessorContracts
