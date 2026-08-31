import Lanius.Extraction.RawLexer.ScanOne.Execution
import Lanius.Extraction.Lexer.Calls
import Lanius.Extraction.Symbol.MainCalls
import Lanius.Extraction.Symbol.CompilerAgreement
import Lanius.Extraction.Number.Calls
import Lanius.FunctionalViewCoreFreshSimulation
import Lanius.FunctionalViewCoreCallFrame

namespace Lanius.Extraction.RawLexer.ScanOne.Calls

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.FunctionalView.FreshSimulation

private theorem scanOneFunction_parameters :
    Functions.scanOneFunction.parameters =
      [(0, .slice Compiler.Lexer.Program.i32Type),
        (1, Compiler.Lexer.Program.i32Type),
        (2, Compiler.Lexer.Program.i32Type)] := by
  native_decide

private theorem parameterBindings_match
    (source : List Compiler.Lexer.Byte) (start : Nat) :
    bindParameters Functions.scanOneFunction.parameters
        (Model.argumentValues source start) =
      some (parameterBindings (Model.environment source start)) := by
  rw [scanOneFunction_parameters]
  simp [bindParameters, Model.argumentValues, Model.environment,
    parameterBindings, List.finRange]

def isNumberHelper (function : FunctionId) : Bool :=
  function = Number.Functions.scanNumberFunction.id ∨
    function = Number.Functions.scanLeadingDotNumberFunction.id

def isSymbolHelper (function : FunctionId) : Bool :=
  function = Symbol.Functions.matchSymbolHeadFunction.id ∨
    function = Symbol.Functions.tokenMatchKindFunction.id ∨
    function = Symbol.Functions.tokenMatchLengthFunction.id

def isTokenScanConstructor (function : FunctionId) : Bool :=
  function = TokenScan.Functions.successfulFunction.id ∨
    function = TokenScan.Functions.failedFunction.id

/-- The helper registry used while executing the exact checked `scan_one`
body.  The routing boundary is the checked function identity, not a
source-program shape. -/
noncomputable def helperCallModel (source : List Compiler.Lexer.Byte) : CallModel :=
  CallModel.route isNumberHelper (Number.Calls.numberCalls source)
    (CallModel.route isSymbolHelper (Symbol.MainCalls.callModel source)
      (CallModel.route isTokenScanConstructor
        TokenScan.Semantics.constructorCallModel
        (Lexer.Calls.callModel source)))

theorem helperCallModel_number
    (selected : isNumberHelper function = true) :
    (helperCallModel source).evaluate
        world function arguments =
      (Number.Calls.numberCalls source).evaluate world function arguments := by
  simp [helperCallModel,
    Lanius.FunctionalView.Core.Effectful.CallModel.route, selected]

theorem helperCallModel_symbol
    (notNumber : isNumberHelper function = false)
    (selected : isSymbolHelper function = true) :
    (helperCallModel source).evaluate
        world function arguments =
      (Symbol.MainCalls.callModel source).evaluate
        world function arguments := by
  simp [helperCallModel,
    Lanius.FunctionalView.Core.Effectful.CallModel.route,
    notNumber, selected]

theorem helperCallModel_tokenScan
    (notNumber : isNumberHelper function = false)
    (notSymbol : isSymbolHelper function = false)
    (selected : isTokenScanConstructor function = true) :
    (helperCallModel source).evaluate
        world function arguments =
      TokenScan.Semantics.constructorCallModel.evaluate
        world function arguments := by
  simp [helperCallModel,
    Lanius.FunctionalView.Core.Effectful.CallModel.route,
    notNumber, notSymbol, selected]

theorem helperCallModel_lexer
    (notNumber : isNumberHelper function = false)
    (notSymbol : isSymbolHelper function = false)
    (notTokenScan : isTokenScanConstructor function = false) :
    (helperCallModel source).evaluate
        world function arguments =
      (Lexer.Calls.callModel source).evaluate world function arguments := by
  simp [helperCallModel,
    Lanius.FunctionalView.Core.Effectful.CallModel.route,
    notNumber, notSymbol, notTokenScan]

theorem helperFramePreservingCallSoundness
    (source : List Compiler.Lexer.Byte)
    (numberSoundness :
      FramePreservingCallSoundness verifiedFrontendCore
        (Number.Calls.numberCalls source)) :
    FramePreservingCallSoundness verifiedFrontendCore
      (helperCallModel source) := by
  apply FreshSimulation.FramePreservingCallSoundness.route numberSoundness
  apply FreshSimulation.FramePreservingCallSoundness.route
    (Symbol.MainCalls.framePreservingCallSoundness source)
  apply FreshSimulation.FramePreservingCallSoundness.route
    TokenScan.Semantics.constructorFramePreservingCallSoundness
  exact Lexer.Calls.framePreservingCallSoundness source

