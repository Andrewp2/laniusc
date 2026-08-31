import Lanius.Extraction.Number.Functions
import Lanius.Extraction.Decimal.Dependencies
import Lanius.Compiler.LexerNumbers
import Lanius.FunctionalViewCoreEffectful

namespace Lanius.Extraction.Number.Model

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Extraction
open Lanius.Extraction.Number.Functions
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful

/-! # Logical call model for the checked number scanners

The registry accepts only the canonical read-only source slice owned by the
enclosing lexer.  Successful model calls are therefore strong enough to
recover the source and offset needed by the checked-body execution proof.
-/

def sourceIntegers (source : List Byte) : List Int :=
  source.map fun byte => Int.ofNat byte.val

def sourceSlice (source : List Byte) : Value :=
  .slice (.scalar (.signed .i32)) 0 [] 0 source.length

def environment (source : List Byte) (start : Nat) : Env 3
  | ⟨0, _⟩ => sourceSlice source
  | ⟨1, _⟩ => .signed .i32 source.length
  | ⟨2, _⟩ => .signed .i32 start

def argumentValues (source : List Byte) (start : Nat) : List Value :=
  [sourceSlice source, .signed .i32 source.length, .signed .i32 start]

@[simp] theorem sourceIntegers_length (source : List Byte) :
    (sourceIntegers source).length = source.length := by
  simp [sourceIntegers]

theorem sourceIntegers_get
    (source : List Byte) (position : Nat) (inBounds : position < source.length) :
    (sourceIntegers source).get ⟨position, by simpa using inBounds⟩ =
      Int.ofNat (source.get ⟨position, inBounds⟩).val := by
  simp [sourceIntegers]

theorem sourceIntegers_getElem?_eq_map
    (source : List Byte) (position : Nat) :
    (sourceIntegers source)[position]? =
      source[position]?.map (fun byte => Int.ofNat byte.val) := by
  simp [sourceIntegers, List.getElem?_map]

def encoded : NumberScanResult → Value
  | .failure errorOffset =>
      Decimal.Dependencies.tokenScanValue false 0 0 errorOffset
  | .success .integer endOffset =>
      Decimal.Dependencies.tokenScanValue true 2 endOffset 0
  | .success .float endOffset =>
      Decimal.Dependencies.tokenScanValue true 33 endOffset 0
  | .success kind endOffset =>
      Decimal.Dependencies.tokenScanValue true kind.gpuCode endOffset 0

def numberCalls (source : List Byte) : CallModel where
  evaluate := fun world function arguments =>
    match arguments with
    | [.slice (.scalar (.signed .i32)) cell projections base length,
        .signed .i32 sourceLength, .signed .i32 start] =>
        if cell = 0 ∧ projections = [] ∧ base = 0 ∧
            length = source.length ∧
            sourceLength = Int.ofNat source.length ∧ 0 ≤ start ∧
            source.length ≤ 2147483647 ∧ start.toNat < source.length then
          if world.i32Slice? 0 = some (sourceIntegers source) then
            if function = scanNumberFunction.id then
              .ok (encoded (scanNumber source start.toNat), world)
            else if function = scanLeadingDotNumberFunction.id then
              .ok (encoded (scanLeadingDotNumber source start.toNat), world)
            else
              .error .invalidPointer
          else
            .error .invalidPointer
        else
          .error .typeMismatch
    | _ => .error .typeMismatch

theorem numberCalls_scanNumber
    (source : List Byte) (world : World) (start : Nat)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    (numberCalls source).evaluate world scanNumberFunction.id
        (argumentValues source start) =
      .ok (encoded (scanNumber source start), world) := by
  simp [numberCalls, argumentValues, sourceSlice, sourceFound, sourceBound,
    startInBounds]

theorem numberCalls_scanLeadingDotNumber
    (source : List Byte) (world : World) (start : Nat)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    (numberCalls source).evaluate world scanLeadingDotNumberFunction.id
        (argumentValues source start) =
      .ok (encoded (scanLeadingDotNumber source start), world) := by
  have distinct : scanLeadingDotNumberFunction.id ≠ scanNumberFunction.id := by
    native_decide
  simp [numberCalls, argumentValues, sourceSlice, sourceFound, sourceBound,
    startInBounds, distinct]

theorem numberCalls_success
    (evaluated : (numberCalls source).evaluate world function arguments =
      .ok (result, afterWorld)) :
    ∃ start : Int,
      arguments = [sourceSlice source, .signed .i32 source.length,
        .signed .i32 start] ∧
      0 ≤ start ∧
      source.length ≤ 2147483647 ∧ start.toNat < source.length ∧
      world.i32Slice? 0 = some (sourceIntegers source) ∧
      ((function = scanNumberFunction.id ∧
          result = encoded (scanNumber source start.toNat)) ∨
        (function = scanLeadingDotNumberFunction.id ∧
          result = encoded (scanLeadingDotNumber source start.toNat))) ∧
      afterWorld = world := by
  simp only [numberCalls] at evaluated
  split at evaluated
  next cell projections base length sourceLength start =>
    split at evaluated
    next valid =>
      split at evaluated
      next sourceFound =>
        split at evaluated
        next numberEq =>
          obtain ⟨rfl, rfl⟩ := evaluated
          obtain ⟨rfl, rfl, rfl, rfl, rfl, nonnegative, sourceBound,
            startInBounds⟩ := valid
          exact ⟨start, rfl, nonnegative, sourceBound, startInBounds, sourceFound,
            Or.inl ⟨numberEq, rfl⟩, rfl⟩
        next notNumber =>
          split at evaluated
          next leadingEq =>
            obtain ⟨rfl, rfl⟩ := evaluated
            obtain ⟨rfl, rfl, rfl, rfl, rfl, nonnegative, sourceBound,
              startInBounds⟩ := valid
            exact ⟨start, rfl, nonnegative, sourceBound, startInBounds, sourceFound,
              Or.inr ⟨leadingEq, rfl⟩, rfl⟩
          next => contradiction
      next => contradiction
    next => contradiction
  next => contradiction

end Lanius.Extraction.Number.Model
