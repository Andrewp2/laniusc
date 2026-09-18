import Lanius.Extraction.Decimal.DigitRunCalls
import Lanius.Extraction.FrontendProgramExtensions
import Lanius.FunctionalViewCoreCheckedSimulation

namespace Lanius.Extraction.Decimal.DigitRunSemantics

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Compiler.Lexer
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Extraction.Decimal
open Lanius.Extraction.Decimal.DigitRunModel

def arguments (source : List Byte) (start base : Nat) : List Value :=
  [sourceSlice source, .signed .i32 source.length,
    .signed .i32 start, .signed .i32 base]

noncomputable def callModel (source : List Byte) : CallModel := by
  classical
  exact { evaluate := fun world function values =>
    if world.i32Slice? 0 = some (sourceIntegers source) then
      if function = extractedScanDigitRunFunction.id then
        match values with
        | [.slice (.scalar (.signed .i32)) cell projections sliceBase length,
            .signed .i32 sourceLength, .signed .i32 start,
            .signed .i32 base] =>
            if cell = 0 ∧ projections = [] ∧ sliceBase = 0 ∧
                length = source.length ∧
                sourceLength = Int.ofNat source.length ∧
                0 ≤ start ∧ start ≤ 2147483647 ∧
                0 ≤ base ∧ base ≤ 2147483647 ∧
                source.length ≤ 2147483647 then
              .ok (digitValue
                (scanDigitRun source start.toNat base.toNat), world)
            else .error .typeMismatch
        | _ => .error .typeMismatch
      else .error .invalidPointer
    else .error .invalidPointer }

theorem callModel_scanDigitRun
    (world : ReadOnly.World) (source : List Byte) (start base : Nat)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startBound : start ≤ 2147483647)
    (baseBound : base ≤ 2147483647) :
    (callModel source).evaluate world
      extractedScanDigitRunFunction.id (arguments source start base) =
      .ok (digitValue (scanDigitRun source start base), world) := by
  simp [callModel, arguments, sourceSlice, Program.i32Type, sourceBound,
    startBound, baseBound, sourceFound]
  omega

private theorem call_success
    (evaluated : (callModel source).evaluate world function values =
      .ok (result, afterWorld)) :
    ∃ start base : Nat,
      world.i32Slice? 0 = some (sourceIntegers source) ∧
      function = extractedScanDigitRunFunction.id ∧
      values = arguments source start base ∧
      source.length ≤ 2147483647 ∧
      start ≤ 2147483647 ∧ base ≤ 2147483647 ∧
      result = digitValue (scanDigitRun source start base) ∧
      afterWorld = world := by
  simp only [callModel] at evaluated
  split at evaluated
  next sourceFound =>
    split at evaluated
    next functionEq =>
      split at evaluated
      next cell projections sliceBase length sourceLength start base =>
        split at evaluated
        next valid =>
          obtain ⟨rfl, rfl⟩ := evaluated
          let startNat := start.toNat
          let baseNat := base.toNat
          have startEq : (startNat : Int) = start := by
            simp [startNat]
            omega
          have baseEq : (baseNat : Int) = base := by
            simp [baseNat]
            omega
          refine ⟨startNat, baseNat, sourceFound, functionEq, ?_, valid.2.2.2.2.2.2.2.2.2,
            ?_, ?_, ?_, rfl⟩
          · simp [arguments, sourceSlice, valid.1, valid.2.1, valid.2.2.1,
              valid.2.2.2.1, valid.2.2.2.2.1, startEq, baseEq,
              Program.i32Type]
          · omega
          · omega
          · simp [startNat, baseNat, startEq, baseEq]
        next => contradiction
      next => contradiction
    next => contradiction
  next => contradiction

theorem verifiedFrontendCore_finds_scanDigitRun :
    verifiedFrontendCore.function? extractedScanDigitRunFunction.id =
      some extractedScanDigitRunFunction := by
  rfl

theorem scanDigitRunFunction_has_body :
    extractedScanDigitRunFunction.body =
      some Lanius.Extraction.Lexer.Digits.scanDigitRunBody := by
  rfl

theorem scanDigitRunFunction_parameters :
    extractedScanDigitRunFunction.parameters =
      [(0, .slice Program.i32Type), (1, Program.i32Type),
        (2, Program.i32Type), (3, Program.i32Type)] := by
  rfl

theorem framePreservingCallSoundness (source : List Byte) :
    FramePreservingCallSoundness verifiedFrontendCore (callModel source) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments function sourceArguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨start, base, sourceFound, rfl, rfl, sourceBound, startBound, baseBound,
      rfl, afterWorldEq⟩ := call_success evaluated
  subst afterWorld
  obtain ⟨afterEnvironment, functionalEvaluation⟩ :=
    DigitRunEvaluation.command_evaluates beforeWorld source start base sourceBound
      startBound baseBound sourceFound
  apply CheckedSimulation.callPreservesFrame
    DigitRunCalls.helperFramePreservingCallSoundness
    argumentsExecution argumentsEffect verifiedFrontendCore_finds_scanDigitRun
    (by
      rw [scanDigitRunFunction_parameters]
      simp [bindParameters, parameterBindings, environment, arguments,
        sourceSlice, List.finRange]
      rfl)
    scanDigitRunFunction_has_body functionalEvaluation (by decide +kernel)
    DigitRunCommand.toCore_exactly afterArgumentsWellFormed represented

theorem worldPreserving (source : List Byte) :
    FreshSimulation.WorldPreserving (callModel source) := by
  intro beforeWorld afterWorld function values value evaluated
  obtain ⟨start, base, sourceFound, functionEq, valuesEq, sourceBound,
      startBound, baseBound, resultEq, afterEq⟩ := call_success evaluated
  exact afterEq

theorem callSoundness (source : List Byte) :
    EffectfulStateful.CallSoundness verifiedFrontendCore (callModel source) :=
  (framePreservingCallSoundness source).toCallSoundness
    (worldPreserving source)

end Lanius.Extraction.Decimal.DigitRunSemantics
