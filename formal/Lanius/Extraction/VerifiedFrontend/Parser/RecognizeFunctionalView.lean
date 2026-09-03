import Lanius.Extraction.VerifiedFrontend.Parser.Recognize
import Lanius.Extraction.VerifiedFrontend.Parser.Scan
import Lanius.Extraction.VerifiedFrontend.Parser.AccessorsFunctionalView
import Lanius.Extraction.VerifiedFrontend.Parser.ReadsFunctionalView
import Lanius.Extraction.VerifiedFrontend.Parser.ValidationFunctionalView
import Lanius.FunctionalViewCoreStatefulReification
import Lanius.FunctionalViewCoreEffectfulStateful

namespace Lanius.Extraction.ParserRecognize

open Lanius.Core
open Lanius.Typing
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction.CoreTyping
open Lanius.Extraction.ParserAccessors
open Lanius.Extraction.ParserAppend
open Lanius.Extraction.ParserFind
open Lanius.Extraction.ParserResult
open Lanius.Extraction.ParserScan
open Lanius.Extraction.ParserValidation
open Lanius.Compiler.Parser
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Stateful.Reification

/-! # Whole-recognizer FunctionalView

The view in this file is recovered from the checked `parser.lani` artifact.
It is not a second, handwritten recognizer AST.  Its indexed round-trip
certificate is the mechanical connection between the source-extracted Core
function and the functional semantics used by subsequent proofs.
-/

def parserRecognizeParameterLayout : Layout 6 := identityLayout

def parserRecognizeParameterContext : Context :=
  parameterContext extractedParserRecognizeFunction.parameters

private def parserRecognizeReification? :=
  reifyCommand? verifiedParserCore extractedParserRecognizeFunction.returnType
    parserRecognizeParameterContext false parserRecognizeParameterLayout 6
    extractedParserRecognizeBody

theorem parserRecognizeReification_exists :
    parserRecognizeReification?.isSome := by
  native_decide

/-- The complete mutable FunctionalView command mechanically recovered from
    the real `parser.lani::recognize` function. -/
def parserRecognizeView :=
  parserRecognizeReification?.get parserRecognizeReification_exists

/-- Re-emitting the FunctionalView command produces the exact checked Core
    body, including every helper call, loop, mutation, and return branch. -/
theorem parserRecognizeView_toCore_exactly :
    toCoreStmt actionAdapter parserRecognizeParameterLayout 6
      parserRecognizeView.command = extractedParserRecognizeBody :=
  parserRecognizeView.toCoreExactly

/-- Exact structural execution of the validated grammar call used by the
    recognizer guard.  This is the primitive source-call boundary behind the
    FunctionalView call model; control flow remains in FunctionalView. -/
theorem grammarValidCall_evaluates_encoded
    (state : State)
    (grammarLocal : state.local? 0 =
      some (parserGrammarValue words grammarCell))
    (grammarLengthLocal : state.local? 1 =
      some (.signed .i32 (Int.ofNat words.length)))
    (invariant : GrammarValidationInvariant layout grammar words grammarCell
      (parserGrammarValidCallee state words grammarCell))
    (stateWellFormed : StateWellFormed state) :
    ∃ after,
      Evaluates verifiedParserCore state parserRecognizeGrammarValidCall
        (.boolean true) after ∧
      ModifiesOnly CellSet.empty state after ∧
      StateWellFormed after := by
  have grammarResult : Evaluates verifiedParserCore state (.local 0)
      (parserGrammarValue words grammarCell) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 0 _ grammarLocal⟩
  have lengthResult : Evaluates verifiedParserCore state (.local 1)
      (.signed .i32 (Int.ofNat words.length)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 1 _
      grammarLengthLocal⟩
  have arguments : ArgumentsEvaluateTo verifiedParserCore state
      parserRecognizeGrammarValidArguments [
        parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat words.length)] state :=
    ArgumentsEvaluateTo.cons grammarResult
      (ArgumentsEvaluateTo.singleton lengthResult)
  simpa [parserRecognizeGrammarValidCall] using
    extractedParserGrammarValidCall_accepts_encoded state state
      parserRecognizeGrammarValidArguments arguments invariant stateWellFormed

namespace StateSeedCall

open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful

/-- Functional semantics for the checked `state_seed` constructor.  The
    existential guard deliberately admits exactly the semantic seeds already
    covered by the source-call contract; successful model evaluation can
    therefore never outrun the proved Core implementation. -/
noncomputable def calls : CallModel where
  evaluate := by
    classical
    exact fun world function values =>
      if function = extractedParserStateSeedFunction.id then
        if found : ∃ seed : StateSeed,
            values = parserStateSeedArgumentsValues seed then
          .ok (.structure 1 values, world)
        else
          .error .typeMismatch
      else
        .error .invalidPointer

theorem calls_at_seed (world : World) (seed : StateSeed) :
    calls.evaluate world extractedParserStateSeedFunction.id
        (parserStateSeedArgumentsValues seed) =
      .ok (stateSeedValue seed, world) := by
  simp only [calls, if_pos rfl]
  rw [dif_pos ⟨seed, rfl⟩]
  rfl

