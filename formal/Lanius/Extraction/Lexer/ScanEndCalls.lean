import Lanius.Extraction.Lexer.ScanEnd
import Lanius.FunctionalViewCoreEffectful

namespace Lanius.Extraction.Lexer.ScanEndCalls

open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.Extraction.Lexer.Functions

/-! Mathematical semantics for the two `ScanEnd` constructors used by the
stateful scanners.  The returned values are exactly those established by the
public constructor-view theorems in `Lexer.ScanEnd`. -/

def calls : CallModel where
  evaluate := fun world function arguments =>
    match arguments with
    | [.signed .i32 offset] =>
        if function = successfulScanFunction.id then
          .ok (ScanEnd.value true offset 0, world)
        else if function = failedScanFunction.id then
          .ok (ScanEnd.value false 0 offset, world)
        else
          .error .invalidPointer
    | _ => .error .typeMismatch

theorem successful (world : World) (offset : Int) :
    calls.evaluate world successfulScanFunction.id [.signed .i32 offset] =
      .ok (ScanEnd.value true offset 0, world) := by
  simp [calls]

theorem failed (world : World) (offset : Int) :
    calls.evaluate world failedScanFunction.id [.signed .i32 offset] =
      .ok (ScanEnd.value false 0 offset, world) := by
  have different : failedScanFunction.id ≠ successfulScanFunction.id := by
    native_decide
  simp [calls, different]

end Lanius.Extraction.Lexer.ScanEndCalls
