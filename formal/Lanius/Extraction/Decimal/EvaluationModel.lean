import Lanius.Extraction.Decimal.Commands
import Lanius.Extraction.Decimal.BaseCalls
import Lanius.Extraction.Decimal.ConstructorCalls
import Lanius.Compiler.LexerNumbers

namespace Lanius.Extraction.Decimal.EvaluationModel

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Extraction.Decimal

def sourceIntegers (source : List Byte) : List Int :=
  DigitRunModel.sourceIntegers source

def sourceSlice (source : List Byte) : Value :=
  DigitRunModel.sourceSlice source

def environment (source : List Byte) (offset : Nat) : Env 3
  | ⟨0, _⟩ => sourceSlice source
  | ⟨1, _⟩ => .signed .i32 source.length
  | ⟨2, _⟩ => .signed .i32 offset

def arguments (source : List Byte) (offset : Nat) : List Value :=
  [sourceSlice source, .signed .i32 source.length, .signed .i32 offset]

def encoded : NumberScanResult → Value
  | .failure error =>
      Lanius.Extraction.TokenScan.Semantics.value false 0 0 error
  | .success .integer finish =>
      Lanius.Extraction.TokenScan.Semantics.value true 2 finish 0
  | .success .float finish =>
      Lanius.Extraction.TokenScan.Semantics.value true 33 finish 0
  | .success kind finish =>
      Lanius.Extraction.TokenScan.Semantics.value true kind.gpuCode finish 0

noncomputable def helperCalls (source : List Byte) : CallModel :=
  CallModel.route
    (fun function =>
      function = Functions.integerScanFunction.id ∨
      function = Functions.floatScanFunction.id ∨
      function = Functions.numberFailureFunction.id)
    ConstructorCalls.callModel (BaseCalls.callModel source)

theorem helperCalls_framePreserving (source : List Byte) :
    FunctionalView.FreshSimulation.FramePreservingCallSoundness
      verifiedFrontendCore (helperCalls source) := by
  exact FunctionalView.FreshSimulation.FramePreservingCallSoundness.route
    ConstructorCalls.framePreservingCallSoundness
    (BaseCalls.framePreservingCallSoundness source)

theorem helperCalls_worldPreserving (source : List Byte) :
    FunctionalView.FreshSimulation.WorldPreserving (helperCalls source) := by
  exact FunctionalView.FreshSimulation.WorldPreserving.route
    ConstructorCalls.worldPreserving (by
      intro beforeWorld afterWorld function values value evaluated
      exact BaseCalls.callModel_worldPreserved evaluated)

theorem helperCalls_sound (source : List Byte) :
    EffectfulStateful.CallSoundness verifiedFrontendCore (helperCalls source) :=
  (helperCalls_framePreserving source).toCallSoundness
    (helperCalls_worldPreserving source)

@[simp] theorem scanDigitRun
    (source : List Byte) (world : World) (start base : Nat)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startBound : start ≤ 2147483647)
    (baseBound : base ≤ 2147483647) :
    (helperCalls source).evaluate world
      extractedScanDigitRunFunction.id
      [sourceSlice source, .signed .i32 source.length,
        .signed .i32 start, .signed .i32 base] =
      .ok (digitScanValue (Compiler.Lexer.scanDigitRun source start base),
        world) := by
  simp only [helperCalls, CallModel.route]
  split
  · contradiction
  · simpa [sourceIntegers, sourceSlice,
      DigitRunSemantics.arguments,
      DigitRunModel.digitValue] using
      BaseCalls.scanDigitRun world source start base sourceFound sourceBound
        startBound baseBound

@[simp] theorem digitSucceeded (source : List Byte) (world : World)
    (result : DigitScanResult)
    (resultBound : match result with
      | .success offset | .failure offset => offset ≤ 2147483647) :
    (helperCalls source).evaluate world
      Lexer.Digits.digitScanSucceededFunction.id [digitScanValue result] =
      .ok (.boolean (match result with
        | .success _ => true | .failure _ => false), world) := by
  simp only [helperCalls, CallModel.route]
  split
  · contradiction
  · cases result <;> rfl

@[simp] theorem digitEnd (source : List Byte) (world : World)
    (finish : Nat) (finishBound : finish ≤ 2147483647) :
    (helperCalls source).evaluate world
      Lexer.Digits.digitScanEndOffsetFunction.id
      [digitScanValue (.success finish)] =
      .ok (.signed .i32 finish, world) := by
  simp only [helperCalls, CallModel.route]
  split
  · contradiction
  · rfl

@[simp] theorem digitError (source : List Byte) (world : World)
    (error : Nat) (errorBound : error ≤ 2147483647) :
    (helperCalls source).evaluate world
      Lexer.Digits.digitScanErrorOffsetFunction.id
      [digitScanValue (.failure error)] =
      .ok (.signed .i32 error, world) := by
  simp only [helperCalls, CallModel.route]
  split
  · contradiction
  · rfl

@[simp] theorem integerScan (source : List Byte) (world : World)
    (finish : Nat) (finishBound : finish ≤ 2147483647) :
    (helperCalls source).evaluate world Functions.integerScanFunction.id
      [.signed .i32 finish] =
      .ok (encoded (.success .integer finish), world) := by
  simp only [helperCalls, CallModel.route]
  rw [if_pos (by native_decide)]
  simpa [encoded] using ConstructorCalls.integerScan world finish finishBound

@[simp] theorem floatScan (source : List Byte) (world : World)
    (finish : Nat) (finishBound : finish ≤ 2147483647) :
    (helperCalls source).evaluate world Functions.floatScanFunction.id
      [.signed .i32 finish] =
      .ok (encoded (.success .float finish), world) := by
  simp only [helperCalls, CallModel.route]
  rw [if_pos (by native_decide)]
  simpa [encoded] using ConstructorCalls.floatScan world finish finishBound

@[simp] theorem numberFailure (source : List Byte) (world : World)
    (error : Nat) (errorBound : error ≤ 2147483647) :
    (helperCalls source).evaluate world Functions.numberFailureFunction.id
      [.signed .i32 error] =
      .ok (encoded (.failure error), world) := by
  simp only [helperCalls, CallModel.route]
  rw [if_pos (by native_decide)]
  simpa [encoded] using ConstructorCalls.numberFailure world error errorBound

noncomputable abbrev termMachine (source : List Byte) :=
  Effectful.machine verifiedFrontendCore (helperCalls source)

noncomputable abbrev commandMachine (source : List Byte) :=
  Stateful.machineWith verifiedFrontendCore
    (Effectful.evaluateOperation verifiedFrontendCore (helperCalls source))

end Lanius.Extraction.Decimal.EvaluationModel