theorem calls_success
    (evaluated : calls.evaluate world function values =
      .ok (value, afterWorld)) :
    ∃ seed : StateSeed,
      function = extractedParserStateSeedFunction.id ∧
      values = parserStateSeedArgumentsValues seed ∧
      value = stateSeedValue seed ∧ afterWorld = world := by
  simp only [calls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next found =>
      obtain ⟨rfl, rfl⟩ := evaluated
      refine ⟨Classical.choose found, functionEq,
        Classical.choose_spec found, ?_, rfl⟩
      exact (congrArg (fun fields => Value.structure 1 fields)
        (Classical.choose_spec found)).trans (by
          rfl)
    next => contradiction
  next => contradiction

/-- Separation-preserving proof that every successful modeled `state_seed`
    call executes the checked source function and leaves the caller's world
    and local ownership unchanged. -/
theorem soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore calls := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨seed, functionEq, valuesEq, valueEq, worldEq⟩ :=
      calls_success evaluated
    subst function
    subst values
    subst value
    subst afterWorld
    obtain ⟨callExecution, callEffect, afterWellFormed⟩ :=
      extractedParserStateSeedCall_contract before afterArguments
        (toCoreExprs layout arguments) seed afterArgumentsWellFormed
        argumentsExecution
    let after := restoreLocals afterArguments
      (parserStateSeedCallee afterArguments seed)
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
    obtain ⟨seed, functionEq, valuesEq, valueEq, worldEq⟩ :=
      calls_success evaluated
    subst afterWorld
    rfl

end StateSeedCall

namespace AppendOrFullCall

open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful

/-- Functional semantics for the checked `append_or_full` diagnostic helper.
    As with `state_seed`, the model accepts precisely values covered by the
    source-level semantic contract. -/
noncomputable def calls : CallModel where
  evaluate := by
    classical
    exact fun world function values =>
      if function = extractedParserAppendOrFullFunction.id then
        if found : ∃ appended : AppendOutcome, ∃ errorPosition : Int,
            values = [appendOutcomeValue appended,
              .signed .i32 errorPosition] then
          let appended := Classical.choose found
          let errorPosition := Classical.choose (Classical.choose_spec found)
          .ok (parseResultValue 2 (Int.ofNat appended.stateCount) (-1)
            errorPosition, world)
        else
          .error .typeMismatch
      else
        .error .invalidPointer

theorem calls_at (world : World) (appended : AppendOutcome)
    (errorPosition : Int) :
    calls.evaluate world extractedParserAppendOrFullFunction.id
        [appendOutcomeValue appended, .signed .i32 errorPosition] =
      .ok (parseResultValue 2 (Int.ofNat appended.stateCount) (-1)
        errorPosition, world) := by
  simp only [calls, if_pos rfl]
  let found : ∃ candidate : AppendOutcome, ∃ position : Int,
      [appendOutcomeValue appended, .signed .i32 errorPosition] =
        [appendOutcomeValue candidate, .signed .i32 position] :=
    ⟨appended, errorPosition, rfl⟩
  rw [dif_pos found]
  let chosen := Classical.choose found
  let chosenPosition := Classical.choose (Classical.choose_spec found)
  have selected := Classical.choose_spec (Classical.choose_spec found)
  have fields : chosen.stateCount = appended.stateCount ∧
      chosenPosition = errorPosition := by
    have decoded := (show
      (appendStatusValue chosen.status = appendStatusValue appended.status ∧
        encodeStateId chosen.stateId = encodeStateId appended.stateId ∧
        Int.ofNat chosen.stateCount = Int.ofNat appended.stateCount ∧
        chosen.inserted = appended.inserted) ∧
        chosenPosition = errorPosition by
      simpa [chosen, chosenPosition, appendOutcomeValue, appendResultValue] using
        selected.symm)
    exact ⟨Int.ofNat_inj.mp decoded.1.2.2.1, decoded.2⟩
  change Except.ok (parseResultValue 2 (Int.ofNat chosen.stateCount) (-1)
    chosenPosition, world) = _
  rw [fields.1, fields.2]

theorem calls_success
    (evaluated : calls.evaluate world function values =
      .ok (value, afterWorld)) :
    ∃ appended : AppendOutcome, ∃ errorPosition : Int,
      function = extractedParserAppendOrFullFunction.id ∧
      values = [appendOutcomeValue appended, .signed .i32 errorPosition] ∧
      value = parseResultValue 2 (Int.ofNat appended.stateCount) (-1)
        errorPosition ∧
      afterWorld = world := by
  simp only [calls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next found =>
      let appended := Classical.choose found
      let errorPosition := Classical.choose (Classical.choose_spec found)
      have valuesEq := Classical.choose_spec
        (Classical.choose_spec found)
      obtain ⟨rfl, rfl⟩ := evaluated
      exact ⟨appended, errorPosition, functionEq, valuesEq, rfl, rfl⟩
    next => contradiction
  next => contradiction

theorem soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore calls := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨appended, errorPosition, functionEq, valuesEq, valueEq,
      worldEq⟩ := calls_success evaluated
    subst function
    subst values
    subst value
    subst afterWorld
    obtain ⟨after, callExecution, callEffect, afterWellFormed⟩ :=
      extractedParserAppendOrFullCall_contract before afterArguments
        (toCoreExprs layout arguments) appended errorPosition
        afterArgumentsWellFormed argumentsExecution
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
    obtain ⟨appended, errorPosition, functionEq, valuesEq, valueEq,
      worldEq⟩ := calls_success evaluated
    subst afterWorld
    rfl

end AppendOrFullCall

namespace AppendStateCall

open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful

/-- Semantic evidence accepted by the `append_state` FunctionalView call
    model.  The wire arguments, owned slice, compact encoding, and source
    bounds are kept together so a successful modeled call has exactly the
    hypotheses required by the checked source-call contract. -/
structure Input (layout : WorkspaceLayout) (world : World)
    (arguments : List Value) where
  workspace : LogicalWorkspace
  values : List Int
  cell : CellId
  position : Nat
  seed : StateSeed
  valuesLength : values.length = layout.workspaceLength
  encoded : EncodesWorkspace layout workspace (listWords values)
  positionBound : position ≤ finalPosition layout.tokenCount
  seedOriginBound : seed.origin ≤ finalPosition layout.tokenCount
  found : world.i32Slice? cell = some values
  argumentsEq : arguments = [
    workspaceValue values cell,
    .signed .i32 (Int.ofNat (stateBase layout.tokenCount)),
    .signed .i32 (Int.ofNat layout.capacity),
    .signed .i32 (Int.ofNat position),
    stateSeedValue seed,
    .signed .i32 (Int.ofNat workspace.states.length)]

def Input.outcome (input : Input layout world arguments) : AppendOutcome :=
  (appendLogical layout.capacity input.position input.seed input.workspace).1

def Input.afterValues (input : Input layout world arguments) : List Int :=
  appendResultValues layout input.workspace input.position input.seed
    input.values

def Input.afterWorld (input : Input layout world arguments) : World :=
  World.setI32Slice world input.cell input.afterValues

private def workspaceCell? : Value → Option CellId
  | .slice _ cell _ _ _ => some cell
  | _ => none

/-- Two semantic witnesses for the same represented call have the same
    observable result.  This removes all dependence on the noncomputable
    witness selected by the partial call model: source-level determinism pins
    both the returned `AppendResult` and the rewritten compact slice. -/
theorem Input.observation_unique
    (left right : Input workspaceLayout world callValues)
    (before afterArguments : State)
    (commandLayout : Layout arity)
    (arguments : List
      (Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity))
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (worldOwned : (World.owns world).holds afterArguments)
    (argumentsExecution : ArgumentsEvaluateTo verifiedParserCore before
      (toCoreExprs commandLayout arguments) callValues afterArguments) :
    appendOutcomeValue left.outcome = appendOutcomeValue right.outcome ∧
      left.afterWorld = right.afterWorld := by
  have leftArguments : ArgumentsEvaluateTo verifiedParserCore before
      (toCoreExprs commandLayout arguments) [
        workspaceValue left.values left.cell,
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
        .signed .i32 (Int.ofNat workspaceLayout.capacity),
        .signed .i32 (Int.ofNat left.position),
        stateSeedValue left.seed,
        .signed .i32 (Int.ofNat left.workspace.states.length)]
      afterArguments := by
    simpa [left.argumentsEq] using argumentsExecution
  have rightArguments : ArgumentsEvaluateTo verifiedParserCore before
      (toCoreExprs commandLayout arguments) [
        workspaceValue right.values right.cell,
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
        .signed .i32 (Int.ofNat workspaceLayout.capacity),
        .signed .i32 (Int.ofNat right.position),
        stateSeedValue right.seed,
        .signed .i32 (Int.ofNat right.workspace.states.length)]
      afterArguments := by
    simpa [right.argumentsEq] using argumentsExecution
  obtain ⟨leftAfter, leftExecution, leftEffect, leftWellFormed,
      leftBacking, leftEncoded⟩ :=
    extractedParserAppendStateCall_evaluates workspaceLayout left.workspace
      left.values left.cell left.position left.seed before afterArguments
      (toCoreExprs commandLayout arguments) left.valuesLength left.encoded
      left.positionBound left.seedOriginBound afterArgumentsWellFormed
      leftArguments (worldOwned left.cell left.values left.found)
  obtain ⟨rightAfter, rightExecution, rightEffect, rightWellFormed,
      rightBacking, rightEncoded⟩ :=
    extractedParserAppendStateCall_evaluates workspaceLayout right.workspace
      right.values right.cell right.position right.seed before afterArguments
      (toCoreExprs commandLayout arguments) right.valuesLength right.encoded
      right.positionBound right.seedOriginBound afterArgumentsWellFormed
      rightArguments
      (worldOwned right.cell right.values right.found)
  have resultAndState := Lanius.Fuel.evaluates_deterministic
    leftExecution rightExecution
  have resultEq : appendOutcomeValue left.outcome =
      appendOutcomeValue right.outcome := by
    simpa [Input.outcome] using resultAndState.1
  have argumentValuesEq := left.argumentsEq.symm.trans right.argumentsEq
  have workspaceValueEq : workspaceValue left.values left.cell =
      workspaceValue right.values right.cell := by
    simpa using congrArg List.head? argumentValuesEq
  have cellEq : left.cell = right.cell := by
    have := congrArg workspaceCell? workspaceValueEq
    simpa [workspaceCell?, workspaceValue] using this
  have inputValuesEq : left.values = right.values := by
    have rightFound : world.i32Slice? left.cell = some right.values := by
      simpa [cellEq] using right.found
    exact Option.some.inj (left.found.symm.trans rightFound)
  have stateEq : leftAfter = rightAfter := resultAndState.2
  rw [← cellEq] at rightBacking
  rw [← stateEq] at rightBacking
  have backingEq := leftBacking.symm.trans rightBacking
  have encodedValuesEq : signedI32Values left.afterValues =
      signedI32Values right.afterValues := by
    simpa [Input.afterValues] using backingEq
  have afterValuesEq : left.afterValues = right.afterValues :=
    signedI32Values_injective encodedValuesEq
  refine ⟨resultEq, ?_⟩
  apply congrArg World.mk
  funext candidate
  change (World.setI32Slice world left.cell left.afterValues).i32Slice?
      candidate =
    (World.setI32Slice world right.cell right.afterValues).i32Slice? candidate
  by_cases same : candidate = left.cell
  · subst candidate
    simp [World.setI32Slice, afterValuesEq, cellEq]
  · have rightDifferent : candidate ≠ right.cell := by
      simpa [cellEq] using same
    simp [World.setI32Slice, same, rightDifferent]

/-- Store-passing semantics for `append_state`.  The model is partial on
    malformed calls; every success carries a compact-workspace witness and
    returns the same logical append result and rewritten slice established by
    the source proof. -/
noncomputable def calls (layout : WorkspaceLayout) : CallModel where
  evaluate := by
    classical
    exact fun world function arguments =>
      if function = extractedParserAppendStateFunction.id then
        if found : Nonempty (Input layout world arguments) then
          let input := Classical.choice found
          .ok (appendOutcomeValue input.outcome, input.afterWorld)
        else
          .error .typeMismatch
      else
        .error .invalidPointer

/-- The partial model evaluates to any represented semantic witness supplied
    by a caller.  `Input.observation_unique` proves that the internal witness
    selected by classical choice is observationally indistinguishable. -/
theorem calls_at_input
    (input : Input workspaceLayout world callValues)
    (before afterArguments : State)
    (commandLayout : Layout arity)
    (arguments : List
      (Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity))
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (worldOwned : (World.owns world).holds afterArguments)
    (argumentsExecution : ArgumentsEvaluateTo verifiedParserCore before
      (toCoreExprs commandLayout arguments) callValues afterArguments) :
    (calls workspaceLayout).evaluate world
        extractedParserAppendStateFunction.id callValues =
      .ok (appendOutcomeValue input.outcome, input.afterWorld) := by
  simp only [calls, if_pos rfl]
  let found : Nonempty (Input workspaceLayout world callValues) := ⟨input⟩
  rw [dif_pos found]
  let chosen := Classical.choice found
  have same := Input.observation_unique chosen input before afterArguments
    commandLayout arguments afterArgumentsWellFormed worldOwned
    argumentsExecution
  rw [same.1, same.2]
  simp

theorem calls_success
    (evaluated : (calls layout).evaluate world function arguments =
      .ok (value, afterWorld)) :
    ∃ input : Input layout world arguments,
      function = extractedParserAppendStateFunction.id ∧
      value = appendOutcomeValue input.outcome ∧
      afterWorld = input.afterWorld := by
  simp only [calls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next found =>
      let input := Classical.choice found
      obtain ⟨rfl, rfl⟩ := evaluated
      exact ⟨input, functionEq, rfl, rfl⟩
    next => contradiction
  next => contradiction

/-- The `append_state` call model is separation preserving.  Its only
    caller-visible mutation is replacement of the workspace slice already
    owned by the FunctionalView world. -/
theorem soundness (layout : WorkspaceLayout) :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore (calls layout) := by
  constructor
  · intro arity commandLayout localCell beforeWorld afterWorld environment
      before afterArguments function arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨input, functionEq, valueEq, worldEq⟩ := calls_success evaluated
    subst function
    subst value
    subst afterWorld
    have argumentsExecution' : ArgumentsEvaluateTo verifiedParserCore before
        (toCoreExprs commandLayout arguments) [
          workspaceValue input.values input.cell,
          .signed .i32 (Int.ofNat (stateBase layout.tokenCount)),
          .signed .i32 (Int.ofNat layout.capacity),
          .signed .i32 (Int.ofNat input.position),
          stateSeedValue input.seed,
          .signed .i32 (Int.ofNat input.workspace.states.length)]
        afterArguments := by
      simpa [input.argumentsEq] using argumentsExecution
    obtain ⟨after, callExecution, callEffect, afterWellFormed, afterBacking,
      afterEncoded⟩ :=
      extractedParserAppendStateCall_evaluates layout input.workspace
        input.values input.cell input.position input.seed before afterArguments
        (toCoreExprs commandLayout arguments) input.valuesLength input.encoded
        input.positionBound input.seedOriginBound afterArgumentsWellFormed
        argumentsExecution'
        (represented.worldOwned input.cell input.values input.found)
    have afterRepresented :
        Lanius.FunctionalView.Core.Stateful.Representation commandLayout
          localCell input.afterWorld environment after := by
      exact represented.replaceI32Slice afterArgumentsWellFormed input.found
        callEffect (by simpa [Input.afterValues] using afterBacking)
    exact ⟨after, CellSet.union argumentWrites
        (CellSet.singleton input.cell), callExecution, afterWellFormed,
      afterRepresented, argumentsEffect.trans callEffect⟩
  · intro beforeWorld afterWorld function arguments value evaluated cell
    obtain ⟨input, functionEq, valueEq, worldEq⟩ := calls_success evaluated
    subst afterWorld
    by_cases same : cell = input.cell
    · subst cell
      simp [Input.afterWorld, Input.afterValues, input.found,
        appendResultValues_length]
    · simp [Input.afterWorld, World.setI32Slice_other same]

end AppendStateCall

namespace EntryCallRegistry

open Lanius.FunctionalView.Core.Effectful

/-- The first compositional recognizer registry.  Grammar validation and
    parse-result construction retain independent contracts and are routed by
    source function ID.  Later recognizer helpers extend this value instead
    of replacing it with a monolithic dispatcher. -/
noncomputable def calls (words : List Int) (grammarCell : CellId) : CallModel :=
  CallModel.route
    (fun function => function == extractedParserGrammarValidFunction.id)
    (ParserValidation.FunctionalView.calls words grammarCell)
    (CallModel.route
      (fun function => function == extractedParserParseResultFunction.id)
      ParseResultCallProof.calls
      (CallModel.route
        (fun function => function == extractedParserStateSeedFunction.id)
        StateSeedCall.calls
        AppendOrFullCall.calls))

theorem soundness
    (encoded : EncodesGrammar layout grammar words)
    (grammarWellFormed : grammar.WellFormed)
    (wordsI32 : words.length ≤ 2147483647) :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore (calls words grammarCell) := by
  exact Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness.route
    (ParserValidation.FunctionalView.call_soundness encoded grammarWellFormed
      wordsI32)
    (Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness.route
      ParseResultCallProof.statefulSoundness
      (Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness.route
        StateSeedCall.soundness AppendOrFullCall.soundness))

end EntryCallRegistry

namespace RecognizerReadCallRegistry

open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.ReadOnly

/-- Read-only helper calls needed by chart traversal, composed in source-call
    ID order.  This registry deliberately excludes workspace mutation. -/
noncomputable def calls (grammar : IndexedGrammar) (words : List Int)
    (grammarCell : CellId) : CallModel :=
  CallModel.route
    (fun function => function == extractedParserStateValueFunction.id)
    ParserReads.Functional.StateValue.genericCalls
    (ParserAccessors.FunctionalView.calls grammar words grammarCell)

theorem calls_at_state_value
    (world : World) (values : List Int) (workspaceCell : CellId)
    (start length address : Nat) (base stateId field value : Int)
    (addressValue : parserStateWordValue verifiedParserCore.target
      base stateId field = Int.ofNat address)
    (sliceBound : address < length)
    (found : world.i32Slice? workspaceCell = some values)
    (backingBound : start + length ≤ values.length)
    (valueFound : ((values.drop start).take length)[address]? = some value) :
    (calls grammar words grammarCell).evaluate world
        extractedParserStateValueFunction.id [
          .slice parserI32Type workspaceCell [] start length,
          .signed .i32 base,
          .signed .i32 stateId,
          .signed .i32 field] =
      .ok (.signed .i32 value, world) := by
  simpa [calls, CallModel.route] using
    ParserReads.Functional.StateValue.genericCalls_at_valid
      addressValue sliceBound found backingBound valueFound

theorem calls_at_rhs_length
    (world : World) (production : Nat)
    (found : world.i32Slice? grammarCell = some words)
    (bound : production < grammar.rhsLengths.length) :
    (calls grammar words grammarCell).evaluate world
        extractedParserRhsLengthFunction.id [
          parserGrammarValue words grammarCell,
          .signed .i32 (Int.ofNat production)] =
      .ok (.signed .i32 (Int.ofNat
        (grammar.rhsLengths.get ⟨production, bound⟩)), world) := by
  have notState : extractedParserRhsLengthFunction.id ≠
      extractedParserStateValueFunction.id := by native_decide
  simpa [calls, CallModel.route, notState] using
    ParserAccessors.FunctionalView.calls_at_rhs_length
      (grammar := grammar) (words := words) (grammarCell := grammarCell)
      found bound

theorem calls_at_lhs
    (world : World) (production : Nat)
    (found : world.i32Slice? grammarCell = some words)
    (bound : production < grammar.productionLhs.length) :
    (calls grammar words grammarCell).evaluate world
        extractedParserLhsFunction.id [
          parserGrammarValue words grammarCell,
          .signed .i32 (Int.ofNat production)] =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionLhs.get ⟨production, bound⟩)), world) := by
  have notState : extractedParserLhsFunction.id ≠
      extractedParserStateValueFunction.id := by native_decide
  simpa [calls, CallModel.route, notState] using
    ParserAccessors.FunctionalView.calls_at_lhs
      (grammar := grammar) (words := words) (grammarCell := grammarCell)
      found bound

