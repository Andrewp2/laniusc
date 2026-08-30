import Lanius.Extraction.VerifiedParserAppend
import Lanius.FunctionalViewCoreEffectful
import Lanius.FunctionalViewCoreEffectfulStateful
import Lanius.FunctionalViewCoreReadOnly

namespace Lanius.Extraction.ParserResult

open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction
open Lanius.Extraction.ParserAppend
open Lanius.Compiler.Parser

def extractedParserParseResultWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "parse_result"

def extractedParserParseResultFunction : Function :=
  CoreDecode.function extractedParserParseResultWire

def extractedParserAppendOrFullWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "append_or_full"

def extractedParserAppendOrFullFunction : Function :=
  CoreDecode.function extractedParserAppendOrFullWire

def parseResultValue
    (status stateCount rootState errorPosition : Int) : Value :=
  .structure 0 [
    .signed .i32 status,
    .signed .i32 stateCount,
    .signed .i32 rootState,
    .signed .i32 errorPosition]

def parserParseResultBindings
    (status stateCount rootState errorPosition : Int) :
    List (VarId × Value) := [
  (0, .signed .i32 status),
  (1, .signed .i32 stateCount),
  (2, .signed .i32 rootState),
  (3, .signed .i32 errorPosition)]

def parserParseResultCallee
    (caller : State) (status stateCount rootState errorPosition : Int) : State :=
  enterCall caller
    (parserParseResultBindings status stateCount rootState errorPosition)

def parserParseResultExpr : Expr :=
  .structValue 0 [.local 0, .local 1, .local 2, .local 3]

def parserParseResultBody : Stmt :=
  .sequence (.returnValue (some parserParseResultExpr)) .skip

theorem extractedParserParseResult_function_shape :
    extractedParserParseResultFunction.id = 4 ∧
      extractedParserParseResultFunction.parameters = [
        (0, parserI32Type), (1, parserI32Type), (2, parserI32Type),
        (3, parserI32Type)] ∧
      extractedParserParseResultFunction.returnType = .structure 0 ∧
      extractedParserParseResultFunction.body = some parserParseResultBody ∧
      extractedParserParseResultFunction.external = none := by
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem verifiedParserCore_finds_parseResult :
    verifiedParserCore.function? extractedParserParseResultFunction.id =
      some extractedParserParseResultFunction := by
  unfold verifiedParserCore extractedParserParseResultFunction
    extractedParserParseResultWire
  rfl

namespace ParseResultProof

open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly

def world : World := { i32Slice? := fun _ => none }

def environment
    (status stateCount rootState errorPosition : Int) : Env 4
  | ⟨0, _⟩ => .signed .i32 status
  | ⟨1, _⟩ => .signed .i32 stateCount
  | ⟨2, _⟩ => .signed .i32 rootState
  | ⟨3, _⟩ => .signed .i32 errorPosition

theorem parameterBindings_eq
    (status stateCount rootState errorPosition : Int) :
    Lanius.FunctionalView.Core.parameterBindings
        (environment status stateCount rootState errorPosition) =
      parserParseResultBindings status stateCount rootState errorPosition := by
  apply List.ext_getElem
  · simp [parserParseResultBindings]
  · intro index leftBound rightBound
    have alternatives : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 := by
      simp [parserParseResultBindings] at rightBound
      omega
    rcases alternatives with rfl | rfl | rfl | rfl <;>
      simp [Lanius.FunctionalView.Core.parameterBindings_getElem,
        parserParseResultBindings, environment]

private def resultTerm : Term Lanius.FunctionalView.Core.signature 4 :=
  .apply (.structValue 0
      [parserI32Type, parserI32Type, parserI32Type, parserI32Type]) [
    .reference (.slot ⟨0, by omega⟩),
    .reference (.slot ⟨1, by omega⟩),
    .reference (.slot ⟨2, by omega⟩),
    .reference (.slot ⟨3, by omega⟩)]

def body : Block Lanius.FunctionalView.Core.signature 4 :=
  .sequence (.returnValue (some resultTerm)) .skip

theorem localCapacity_eq_zero :
    Lanius.FunctionalView.Core.localCapacity body = 0 := by rfl

/-- The functional constructor translates exactly to the body decoded from
    the checked `parser.lani` artifact. -/
