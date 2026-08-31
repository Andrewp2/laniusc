import Lanius.Extraction.RawLexer.ScanOne.Calls
import Lanius.Extraction.RawLexer.Results.Semantics

namespace Lanius.Extraction.RawLexer.LexInto.Calls

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.Extraction.RawLexer

/-! The exact helper registry used by `lex_into`.

The outer loop calls only `scan_one`, the four `TokenScan` accessors, and the
three `LexResult` constructors.  Each component registry is separately tied
to the checked merged frontend; this routing layer gives the loop one total
semantic interface without inventing a substitute implementation.
-/

def callModel (source : List Compiler.Lexer.Byte) : CallModel :=
  CallModel.route (fun function => function == ScanOne.Functions.scanOneFunction.id)
    (ScanOne.Model.callModel source)
    (CallModel.route (fun function => function < 49)
      TokenScan.Semantics.callModel Results.Semantics.constructorCalls)

theorem nonScanningCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore
      (CallModel.route (fun function => function < 49)
        TokenScan.Semantics.callModel Results.Semantics.constructorCalls) :=
  Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness.route
    TokenScan.Semantics.callSoundness Results.Semantics.constructorCall_soundness

/-- The complete concrete helper registry for `lex_into`.  The `scan_one`
branch already closes over the checked lexer, number/decimal, symbol, and
token-result registries; the remaining branch contains only checked accessors
and result constructors. -/
theorem callSoundness (source : List Compiler.Lexer.Byte) :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore (callModel source) :=
  Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness.route
    (ScanOne.Calls.callSoundness source) nonScanningCall_soundness

theorem scanOne (source : List Compiler.Lexer.Byte) (world : ReadOnly.World)
    (start : Nat)
    (sourceBound : source.length ≤ 2147483646)
    (startBound : start ≤ 2147483647)
    (sourceFound :
      world.i32Slice? 0 = some (ScanOne.Model.sourceIntegers source)) :
    (callModel source).evaluate world ScanOne.Functions.scanOneFunction.id
        (ScanOne.Model.argumentValues source start) =
      .ok (ScanOne.Model.encoded (Compiler.Lexer.scanOne source start), world) := by
  simp only [callModel, CallModel.route, ScanOne.Functions.scanOneFunction]
  exact ScanOne.Model.callModel_at source world start sourceBound startBound
    sourceFound

theorem succeeded (source : List Compiler.Lexer.Byte) (world : ReadOnly.World)
    (success : Bool) (kind endOffset errorOffset : Int) :
    (callModel source).evaluate world TokenScan.Functions.succeededFunction.id
        [TokenScan.Semantics.value success kind endOffset errorOffset] =
      .ok (.boolean success, world) := by
  rfl

theorem kind (source : List Compiler.Lexer.Byte) (world : ReadOnly.World)
    (success : Bool) (kind endOffset errorOffset : Int) :
    (callModel source).evaluate world TokenScan.Functions.kindFunction.id
        [TokenScan.Semantics.value success kind endOffset errorOffset] =
      .ok (.signed .i32 kind, world) := by
  rfl

theorem endOffset (source : List Compiler.Lexer.Byte) (world : ReadOnly.World)
    (success : Bool) (kind endOffset errorOffset : Int) :
    (callModel source).evaluate world TokenScan.Functions.endOffsetFunction.id
        [TokenScan.Semantics.value success kind endOffset errorOffset] =
      .ok (.signed .i32 endOffset, world) := by
  rfl

theorem errorOffset (source : List Compiler.Lexer.Byte) (world : ReadOnly.World)
    (success : Bool) (kind endOffset errorOffset : Int) :
    (callModel source).evaluate world TokenScan.Functions.errorOffsetFunction.id
        [TokenScan.Semantics.value success kind endOffset errorOffset] =
      .ok (.signed .i32 errorOffset, world) := by
  rfl

theorem completed (source : List Compiler.Lexer.Byte) (world : ReadOnly.World)
    (tokenCount : Int) :
    (callModel source).evaluate world Results.Functions.completedFunction.id
        [.signed .i32 tokenCount] =
      .ok (Results.Semantics.value 0 tokenCount 0, world) := by
  rfl

theorem lexicalFailure (source : List Compiler.Lexer.Byte)
    (world : ReadOnly.World)
    (tokenCount errorOffset : Int) :
    (callModel source).evaluate world
        Results.Functions.lexicalFailureFunction.id
        [.signed .i32 tokenCount, .signed .i32 errorOffset] =
      .ok (Results.Semantics.value 1 tokenCount errorOffset, world) := by
  rfl

theorem outputFull (source : List Compiler.Lexer.Byte) (world : ReadOnly.World)
    (tokenCount sourceOffset : Int) :
    (callModel source).evaluate world Results.Functions.outputFullFunction.id
        [.signed .i32 tokenCount, .signed .i32 sourceOffset] =
      .ok (Results.Semantics.value 2 tokenCount sourceOffset, world) := by
  rfl

end Lanius.Extraction.RawLexer.LexInto.Calls