theorem calls_at_rhs_symbol
    (world : World) (production dot : Nat)
    (found : world.i32Slice? grammarCell = some words)
    (productionBound : production < grammar.productionCount)
    (dotBound : dot <
      (grammar.productionAt ⟨production, productionBound⟩).rhs.length) :
    (calls grammar words grammarCell).evaluate world
        extractedParserRhsSymbolFunction.id [
          parserGrammarValue words grammarCell,
          .signed .i32 (Int.ofNat production),
          .signed .i32 (Int.ofNat dot)] =
      .ok (.signed .i32 (Int.ofNat
        ((grammar.productionAt ⟨production, productionBound⟩).rhs.get
          ⟨dot, dotBound⟩)), world) := by
  have notState : extractedParserRhsSymbolFunction.id ≠
      extractedParserStateValueFunction.id := by native_decide
  simpa [calls, CallModel.route, notState] using
    ParserAccessors.FunctionalView.calls_at_rhs_symbol
      (grammar := grammar) (words := words) (grammarCell := grammarCell)
      found productionBound dotBound

end RecognizerReadCallRegistry

namespace RecognizerCallRegistry

open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.ReadOnly

/-- Full call registry needed by the state-seeding recognizer loops.  The
    mutating workspace operation is routed first; all store-pure entry and
    diagnostic helpers remain independently proved entries behind it. -/