theorem body_toCore_exactly :
    toCoreStmt (identityLayout (arity := 4)) 4 body =
      parserParseResultBody := by
  rfl

theorem evaluates (status stateCount rootState errorPosition : Int) :
    Block.evaluate (machine verifiedParserCore) world
        (environment status stateCount rootState errorPosition) body =
      .done (.returned (some
        (parseResultValue status stateCount rootState errorPosition))) world := by
  rfl

theorem world_represents (state : State) : World.Represents world state := by
  intro _ _ found
  simp [world] at found

end ParseResultProof

namespace ParseResultCallProof

open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful

/-- Functional semantics for the checked `parse_result` source function.
    This entry is intentionally separate from the generic effectful simulator:
    parser functions are registered here, while FunctionalView itself remains
    independent of any one source program. -/
def calls : CallModel where
  evaluate := fun world function values =>
    if function = extractedParserParseResultFunction.id then
      match values with
      | [.signed .i32 status, .signed .i32 stateCount,
          .signed .i32 rootState, .signed .i32 errorPosition] =>
          .ok (parseResultValue status stateCount rootState errorPosition,
            world)
      | _ => .error .typeMismatch
    else
      .error .invalidPointer

theorem calls_success
    (evaluated : calls.evaluate world function values =
      .ok (value, afterWorld)) :
    ∃ status stateCount rootState errorPosition,
      function = extractedParserParseResultFunction.id ∧
      values = [
        .signed .i32 status, .signed .i32 stateCount,
        .signed .i32 rootState, .signed .i32 errorPosition] ∧
      value = parseResultValue status stateCount rootState errorPosition ∧
      afterWorld = world := by
  simp only [calls] at evaluated
  split at evaluated
  next same =>
    split at evaluated
    next status stateCount rootState errorPosition =>
      obtain ⟨rfl, rfl⟩ := evaluated
      exact ⟨status, stateCount, rootState,
        errorPosition, same, rfl, rfl, rfl⟩
    next => contradiction
  next different => simp at evaluated

end ParseResultCallProof

/-- Store-pure contract for the extracted four-field `parse_result`
    constructor. Every recognizer exit uses this one checked constructor. -/
theorem extractedParserParseResultCall_contract
    (before afterArguments : State) (arguments : List Expr)
    (status stateCount rootState errorPosition : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      .signed .i32 status, .signed .i32 stateCount,
      .signed .i32 rootState, .signed .i32 errorPosition] afterArguments) :
    let callee := parserParseResultCallee afterArguments status stateCount
      rootState errorPosition
    let after := restoreLocals afterArguments callee
    Evaluates verifiedParserCore before
      (.call extractedParserParseResultFunction.id arguments)
      (parseResultValue status stateCount rootState errorPosition) after ∧
    ModifiesOnly CellSet.empty afterArguments after ∧
    StateWellFormed after := by
  let bindings := parserParseResultBindings status stateCount rootState
    errorPosition
  let callee := parserParseResultCallee afterArguments status stateCount
    rootState errorPosition
  let after := restoreLocals afterArguments callee
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, parserParseResultCallee, bindings,
      parserParseResultBindings] using
      (enterCall_preserves_wellFormed
        (bindings := bindings) afterArgumentsWellFormed)
  have bodyResult : Executes verifiedParserCore callee parserParseResultBody
      (.returned (some
        (parseResultValue status stateCount rootState errorPosition)))
      callee := by
    have environmentMatches :
        Lanius.FunctionalView.Core.EnvironmentMatches
          (Lanius.FunctionalView.Core.identityLayout (arity := 4))
          (ParseResultProof.environment status stateCount rootState
            errorPosition) callee := by
      simpa [callee, parserParseResultCallee, parserParseResultBindings,
        ParseResultProof.parameterBindings_eq] using
        (Lanius.FunctionalView.Core.enterCall_parameterBindings_matches
          (environment := ParseResultProof.environment status stateCount
            rootState errorPosition)
          afterArgumentsWellFormed)
    have sound := Lanius.FunctionalView.Core.block_executes_without_locals
      (nextLocal := 4)
      (Lanius.FunctionalView.Core.ReadOnly.bridge verifiedParserCore)
      (ParseResultProof.world_represents callee) environmentMatches
      ParseResultProof.localCapacity_eq_zero
      (ParseResultProof.evaluates status stateCount rootState errorPosition)
    rw [ParseResultProof.body_toCore_exactly] at sound
    exact sound.1
  have evaluation : Evaluates verifiedParserCore before
      (.call extractedParserParseResultFunction.id arguments)
      (parseResultValue status stateCount rootState errorPosition) after := by
    apply evaluatesCallReturned (body := parserParseResultBody)
      argumentsResult verifiedParserCore_finds_parseResult
    · rw [extractedParserParseResult_function_shape.2.1]
      rfl
    · exact extractedParserParseResult_function_shape.2.2.2.1
    · simpa [after, callee, parserParseResultCallee, bindings,
        parserParseResultBindings] using bodyResult
  have entered : StoreEffect CellSet.empty afterArguments callee := by
    simpa [callee, parserParseResultCallee, bindings,
      parserParseResultBindings] using enterCall_effect afterArguments bindings
  have effect : ModifiesOnly CellSet.empty afterArguments after := by
    simpa [after] using entered.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    entered.restoreLocals_wellFormed afterArgumentsWellFormed calleeWellFormed
  exact ⟨evaluation, effect, afterWellFormed⟩

