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
    decide +kernel
  simp [calls, different]

theorem calls_success
    (evaluated : calls.evaluate world function values =
      .ok (value, afterWorld)) :
    (∃ offset, function = successfulScanFunction.id ∧
      values = [.signed .i32 offset] ∧
      value = ScanEnd.value true offset 0 ∧ afterWorld = world) ∨
    (∃ offset, function = failedScanFunction.id ∧
      values = [.signed .i32 offset] ∧
      value = ScanEnd.value false 0 offset ∧ afterWorld = world) := by
  simp only [calls] at evaluated
  split at evaluated
  next offset =>
    split at evaluated
    next successful =>
      obtain ⟨rfl, rfl⟩ := evaluated
      exact .inl ⟨offset, successful, rfl, rfl, rfl⟩
    next notSuccessful =>
      split at evaluated
      next failed =>
        obtain ⟨rfl, rfl⟩ := evaluated
        exact .inr ⟨offset, failed, rfl, rfl, rfl⟩
      next => contradiction
  next => contradiction

end Lanius.Extraction.Lexer.ScanEndCalls
