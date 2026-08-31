import Lanius.Extraction.Decimal.ScanExponentEvaluation
import Lanius.FunctionalViewCoreFreshSimulation
import Lanius.FunctionalViewCoreCallFrame

namespace Lanius.Extraction.Decimal.ScanExponentSemantics

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Extraction.Decimal
open Lanius.Extraction.Decimal.EvaluationModel

noncomputable def callModel (source : List Byte) : CallModel := by
  classical
  exact { evaluate := fun world function values =>
    if world.i32Slice? 0 = some (sourceIntegers source) then
      if function = Functions.scanExponentFunction.id then
        match values with
        | [.slice (.scalar (.signed .i32)) cell projections sliceBase length,
            .signed .i32 sourceLength, .signed .i32 start] =>
            if cell = 0 ∧ projections = [] ∧ sliceBase = 0 ∧
                length = source.length ∧
                sourceLength = Int.ofNat source.length ∧
                0 ≤ start ∧ start.toNat < source.length ∧
                source.length ≤ 2147483647 then
              .ok (encoded (scanExponent source start.toNat), world)
            else .error .typeMismatch
        | _ => .error .typeMismatch
      else .error .invalidPointer
    else .error .invalidPointer }

@[simp] theorem evaluate
    (world : ReadOnly.World) (source : List Byte) (start : Nat)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    (callModel source).evaluate world Functions.scanExponentFunction.id
        (arguments source start) =
      .ok (encoded (scanExponent source start), world) := by
  have startBound : start ≤ 2147483647 := by omega
  simp [callModel, arguments, EvaluationModel.sourceSlice,
    DigitRunModel.sourceSlice, Program.i32Type, sourceFound, sourceBound,
    startInBounds, startBound]

private theorem call_success
    (evaluated : (callModel source).evaluate world function values =
      .ok (result, afterWorld)) :
    ∃ start : Nat,
      world.i32Slice? 0 = some (sourceIntegers source) ∧
      function = Functions.scanExponentFunction.id ∧
      values = arguments source start ∧
      source.length ≤ 2147483647 ∧ start < source.length ∧
      result = encoded (scanExponent source start) ∧ afterWorld = world := by
  simp only [callModel] at evaluated
  split at evaluated
  next sourceFound =>
    split at evaluated
    next functionEq =>
      split at evaluated
      next cell projections sliceBase length sourceLength start =>
        split at evaluated
        next valid =>
          obtain ⟨rfl, rfl⟩ := evaluated
          let startNat := start.toNat
          have startEq : (startNat : Int) = start := by
            simp [startNat]
            omega
          refine ⟨startNat, sourceFound, functionEq, ?_,
            valid.2.2.2.2.2.2.2, valid.2.2.2.2.2.2.1, ?_, rfl⟩
          · simp [arguments, EvaluationModel.sourceSlice,
              DigitRunModel.sourceSlice, Program.i32Type, startNat, startEq,
              valid.1, valid.2.1, valid.2.2.1, valid.2.2.2.1,
              valid.2.2.2.2.1]
          · simp [startNat, startEq]
        next => contradiction
      next => contradiction
    next => contradiction
  next => contradiction

theorem verifiedFrontendCore_finds :
    verifiedFrontendCore.function? Functions.scanExponentFunction.id =
      some Functions.scanExponentFunction := by rfl

theorem scanExponentFunction_parameters :
    Functions.scanExponentFunction.parameters =
      [(0, .slice Program.i32Type), (1, Program.i32Type),
        (2, Program.i32Type)] := by
  native_decide

theorem scanExponentFunction_has_body :
    Functions.scanExponentFunction.body =
      some Functions.scanExponentBody := by
  rfl

theorem framePreservingCallSoundness (source : List Byte) :
    FramePreservingCallSoundness verifiedFrontendCore (callModel source) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments function sourceArguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨start, sourceFound, rfl, rfl, sourceBound, startInBounds,
      rfl, rfl⟩ := call_success evaluated
  let calleeEnvironment := environment source start
  let bindings := parameterBindings calleeEnvironment
  let callee := enterCall afterArguments bindings
  have calleeRepresented : Representation identityLayout
      (callLocalCells afterArguments) afterWorld calleeEnvironment callee := by
    simpa [callee, bindings] using
      represented.enterCallParameters afterArgumentsWellFormed
        (environment := calleeEnvironment)
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, bindings] using
      enterCall_preserves_wellFormed afterArgumentsWellFormed
  have functionalEvaluation :=
    ScanExponentEvaluation.scanExponent_evaluates source afterWorld start
      sourceFound sourceBound startInBounds
  let operations := operationSoundness verifiedFrontendCore
    (helperCalls source) (helperCalls_framePreserving source)
  have simulation := commandSoundness operations functionalEvaluation
    (by native_decide) calleeRepresented
    (LayoutBelow.identity (arity := 3)) calleeWellFormed
    (frontier := afterArguments.nextCell)
    (by intro index; simp [callLocalCells])
    (by simpa [callee] using (enterCall_effect afterArguments bindings).nextCell)
  obtain ⟨completed, bodyExecution, completedWellFormed,
      completedRepresented, bodyEffect⟩ := simulation
  rw [Commands.scanExponentReadable_toCore_exactly] at bodyExecution
  have callExecution : Evaluates verifiedFrontendCore before
      (.call Functions.scanExponentFunction.id
        (toCoreExprs layout sourceArguments))
      (encoded (scanExponent source start))
      (restoreLocals afterArguments completed) := by
    apply evaluatesCallReturned (bindings := bindings)
      (body := Functions.scanExponentBody) argumentsExecution
      verifiedFrontendCore_finds
    · rw [scanExponentFunction_parameters]
      simp [bindParameters, bindings, calleeEnvironment, parameterBindings,
        environment, arguments, EvaluationModel.sourceSlice,
        DigitRunModel.sourceSlice, Program.i32Type, List.finRange]
    · exact scanExponentFunction_has_body
    · change Executes verifiedFrontendCore callee Functions.scanExponentBody
        (.returned (some (encoded (scanExponent source start)))) completed at bodyExecution
      simpa [callee, bindings] using bodyExecution
  obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
    represented.restoreFreshCall afterArgumentsWellFormed completedWellFormed
      (bindings := bindings) bodyEffect (by intro cell written; exact written)
  exact ⟨restoreLocals afterArguments completed, callExecution,
    afterWellFormed, afterRepresented,
    argumentsEffect.trans_same (callEffect.weaken CellSet.empty_subset)⟩

theorem worldPreserving (source : List Byte) :
    WorldPreserving (callModel source) := by
  intro beforeWorld afterWorld function values value evaluated
  obtain ⟨start, sourceFound, functionEq, valuesEq, sourceBound,
      startInBounds, resultEq, afterEq⟩ := call_success evaluated
  exact afterEq

theorem callSoundness (source : List Byte) :
    EffectfulStateful.CallSoundness verifiedFrontendCore (callModel source) :=
  (framePreservingCallSoundness source).toCallSoundness (worldPreserving source)

end Lanius.Extraction.Decimal.ScanExponentSemantics