private theorem lexerEncodedScanEnd_eq (result : Compiler.Lexer.ScanEnd) :
    Lexer.Calls.encodedScanEnd result = Model.encodedScanEnd result := by
  cases result <;> rfl

private theorem numberEncoded_eq (result : Compiler.Lexer.NumberScanResult) :
    Number.Model.encoded result = Model.encodedNumber result := by
  cases result with
  | failure => rfl
  | success kind finish => cases kind <;> rfl

theorem helperContract
    (source : List Compiler.Lexer.Byte)
    (sourceBound : source.length ≤ 2147483646)
    (world : ReadOnly.World)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source)) :
    Evaluation.HelperContract (helperCallModel source) source world := by
  have sourceI32Bound : source.length ≤ 2147483647 := by omega
  constructor
  · intro offset
    rw [helperCallModel_tokenScan (source := source)
      (by native_decide) (by native_decide) (by native_decide)]
    exact TokenScan.Semantics.constructorCallModel_failed world offset
  · intro kind finish
    rw [helperCallModel_tokenScan (source := source)
      (by native_decide) (by native_decide) (by native_decide)]
    exact TokenScan.Semantics.constructorCallModel_successful world
      kind.gpuCode finish
  · intro byte
    rw [helperCallModel_lexer (source := source)
      (by native_decide) (by native_decide) (by native_decide)]
    exact Lexer.Calls.callModel_classifyStart source world byte
  · intro byte
    rw [helperCallModel_lexer (source := source)
      (by native_decide) (by native_decide) (by native_decide)]
    exact Lexer.Calls.callModel_decimalDigit source world byte
  · intro start startInBounds startBound
    rw [helperCallModel_lexer (source := source)
      (by native_decide) (by native_decide) (by native_decide)]
    simpa [Model.argumentValues, Lexer.Calls.scannerArguments,
      Model.sourceSlice, Lexer.Calls.sourceSlice] using
      Lexer.Calls.callModel_identifier_in_world source world start
        sourceI32Bound startInBounds startBound sourceFound
  · intro start startInBounds startBound
    rw [helperCallModel_lexer (source := source)
      (by native_decide) (by native_decide) (by native_decide)]
    simpa [Model.argumentValues, Lexer.Calls.scannerArguments,
      Model.sourceSlice, Lexer.Calls.sourceSlice] using
      Lexer.Calls.callModel_whitespace_in_world source world start
        sourceI32Bound startInBounds startBound sourceFound
  · intro start startInBounds startBound
    rw [helperCallModel_lexer (source := source)
      (by native_decide) (by native_decide) (by native_decide)]
    simpa [Model.argumentValues, Lexer.Calls.scannerArguments,
      Model.sourceSlice, Lexer.Calls.sourceSlice,
      lexerEncodedScanEnd_eq,
      (by native_decide : Compiler.Lexer.Program.doubleQuoteByte =
        Compiler.Lexer.doubleQuote)] using
      Lexer.Calls.callModel_string_in_world source world start
        sourceI32Bound startInBounds startBound sourceFound
  · intro start startInBounds startBound
    rw [helperCallModel_lexer (source := source)
      (by native_decide) (by native_decide) (by native_decide)]
    simpa [Model.argumentValues, Lexer.Calls.scannerArguments,
      Model.sourceSlice, Lexer.Calls.sourceSlice,
      lexerEncodedScanEnd_eq,
      (by native_decide : Compiler.Lexer.Program.singleQuoteByte =
        Compiler.Lexer.singleQuote)] using
      Lexer.Calls.callModel_character_in_world source world start
        sourceI32Bound startInBounds startBound sourceFound
  · intro start openingInBounds startBound
    rw [helperCallModel_lexer (source := source)
      (by native_decide) (by native_decide) (by native_decide)]
    simpa [Model.argumentValues, Lexer.Calls.scannerArguments,
      Model.sourceSlice, Lexer.Calls.sourceSlice] using
      Lexer.Calls.callModel_lineComment_in_world source world start
        sourceI32Bound openingInBounds startBound sourceFound
  · intro start openingInBounds startBound
    rw [helperCallModel_lexer (source := source)
      (by native_decide) (by native_decide) (by native_decide)]
    simpa [Model.argumentValues, Lexer.Calls.scannerArguments,
      Model.sourceSlice, Lexer.Calls.sourceSlice,
      lexerEncodedScanEnd_eq] using
      Lexer.Calls.callModel_blockComment_in_world source world start
        sourceI32Bound openingInBounds startBound sourceFound
  · intro result
    rw [helperCallModel_lexer (source := source)
      (by native_decide) (by native_decide) (by native_decide)]
    cases result <;> exact Lexer.Calls.callModel_scanSucceeded source world _ _ _
  · intro finish
    rw [helperCallModel_lexer (source := source)
      (by native_decide) (by native_decide) (by native_decide)]
    exact Lexer.Calls.callModel_scanEndOffset source world true finish 0
  · intro error
    rw [helperCallModel_lexer (source := source)
      (by native_decide) (by native_decide) (by native_decide)]
    exact Lexer.Calls.callModel_scanErrorOffset source world false 0 error
  · intro start startInBounds startBound
    rw [helperCallModel_number (source := source) (by native_decide)]
    simpa [Model.argumentValues, Number.Model.argumentValues,
      Model.sourceSlice, Number.Model.sourceSlice, numberEncoded_eq] using
      Number.Calls.numberCalls_scanNumber source world start
        sourceFound sourceI32Bound startInBounds
  · intro start openingInBounds startBound
    rw [helperCallModel_number (source := source) (by native_decide)]
    have startInBounds : start < source.length := by omega
    simpa [Model.argumentValues, Number.Model.argumentValues,
      Model.sourceSlice, Number.Model.sourceSlice, numberEncoded_eq] using
      Number.Calls.numberCalls_scanLeadingDotNumber source world start
        sourceFound sourceI32Bound startInBounds
  · intro start rule startInBounds startBound selected
    rw [helperCallModel_symbol (source := source)
      (by native_decide) (by native_decide)]
    have evaluated := Symbol.MainCalls.callModel_matchSymbolHead
      source world start sourceBound startInBounds sourceFound
    rw [Symbol.CompilerAgreement.encoded_eq_selected selected] at evaluated
    simpa [Model.argumentValues, Symbol.Model.argumentValues,
      Model.sourceSlice, Symbol.Model.sourceSlice] using evaluated
  · intro kind length
    rw [helperCallModel_symbol (source := source)
      (by native_decide) (by native_decide)]
    exact Symbol.MainCalls.callModel_tokenMatchKind source world kind length
  · intro kind length
    rw [helperCallModel_symbol (source := source)
      (by native_decide) (by native_decide)]
    exact Symbol.MainCalls.callModel_tokenMatchLength source world kind length