noncomputable def calls (workspaceLayout : WorkspaceLayout)
    (words : List Int) (grammarCell : CellId) : CallModel :=
  CallModel.route
    (fun function => function == extractedParserAppendStateFunction.id)
    (AppendStateCall.calls workspaceLayout)
    (EntryCallRegistry.calls words grammarCell)

/-- The full recognizer registry exposes the state constructor without
    requiring clients to unfold its nested function-ID routing tree. -/
theorem calls_at_seed (world : World) (seed : StateSeed) :
    (calls workspaceLayout words grammarCell).evaluate world
        extractedParserStateSeedFunction.id
        (parserStateSeedArgumentsValues seed) =
      .ok (stateSeedValue seed, world) := by
  have notAppend : extractedParserStateSeedFunction.id ≠
      extractedParserAppendStateFunction.id := by native_decide
  have notGrammar : extractedParserStateSeedFunction.id ≠
      extractedParserGrammarValidFunction.id := by native_decide
  have notResult : extractedParserStateSeedFunction.id ≠
      extractedParserParseResultFunction.id := by native_decide
  simpa [calls, EntryCallRegistry.calls, CallModel.route, notAppend,
    notGrammar, notResult] using
    StateSeedCall.calls_at_seed world seed

/-- Registry-level semantics of the capacity diagnostic helper. -/
theorem calls_at_append_or_full (world : World) (appended : AppendOutcome)
    (errorPosition : Int) :
    (calls workspaceLayout words grammarCell).evaluate world
        extractedParserAppendOrFullFunction.id
        [appendOutcomeValue appended, .signed .i32 errorPosition] =
      .ok (parseResultValue 2 (Int.ofNat appended.stateCount) (-1)
        errorPosition, world) := by
  have notAppend : extractedParserAppendOrFullFunction.id ≠
      extractedParserAppendStateFunction.id := by native_decide
  have notGrammar : extractedParserAppendOrFullFunction.id ≠
      extractedParserGrammarValidFunction.id := by native_decide
  have notResult : extractedParserAppendOrFullFunction.id ≠
      extractedParserParseResultFunction.id := by native_decide
  have notSeed : extractedParserAppendOrFullFunction.id ≠
      extractedParserStateSeedFunction.id := by native_decide
  simpa [calls, EntryCallRegistry.calls, CallModel.route, notAppend,
    notGrammar, notResult, notSeed] using
    AppendOrFullCall.calls_at world appended errorPosition

