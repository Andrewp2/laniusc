import Lanius.Compiler.LexerCanonical
import Lanius.ExecutionRules

namespace Lanius.Extraction.CanonicalTokens.CanonicalizeModel

open Lanius
open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.Semantics

/-! # Logical in-place canonicalization model

The checked function receives a flat array of `{kind, start, exclusive_end}`
rows.  Its observable result is the canonical token count and a rewritten
prefix; storage after that prefix is caller capacity and remains unchanged.
This model deliberately reuses `Lexer.canonicalizeTokens`, the independent
language-level lexer specification.
-/

def sourceIntegers (source : List Byte) : List Int :=
  source.map fun byte => Int.ofNat byte.val

def encodeToken (token : RawToken) : List Int :=
  [Int.ofNat token.kind.gpuCode, Int.ofNat token.start,
    Int.ofNat token.finish]

def encodeTokens (tokens : List RawToken) : List Int :=
  tokens.flatMap encodeToken

def writeToken (records : List Int) (tokenIndex : Nat)
    (token : RawToken) : List Int :=
  let row := 3 * tokenIndex
  setI32Value
    (setI32Value
      (setI32Value records row (Int.ofNat token.kind.gpuCode))
      (row + 1) (Int.ofNat token.start))
    (row + 2) (Int.ofNat token.finish)

def writeTokens (records : List Int) (tokenIndex : Nat) :
    List RawToken → List Int
  | [] => records
  | token :: rest =>
      writeTokens (writeToken records tokenIndex token) (tokenIndex + 1) rest

def outputTokens (source : List Byte) (raw : List RawToken) : List RawToken :=
  canonicalizeTokens source raw

def outputCount (source : List Byte) (raw : List RawToken) : Nat :=
  (outputTokens source raw).length

def outputRecords (source : List Byte) (raw : List RawToken)
    (records : List Int) : List Int :=
  writeTokens records 0 (outputTokens source raw)

@[simp] theorem writeToken_length (records : List Int) (tokenIndex : Nat)
    (token : RawToken) :
    (writeToken records tokenIndex token).length = records.length := by
  simp [writeToken]

@[simp] theorem writeTokens_length (records : List Int) (tokenIndex : Nat)
    (tokens : List RawToken) :
    (writeTokens records tokenIndex tokens).length = records.length := by
  induction tokens generalizing records tokenIndex with
  | nil => rfl
  | cons token rest induction =>
      simp [writeTokens, induction]

@[simp] theorem outputRecords_length (source : List Byte)
    (raw : List RawToken) (records : List Int) :
    (outputRecords source raw records).length = records.length := by
  simp [outputRecords]

theorem output_has_no_trivia (source : List Byte) (raw : List RawToken) :
    ∀ token, token ∈ outputTokens source raw →
      isTriviaKind token.kind = false := by
  exact canonicalizeTokens_contains_no_trivia source raw

/-- Inputs for which all physical `i32` indices in the checked source agree
with the mathematical natural-number model. -/
structure Request where
  source : List Byte
  raw : List RawToken
  records : List Int
  /-- The mutable storage really is the flat `{kind, start, finish}` encoding
  of `raw`.  Without this relation, `raw` would be disconnected ghost data and
  an execution theorem could not honestly refine `canonicalizeTokens`. -/
  recordsEncodeRaw : records = encodeTokens raw
  sourceFitsI32 : source.length ≤ 2147483647
  recordsLength : records.length = 3 * raw.length
  recordsFitI32 : records.length ≤ 2147483647
  spansOrdered : ∀ token, token ∈ raw → token.start ≤ token.finish
  spansInBounds : ∀ token, token ∈ raw → token.finish ≤ source.length

def Request.resultCount (request : Request) : Nat :=
  outputCount request.source request.raw

def Request.resultRecords (request : Request) : List Int :=
  outputRecords request.source request.raw request.records

@[simp] theorem Request.resultRecords_length (request : Request) :
    request.resultRecords.length = request.records.length := by
  simp [Request.resultRecords]

end Lanius.Extraction.CanonicalTokens.CanonicalizeModel
