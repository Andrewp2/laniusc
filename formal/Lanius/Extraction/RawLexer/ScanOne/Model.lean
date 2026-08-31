import Lanius.Extraction.RawLexer.ScanOne.Functions
import Lanius.Extraction.TokenScan.Semantics
import Lanius.Extraction.Lexer.ScanEnd
import Lanius.Compiler.LexerStream
import Lanius.FunctionalViewCoreEffectful

namespace Lanius.Extraction.RawLexer.ScanOne.Model

set_option maxRecDepth 100000

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.Extraction
open Lanius.Extraction.RawLexer.ScanOne.Functions
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful

/-! # Logical model of one checked raw-token scan

The model is indexed by the source whose backing storage the enclosing lexer
owns.  It accepts a call only when the abstract world still contains that
exact source at the canonical source cell and the three arguments are the
canonical source slice, its length, and a nonnegative offset.  Consequently a
successful model result carries enough information for the separation proof
to execute the exact checked `scan_one` body.
-/

def sourceIntegers (source : List Byte) : List Int :=
  source.map fun byte => Int.ofNat byte.val

def sourceSlice (source : List Byte) : Value :=
  .slice (.scalar (.signed .i32)) 0 [] 0 source.length

def sourceWorld (source : List Byte) : World :=
  World.singleton 0 (sourceIntegers source)

def environment (source : List Byte) (start : Nat) : Env 3
  | ⟨0, _⟩ => sourceSlice source
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)

def encoded : OneTokenResult → Value
  | .failure errorOffset =>
      TokenScan.Semantics.value false 0 0 (Int.ofNat errorOffset)
  | .token token =>
      TokenScan.Semantics.value true (Int.ofNat token.kind.gpuCode)
        (Int.ofNat token.finish) 0

/-- The checked number scanners already return the `TokenScan` wire shape.
Keeping this conversion named avoids reopening the representation when
`scan_one` forwards their result unchanged. -/
def encodedNumber : NumberScanResult → Value
  | .failure errorOffset =>
      TokenScan.Semantics.value false 0 0 (Int.ofNat errorOffset)
  | .success kind endOffset =>
      TokenScan.Semantics.value true (Int.ofNat kind.gpuCode)
        (Int.ofNat endOffset) 0

@[simp] theorem encoded_tokenFromNumber
    (start : Nat) (result : NumberScanResult) :
    encoded (tokenFromNumber start result) = encodedNumber result := by
  cases result <;> rfl

/-- Checked quoted/comment scanners return the `ScanEnd` wire shape before
`scan_one` converts it into a token result. -/
def encodedScanEnd : ScanEnd → Value
  | .failure errorOffset =>
      Lanius.Extraction.Lexer.ScanEnd.value false 0 (Int.ofNat errorOffset)
  | .success endOffset =>
      Lanius.Extraction.Lexer.ScanEnd.value true (Int.ofNat endOffset) 0

def encodedDelimited (kind : TokenKind) : ScanEnd → Value
  | .failure errorOffset =>
      TokenScan.Semantics.value false 0 0 (Int.ofNat errorOffset)
  | .success endOffset =>
      TokenScan.Semantics.value true (Int.ofNat kind.gpuCode)
        (Int.ofNat endOffset) 0

@[simp] theorem encoded_tokenFromDelimited
    (kind : TokenKind) (start : Nat) (result : ScanEnd) :
    encoded (tokenFromDelimited kind start result) =
      encodedDelimited kind result := by
  cases result <;> rfl

@[simp] theorem sourceWorld_finds (source : List Byte) :
    (sourceWorld source).i32Slice? 0 = some (sourceIntegers source) := by
  simp [sourceWorld]

@[simp] theorem sourceIntegers_length (source : List Byte) :
    (sourceIntegers source).length = source.length := by
  simp [sourceIntegers]

theorem sourceIntegers_get
    (source : List Byte) (position : Nat) (inBounds : position < source.length) :
    (sourceIntegers source).get
        ⟨position, by simpa using inBounds⟩ =
      Int.ofNat (source.get ⟨position, inBounds⟩).val := by
  simp [sourceIntegers]

