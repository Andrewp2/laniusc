import Lanius.Extraction.Decimal.HelperFrames

namespace Lanius.Extraction.Decimal.BaseCalls

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.FunctionalView.FreshSimulation

def digitAccessors : CallModel :=
  CallModel.route (fun function =>
      function = Lanius.Extraction.Lexer.Digits.digitScanSucceededFunction.id)
    Lanius.Extraction.Lexer.DigitAccessorContracts.digitScanSucceededCalls
    (CallModel.route (fun function =>
        function = Lanius.Extraction.Lexer.Digits.digitScanEndOffsetFunction.id)
      Lanius.Extraction.Lexer.DigitAccessorContracts.digitScanEndOffsetCalls Lanius.Extraction.Lexer.DigitAccessorContracts.digitScanErrorOffsetCalls)

noncomputable def digitOperations (source : List Byte) : CallModel :=
  CallModel.route (fun function =>
      function = extractedIsDigitForBaseFunction.id ∨
      function = extractedSuccessfulDigitsFunction.id ∨
      function = extractedFailedDigitsFunction.id)
    Lanius.Extraction.Decimal.DigitRunModel.helperCallModel
    (CallModel.route (fun function =>
        function = Lanius.Extraction.Lexer.Digits.digitScanSucceededFunction.id ∨
        function = Lanius.Extraction.Lexer.Digits.digitScanEndOffsetFunction.id ∨
        function = Lanius.Extraction.Lexer.Digits.digitScanErrorOffsetFunction.id)
      digitAccessors (Lanius.Extraction.Decimal.DigitRunSemantics.callModel source))

def tokenConstructors : CallModel :=
  CallModel.route (fun function =>
      function = Lanius.Extraction.TokenScan.Functions.successfulFunction.id)
    Lanius.Extraction.TokenScan.Semantics.successfulCalls Lanius.Extraction.TokenScan.Semantics.failedCalls

noncomputable def callModel (source : List Byte) : CallModel :=
  CallModel.route (fun function =>
      function = extractedIsDigitForBaseFunction.id ∨
      function = extractedSuccessfulDigitsFunction.id ∨
      function = extractedFailedDigitsFunction.id ∨
      function = Lanius.Extraction.Lexer.Digits.digitScanSucceededFunction.id ∨
      function = Lanius.Extraction.Lexer.Digits.digitScanEndOffsetFunction.id ∨
      function = Lanius.Extraction.Lexer.Digits.digitScanErrorOffsetFunction.id ∨
      function = extractedScanDigitRunFunction.id)
    (digitOperations source) tokenConstructors

theorem digitAccessors_framePreserving :
    FramePreservingCallSoundness verifiedFrontendCore digitAccessors := by
  apply FramePreservingCallSoundness.route
    Lanius.Extraction.Decimal.HelperFrames.Accessors.succeeded
  exact FramePreservingCallSoundness.route
    Lanius.Extraction.Decimal.HelperFrames.Accessors.endOffset
    Lanius.Extraction.Decimal.HelperFrames.Accessors.errorOffset

theorem digitOperations_framePreserving (source : List Byte) :
    FramePreservingCallSoundness verifiedFrontendCore
      (digitOperations source) := by
  rw [digitOperations]
  exact FramePreservingCallSoundness.route
    Lanius.Extraction.Decimal.DigitRunCalls.helperFramePreservingCallSoundness
    (FramePreservingCallSoundness.route digitAccessors_framePreserving
      (Lanius.Extraction.Decimal.DigitRunSemantics.framePreservingCallSoundness
        source))

theorem tokenConstructors_framePreserving :
    FramePreservingCallSoundness verifiedFrontendCore tokenConstructors := by
  exact FramePreservingCallSoundness.route Lanius.Extraction.Decimal.HelperFrames.TokenConstructors.successful
    Lanius.Extraction.Decimal.HelperFrames.TokenConstructors.failed

theorem framePreservingCallSoundness (source : List Byte) :
    FramePreservingCallSoundness verifiedFrontendCore (callModel source) := by
  exact FramePreservingCallSoundness.route
    (digitOperations_framePreserving source)
    tokenConstructors_framePreserving