/-- The exact checked `scan_one` body preserves every caller-visible cell
when all of its checked helper calls satisfy the same frame-preserving
contract. -/
theorem mainFramePreservingCallSoundness
    (source : List Compiler.Lexer.Byte) (helpers : CallModel)
    (helperContract : source.length ≤ 2147483646 → ∀ world : ReadOnly.World,
      world.i32Slice? 0 = some (Model.sourceIntegers source) →
        Evaluation.HelperContract helpers source world)
    (helperSoundness :
      FramePreservingCallSoundness verifiedFrontendCore helpers) :
    FramePreservingCallSoundness verifiedFrontendCore
      (Model.callModel source) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments function sourceArguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨startInt, rfl, valuesEq, sourceBound, startNonnegative,
      startBoundInt, sourceFound, rfl, afterWorldEq⟩ :=
    Model.callModel_success evaluated
  subst afterWorld
  let start := startInt.toNat
  have startEq : (start : Int) = startInt := by
    simp [start]
    omega
  have startBound : start ≤ 2147483647 := by
    simp [start]
    omega
  let calleeEnvironment := Model.environment source start
  let bindings := parameterBindings calleeEnvironment
  let callee := enterCall afterArguments bindings
  have calleeRepresented : Representation identityLayout
      (callLocalCells afterArguments) beforeWorld calleeEnvironment callee := by
    simpa [callee, bindings] using
      represented.enterCallParameters afterArgumentsWellFormed
        (environment := calleeEnvironment)
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, bindings] using
      enterCall_preserves_wellFormed afterArgumentsWellFormed
  have sourceI32Bound : source.length ≤ 2147483647 := by omega
  have functionalRun := Evaluation.scanOne_run
    (helperContract sourceBound beforeWorld sourceFound) sourceI32Bound sourceFound
    startBound
  have functionalEvaluation := Stateful.Acyclic.run?_sound functionalRun
  let operations := operationSoundness verifiedFrontendCore helpers
    helperSoundness
  have simulation := commandSoundness operations functionalEvaluation
    (by native_decide)
    calleeRepresented (LayoutBelow.identity (arity := 3)) calleeWellFormed
    (frontier := afterArguments.nextCell)
    (by
      intro index
      simp [callLocalCells])
    (by
      simpa [callee] using
        (enterCall_effect afterArguments bindings).nextCell)
  obtain ⟨completed, bodyExecution, completedWellFormed,
      completedRepresented, bodyEffect⟩ := simulation
  rw [Commands.scanOne_toCore_exactly] at bodyExecution
  change Executes verifiedFrontendCore callee Functions.scanOneBody
    (.returned (some (Model.encoded
      (Compiler.Lexer.scanOne source start)))) completed at bodyExecution
  have callExecution : Evaluates verifiedFrontendCore before
      (.call Functions.scanOneFunction.id
        (toCoreExprs layout sourceArguments))
      (Model.encoded (Compiler.Lexer.scanOne source start))
      (restoreLocals afterArguments completed) := by
    apply evaluatesCallReturned
      (bindings := bindings) (body := Functions.scanOneBody)
      argumentsExecution (by rfl)
    · rw [valuesEq]
      rw [show [Model.sourceSlice source,
          .signed .i32 (Int.ofNat source.length), .signed .i32 startInt] =
          Model.argumentValues source start by
        simp [Model.argumentValues, startEq]]
      simpa [bindings, calleeEnvironment] using
        parameterBindings_match source start
    · rfl
    · simpa [callee, bindings] using bodyExecution
  obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
    represented.restoreFreshCall afterArgumentsWellFormed
      completedWellFormed (bindings := bindings) bodyEffect (by
        intro cell written
        exact written)
  exact ⟨restoreLocals afterArguments completed, callExecution,
    afterWellFormed, afterRepresented,
    argumentsEffect.trans_same
      (callEffect.weaken CellSet.empty_subset)⟩