theorem sourceIntegers_getElem?_eq_map (source : List Byte) (position : Nat) :
    (sourceIntegers source)[position]? =
      source[position]?.map (fun byte => Int.ofNat byte.val) := by
  simp [sourceIntegers, List.getElem?_map]

@[simp] theorem environment_source (source : List Byte) (start : Nat) :
    environment source start ⟨0, by omega⟩ = sourceSlice source := by
  rfl

@[simp] theorem environment_length (source : List Byte) (start : Nat) :
    environment source start ⟨1, by omega⟩ =
      .signed .i32 (Int.ofNat source.length) := by
  rfl

@[simp] theorem environment_start (source : List Byte) (start : Nat) :
    environment source start ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat start) := by
  rfl

def argumentValues (source : List Byte) (start : Nat) : List Value :=
  [sourceSlice source,
    .signed .i32 (Int.ofNat source.length),
    .signed .i32 (Int.ofNat start)]

/-- Concrete source-indexed registry for checked calls of function 52. -/
def callModel (source : List Byte) : CallModel where
  evaluate := fun world function arguments =>
    if function = scanOneFunction.id then
      match arguments with
      | [.slice (.scalar (.signed .i32)) cell projections base length,
          .signed .i32 sourceLength, .signed .i32 start] =>
          if cell = 0 ∧ projections = [] ∧ base = 0 ∧
              length = source.length ∧
              sourceLength = Int.ofNat source.length ∧
              -- `match_symbol_head` forms `start + 2` in signed i32 before
              -- testing the lookahead bound, so a universally safe source
              -- reserves one value below `i32::MAX`.
              source.length ≤ 2147483646 ∧
              0 ≤ start ∧ start ≤ 2147483647 then
            if world.i32Slice? 0 = some (sourceIntegers source) then
              .ok (encoded (scanOne source start.toNat), world)
            else
              .error .invalidPointer
          else
            .error .typeMismatch
      | _ => .error .typeMismatch
    else
      .error .invalidPointer

theorem callModel_at
    (source : List Byte) (world : World) (start : Nat)
    (sourceBound : source.length ≤ 2147483646)
    (startBound : start ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    (callModel source).evaluate world scanOneFunction.id
        (argumentValues source start) =
      .ok (encoded (scanOne source start), world) := by
  have startBoundInt : (Int.ofNat start) ≤ 2147483647 := by
    exact Int.ofNat_le.mpr startBound
  have startNonnegative : (0 : Int) ≤ Int.ofNat start :=
    Int.natCast_nonneg start
  have startRoundTrip : (Int.ofNat start).toNat = start := by
    exact Int.toNat_natCast start
  simp only [callModel, argumentValues, sourceSlice]
  rw [if_pos trivial]
  rw [if_pos (by
    exact ⟨trivial, trivial, trivial, trivial, trivial, sourceBound,
      startNonnegative, startBoundInt⟩)]
  rw [if_pos sourceFound]
  rw [startRoundTrip]

theorem callModel_success
    (evaluated : (callModel source).evaluate world function arguments =
      .ok (result, afterWorld)) :
    ∃ start : Int,
      function = scanOneFunction.id ∧
      arguments = [sourceSlice source,
        .signed .i32 (Int.ofNat source.length), .signed .i32 start] ∧
      source.length ≤ 2147483646 ∧
      0 ≤ start ∧ start ≤ 2147483647 ∧
      world.i32Slice? 0 = some (sourceIntegers source) ∧
      result = encoded (scanOne source start.toNat) ∧
      afterWorld = world := by
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
              startBound⟩ := valid
          exact ⟨start, functionEq, rfl, sourceBound, nonnegative, startBound,
            sourceFound, rfl, rfl⟩
        next => contradiction
      next => contradiction
    next => contradiction
  next => contradiction

end Lanius.Extraction.RawLexer.ScanOne.Model