/-- Registry-level semantics of the mutating workspace append.  The source
    execution evidence is used only to establish that the partial semantic
    model's internal witness is observationally unique. -/
theorem calls_at_append_input
    (input : AppendStateCall.Input workspaceLayout world callValues)
    (before afterArguments : State)
    (commandLayout : Layout arity)
    (arguments : List
      (Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity))
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (worldOwned : (World.owns world).holds afterArguments)
    (argumentsExecution : ArgumentsEvaluateTo verifiedParserCore before
      (toCoreExprs commandLayout arguments) callValues afterArguments) :
    (calls workspaceLayout words grammarCell).evaluate world
        extractedParserAppendStateFunction.id callValues =
      .ok (appendOutcomeValue input.outcome, input.afterWorld) := by
  simpa [calls, CallModel.route] using
    AppendStateCall.calls_at_input input before afterArguments commandLayout
      arguments afterArgumentsWellFormed worldOwned argumentsExecution

theorem soundness
    (encoded : EncodesGrammar grammarLayout grammar words)
    (grammarWellFormed : grammar.WellFormed)
    (wordsI32 : words.length ≤ 2147483647) :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore
        (calls workspaceLayout words grammarCell) := by
  exact Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness.route
    (AppendStateCall.soundness workspaceLayout)
    (EntryCallRegistry.soundness encoded grammarWellFormed wordsI32)

end RecognizerCallRegistry

namespace RecognizerTraversalCallRegistry

open Lanius.FunctionalView.Core.Effectful

/-- Call model for chart traversal: packed state/grammar reads followed by
    the already verified constructor, append, and parse-result operations. -/
noncomputable def calls (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int)
    (grammarCell : CellId) : CallModel :=
  CallModel.route
    (fun function => function == extractedParserStateValueFunction.id ||
      function == extractedParserRhsLengthFunction.id ||
      function == extractedParserLhsFunction.id ||
      function == extractedParserRhsSymbolFunction.id)
    (RecognizerReadCallRegistry.calls grammar words grammarCell)
    (RecognizerCallRegistry.calls workspaceLayout words grammarCell)