namespace ParseResultCallProof

open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful

/-- The functional call entry is not an assumption: every successful model
    evaluation is discharged by the contract for the source-extracted Core
    function. Argument effects are retained, while the constructor call
    itself has an empty caller-visible write footprint. -/
theorem soundness : CallSoundness verifiedParserCore calls := by
  constructor
  intro arity layout environment beforeWorld afterWorld before afterArguments
    function arguments values value argumentWrites afterArgumentsWellFormed
    represented environmentMatches argumentsExecution argumentsEffect
    evaluated
  obtain ⟨status, stateCount, rootState, errorPosition, functionEq,
    valuesEq, valueEq, worldEq⟩ := calls_success evaluated
  subst function
  subst values
  subst value
  subst afterWorld
  obtain ⟨callExecution, callEffect, afterWellFormed⟩ :=
    extractedParserParseResultCall_contract before afterArguments
      (toCoreExprs layout arguments) status stateCount rootState errorPosition
      afterArgumentsWellFormed argumentsExecution
  have afterRepresented : World.Represents beforeWorld
      (restoreLocals afterArguments
        (parserParseResultCallee afterArguments status stateCount rootState
          errorPosition)) := by
    intro cell contents found
    obtain ⟨backing, allocated⟩ := represented cell contents found
    exact ⟨callEffect.empty_preserves_entry afterArgumentsWellFormed backing,
      Nat.lt_of_lt_of_le allocated callEffect.nextCell⟩
  have afterMatches : EnvironmentMatches layout environment
      (restoreLocals afterArguments
        (parserParseResultCallee afterArguments status stateCount rootState
          errorPosition)) :=
    environmentMatches.preserve afterArgumentsWellFormed callEffect
  exact ⟨_, CellSet.union argumentWrites CellSet.empty, callExecution,
    afterWellFormed, afterRepresented, afterMatches,
    argumentsEffect.trans callEffect⟩

/-- Separation-preserving form of `soundness`, suitable for mutable parser
    commands whose expressions may invoke `parse_result`. -/
theorem statefulSoundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore calls := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨status, stateCount, rootState, errorPosition, functionEq,
      valuesEq, valueEq, worldEq⟩ := calls_success evaluated
    subst function
    subst values
    subst value
    subst afterWorld
    obtain ⟨callExecution, callEffect, afterWellFormed⟩ :=
      extractedParserParseResultCall_contract before afterArguments
        (toCoreExprs layout arguments) status stateCount rootState errorPosition
        afterArgumentsWellFormed argumentsExecution
    let after := restoreLocals afterArguments
      (parserParseResultCallee afterArguments status stateCount rootState
        errorPosition)
    have afterRepresented :
        Lanius.FunctionalView.Core.Stateful.Representation layout localCell
          beforeWorld environment after := {
      worldOwned := callEffect.empty_preserves_assertion
        afterArgumentsWellFormed (World.owns beforeWorld)
        represented.worldOwned
      localOwned := fun index => callEffect.empty_preserves_assertion
        afterArgumentsWellFormed
        (Assertion.localPointsTo (layout index) (localCell index)
          (some (environment index))) (represented.localOwned index)
      localCellsInjective := represented.localCellsInjective
      worldLocalsDisjoint := represented.worldLocalsDisjoint
    }
    exact ⟨after, CellSet.union argumentWrites CellSet.empty, callExecution,
      afterWellFormed, afterRepresented, argumentsEffect.trans callEffect⟩
  · intro beforeWorld afterWorld function values value evaluated cell
    obtain ⟨status, stateCount, rootState, errorPosition, functionEq,
      valuesEq, valueEq, worldEq⟩ := calls_success evaluated
    subst afterWorld
    rfl

