import Lanius.Extraction.Decimal.FinishSemantics

namespace Lanius.Extraction.Decimal.ConcreteSemantics

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Extraction.Decimal

noncomputable def callModel (source : List Byte) : CallModel :=
  CallModel.route
    (fun function => function = Functions.finishDecimalFunction.id)
    (FinishSemantics.callModel source)
    (FinishEvaluationModel.helperCalls source)

theorem framePreservingCallSoundness (source : List Byte) :
    FramePreservingCallSoundness verifiedFrontendCore (callModel source) :=
  FramePreservingCallSoundness.route
    (FinishSemantics.framePreservingCallSoundness source)
    (FinishEvaluationModel.helperCalls_framePreserving source)

theorem worldPreserving (source : List Byte) :
    WorldPreserving (callModel source) :=
  WorldPreserving.route (FinishSemantics.worldPreserving source)
    (FinishEvaluationModel.helperCalls_worldPreserving source)

theorem callSoundness (source : List Byte) :
    EffectfulStateful.CallSoundness verifiedFrontendCore (callModel source) :=
  (framePreservingCallSoundness source).toCallSoundness
    (worldPreserving source)

private theorem helper
    (different : function ≠ Functions.finishDecimalFunction.id)
    (evaluated : (FinishEvaluationModel.helperCalls source).evaluate
      world function values = result) :
    (callModel source).evaluate world function values = result := by
  simp [callModel, CallModel.route, different, evaluated]

@[simp] theorem finishDecimal
    (source : List Byte) (world : ReadOnly.World) (integerEnd : Nat)
    (sourceFound : world.i32Slice? 0 = some
      (EvaluationModel.sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startBound : integerEnd ≤ source.length) :
    (callModel source).evaluate world Functions.finishDecimalFunction.id
      (EvaluationModel.arguments source integerEnd) =
      .ok (EvaluationModel.encoded
        (Compiler.Lexer.finishDecimal source integerEnd), world) := by
  simp only [callModel, CallModel.route]
  rw [if_pos (by native_decide)]
  exact FinishSemantics.evaluate world source integerEnd sourceFound
    sourceBound startBound

@[simp] theorem scanExponent
    (source : List Byte) (world : ReadOnly.World) (start : Nat)
    (sourceFound : world.i32Slice? 0 = some
      (EvaluationModel.sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    (callModel source).evaluate world Functions.scanExponentFunction.id
      (EvaluationModel.arguments source start) =
      .ok (EvaluationModel.encoded
        (Compiler.Lexer.scanExponent source start), world) := by
  apply helper (by native_decide)
  exact FinishEvaluationModel.scanExponent source world start sourceFound
    sourceBound startInBounds

@[simp] theorem scanDigitRun
    (source : List Byte) (world : ReadOnly.World) (start radix : Nat)
    (sourceFound : world.i32Slice? 0 = some
      (EvaluationModel.sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startBound : start ≤ 2147483647)
    (radixBound : radix ≤ 2147483647) :
    (callModel source).evaluate world extractedScanDigitRunFunction.id
      [EvaluationModel.sourceSlice source, .signed .i32 source.length,
        .signed .i32 start, .signed .i32 radix] =
      .ok (digitScanValue
        (Compiler.Lexer.scanDigitRun source start radix), world) := by
  apply helper (by native_decide)
  exact FinishEvaluationModel.scanDigitRun source world start radix sourceFound
    sourceBound startBound radixBound

@[simp] theorem digitSucceeded
    (source : List Byte) (world : ReadOnly.World) (result : DigitScanResult)
    (resultBound : match result with
      | .success offset | .failure offset => offset ≤ 2147483647) :
    (callModel source).evaluate world
      Lexer.Digits.digitScanSucceededFunction.id [digitScanValue result] =
      .ok (.boolean (match result with
        | .success _ => true | .failure _ => false), world) := by
  apply helper (by native_decide)
  exact FinishEvaluationModel.digitSucceeded source world result resultBound

@[simp] theorem digitEnd (source : List Byte) (world : ReadOnly.World)
    (finish : Nat) (finishBound : finish ≤ 2147483647) :
    (callModel source).evaluate world
      Lexer.Digits.digitScanEndOffsetFunction.id
      [digitScanValue (.success finish)] =
      .ok (.signed .i32 finish, world) := by
  apply helper (by native_decide)
  exact FinishEvaluationModel.digitEnd source world finish finishBound

@[simp] theorem digitError (source : List Byte) (world : ReadOnly.World)
    (error : Nat) (errorBound : error ≤ 2147483647) :
    (callModel source).evaluate world
      Lexer.Digits.digitScanErrorOffsetFunction.id
      [digitScanValue (.failure error)] =
      .ok (.signed .i32 error, world) := by
  apply helper (by native_decide)
  exact FinishEvaluationModel.digitError source world error errorBound

@[simp] theorem integerScan (source : List Byte) (world : ReadOnly.World)
    (finish : Nat) (finishBound : finish ≤ 2147483647) :
    (callModel source).evaluate world Functions.integerScanFunction.id
      [.signed .i32 finish] =
      .ok (EvaluationModel.encoded (.success .integer finish), world) := by
  apply helper (by native_decide)
  exact FinishEvaluationModel.integerScan source world finish finishBound

@[simp] theorem floatScan (source : List Byte) (world : ReadOnly.World)
    (finish : Nat) (finishBound : finish ≤ 2147483647) :
    (callModel source).evaluate world Functions.floatScanFunction.id
      [.signed .i32 finish] =
      .ok (EvaluationModel.encoded (.success .float finish), world) := by
  apply helper (by native_decide)
  exact FinishEvaluationModel.floatScan source world finish finishBound

@[simp] theorem numberFailure (source : List Byte) (world : ReadOnly.World)
    (error : Nat) (errorBound : error ≤ 2147483647) :
    (callModel source).evaluate world Functions.numberFailureFunction.id
      [.signed .i32 error] =
      .ok (EvaluationModel.encoded (.failure error), world) := by
  apply helper (by native_decide)
  exact FinishEvaluationModel.numberFailure source world error errorBound

end Lanius.Extraction.Decimal.ConcreteSemantics