theorem calls_at_state_value
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (values : List Int) (workspaceCell : CellId)
    (start length address : Nat) (base stateId field value : Int)
    (addressValue : parserStateWordValue verifiedParserCore.target
      base stateId field = Int.ofNat address)
    (sliceBound : address < length)
    (found : world.i32Slice? workspaceCell = some values)
    (backingBound : start + length ≤ values.length)
    (valueFound : ((values.drop start).take length)[address]? = some value) :
    (calls workspaceLayout grammar words grammarCell).evaluate world
        extractedParserStateValueFunction.id [
          .slice parserI32Type workspaceCell [] start length,
          .signed .i32 base,
          .signed .i32 stateId,
          .signed .i32 field] =
      .ok (.signed .i32 value, world) := by
  simpa [calls, CallModel.route] using
    RecognizerReadCallRegistry.calls_at_state_value
      (grammar := grammar) (words := words) (grammarCell := grammarCell)
      world values workspaceCell start length address base stateId field value
      addressValue sliceBound found backingBound valueFound

theorem calls_at_rhs_length
    (world : Lanius.FunctionalView.Core.ReadOnly.World) (production : Nat)
    (found : world.i32Slice? grammarCell = some words)
    (bound : production < grammar.rhsLengths.length) :
    (calls workspaceLayout grammar words grammarCell).evaluate world
        extractedParserRhsLengthFunction.id [
          parserGrammarValue words grammarCell,
          .signed .i32 (Int.ofNat production)] =
      .ok (.signed .i32 (Int.ofNat
        (grammar.rhsLengths.get ⟨production, bound⟩)), world) := by
  simpa [calls, CallModel.route] using
    RecognizerReadCallRegistry.calls_at_rhs_length
      (grammar := grammar) (words := words) (grammarCell := grammarCell)
      world production found bound

theorem calls_at_lhs
    (world : Lanius.FunctionalView.Core.ReadOnly.World) (production : Nat)
    (found : world.i32Slice? grammarCell = some words)
    (bound : production < grammar.productionLhs.length) :
    (calls workspaceLayout grammar words grammarCell).evaluate world
        extractedParserLhsFunction.id [
          parserGrammarValue words grammarCell,
          .signed .i32 (Int.ofNat production)] =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionLhs.get ⟨production, bound⟩)), world) := by
  simpa [calls, CallModel.route] using
    RecognizerReadCallRegistry.calls_at_lhs
      (grammar := grammar) (words := words) (grammarCell := grammarCell)
      world production found bound

theorem calls_at_rhs_symbol
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (production dot : Nat)
    (found : world.i32Slice? grammarCell = some words)
    (productionBound : production < grammar.productionCount)
    (dotBound : dot <
      (grammar.productionAt ⟨production, productionBound⟩).rhs.length) :
    (calls workspaceLayout grammar words grammarCell).evaluate world
        extractedParserRhsSymbolFunction.id [
          parserGrammarValue words grammarCell,
          .signed .i32 (Int.ofNat production),
          .signed .i32 (Int.ofNat dot)] =
      .ok (.signed .i32 (Int.ofNat
        ((grammar.productionAt ⟨production, productionBound⟩).rhs.get
          ⟨dot, dotBound⟩)), world) := by
  simpa [calls, CallModel.route] using
    RecognizerReadCallRegistry.calls_at_rhs_symbol
      (grammar := grammar) (words := words) (grammarCell := grammarCell)
      world production dot found productionBound dotBound

theorem calls_at_seed
    (world : Lanius.FunctionalView.Core.ReadOnly.World) (seed : StateSeed) :
    (calls workspaceLayout grammar words grammarCell).evaluate world
        extractedParserStateSeedFunction.id
        (parserStateSeedArgumentsValues seed) =
      .ok (stateSeedValue seed, world) := by
  have notState : extractedParserStateSeedFunction.id ≠
      extractedParserStateValueFunction.id := by native_decide
  have notRhs : extractedParserStateSeedFunction.id ≠
      extractedParserRhsLengthFunction.id := by native_decide
  have notLhs : extractedParserStateSeedFunction.id ≠
      extractedParserLhsFunction.id := by native_decide
  have notSymbol : extractedParserStateSeedFunction.id ≠
      extractedParserRhsSymbolFunction.id := by native_decide
  simpa [calls, CallModel.route, notState, notRhs, notLhs, notSymbol] using
    RecognizerCallRegistry.calls_at_seed
      (workspaceLayout := workspaceLayout) (words := words)
      (grammarCell := grammarCell) world seed

theorem calls_at_append_or_full
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (appended : AppendOutcome) (errorPosition : Int) :
    (calls workspaceLayout grammar words grammarCell).evaluate world
        extractedParserAppendOrFullFunction.id
        [appendOutcomeValue appended, .signed .i32 errorPosition] =
      .ok (parseResultValue 2 (Int.ofNat appended.stateCount) (-1)
        errorPosition, world) := by
  have notState : extractedParserAppendOrFullFunction.id ≠
      extractedParserStateValueFunction.id := by native_decide
  have notRhs : extractedParserAppendOrFullFunction.id ≠
      extractedParserRhsLengthFunction.id := by native_decide
  have notLhs : extractedParserAppendOrFullFunction.id ≠
      extractedParserLhsFunction.id := by native_decide
  have notSymbol : extractedParserAppendOrFullFunction.id ≠
      extractedParserRhsSymbolFunction.id := by native_decide
  simpa [calls, CallModel.route, notState, notRhs, notLhs, notSymbol] using
    RecognizerCallRegistry.calls_at_append_or_full
      (workspaceLayout := workspaceLayout) (words := words)
      (grammarCell := grammarCell) world appended errorPosition

/-- Registry-level semantics of the ordinary four-field parse-result
    constructor. Root selection and rejection use this route directly. -/
theorem calls_at_parse_result
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (status stateCount rootState errorPosition : Int) :
    (calls workspaceLayout grammar words grammarCell).evaluate world
        extractedParserParseResultFunction.id [
          .signed .i32 status, .signed .i32 stateCount,
          .signed .i32 rootState, .signed .i32 errorPosition] =
      .ok (parseResultValue status stateCount rootState errorPosition,
        world) := by
  have notState : extractedParserParseResultFunction.id ≠
      extractedParserStateValueFunction.id := by native_decide
  have notRhs : extractedParserParseResultFunction.id ≠
      extractedParserRhsLengthFunction.id := by native_decide
  have notLhs : extractedParserParseResultFunction.id ≠
      extractedParserLhsFunction.id := by native_decide
  have notSymbol : extractedParserParseResultFunction.id ≠
      extractedParserRhsSymbolFunction.id := by native_decide
  have notAppend : extractedParserParseResultFunction.id ≠
      extractedParserAppendStateFunction.id := by native_decide
  have notGrammar : extractedParserParseResultFunction.id ≠
      extractedParserGrammarValidFunction.id := by native_decide
  simp [calls, RecognizerCallRegistry.calls, EntryCallRegistry.calls,
    CallModel.route, ParseResultCallProof.calls, notState, notRhs, notLhs,
    notSymbol, notAppend, notGrammar]