end ParseResultCallProof

def parserAppendOrFullBindings
    (appended : AppendOutcome) (errorPosition : Int) :
    List (VarId × Value) := [
  (0, appendOutcomeValue appended),
  (1, .signed .i32 errorPosition)]

def parserAppendOrFullCallee
    (caller : State) (appended : AppendOutcome) (errorPosition : Int) : State :=
  enterCall caller (parserAppendOrFullBindings appended errorPosition)

def parserAppendOrFullResultCall : Expr :=
  .call extractedParserParseResultFunction.id [
    .constant 2,
    .field (.local 0) 2,
    .unary .negate (.value (.signed .i32 1)),
    .local 1]

def parserAppendOrFullBody : Stmt :=
  .sequence (.returnValue (some parserAppendOrFullResultCall)) .skip

theorem extractedParserAppendOrFull_function_shape :
    extractedParserAppendOrFullFunction.id = 18 ∧
      extractedParserAppendOrFullFunction.parameters = [
        (0, .structure 2), (1, parserI32Type)] ∧
      extractedParserAppendOrFullFunction.returnType = .structure 0 ∧
      extractedParserAppendOrFullFunction.body = some parserAppendOrFullBody ∧
      extractedParserAppendOrFullFunction.external = none := by
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem verifiedParserCore_finds_appendOrFull :
    verifiedParserCore.function? extractedParserAppendOrFullFunction.id =
      some extractedParserAppendOrFullFunction := by
  unfold verifiedParserCore extractedParserAppendOrFullFunction
    extractedParserAppendOrFullWire
  rfl

theorem verifiedParser_parse_output_full_constant :
    verifiedParserCore.constant? 2 = some {
      id := 2, type := parserI32Type, value := .signed .i32 2
    } := by
  rfl

namespace AppendOrFullProof

open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful

def world : World := { i32Slice? := fun _ => none }

def environment (appended : AppendOutcome) (errorPosition : Int) : Env 2
  | ⟨0, _⟩ => appendOutcomeValue appended
  | ⟨1, _⟩ => .signed .i32 errorPosition

theorem parameterBindings_eq
    (appended : AppendOutcome) (errorPosition : Int) :
    Lanius.FunctionalView.Core.parameterBindings
        (environment appended errorPosition) =
      parserAppendOrFullBindings appended errorPosition := by
  apply List.ext_getElem
  · simp [parserAppendOrFullBindings]
  · intro index leftBound rightBound
    have alternatives : index = 0 ∨ index = 1 := by
      simp [parserAppendOrFullBindings] at rightBound
      omega
    rcases alternatives with rfl | rfl <;>
      simp [Lanius.FunctionalView.Core.parameterBindings_getElem,
        parserAppendOrFullBindings, environment]

def resultArguments : List (Term Lanius.FunctionalView.Core.signature 2) := [
  .apply (.constant 2 parserI32Type) [],
  .apply (.field (.structure 2) 2 parserI32Type) [
    .reference (.slot ⟨0, by omega⟩)],
  .apply (.unary .negate parserI32Type parserI32Type) [
    .reference (.literal (.signed .i32 1))],
  .reference (.slot ⟨1, by omega⟩)]

def resultTerm : Term Lanius.FunctionalView.Core.signature 2 :=
  .apply (.call extractedParserParseResultFunction.id [
      parserI32Type, parserI32Type, parserI32Type, parserI32Type]
    (.structure 0)) resultArguments

def body : Block Lanius.FunctionalView.Core.signature 2 :=
  .sequence (.returnValue (some resultTerm)) .skip

/-- The proof view is an exact re-expression of the checked source body. -/
theorem body_toCore_exactly :
    toCoreStmt (identityLayout (arity := 2)) 2 body =
      parserAppendOrFullBody := by
  rfl