/-- Ordinary checked-call soundness follows from caller-frame preservation. -/
theorem mainCallSoundness
    (source : List Compiler.Lexer.Byte) (helpers : CallModel)
    (helperContract : source.length ≤ 2147483646 → ∀ world : ReadOnly.World,
      world.i32Slice? 0 = some (Model.sourceIntegers source) →
        Evaluation.HelperContract helpers source world)
    (helperSoundness :
      FramePreservingCallSoundness verifiedFrontendCore helpers) :
    EffectfulStateful.CallSoundness verifiedFrontendCore
      (Model.callModel source) := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments values result argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨after, callExecution, afterWellFormed, afterRepresented,
        callEffect⟩ :=
      (mainFramePreservingCallSoundness source helpers helperContract
        helperSoundness).call afterArgumentsWellFormed represented
          argumentsExecution argumentsEffect evaluated
    exact ⟨after, argumentWrites, callExecution, afterWellFormed,
      afterRepresented, callEffect⟩
  · intro beforeWorld afterWorld function values result evaluated cell
    obtain ⟨start, rfl, valuesEq, sourceBound, startNonnegative,
        startBound, sourceFound, rfl, rfl⟩ :=
      Model.callModel_success evaluated
    rfl

theorem framePreservingCallSoundnessOfNumber
    (source : List Compiler.Lexer.Byte)
    (numberSoundness : FramePreservingCallSoundness verifiedFrontendCore
      (Number.Calls.numberCalls source)) :
    FramePreservingCallSoundness verifiedFrontendCore
      (Model.callModel source) :=
  mainFramePreservingCallSoundness source (helperCallModel source)
    (fun sourceBound world sourceFound =>
      helperContract source sourceBound world sourceFound)
    (helperFramePreservingCallSoundness source numberSoundness)

theorem callSoundnessOfNumber
    (source : List Compiler.Lexer.Byte)
    (numberSoundness : FramePreservingCallSoundness verifiedFrontendCore
      (Number.Calls.numberCalls source)) :
    EffectfulStateful.CallSoundness verifiedFrontendCore
      (Model.callModel source) :=
  mainCallSoundness source (helperCallModel source)
    (fun sourceBound world sourceFound =>
      helperContract source sourceBound world sourceFound)
    (helperFramePreservingCallSoundness source numberSoundness)

/-- The exact checked `scan_one` body, with every nested checked helper bound
to its concrete frontend registry, preserves every caller-visible cell. -/
theorem framePreservingCallSoundness
    (source : List Compiler.Lexer.Byte) :
    FramePreservingCallSoundness verifiedFrontendCore
      (Model.callModel source) :=
  framePreservingCallSoundnessOfNumber source
    (Number.Calls.numberFramePreservingCallSoundness source)

/-- Premise-free checked-program call semantics for `raw_lexer.lani::scan_one`. -/
theorem callSoundness
    (source : List Compiler.Lexer.Byte) :
    EffectfulStateful.CallSoundness verifiedFrontendCore
      (Model.callModel source) :=
  callSoundnessOfNumber source
    (Number.Calls.numberFramePreservingCallSoundness source)

end Lanius.Extraction.RawLexer.ScanOne.Calls