theorem calls_at_append_input
    (input : AppendStateCall.Input workspaceLayout world callValues)
    (before afterArguments : State)
    (commandLayout : Layout arity)
    (arguments : List
      (Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity))
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (worldOwned : (Lanius.FunctionalView.Core.ReadOnly.World.owns world).holds
      afterArguments)
    (argumentsExecution : ArgumentsEvaluateTo verifiedParserCore before
      (toCoreExprs commandLayout arguments) callValues afterArguments) :
    (calls workspaceLayout grammar words grammarCell).evaluate world
        extractedParserAppendStateFunction.id callValues =
      .ok (appendOutcomeValue input.outcome, input.afterWorld) := by
  have notState : extractedParserAppendStateFunction.id ≠
      extractedParserStateValueFunction.id := by native_decide
  have notRhs : extractedParserAppendStateFunction.id ≠
      extractedParserRhsLengthFunction.id := by native_decide
  have notLhs : extractedParserAppendStateFunction.id ≠
      extractedParserLhsFunction.id := by native_decide
  have notSymbol : extractedParserAppendStateFunction.id ≠
      extractedParserRhsSymbolFunction.id := by native_decide
  simpa [calls, CallModel.route, notState, notRhs, notLhs, notSymbol] using
    RecognizerCallRegistry.calls_at_append_input
      (workspaceLayout := workspaceLayout) (words := words)
      (grammarCell := grammarCell) input before afterArguments commandLayout
      arguments afterArgumentsWellFormed worldOwned argumentsExecution

/-- Traversal-specific routes leave every other recognizer call unchanged. -/
theorem calls_at_base
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (function : FunctionId) (values : List Value)
    (notState : function ≠ extractedParserStateValueFunction.id)
    (notRhs : function ≠ extractedParserRhsLengthFunction.id)
    (notLhs : function ≠ extractedParserLhsFunction.id)
    (notSymbol : function ≠ extractedParserRhsSymbolFunction.id) :
    (calls workspaceLayout grammar words grammarCell).evaluate world function
        values =
      (RecognizerCallRegistry.calls workspaceLayout words grammarCell).evaluate
        world function values := by
  simp [calls, CallModel.route, notState, notRhs, notLhs, notSymbol]

end RecognizerTraversalCallRegistry

namespace RecognizerStateCallRegistry

open Lanius.FunctionalView.Core.Effectful

private noncomputable def scanInput (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId) (values : List Value) : Nat × Nat := by
  classical
  exact if found : ∃ input : Nat × Nat,
      values = [parserGrammarValue words grammarCell,
        parserTokensValue tokens tokensCell,
        .signed .i32 (Int.ofNat tokens.length),
        .signed .i32 (Int.ofNat input.1),
        .signed .i32 (Int.ofNat input.2)] then
    found.choose
  else (0, 0)

private theorem scanInput_expected
    (words : List Int) (tokens : List Nat) (grammarCell tokensCell : CellId)
    (position semanticKind : Nat) :
    scanInput words tokens grammarCell tokensCell [
        parserGrammarValue words grammarCell,
        parserTokensValue tokens tokensCell,
        .signed .i32 (Int.ofNat tokens.length),
        .signed .i32 (Int.ofNat position),
        .signed .i32 (Int.ofNat semanticKind)] =
      (position, semanticKind) := by
  simp only [scanInput]
  split
  next found =>
    apply Prod.ext
    · have valueEq := congrArg
          (fun values : List Value => values[3]?) found.choose_spec
      have intEq : Int.ofNat found.choose.1 = Int.ofNat position := by
        simpa using valueEq.symm
      exact Int.ofNat_inj.mp intEq
    · have valueEq := congrArg
          (fun values : List Value => values[4]?) found.choose_spec
      have intEq : Int.ofNat found.choose.2 = Int.ofNat semanticKind := by
        simpa using valueEq.symm
      exact Int.ofNat_inj.mp intEq
  next notFound =>
    exact (notFound ⟨(position, semanticKind), rfl⟩).elim

/-- The terminal-scan operation first encountered by the enclosing state loop. -/
noncomputable def scanCalls (grammar : IndexedGrammar) (words : List Int)
    (tokens : List Nat) (grammarCell tokensCell : CellId) : CallModel := by
  classical
  exact {
    evaluate := fun world function values =>
      if function = extractedParserScanTerminalFunction.id then
        if found : ∃ input : Nat × Nat,
            values = [parserGrammarValue words grammarCell,
              parserTokensValue tokens tokensCell,
              .signed .i32 (Int.ofNat tokens.length),
              .signed .i32 (Int.ofNat input.1),
              .signed .i32 (Int.ofNat input.2)] ∧
            world.i32Slice? grammarCell = some words ∧
            world.i32Slice? tokensCell = some (tokens.map Int.ofNat) then
          .ok (scanTerminalValue
            (Lanius.Compiler.Parser.scanTerminal grammar tokens
              (scanInput words tokens grammarCell tokensCell values).1
              (scanInput words tokens grammarCell tokensCell values).2), world)
        else .error .typeMismatch
      else .error .invalidPointer
  }

/-- State-loop calls extend traversal calls without changing the inner-loop
    registries or their already proved call boundaries. -/
noncomputable def calls (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId) : CallModel :=
  CallModel.route
    (fun function => function == extractedParserScanTerminalFunction.id)
    (scanCalls grammar words tokens grammarCell tokensCell)
    (CallModel.route
      (fun function => function == extractedParserChartWordFunction.id)
      ParserReads.Functional.ChartWord.calls
      (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
        grammarCell))