theorem arguments_evaluate (appended : AppendOutcome) (errorPosition : Int) :
    evaluateTerms (ReadOnly.machine verifiedParserCore) world
        (environment appended errorPosition) resultArguments =
      .ok ([
        .signed .i32 2,
        .signed .i32 (Int.ofNat appended.stateCount),
        .signed .i32 (-1),
        .signed .i32 errorPosition], world) := by
  rfl

/-- At the functional level the exact source body returns the modeled
    four-field diagnostic. The separate call-soundness theorem connects this
    successful model step to the source-extracted `parse_result` body. -/
theorem evaluates (appended : AppendOutcome) (errorPosition : Int) :
    Block.evaluate
        (Effectful.machine verifiedParserCore ParseResultCallProof.calls)
        world (environment appended errorPosition) body =
      .done (.returned (some (parseResultValue 2
        (Int.ofNat appended.stateCount) (-1) errorPosition))) world := by
  rfl

theorem world_represents (state : State) : World.Represents world state := by
  intro _ _ found
  simp [world] at found

end AppendOrFullProof

/-- The extracted `append_or_full` helper is store-pure and returns the exact
    output-capacity diagnostic while retaining the append state count. -/
theorem extractedParserAppendOrFullCall_contract
    (before afterArguments : State) (arguments : List Expr)
    (appended : AppendOutcome) (errorPosition : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      appendOutcomeValue appended, .signed .i32 errorPosition]
      afterArguments) :
    ∃ after,
      Evaluates verifiedParserCore before
        (.call extractedParserAppendOrFullFunction.id arguments)
        (parseResultValue 2 (Int.ofNat appended.stateCount) (-1)
          errorPosition) after ∧
      ModifiesOnly CellSet.empty afterArguments after ∧
      StateWellFormed after := by
  let bindings := parserAppendOrFullBindings appended errorPosition
  let callee := parserAppendOrFullCallee afterArguments appended errorPosition
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, parserAppendOrFullCallee, bindings,
      parserAppendOrFullBindings] using
      (enterCall_preserves_wellFormed
        (bindings := bindings) afterArgumentsWellFormed)
  have environmentMatches :
      Lanius.FunctionalView.Core.EnvironmentMatches
        (Lanius.FunctionalView.Core.identityLayout (arity := 2))
        (AppendOrFullProof.environment appended errorPosition) callee := by
    simpa [callee, parserAppendOrFullCallee, parserAppendOrFullBindings,
      AppendOrFullProof.parameterBindings_eq] using
      (Lanius.FunctionalView.Core.enterCall_parameterBindings_matches
        (environment := AppendOrFullProof.environment appended errorPosition)
        afterArgumentsWellFormed)
  have functionalArguments :=
    Lanius.FunctionalView.Core.terms_evaluate
      (Lanius.FunctionalView.Core.ReadOnly.bridge verifiedParserCore)
      (AppendOrFullProof.world_represents callee) environmentMatches
      (AppendOrFullProof.arguments_evaluate appended errorPosition)
  have resultArguments : ArgumentsEvaluateTo verifiedParserCore callee
      [.constant 2, .field (.local 0) 2,
        .unary .negate (.value (.signed .i32 1)), .local 1]
      [.signed .i32 2, .signed .i32 (Int.ofNat appended.stateCount),
        .signed .i32 (-1), .signed .i32 errorPosition] callee := by
    simpa [AppendOrFullProof.resultArguments,
      Lanius.FunctionalView.Core.toCoreExprs,
      Lanius.FunctionalView.Core.toCoreExpr,
      Lanius.FunctionalView.Core.refToCoreExpr,
      Lanius.FunctionalView.Core.Operation.toCoreExpr,
      Lanius.FunctionalView.Core.identityLayout] using
      functionalArguments.1.toArgumentsEvaluateTo
  let afterResult := restoreLocals callee
    (parserParseResultCallee callee 2 (Int.ofNat appended.stateCount) (-1)
      errorPosition)
  have resultContract := extractedParserParseResultCall_contract callee callee
    [.constant 2, .field (.local 0) 2,
      .unary .negate (.value (.signed .i32 1)), .local 1]
    2 (Int.ofNat appended.stateCount) (-1) errorPosition calleeWellFormed
    resultArguments
  have bodyResult : Executes verifiedParserCore callee parserAppendOrFullBody
      (.returned (some (parseResultValue 2
        (Int.ofNat appended.stateCount) (-1) errorPosition))) afterResult := by
    simpa [parserAppendOrFullBody, parserAppendOrFullResultCall, afterResult]
      using
        (executesSequenceReturned (second := Stmt.skip)
          (executesReturnValue resultContract.1))
  let after := restoreLocals afterArguments afterResult
  have evaluation : Evaluates verifiedParserCore before
      (.call extractedParserAppendOrFullFunction.id arguments)
      (parseResultValue 2 (Int.ofNat appended.stateCount) (-1)
        errorPosition) after := by
    apply evaluatesCallReturned (body := parserAppendOrFullBody)
      argumentsResult verifiedParserCore_finds_appendOrFull
    · rw [extractedParserAppendOrFull_function_shape.2.1]
      rfl
    · exact extractedParserAppendOrFull_function_shape.2.2.2.1
    · simpa [after, callee, parserAppendOrFullCallee, bindings,
        parserAppendOrFullBindings] using bodyResult
  have entered : StoreEffect CellSet.empty afterArguments callee := by
    simpa [callee, parserAppendOrFullCallee, bindings,
      parserAppendOrFullBindings] using enterCall_effect afterArguments bindings
  have bodyEffect : ModifiesOnly CellSet.empty callee afterResult := by
    simpa [afterResult] using resultContract.2.1
  have combined : StoreEffect CellSet.empty afterArguments afterResult :=
    entered.trans_same bodyEffect.toStoreEffect
  have effect : ModifiesOnly CellSet.empty afterArguments after := by
    simpa [after] using combined.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    combined.restoreLocals_wellFormed afterArgumentsWellFormed
      resultContract.2.2
  exact ⟨after, evaluation, effect, afterWellFormed⟩

