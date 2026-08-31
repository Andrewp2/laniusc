import Lanius.Extraction.Decimal.ScanExponentSemantics

namespace Lanius.Extraction.Decimal.FinishEvaluationModel

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Extraction.Decimal

noncomputable def helperCalls (source : List Byte) : CallModel :=
  CallModel.route
    (fun function => function = Functions.scanExponentFunction.id)
    (ScanExponentSemantics.callModel source)
    (EvaluationModel.helperCalls source)

theorem helperCalls_framePreserving (source : List Byte) :
    FramePreservingCallSoundness verifiedFrontendCore (helperCalls source) :=
  FramePreservingCallSoundness.route
    (ScanExponentSemantics.framePreservingCallSoundness source)
    (EvaluationModel.helperCalls_framePreserving source)

theorem helperCalls_worldPreserving (source : List Byte) :
    WorldPreserving (helperCalls source) :=
  WorldPreserving.route (ScanExponentSemantics.worldPreserving source)
    (EvaluationModel.helperCalls_worldPreserving source)

theorem helperCalls_sound (source : List Byte) :
    EffectfulStateful.CallSoundness verifiedFrontendCore (helperCalls source) :=
  (helperCalls_framePreserving source).toCallSoundness
    (helperCalls_worldPreserving source)

@[simp] theorem scanExponent
    (source : List Byte) (world : ReadOnly.World) (start : Nat)
    (sourceFound : world.i32Slice? 0 = some
      (EvaluationModel.sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    (helperCalls source).evaluate world Functions.scanExponentFunction.id
      (EvaluationModel.arguments source start) =
      .ok (EvaluationModel.encoded
        (Compiler.Lexer.scanExponent source start), world) := by
  simp only [helperCalls, CallModel.route]
  simp only [decide_true, Bool.true_eq, if_true]
  exact ScanExponentSemantics.evaluate world source start sourceFound
    sourceBound startInBounds

private theorem base
    (different : function ≠ Functions.scanExponentFunction.id)
    (evaluated : (EvaluationModel.helperCalls source).evaluate world function values =
      result) :
    (helperCalls source).evaluate world function values = result := by
  simp [helperCalls, CallModel.route, different, evaluated]

@[simp] theorem scanDigitRun
    (source : List Byte) (world : ReadOnly.World) (start radix : Nat)
    (sourceFound : world.i32Slice? 0 = some
      (EvaluationModel.sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startBound : start ≤ 2147483647)
    (radixBound : radix ≤ 2147483647) :
    (helperCalls source).evaluate world extractedScanDigitRunFunction.id
      [EvaluationModel.sourceSlice source, .signed .i32 source.length,
        .signed .i32 start, .signed .i32 radix] =
      .ok (digitScanValue (Compiler.Lexer.scanDigitRun source start radix),
        world) := by
  apply base (by native_decide)
  exact EvaluationModel.scanDigitRun source world start radix sourceFound
    sourceBound startBound radixBound

@[simp] theorem isDigit
    (source : List Byte) (world : ReadOnly.World) (byte : Byte) (radix : Nat)
    (radixBound : radix ≤ 2147483647) :
    (helperCalls source).evaluate world extractedIsDigitForBaseFunction.id
      [.signed .i32 byte.val, .signed .i32 radix] =
      .ok (.boolean (isDigitForBase byte radix), world) := by
  apply base (by native_decide)
  simp [EvaluationModel.helperCalls, BaseCalls.callModel,
    BaseCalls.digitOperations, CallModel.route]
  exact DigitRunModel.helperCallModel_isDigit world byte radix radixBound

@[simp] theorem digitSucceeded
    (source : List Byte) (world : ReadOnly.World) (result : DigitScanResult)
    (resultBound : match result with
      | .success offset | .failure offset => offset ≤ 2147483647) :
    (helperCalls source).evaluate world
      Lexer.Digits.digitScanSucceededFunction.id [digitScanValue result] =
      .ok (.boolean (match result with
        | .success _ => true | .failure _ => false), world) := by
  apply base (by native_decide)
  exact EvaluationModel.digitSucceeded source world result resultBound

@[simp] theorem digitEnd (source : List Byte) (world : ReadOnly.World)
    (finish : Nat) (finishBound : finish ≤ 2147483647) :
    (helperCalls source).evaluate world
      Lexer.Digits.digitScanEndOffsetFunction.id
      [digitScanValue (.success finish)] =
      .ok (.signed .i32 finish, world) := by
  apply base (by native_decide)
  exact EvaluationModel.digitEnd source world finish finishBound

@[simp] theorem digitError (source : List Byte) (world : ReadOnly.World)
    (error : Nat) (errorBound : error ≤ 2147483647) :
    (helperCalls source).evaluate world
      Lexer.Digits.digitScanErrorOffsetFunction.id
      [digitScanValue (.failure error)] =
      .ok (.signed .i32 error, world) := by
  apply base (by native_decide)
  exact EvaluationModel.digitError source world error errorBound

@[simp] theorem integerScan (source : List Byte) (world : ReadOnly.World)
    (finish : Nat) (finishBound : finish ≤ 2147483647) :
    (helperCalls source).evaluate world Functions.integerScanFunction.id
      [.signed .i32 finish] =
      .ok (EvaluationModel.encoded (.success .integer finish), world) := by
  apply base (by native_decide)
  exact EvaluationModel.integerScan source world finish finishBound

@[simp] theorem floatScan (source : List Byte) (world : ReadOnly.World)
    (finish : Nat) (finishBound : finish ≤ 2147483647) :
    (helperCalls source).evaluate world Functions.floatScanFunction.id
      [.signed .i32 finish] =
      .ok (EvaluationModel.encoded (.success .float finish), world) := by
  apply base (by native_decide)
  exact EvaluationModel.floatScan source world finish finishBound

@[simp] theorem numberFailure (source : List Byte) (world : ReadOnly.World)
    (error : Nat) (errorBound : error ≤ 2147483647) :
    (helperCalls source).evaluate world Functions.numberFailureFunction.id
      [.signed .i32 error] =
      .ok (EvaluationModel.encoded (.failure error), world) := by
  apply base (by native_decide)
  exact EvaluationModel.numberFailure source world error errorBound

noncomputable def operationEvaluator (source : List Byte) :
    Stateful.OperationEvaluator :=
    (Effectful.evaluateOperation verifiedFrontendCore (helperCalls source))

noncomputable abbrev termMachine (source : List Byte) :=
  Stateful.termMachine (operationEvaluator source)

noncomputable abbrev commandMachine (source : List Byte) :=
  Stateful.machineWith verifiedFrontendCore
    (operationEvaluator source)

end Lanius.Extraction.Decimal.FinishEvaluationModel