theorem calls_at_scan_terminal
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (position semanticKind : Nat)
    (grammarFound : world.i32Slice? grammarCell = some words)
    (tokensFound : world.i32Slice? tokensCell =
      some (tokens.map Int.ofNat)) :
    (calls workspaceLayout grammar words tokens grammarCell tokensCell).evaluate
        world extractedParserScanTerminalFunction.id [
          parserGrammarValue words grammarCell,
          parserTokensValue tokens tokensCell,
          .signed .i32 (Int.ofNat tokens.length),
          .signed .i32 (Int.ofNat position),
          .signed .i32 (Int.ofNat semanticKind)] =
      .ok (scanTerminalValue
        (Lanius.Compiler.Parser.scanTerminal grammar tokens position
          semanticKind), world) := by
  simp only [calls, CallModel.route, beq_iff_eq, if_true]
  simp only [scanCalls]
  simp only [if_true]
  split
  next found =>
    rw [scanInput_expected]
  next notFound =>
    exact (notFound ⟨(position, semanticKind), rfl, grammarFound,
      tokensFound⟩).elim

theorem calls_at_chart_word
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (position field : Nat)
    (positionBound : position ≤ finalPosition workspaceLayout.tokenCount)
    (fieldBound : field < chartWords) :
    (calls workspaceLayout grammar words tokens grammarCell tokensCell).evaluate
        world extractedParserChartWordFunction.id [
          .signed .i32 (Int.ofNat position),
          .signed .i32 (Int.ofNat field)] =
      .ok (.signed .i32 (Int.ofNat (chartWord position field)), world) := by
  have notScan : extractedParserChartWordFunction.id ≠
      extractedParserScanTerminalFunction.id := by native_decide
  simp only [calls, CallModel.route, beq_iff_eq, notScan, if_false, if_true]
  have evaluated := ParserReads.Functional.ChartWord.calls_at_arguments
      (world := world) (position := Int.ofNat position)
      (field := Int.ofNat field)
  have addressValue := workspaceLayout.chart_value_eq_address
    positionBound fieldBound
  simp only [ParserReads.Functional.ChartWord.result] at evaluated
  rw [addressValue] at evaluated
  simpa [ParserReads.Functional.ChartWord.arguments] using evaluated

theorem calls_at_traversal
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (function : FunctionId) (values : List Value)
    (notScan : function ≠ extractedParserScanTerminalFunction.id)
    (notChart : function ≠ extractedParserChartWordFunction.id) :
    (calls workspaceLayout grammar words tokens grammarCell tokensCell).evaluate
        world function values =
      (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
        grammarCell).evaluate world function values := by
  simp [calls, CallModel.route, notScan, notChart]

end RecognizerStateCallRegistry

namespace GrammarGuardBlock

open Lanius.FunctionalView
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.ReadOnly

private def layout : Layout 2 := pairLayout 0 1

private def environment (words : List Int) (grammarCell : CellId) : Env 2 :=
  pairEnvironment (parserGrammarValue words grammarCell)
    (.signed .i32 (Int.ofNat words.length))

private def validCall : Term signature 2 :=
  .apply (.call extractedParserGrammarValidFunction.id
      [.slice parserI32Type, parserI32Type] (.scalar .bool)) [
    .reference (.slot ⟨0, by omega⟩),
    .reference (.slot ⟨1, by omega⟩)]

private def condition : Term signature 2 :=
  .apply (.unary .logicalNot (.scalar .bool) (.scalar .bool)) [validCall]

private def badResult : Term signature 2 :=
  .apply (.call extractedParserParseResultFunction.id
      [parserI32Type, parserI32Type, parserI32Type, parserI32Type]
      (.structure 0)) [
    .apply (.constant 3 parserI32Type) [],
    .reference (.literal (.signed .i32 0)),
    .apply (.unary .negate parserI32Type parserI32Type)
      [.reference (.literal (.signed .i32 1))],
    .reference (.literal (.signed .i32 0))]

private def badBranch : Block signature 2 :=
  .sequence (.returnValue (some badResult)) .skip

def block : Block signature 2 :=
  .ifThenElse condition badBranch .skip

theorem block_toCore_exactly :
    Lanius.FunctionalView.Core.toCoreStmt layout 2 block =
      parserRecognizeGrammarGuard := by
  rfl

theorem evaluates_valid
    (found : world.i32Slice? grammarCell = some words) :
    Block.evaluate
      (Effectful.machine verifiedParserCore
        (EntryCallRegistry.calls words grammarCell))
      world (environment words grammarCell) block =
        .done .next world := by
  have callResult : Term.evaluate
      (Effectful.machine verifiedParserCore
        (EntryCallRegistry.calls words grammarCell))
      world (environment words grammarCell) validCall =
        .ok (.boolean true, world) := by
    simp [validCall, Effectful.machine, Term.evaluate, evaluateTerms,
      Ref.evaluate, environment, pairEnvironment,
      Effectful.evaluateOperation, EntryCallRegistry.calls,
      CallModel.route, ParserValidation.FunctionalView.calls, found,
      bind, Except.bind]
  simp only [block, Block.evaluate, condition, Term.evaluate, evaluateTerms,
    callResult, bind, Except.bind]
  rfl

/-- Replacement for the old hand-assembled Core proof of the entry guard.
    The FunctionalView evaluation is simulated through the verified helper
    registry and then rewritten to the exact artifact-derived statement. -/
theorem executes_valid
    (state : State)
    (grammarLocal : state.local? 0 =
      some (parserGrammarValue words grammarCell))
    (grammarLengthLocal : state.local? 1 =
      some (.signed .i32 (Int.ofNat words.length)))
    (invariant : GrammarValidationInvariant grammarLayout grammar words
      grammarCell (parserGrammarValidCallee state words grammarCell))
    (stateWellFormed : StateWellFormed state) :
    ∃ after,
      Executes verifiedParserCore state parserRecognizeGrammarGuard .next after ∧
      ModifiesOnly CellSet.empty state after ∧
      StateWellFormed after := by
  obtain ⟨after, call, effect, afterWellFormed⟩ :=
    grammarValidCall_evaluates_encoded state grammarLocal grammarLengthLocal
      invariant stateWellFormed
  have conditionExecution : Evaluates verifiedParserCore state
      (Lanius.FunctionalView.Core.toCoreExpr layout condition)
      (.boolean false) after := by
    apply evaluatesUnary call
    simp [evalUnaryValue]
  have execution : Executes verifiedParserCore state
      (Lanius.FunctionalView.Core.toCoreStmt layout 2 block) .next after := by
    exact executesIfFalse conditionExecution
      (executesSkip verifiedParserCore after)
  rw [block_toCore_exactly] at execution
  exact ⟨after, execution, effect, afterWellFormed⟩

end GrammarGuardBlock

end Lanius.Extraction.ParserRecognize