def parserAppendOutcomeFullCall
    (resultLocal : VarId) (errorPosition : Expr) : Expr :=
  .call extractedParserAppendOrFullFunction.id
    [.local resultLocal, errorPosition]

def parserAppendOutcomeFullBranch
    (resultLocal : VarId) (errorPosition : Expr) : Stmt :=
  .sequence
    (.returnValue (some
      (parserAppendOutcomeFullCall resultLocal errorPosition))) .skip

/-- Common control flow generated after every `append_state` invocation in
    the recognizer. It either returns a capacity diagnostic or commits the
    returned state count. Keeping this as data lets each extracted site prove
    an exact shape equality and then reuse one semantic theorem. -/
def parserAppendOutcomeContinuationThen
    (resultLocal stateCountLocal : VarId) (errorPosition : Expr)
    (tail : Stmt) : Stmt :=
  .sequence
    (.ifThenElse
      (.binary .equal (.field (.local resultLocal) 0) (.constant 41))
      (parserAppendOutcomeFullBranch resultLocal errorPosition) .skip)
    (.sequence
      (.expression
        (.assign .set (.local stateCountLocal)
          (.field (.local resultLocal) 2)))
      tail)

def parserAppendOutcomeContinuation
    (resultLocal stateCountLocal : VarId) (errorPosition : Expr) : Stmt :=
  parserAppendOutcomeContinuationThen resultLocal stateCountLocal
    errorPosition .skip

structure AppendOutcomeFullControlThenResult
    (before : State) (resultLocal stateCountLocal : VarId)
    (errorPosition : Expr)
    (tail : Stmt) (outcome : AppendOutcome) (errorValue : Int) where
  after : State
  execution : Executes verifiedParserCore before
    (parserAppendOutcomeContinuationThen resultLocal stateCountLocal
      errorPosition tail)
    (.returned (some (parseResultValue 2
      (Int.ofNat outcome.stateCount) (-1) errorValue))) after
  effect : ModifiesOnly CellSet.empty before after
  wellFormed : StateWellFormed after

/-- The capacity return is independent of the successful continuation tail:
    return propagation skips that tail for every extracted append site. -/