theorem callModel_worldPreserved
    (evaluated : (callModel source).evaluate beforeWorld function values =
      .ok (value, afterWorld)) : afterWorld = beforeWorld := by
  let accessorsPreserve : WorldPreserving digitAccessors :=
    WorldPreserving.route
      (Lanius.Extraction.Decimal.HelperFrames.Accessors.worldPreserving
        _ 0)
      (WorldPreserving.route
        (Lanius.Extraction.Decimal.HelperFrames.Accessors.worldPreserving
          _ 1)
        (Lanius.Extraction.Decimal.HelperFrames.Accessors.worldPreserving
          _ 2))
  let digitsPreserve : WorldPreserving (digitOperations source) := by
    rw [digitOperations]
    exact WorldPreserving.route
      Lanius.Extraction.Decimal.DigitRunCalls.helperWorldPreserving
      (WorldPreserving.route accessorsPreserve
        (Lanius.Extraction.Decimal.DigitRunSemantics.worldPreserving source))
  let tokensPreserve : WorldPreserving tokenConstructors := by
    rw [tokenConstructors]
    exact WorldPreserving.route
      Lanius.Extraction.Decimal.HelperFrames.TokenConstructors.successfulWorldPreserving
      Lanius.Extraction.Decimal.HelperFrames.TokenConstructors.failedWorldPreserving
  exact (WorldPreserving.route digitsPreserve tokensPreserve) evaluated

theorem callSoundness (source : List Byte) :
    EffectfulStateful.CallSoundness verifiedFrontendCore (callModel source) :=
  (framePreservingCallSoundness source).toCallSoundness
    callModel_worldPreserved

@[simp] theorem scanDigitRun
    (world : ReadOnly.World) (source : List Byte) (start base : Nat)
    (sourceFound : world.i32Slice? 0 = some
      (DigitRunModel.sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startBound : start ≤ 2147483647)
    (baseBound : base ≤ 2147483647) :
    (callModel source).evaluate world extractedScanDigitRunFunction.id
      (Lanius.Extraction.Decimal.DigitRunSemantics.arguments source start base) =
      .ok (DigitRunModel.digitValue
        (Compiler.Lexer.scanDigitRun source start base), world) := by
  simp [callModel, digitOperations, CallModel.route]
  exact Lanius.Extraction.Decimal.DigitRunSemantics.callModel_scanDigitRun world source start base sourceFound
    sourceBound startBound baseBound

@[simp] theorem digitSucceeded (world : ReadOnly.World)
    (success : Bool) (endOffset errorOffset : Int) :
    (callModel source).evaluate world Lanius.Extraction.Lexer.Digits.digitScanSucceededFunction.id
      [Lanius.Extraction.Lexer.DigitAccessorContracts.resultValue success endOffset errorOffset] =
      .ok (.boolean success, world) := by
  rfl

@[simp] theorem digitEndOffset (world : ReadOnly.World)
    (success : Bool) (endOffset errorOffset : Int) :
    (callModel source).evaluate world Lanius.Extraction.Lexer.Digits.digitScanEndOffsetFunction.id
      [Lanius.Extraction.Lexer.DigitAccessorContracts.resultValue success endOffset errorOffset] =
      .ok (.signed .i32 endOffset, world) := by
  rfl

@[simp] theorem digitErrorOffset (world : ReadOnly.World)
    (success : Bool) (endOffset errorOffset : Int) :
    (callModel source).evaluate world Lanius.Extraction.Lexer.Digits.digitScanErrorOffsetFunction.id
      [Lanius.Extraction.Lexer.DigitAccessorContracts.resultValue success endOffset errorOffset] =
      .ok (.signed .i32 errorOffset, world) := by
  rfl

@[simp] theorem tokenSuccessful (world : ReadOnly.World)
    (kind endOffset : Int) :
    (callModel source).evaluate world Lanius.Extraction.TokenScan.Functions.successfulFunction.id
      [.signed .i32 kind, .signed .i32 endOffset] =
      .ok (Lanius.Extraction.TokenScan.Semantics.value true kind endOffset 0, world) := by
  rfl

@[simp] theorem tokenFailed (world : ReadOnly.World) (errorOffset : Int) :
    (callModel source).evaluate world Lanius.Extraction.TokenScan.Functions.failedFunction.id
      [.signed .i32 errorOffset] =
      .ok (Lanius.Extraction.TokenScan.Semantics.value false 0 0 errorOffset, world) := by
  rfl

end Lanius.Extraction.Decimal.BaseCalls
