import Lanius.Extraction.Symbol.Execution
import Lanius.Compiler.LexerSymbols

namespace Lanius.Extraction.Symbol.Model

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.Extraction.Symbol.Functions

/-! A source-indexed logical call model for checked function 45.  Successful
calls require the canonical source slice and an arbitrary world that still
contains that source at cell zero. -/

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

def logicalMatch (source : List Byte) (start : Nat) : Behavior.Match :=
  Behavior.classify
    ((sourceIntegers source)[start]?.getD (-1))
    ((sourceIntegers source)[start + 1]?.getD (-1))
    ((sourceIntegers source)[start + 2]?.getD (-1))

def encoded (source : List Byte) (start : Nat) : Value :=
  let matched := logicalMatch source start
  Semantics.value matched.kind matched.length

def callModel (source : List Byte) : CallModel where
  evaluate := fun world function arguments =>
    if function = matchSymbolHeadFunction.id then
      match arguments with
      | [.slice (.scalar (.signed .i32)) cell projections base length,
          .signed .i32 sourceLength, .signed .i32 start] =>
          if cell = 0 ∧ projections = [] ∧ base = 0 ∧
              length = source.length ∧ sourceLength = source.length ∧
              source.length ≤ 2147483646 ∧ 0 ≤ start ∧
              start.toNat < source.length then
            if world.i32Slice? 0 = some (sourceIntegers source) then
              .ok (encoded source start.toNat, world)
            else .error .invalidPointer
          else .error .typeMismatch
      | _ => .error .typeMismatch
    else .error .invalidPointer

@[simp] theorem sourceIntegers_length (source : List Byte) :
    (sourceIntegers source).length = source.length := by
  simp [sourceIntegers]

theorem sourceIntegers_get (source : List Byte) (position : Nat)
    (inBounds : position < source.length) :
    (sourceIntegers source).get ⟨position, by simpa using inBounds⟩ =
      Int.ofNat source[position].val := by
  simp [sourceIntegers]

theorem callModel_at
    (source : List Byte) (world : World) (start : Nat)
    (sourceBound : source.length ≤ 2147483646)
    (startInBounds : start < source.length)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    (callModel source).evaluate world matchSymbolHeadFunction.id
        (argumentValues source start) =
      .ok (encoded source start, world) := by
  simp [callModel, argumentValues, sourceSlice, sourceBound, startInBounds,
    sourceFound]

theorem callModel_success
    (evaluated : (callModel source).evaluate world function arguments =
      .ok (result, afterWorld)) :
    ∃ start : Int,
      function = matchSymbolHeadFunction.id ∧
      arguments = [sourceSlice source, .signed .i32 source.length,
        .signed .i32 start] ∧
      source.length ≤ 2147483646 ∧ 0 ≤ start ∧
      start.toNat < source.length ∧
      world.i32Slice? 0 = some (sourceIntegers source) ∧
      result = encoded source start.toNat ∧ afterWorld = world := by
  simp only [callModel] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next cell projections base length sourceLength start =>
      split at evaluated
      next valid =>
        split at evaluated
        next sourceFound =>
          obtain ⟨rfl, rfl⟩ := evaluated
          obtain ⟨rfl, rfl, rfl, rfl, rfl, sourceBound, nonnegative,
            startInBounds⟩ := valid
          exact ⟨start, functionEq, rfl, sourceBound, nonnegative,
            startInBounds, sourceFound, rfl, rfl⟩
        next => contradiction
      next => contradiction
    next => contradiction
  next => contradiction

theorem logicalMatch_eq_execution
    (source : List Byte) (start : Nat) (startInBounds : start < source.length) :
    encoded source start =
      Semantics.value
        (Behavior.classify
          ((sourceIntegers source).get
            ⟨start, by simpa using startInBounds⟩)
          (Execution.optionalAt (sourceIntegers source) (start + 1))
          (Execution.optionalAt (sourceIntegers source) (start + 2))).kind
        (Behavior.classify
          ((sourceIntegers source).get
            ⟨start, by simpa using startInBounds⟩)
          (Execution.optionalAt (sourceIntegers source) (start + 1))
          (Execution.optionalAt (sourceIntegers source) (start + 2))).length := by
  simp [encoded, logicalMatch, Execution.optionalAt, startInBounds]

end Lanius.Extraction.Symbol.Model