noncomputable def executeAppendOutcomeFullThen
    (before : State) (resultLocal stateCountLocal : VarId)
    (errorPosition : Expr) (tail : Stmt)
    (outcome : AppendOutcome) (errorValue : Int)
    (wellFormed : StateWellFormed before)
    (resultFound : before.local? resultLocal =
      some (appendOutcomeValue outcome))
    (errorResult : Evaluates verifiedParserCore before errorPosition
      (.signed .i32 errorValue) before)
    (statusFull : outcome.status = .full) :
    AppendOutcomeFullControlThenResult before resultLocal stateCountLocal
      errorPosition tail outcome errorValue := by
  have localResult : Evaluates verifiedParserCore before (.local resultLocal)
      (appendOutcomeValue outcome) before :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore before resultLocal _
      resultFound⟩
  have statusResult : Evaluates verifiedParserCore before
      (.field (.local resultLocal) 0) (.signed .i32 1) before := by
    apply evaluatesStructureField localResult
    rw [statusFull]
    simp [appendOutcomeValue, appendResultValue, appendStatusValue]
  have fullConstant : Evaluates verifiedParserCore before (.constant 41)
      (.signed .i32 1) before :=
    evaluatesConstant verifiedParser_append_status_constants.2
  have fullCondition : Evaluates verifiedParserCore before
      (.binary .equal (.field (.local resultLocal) 0) (.constant 41))
      (.boolean true) before := by
    apply evaluatesEagerBinary (by decide) (by decide) statusResult
      fullConstant
    simp [evalBinaryValue, scalarEqual]
  have callArguments : ArgumentsEvaluateTo verifiedParserCore before
      [.local resultLocal, errorPosition]
      [appendOutcomeValue outcome, .signed .i32 errorValue] before :=
    ArgumentsEvaluateTo.cons localResult
      (ArgumentsEvaluateTo.singleton errorResult)
  let callResult := extractedParserAppendOrFullCall_contract before before
    [.local resultLocal, errorPosition] outcome errorValue wellFormed
    callArguments
  let after := Classical.choose callResult
  have callFacts := Classical.choose_spec callResult
  have fullBranch : Executes verifiedParserCore before
      (parserAppendOutcomeFullBranch resultLocal errorPosition)
      (.returned (some (parseResultValue 2
        (Int.ofNat outcome.stateCount) (-1) errorValue))) after := by
    exact executesSequenceReturned (executesReturnValue (by
      simpa [parserAppendOutcomeFullCall] using callFacts.1))
  have selected : Executes verifiedParserCore before
      (.ifThenElse
        (.binary .equal (.field (.local resultLocal) 0) (.constant 41))
        (parserAppendOutcomeFullBranch resultLocal errorPosition) .skip)
      (.returned (some (parseResultValue 2
        (Int.ofNat outcome.stateCount) (-1) errorValue))) after :=
    executesIfTrue fullCondition fullBranch
  exact {
    after := after
    execution := by
      exact executesSequenceReturned selected
    effect := callFacts.2.1
    wellFormed := callFacts.2.2
  }

structure AppendOutcomeFullControlResult
    (before : State) (resultLocal stateCountLocal : VarId)
    (errorPosition : Expr)
    (outcome : AppendOutcome) (errorValue : Int) where
  after : State
  execution : Executes verifiedParserCore before
    (parserAppendOutcomeContinuation resultLocal stateCountLocal errorPosition)
    (.returned (some (parseResultValue 2
      (Int.ofNat outcome.stateCount) (-1) errorValue))) after
  effect : ModifiesOnly CellSet.empty before after
  wellFormed : StateWellFormed after

/-- Generic full arm for all extracted recognizer append sites. -/
noncomputable def executeAppendOutcomeFull
    (before : State) (resultLocal stateCountLocal : VarId)
    (errorPosition : Expr) (outcome : AppendOutcome) (errorValue : Int)
    (wellFormed : StateWellFormed before)
    (resultFound : before.local? resultLocal =
      some (appendOutcomeValue outcome))
    (errorResult : Evaluates verifiedParserCore before errorPosition
      (.signed .i32 errorValue) before)
    (statusFull : outcome.status = .full) :
    AppendOutcomeFullControlResult before resultLocal stateCountLocal
      errorPosition outcome errorValue := by
  let result := executeAppendOutcomeFullThen before resultLocal
    stateCountLocal errorPosition .skip outcome errorValue wellFormed
    resultFound errorResult statusFull
  exact {
    after := result.after
    execution := by
      simpa [parserAppendOutcomeContinuation] using result.execution
    effect := result.effect
    wellFormed := result.wellFormed
  }

