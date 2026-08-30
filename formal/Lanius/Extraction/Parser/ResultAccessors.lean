import Lanius.Extraction.VerifiedParserResult
import Lanius.FunctionalViewCoreReification

namespace Lanius.Extraction.Parser.ResultAccessors

open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction.ParserResult
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Reification

/-! # Public `ParseResult` accessors

The four views in this module are mechanically recovered from the checked
`parser.lani` artifact. A shared semantic contract captures their actual
uniform behavior: bind one `ParseResult`, project one field, return it, and
preserve every caller-owned resource.
-/

def parseStatusWire : CoreFunction :=
  artifact_function%
    (include_str "../Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "parse_status"

def parseStateCountWire : CoreFunction :=
  artifact_function%
    (include_str "../Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "parse_state_count"

def parseRootStateWire : CoreFunction :=
  artifact_function%
    (include_str "../Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "parse_root_state"

def parseErrorPositionWire : CoreFunction :=
  artifact_function%
    (include_str "../Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "parse_error_position"

def parseStatusFunction : Function := CoreDecode.function parseStatusWire
def parseStateCountFunction : Function := CoreDecode.function parseStateCountWire
def parseRootStateFunction : Function := CoreDecode.function parseRootStateWire
def parseErrorPositionFunction : Function :=
  CoreDecode.function parseErrorPositionWire

def resultType : Ty := .structure 0

def accessorBody (field : FieldId) : Stmt :=
  .sequence (.returnValue (some (.field (.local 0) field))) .skip

def functionBody (function : Function) : Stmt :=
  function.body.getD .skip

theorem function_shapes :
    parseStatusFunction.id = 0 ∧
      parseStateCountFunction.id = 1 ∧
      parseRootStateFunction.id = 2 ∧
      parseErrorPositionFunction.id = 3 ∧
      parseStatusFunction.parameters = [(0, resultType)] ∧
      parseStateCountFunction.parameters = [(0, resultType)] ∧
      parseRootStateFunction.parameters = [(0, resultType)] ∧
      parseErrorPositionFunction.parameters = [(0, resultType)] ∧
      parseStatusFunction.returnType = parserI32Type ∧
      parseStateCountFunction.returnType = parserI32Type ∧
      parseRootStateFunction.returnType = parserI32Type ∧
      parseErrorPositionFunction.returnType = parserI32Type ∧
      parseStatusFunction.body = some (accessorBody 0) ∧
      parseStateCountFunction.body = some (accessorBody 1) ∧
      parseRootStateFunction.body = some (accessorBody 2) ∧
      parseErrorPositionFunction.body = some (accessorBody 3) := by
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl,
    rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem core_finds_parseStatus :
    verifiedParserCore.function? parseStatusFunction.id =
      some parseStatusFunction := by
  unfold verifiedParserCore parseStatusFunction parseStatusWire
  rfl

theorem core_finds_parseStateCount :
    verifiedParserCore.function? parseStateCountFunction.id =
      some parseStateCountFunction := by
  unfold verifiedParserCore parseStateCountFunction parseStateCountWire
  rfl

theorem core_finds_parseRootState :
    verifiedParserCore.function? parseRootStateFunction.id =
      some parseRootStateFunction := by
  unfold verifiedParserCore parseRootStateFunction parseRootStateWire
  rfl

theorem core_finds_parseErrorPosition :
    verifiedParserCore.function? parseErrorPositionFunction.id =
      some parseErrorPositionFunction := by
  unfold verifiedParserCore parseErrorPositionFunction parseErrorPositionWire
  rfl

def reification? (function : Function) :=
  reifyBlock? verifiedParserCore function.returnType
    (Lanius.Typing.parameterContext function.parameters) false
    (identityLayout (arity := function.parameters.length))
    function.parameters.length (functionBody function)

theorem parseStatusReification_exists :
    (reification? parseStatusFunction).isSome := by native_decide

theorem parseStateCountReification_exists :
    (reification? parseStateCountFunction).isSome := by native_decide

theorem parseRootStateReification_exists :
    (reification? parseRootStateFunction).isSome := by native_decide

theorem parseErrorPositionReification_exists :
    (reification? parseErrorPositionFunction).isSome := by native_decide

def parseStatusView :=
  (reification? parseStatusFunction).get parseStatusReification_exists

def parseStateCountView :=
  (reification? parseStateCountFunction).get parseStateCountReification_exists

def parseRootStateView :=
  (reification? parseRootStateFunction).get parseRootStateReification_exists

def parseErrorPositionView :=
  (reification? parseErrorPositionFunction).get
    parseErrorPositionReification_exists

theorem parseStatusView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 parseStatusView.block =
      functionBody parseStatusFunction :=
  parseStatusView.toCoreExactly

theorem parseStateCountView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 parseStateCountView.block =
      functionBody parseStateCountFunction :=
  parseStateCountView.toCoreExactly

theorem parseRootStateView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 parseRootStateView.block =
      functionBody parseRootStateFunction :=
  parseRootStateView.toCoreExactly

theorem parseErrorPositionView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1
        parseErrorPositionView.block =
      functionBody parseErrorPositionFunction :=
  parseErrorPositionView.toCoreExactly

private def slot0 : Term signature 1 :=
  .reference (.slot ⟨0, by omega⟩)

def accessorBlock (field : FieldId) : Block signature 1 :=
  .sequence
    (.returnValue (some
      (.apply (.field resultType field parserI32Type) [slot0])))
    .skip

theorem parseStatus_agrees_with_reification :
    toCoreStmt (identityLayout (arity := 1)) 1 (accessorBlock 0) =
      toCoreStmt (identityLayout (arity := 1)) 1 parseStatusView.block := by
  rw [parseStatusView_toCore_exactly]
  rfl

theorem parseStateCount_agrees_with_reification :
    toCoreStmt (identityLayout (arity := 1)) 1 (accessorBlock 1) =
      toCoreStmt (identityLayout (arity := 1)) 1 parseStateCountView.block := by
  rw [parseStateCountView_toCore_exactly]
  rfl

theorem parseRootState_agrees_with_reification :
    toCoreStmt (identityLayout (arity := 1)) 1 (accessorBlock 2) =
      toCoreStmt (identityLayout (arity := 1)) 1 parseRootStateView.block := by
  rw [parseRootStateView_toCore_exactly]
  rfl

theorem parseErrorPosition_agrees_with_reification :
    toCoreStmt (identityLayout (arity := 1)) 1 (accessorBlock 3) =
      toCoreStmt (identityLayout (arity := 1)) 1
        parseErrorPositionView.block := by
  rw [parseErrorPositionView_toCore_exactly]
  rfl

def world : World := { i32Slice? := fun _ => none }

def environment (status stateCount rootState errorPosition : Int) : Env 1 :=
  fun _ => parseResultValue status stateCount rootState errorPosition

theorem parseStatus_evaluates
    (status stateCount rootState errorPosition : Int) :
    Block.evaluate (ReadOnly.machine verifiedParserCore) world
        (environment status stateCount rootState errorPosition)
        (accessorBlock 0) =
      .done (.returned (some (.signed .i32 status))) world := by
  rfl

theorem parseStateCount_evaluates
    (status stateCount rootState errorPosition : Int) :
    Block.evaluate (ReadOnly.machine verifiedParserCore) world
        (environment status stateCount rootState errorPosition)
        (accessorBlock 1) =
      .done (.returned (some (.signed .i32 stateCount))) world := by
  rfl

theorem parseRootState_evaluates
    (status stateCount rootState errorPosition : Int) :
    Block.evaluate (ReadOnly.machine verifiedParserCore) world
        (environment status stateCount rootState errorPosition)
        (accessorBlock 2) =
      .done (.returned (some (.signed .i32 rootState))) world := by
  rfl

theorem parseErrorPosition_evaluates
    (status stateCount rootState errorPosition : Int) :
    Block.evaluate (ReadOnly.machine verifiedParserCore) world
        (environment status stateCount rootState errorPosition)
        (accessorBlock 3) =
      .done (.returned (some (.signed .i32 errorPosition))) world := by
  rfl

def callsFor (function : FunctionId) (field : FieldId) : CallModel where
  evaluate := fun world candidate values =>
    if candidate = function then
      match values with
      | [.structure 0 fields] =>
          match fields[field]? with
          | some value => .ok (value, world)
          | none => .error .typeMismatch
      | _ => .error .typeMismatch
    else
      .error .invalidPointer

theorem callsFor_success
    {world : World} {function : FunctionId} {values : List Value}
    {value : Value} {afterWorld : World}
    (evaluated : (callsFor expectedFunction field).evaluate world function
      values = .ok (value, afterWorld)) :
    ∃ fields,
      function = expectedFunction ∧
      values = [.structure 0 fields] ∧
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

def accessorBindings (fields : List Value) : List (VarId × Value) :=
  [(0, .structure 0 fields)]

def accessorCallState (state : State) (fields : List Value) : State :=
  restoreLocals state (enterCall state (accessorBindings fields))

theorem callSoundnessFor
    (function : Function) (field : FieldId)
    (foundFunction : verifiedParserCore.function? function.id = some function)
    (parameters : function.parameters = [(0, resultType)])
    (body : function.body = some (accessorBody field)) :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore (callsFor function.id field) := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld callerEnvironment
      before afterArguments calledFunction arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨fields, functionEq, valuesEq, fieldFound, worldEq⟩ :=
      callsFor_success (expectedFunction := function.id) (field := field)
        (world := beforeWorld) (function := calledFunction) (values := values)
        (value := value) (afterWorld := afterWorld) evaluated
    subst calledFunction
    subst values
    subst afterWorld
    let callee := enterCall afterArguments (accessorBindings fields)
    let after := restoreLocals afterArguments callee
    have calleeWellFormed : StateWellFormed callee := by
      simpa [callee] using
        (enterCall_preserves_wellFormed
          (bindings := accessorBindings fields) afterArgumentsWellFormed)
    have resultLocal : callee.local? 0 = some (.structure 0 fields) := by
      simpa [callee, accessorBindings] using
        enterCall_local_of_binding afterArguments [] [] 0
          (.structure 0 fields) afterArgumentsWellFormed (by simp)
    have localEvaluation : Evaluates verifiedParserCore callee (.local 0)
        (.structure 0 fields) callee :=
      ⟨1, evalLocal_of_local 1 verifiedParserCore callee 0 _ resultLocal⟩
    have fieldEvaluation : Evaluates verifiedParserCore callee
        (.field (.local 0) field) value callee :=
      evaluatesStructureField localEvaluation fieldFound
    have bodyExecution : Executes verifiedParserCore callee
        (accessorBody field) (.returned (some value)) callee := by
      exact executesSequenceReturned
        (executesReturnValue fieldEvaluation)
    have callExecution : Evaluates verifiedParserCore before
        (.call function.id (toCoreExprs layout arguments)) value after := by
      apply evaluatesCallReturned argumentsExecution foundFunction
      · rw [parameters]
        rfl
      · exact body
      · simpa [callee, after, accessorBindings] using bodyExecution
    have entered : StoreEffect CellSet.empty afterArguments callee := by
      simpa [callee] using
        enterCall_effect afterArguments (accessorBindings fields)
    have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
      simpa [after] using entered.restoreLocals
    have afterWellFormed : StateWellFormed after := by
      exact entered.restoreLocals_wellFormed afterArgumentsWellFormed
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
        (world := beforeWorld) (function := calledFunction) (values := values)
        (value := value) (afterWorld := afterWorld) evaluated
    exact congrArg (fun currentWorld : World =>
      (currentWorld.i32Slice? cell).map List.length) worldEq

def parseStatusCalls : CallModel := callsFor parseStatusFunction.id 0
def parseStateCountCalls : CallModel := callsFor parseStateCountFunction.id 1
def parseRootStateCalls : CallModel := callsFor parseRootStateFunction.id 2
def parseErrorPositionCalls : CallModel :=
  callsFor parseErrorPositionFunction.id 3

theorem parseStatusCalls_at_result :
    parseStatusCalls.evaluate worldValue parseStatusFunction.id
        [parseResultValue status stateCount rootState errorPosition] =
      .ok (.signed .i32 status, worldValue) := by
  rfl

theorem parseStateCountCalls_at_result :
    parseStateCountCalls.evaluate worldValue parseStateCountFunction.id
        [parseResultValue status stateCount rootState errorPosition] =
      .ok (.signed .i32 stateCount, worldValue) := by
  rfl

theorem parseRootStateCalls_at_result :
    parseRootStateCalls.evaluate worldValue parseRootStateFunction.id
        [parseResultValue status stateCount rootState errorPosition] =
      .ok (.signed .i32 rootState, worldValue) := by
  rfl

theorem parseErrorPositionCalls_at_result :
    parseErrorPositionCalls.evaluate worldValue parseErrorPositionFunction.id
        [parseResultValue status stateCount rootState errorPosition] =
      .ok (.signed .i32 errorPosition, worldValue) := by
  rfl

theorem parseStatusCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore parseStatusCalls := by
  exact callSoundnessFor parseStatusFunction 0 core_finds_parseStatus
    function_shapes.2.2.2.2.1 function_shapes.2.2.2.2.2.2.2.2.2.2.2.2.1

theorem parseStateCountCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore parseStateCountCalls := by
  exact callSoundnessFor parseStateCountFunction 1 core_finds_parseStateCount
    function_shapes.2.2.2.2.2.1
    function_shapes.2.2.2.2.2.2.2.2.2.2.2.2.2.1

theorem parseRootStateCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore parseRootStateCalls := by
  exact callSoundnessFor parseRootStateFunction 2 core_finds_parseRootState
    function_shapes.2.2.2.2.2.2.1
    function_shapes.2.2.2.2.2.2.2.2.2.2.2.2.2.2.1

theorem parseErrorPositionCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore parseErrorPositionCalls := by
  exact callSoundnessFor parseErrorPositionFunction 3
    core_finds_parseErrorPosition function_shapes.2.2.2.2.2.2.2.1
    function_shapes.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2

end Lanius.Extraction.Parser.ResultAccessors
