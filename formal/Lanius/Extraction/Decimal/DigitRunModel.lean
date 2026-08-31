import Lanius.Extraction.Decimal.DigitRunCommand
import Lanius.FunctionalViewLoop
import Lanius.FunctionalViewCoreEffectfulStateful

namespace Lanius.Extraction.Decimal.DigitRunModel

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Stateful

def sourceIntegers (source : List Byte) : List Int :=
  source.map fun byte => Int.ofNat byte.val

def sourceWorld (source : List Byte) : World :=
  World.singleton 0 (sourceIntegers source)

def sourceSlice (source : List Byte) : Value :=
  .slice i32Type 0 [] 0 source.length

def environment (source : List Byte) (start base : Nat) : Env 4
  | ⟨0, _⟩ => sourceSlice source
  | ⟨1, _⟩ => .signed .i32 source.length
  | ⟨2, _⟩ => .signed .i32 start
  | ⟨3, _⟩ => .signed .i32 base

def loopEnvironment (source : List Byte) (start base offset : Nat) : Env 5 :=
  (environment source start base).push (.signed .i32 offset)

def digitValue (result : DigitScanResult) : Value :=
  digitScanValue result

def byteOfInt (value : Int) : Byte :=
  ⟨value.toNat % 256, Nat.mod_lt _ (by omega)⟩

theorem byteOfInt_of_byte (byte : Byte) :
    byteOfInt (Int.ofNat byte.val) = byte := by
  apply Fin.ext
  simp [byteOfInt, Nat.mod_eq_of_lt byte.isLt]

def isDigitInt (byte base : Int) : Bool :=
  isDigitForBase (byteOfInt byte) base.toNat

theorem isDigitInt_of_byte (byte : Byte) (base : Nat) :
    isDigitInt (byte.val : Int) (base : Int) =
      isDigitForBase byte base := by
  change isDigitForBase (byteOfInt (byte.val : Int))
      (base : Int).toNat = _
  have decoded : byteOfInt (byte.val : Int) = byte := by
    apply Fin.ext
    simp [byteOfInt, Nat.mod_eq_of_lt byte.isLt]
  rw [decoded]
  simp

def helperCallModel : CallModel where
  evaluate := fun world function arguments =>
    if function = extractedIsDigitForBaseFunction.id then
      match arguments with
      | [.signed .i32 byte, .signed .i32 base] =>
          if 0 ≤ byte ∧ byte ≤ 255 ∧ 0 ≤ base ∧ base ≤ 2147483647 then
            .ok (.boolean (isDigitInt byte base), world)
          else .error .typeMismatch
      | _ => .error .typeMismatch
    else if function = extractedSuccessfulDigitsFunction.id then
      match arguments with
      | [.signed .i32 offset] =>
          if 0 ≤ offset ∧ offset ≤ 2147483647 then
            .ok (digitValue (.success offset.toNat), world)
          else .error .typeMismatch
      | _ => .error .typeMismatch
    else if function = extractedFailedDigitsFunction.id then
      match arguments with
      | [.signed .i32 offset] =>
          if 0 ≤ offset ∧ offset ≤ 2147483647 then
            .ok (digitValue (.failure offset.toNat), world)
          else .error .typeMismatch
      | _ => .error .typeMismatch
    else
      .error .invalidPointer

theorem helperCallModel_isDigit (world : World) (byte : Byte) (base : Nat)
    (baseBound : base ≤ 2147483647) :
    helperCallModel.evaluate world extractedIsDigitForBaseFunction.id
    [.signed .i32 byte.val, .signed .i32 base] =
      .ok (.boolean (isDigitForBase byte base), world) := by
  have byteBound : (byte.val : Int) ≤ 255 := by omega
  have baseIntBound : (base : Int) ≤ 2147483647 := by omega
  simp only [helperCallModel, if_pos, Except.ok.injEq]
  simp [byteBound, baseIntBound]
  rw [isDigitInt_of_byte byte base]

theorem helperCallModel_successful (world : World) (offset : Nat)
    (offsetBound : offset ≤ 2147483647) :
    helperCallModel.evaluate world extractedSuccessfulDigitsFunction.id
        [.signed .i32 offset] =
      .ok (digitValue (.success offset), world) := by
  have different : extractedSuccessfulDigitsFunction.id ≠
      extractedIsDigitForBaseFunction.id := by native_decide
  have offsetIntBound : (offset : Int) ≤ 2147483647 := by omega
  simp [helperCallModel, digitValue, digitScanValue, different, offsetIntBound,
    show digitScanDeclaration.id = 2 by rfl]

theorem helperCallModel_failed (world : World) (offset : Nat)
    (offsetBound : offset ≤ 2147483647) :
    helperCallModel.evaluate world extractedFailedDigitsFunction.id
        [.signed .i32 offset] =
      .ok (digitValue (.failure offset), world) := by
  have first : extractedFailedDigitsFunction.id ≠
      extractedIsDigitForBaseFunction.id := by native_decide
  have second : extractedFailedDigitsFunction.id ≠
      extractedSuccessfulDigitsFunction.id := by native_decide
  have offsetIntBound : (offset : Int) ≤ 2147483647 := by omega
  simp [helperCallModel, digitValue, digitScanValue, first, second,
    offsetIntBound,
    show digitScanDeclaration.id = 2 by rfl]

abbrev termMachine :=
  Lanius.FunctionalView.Core.Effectful.machine
    verifiedFrontendCore helperCallModel

abbrev commandMachine :=
  Lanius.FunctionalView.Core.Stateful.machineWith verifiedFrontendCore
    (Lanius.FunctionalView.Core.Effectful.evaluateOperation
      verifiedFrontendCore helperCallModel)

@[simp] theorem sourceIntegers_length :
    (sourceIntegers source).length = source.length := by
  simp [sourceIntegers]

end Lanius.Extraction.Decimal.DigitRunModel