structure AppendOutcomeOkControlResult
    (before : State) (resultLocal stateCountLocal : VarId)
    (stateCountCell : CellId) (errorPosition : Expr)
    (outcome : AppendOutcome) where
  after : State
  execution : Executes verifiedParserCore before
    (parserAppendOutcomeContinuation resultLocal stateCountLocal errorPosition)
    .next after
  guardExecution : Executes verifiedParserCore before
    (.ifThenElse
      (.binary .equal (.field (.local resultLocal) 0) (.constant 41))
      (parserAppendOutcomeFullBranch resultLocal errorPosition) .skip)
    .next before
  assignmentEvaluation : Evaluates verifiedParserCore before
    (.assign .set (.local stateCountLocal)
      (.field (.local resultLocal) 2)) .unit after
  effect : ModifiesOnly (CellSet.singleton stateCountCell) before after
  stateCountOwned : (Assertion.localPointsTo stateCountLocal stateCountCell
    (some (.signed .i32 (Int.ofNat outcome.stateCount)))).holds after
  wellFormed : StateWellFormed after

/-- Generic non-full arm for all extracted recognizer append sites. -/
noncomputable def executeAppendOutcomeOk
    (before : State) (resultLocal stateCountLocal : VarId)
    (stateCountCell : CellId) (errorPosition : Expr)
    (outcome : AppendOutcome) (oldStateCount : Nat)
    (wellFormed : StateWellFormed before)
    (resultFound : before.local? resultLocal =
      some (appendOutcomeValue outcome))
    (stateCountOwned : (Assertion.localPointsTo stateCountLocal stateCountCell
      (some (.signed .i32 (Int.ofNat oldStateCount)))).holds before)
    (statusOk : outcome.status = .ok) :
    AppendOutcomeOkControlResult before resultLocal stateCountLocal
      stateCountCell errorPosition outcome := by
  have localResult : Evaluates verifiedParserCore before (.local resultLocal)
      (appendOutcomeValue outcome) before :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore before resultLocal _
      resultFound⟩
  have statusResult : Evaluates verifiedParserCore before
      (.field (.local resultLocal) 0) (.signed .i32 0) before := by
    apply evaluatesStructureField localResult
    rw [statusOk]
    simp [appendOutcomeValue, appendResultValue, appendStatusValue]
  have fullConstant : Evaluates verifiedParserCore before (.constant 41)
      (.signed .i32 1) before :=
    evaluatesConstant verifiedParser_append_status_constants.2
  have notFull : Evaluates verifiedParserCore before
      (.binary .equal (.field (.local resultLocal) 0) (.constant 41))
      (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) statusResult
      fullConstant
    simp [evalBinaryValue, scalarEqual]
  have skipped : Executes verifiedParserCore before
      (.ifThenElse
        (.binary .equal (.field (.local resultLocal) 0) (.constant 41))
        (parserAppendOutcomeFullBranch resultLocal errorPosition) .skip)
      .next before := executesIfFalse notFull
        (executesSkip verifiedParserCore before)
  have countField : Evaluates verifiedParserCore before
      (.field (.local resultLocal) 2)
      (.signed .i32 (Int.ofNat outcome.stateCount)) before := by
    apply evaluatesStructureField localResult
    simp [appendOutcomeValue, appendResultValue]
  let assignmentResult := evaluatesSetOwnedLocalFromEmpty
    (program := verifiedParserCore) stateCountLocal stateCountCell wellFormed
    stateCountOwned countField wellFormed (ModifiesOnly.refl before)
  let after := Classical.choose assignmentResult
  have assignmentFacts := Classical.choose_spec assignmentResult
  have assignmentExecution : Executes verifiedParserCore before
      (.sequence
        (.expression
          (.assign .set (.local stateCountLocal)
            (.field (.local resultLocal) 2))) .skip) .next after :=
    executesSequence (executesExpression assignmentFacts.1)
      (executesSkip verifiedParserCore after)
  exact {
    after := after
    execution := executesSequence skipped assignmentExecution
    guardExecution := skipped
    assignmentEvaluation := assignmentFacts.1
    effect := assignmentFacts.2.2.2
    stateCountOwned := assignmentFacts.2.2.1
    wellFormed := assignmentFacts.2.1
  }

end Lanius.Extraction.ParserResult
