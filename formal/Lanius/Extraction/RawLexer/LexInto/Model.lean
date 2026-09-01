import Lanius.Compiler.LexerStream
import Lanius.Core
import Lanius.ExecutionRules

namespace Lanius.Extraction.RawLexer.LexInto.Model

open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.Semantics

/-! # Capacity-aware logical model of `raw_lexer.lani::lex_into`

`lexRaw` specifies the unbounded token stream.  `limitResult` applies the
caller's record capacity after scanning each next token, exactly matching the
source function's ordering: a lexical error wins over a simultaneous full
output buffer because `scan_one` is checked before capacity.
-/

inductive Outcome where
  | completed (tokens : List RawToken)
  | lexicalFailure (accepted : List RawToken) (errorOffset : Nat)
  | outputFull (accepted : List RawToken) (sourceOffset : Nat)
  | impossibleFuelExhaustion (accepted : List RawToken) (sourceOffset : Nat)
deriving DecidableEq, Repr

def firstUnwrittenOffset (tokens : List RawToken) (capacity : Nat) : Nat :=
  match tokens.drop capacity with
  | token :: _ => token.start
  | [] => 0

def limitAccepted (capacity : Nat) (tokens : List RawToken)
    (whenFits : List RawToken → Outcome) : Outcome :=
  if tokens.length ≤ capacity then
    whenFits tokens
  else
    .outputFull (tokens.take capacity)
      (firstUnwrittenOffset tokens capacity)

def limitResult (capacity : Nat) : RawLexResult → Outcome
  | .success tokens => limitAccepted capacity tokens .completed
  | .failure accepted errorOffset =>
      limitAccepted capacity accepted
        (fun tokens => .lexicalFailure tokens errorOffset)
  | .fuelExhausted accepted sourceOffset =>
      .impossibleFuelExhaustion accepted sourceOffset

def lexInto (source : List Byte) (capacity : Nat) : Outcome :=
  limitResult capacity (lexRaw source)

/-- Prefix an already accepted token sequence onto the rest of a logical lexer
result.  This is the bridge between the tail-recursive checked loop and the
cons-recursive unbounded lexer specification. -/
def prefixResult (accepted : List RawToken) : RawLexResult → RawLexResult
  | .success tokens => .success (accepted ++ tokens)
  | .failure tokens errorOffset =>
      .failure (accepted ++ tokens) errorOffset
  | .fuelExhausted tokens sourceOffset =>
      .fuelExhausted (accepted ++ tokens) sourceOffset

@[simp] theorem prefixResult_nil (result : RawLexResult) :
    prefixResult [] result = result := by
  cases result <;> rfl

theorem scanOne_token_start
    {source : List Byte} {offset : Nat} {token : RawToken}
    (scanned : scanOne source offset = .token token) :
    token.start = offset := by
  exact Lanius.Compiler.Lexer.scanOne_token_start scanned

def emittedTokens : Outcome → List RawToken
  | .completed tokens
  | .lexicalFailure tokens _
  | .outputFull tokens _
  | .impossibleFuelExhaustion tokens _ => tokens

def encodeToken (token : RawToken) : List Int :=
  [Int.ofNat token.kind.gpuCode,
    Int.ofNat token.start,
    Int.ofNat token.finish]

def encodedRecords (outcome : Outcome) : List Int :=
  (emittedTokens outcome).flatMap encodeToken

/-- The three physical stores performed by one successful loop iteration. -/
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
  | token :: tokens =>
      writeTokens (writeToken records tokenIndex token) (tokenIndex + 1) tokens

/-- Executable state carried by the checked `lex_into` loop.  This is not a
second lexer: every step delegates to the logical `scanOne` model above and
only adds the source function's capacity check and three record writes. -/
structure RunState where
  outcome : Outcome
  records : List Int
  offset : Nat
  tokenCount : Nat
deriving DecidableEq, Repr

/-- Inputs on which the checked `i32` offsets and record indices agree with
their mathematical natural-number model.  Public execution theorems consume a
`Request`, so unsupported sizes cannot accidentally receive a successful
logical contract. -/
structure Request where
  source : List Byte
  capacity : Nat
  /-- The checked symbol matcher forms `start + 2` before testing the optional
  third byte, so the source domain stops one below signed-i32 maximum. -/
  sourceFitsI32 : source.length ≤ 2147483646
  recordsFitI32 : 3 * capacity ≤ 2147483647

def Request.outcome (request : Request) : Outcome :=
  lexInto request.source request.capacity

def runFromFuel (source : List Byte) (capacity : Nat) :
    Nat → Nat → Nat → List RawToken → List Int → RunState
  | 0, offset, tokenCount, accepted, records =>
      ⟨.impossibleFuelExhaustion accepted offset, records, offset, tokenCount⟩
  | fuel + 1, offset, tokenCount, accepted, records =>
      if source.length ≤ offset then
        ⟨.completed accepted, records, offset, tokenCount⟩
      else
        match scanOne source offset with
        | .failure error =>
            ⟨.lexicalFailure accepted error, records, offset, tokenCount⟩
        | .token token =>
            if capacity ≤ tokenCount then
              ⟨.outputFull accepted offset, records, offset, tokenCount⟩
            else
              runFromFuel source capacity fuel token.finish (tokenCount + 1)
                (accepted ++ [token]) (writeToken records tokenCount token)

def run (source : List Byte) (capacity : Nat) (records : List Int) : RunState :=
  runFromFuel source capacity (source.length + 1) 0 0 [] records

theorem prefixResult_prepend
    (accepted : List RawToken) (token : RawToken) (result : RawLexResult) :
    prefixResult accepted (result.prepend token) =
      prefixResult (accepted ++ [token]) result := by
  cases result <;> simp [prefixResult, RawLexResult.prepend, List.append_assoc]

theorem firstUnwrittenOffset_prefix_at_capacity
    (accepted tail : List RawToken) (capacity : Nat)
    (acceptedLength : accepted.length = capacity) :
    firstUnwrittenOffset (accepted ++ tail) capacity =
      match tail with
      | token :: _ => token.start
      | [] => 0 := by
  simp [firstUnwrittenOffset, acceptedLength]

/-- The executable loop returns exactly the capacity-limited result of the
unbounded logical lexer, including failure precedence and the first unwritten
token's source offset. -/
theorem runFromFuel_outcome
    (source : List Byte) (capacity fuel offset tokenCount : Nat)
    (accepted : List RawToken) (records : List Int)
    (enoughFuel : source.length - offset < fuel)
    (acceptedCount : accepted.length = tokenCount)
    (countFits : tokenCount ≤ capacity) :
    (runFromFuel source capacity fuel offset tokenCount accepted records).outcome =
      limitResult capacity
        (prefixResult accepted (lexRawFromFuel source fuel offset)) := by
  induction fuel generalizing offset tokenCount accepted records with
  | zero => omega
  | succ fuel induction =>
      rw [runFromFuel, lexRawFromFuel]
      by_cases atEnd : source.length ≤ offset
      · simp [atEnd, prefixResult, limitResult, limitAccepted, acceptedCount,
          countFits]
      · have beforeEnd : offset < source.length := by omega
        rw [if_neg atEnd]
        cases scanned : scanOne source offset with
        | failure error =>
            simp [atEnd, prefixResult, limitResult, limitAccepted,
              acceptedCount, countFits]
        | token token =>
            simp only [if_neg atEnd]
            by_cases full : capacity ≤ tokenCount
            · have exactlyFull : tokenCount = capacity := by omega
              have acceptedLength : accepted.length = capacity := by omega
              have advances := scanOne_token_advances scanned
              have tailFuel : source.length - token.finish < fuel := by omega
              have tailNotExhausted :=
                lexRawFromFuel_ne_exhausted source tailFuel
              cases tailResult : lexRawFromFuel source fuel token.finish with
              | success tokens =>
                  have noFits : ¬capacity + (tokens.length + 1) ≤ capacity :=
                    by omega
                  simp [full, RawLexResult.prepend, prefixResult,
                    limitResult, limitAccepted, acceptedLength,
                    firstUnwrittenOffset_prefix_at_capacity, noFits,
                    scanOne_token_start scanned]
              | failure tokens errorOffset =>
                  have noFits : ¬capacity + (tokens.length + 1) ≤ capacity :=
                    by omega
                  simp [full, RawLexResult.prepend, prefixResult,
                    limitResult, limitAccepted, acceptedLength,
                    firstUnwrittenOffset_prefix_at_capacity, noFits,
                    scanOne_token_start scanned]
              | fuelExhausted tokens exhaustedAt =>
                  exact False.elim (tailNotExhausted tokens exhaustedAt tailResult)
            · have room : tokenCount < capacity := by omega
              have advances := scanOne_token_advances scanned
              have tailFuel : source.length - token.finish < fuel := by omega
              have nextAcceptedCount :
                  (accepted ++ [token]).length = tokenCount + 1 := by
                simp [acceptedCount]
              have nextCountFits : tokenCount + 1 ≤ capacity := by omega
              have recursive := induction token.finish (tokenCount + 1)
                (accepted ++ [token])
                (writeToken records tokenCount token) tailFuel
                nextAcceptedCount nextCountFits
              rw [if_neg full, recursive, prefixResult_prepend]

theorem run_outcome (source : List Byte) (capacity : Nat) (records : List Int) :
    (run source capacity records).outcome = lexInto source capacity := by
  simpa only [run, lexInto, lexRaw, prefixResult_nil] using
    (runFromFuel_outcome source capacity (source.length + 1) 0 0 [] records
      (by simp) (by simp) (by simp))

theorem writeToken_length
    (records : List Int) (tokenIndex : Nat) (token : RawToken) :
    (writeToken records tokenIndex token).length = records.length := by
  simp [writeToken]

theorem runFromFuel_records_length
    (source : List Byte) (capacity fuel offset tokenCount : Nat)
    (accepted : List RawToken) (records : List Int) :
    (runFromFuel source capacity fuel offset tokenCount accepted records).records.length =
      records.length := by
  induction fuel generalizing offset tokenCount accepted records with
  | zero => rfl
  | succ fuel induction =>
      rw [runFromFuel]
      split
      · rfl
      · split
        · rfl
        · split
          · rfl
          · rw [induction]
            exact writeToken_length records tokenCount _

theorem run_records_length
    (source : List Byte) (capacity : Nat) (records : List Int) :
    (run source capacity records).records.length = records.length := by
  exact runFromFuel_records_length source capacity (source.length + 1) 0 0
    [] records

theorem runFromFuel_tokenCount
    (source : List Byte) (capacity fuel offset tokenCount : Nat)
    (accepted : List RawToken) (records : List Int)
    (acceptedCount : accepted.length = tokenCount) :
    (runFromFuel source capacity fuel offset tokenCount accepted records).tokenCount =
      (emittedTokens
        (runFromFuel source capacity fuel offset tokenCount accepted records).outcome).length := by
  induction fuel generalizing offset tokenCount accepted records with
  | zero => simpa [runFromFuel, emittedTokens] using acceptedCount.symm
  | succ fuel induction =>
      rw [runFromFuel]
      split
      · simpa [emittedTokens] using acceptedCount.symm
      · split
        · simpa [emittedTokens] using acceptedCount.symm
        · split
          · simpa [emittedTokens] using acceptedCount.symm
          · apply induction
            simp [acceptedCount]

theorem run_tokenCount
    (source : List Byte) (capacity : Nat) (records : List Int) :
    (run source capacity records).tokenCount =
      (emittedTokens (run source capacity records).outcome).length := by
  exact runFromFuel_tokenCount source capacity (source.length + 1) 0 0 []
    records (by simp)

theorem runFromFuel_emitted_prefix
    (source : List Byte) (capacity fuel offset tokenCount : Nat)
    (accepted : List RawToken) (records : List Int) :
    ∃ tail,
      emittedTokens
          (runFromFuel source capacity fuel offset tokenCount accepted records).outcome =
        accepted ++ tail := by
  induction fuel generalizing offset tokenCount accepted records with
  | zero => exact ⟨[], by simp [runFromFuel, emittedTokens]⟩
  | succ fuel induction =>
      rw [runFromFuel]
      split
      · exact ⟨[], by simp [emittedTokens]⟩
      · split
        · exact ⟨[], by simp [emittedTokens]⟩
        · split
          · exact ⟨[], by simp [emittedTokens]⟩
          · rename_i atEnd scan token scanned room
            obtain ⟨tail, tailEq⟩ := induction token.finish (tokenCount + 1)
              (accepted ++ [token]) (writeToken records tokenCount token)
            exact ⟨token :: tail,
              by simpa [List.append_assoc] using tailEq⟩

theorem runFromFuel_records
    (source : List Byte) (capacity fuel offset tokenCount : Nat)
    (accepted : List RawToken) (records : List Int)
    (acceptedCount : accepted.length = tokenCount) :
    (runFromFuel source capacity fuel offset tokenCount accepted records).records =
      writeTokens records tokenCount
        ((emittedTokens
          (runFromFuel source capacity fuel offset tokenCount accepted records).outcome).drop
            tokenCount) := by
  induction fuel generalizing offset tokenCount accepted records with
  | zero =>
      have dropped : accepted.drop tokenCount = [] := by
        rw [← acceptedCount]
        exact List.drop_length
      simp [runFromFuel, emittedTokens, writeTokens, dropped]
  | succ fuel induction =>
      rw [runFromFuel]
      split
      · have dropped : accepted.drop tokenCount = [] := by
          rw [← acceptedCount]
          exact List.drop_length
        simp [emittedTokens, writeTokens, dropped]
      · split
        · have dropped : accepted.drop tokenCount = [] := by
            rw [← acceptedCount]
            exact List.drop_length
          simp [emittedTokens, writeTokens, dropped]
        · split
          · have dropped : accepted.drop tokenCount = [] := by
              rw [← acceptedCount]
              exact List.drop_length
            simp [emittedTokens, writeTokens, dropped]
          · rename_i atEnd scan token scanned room
            have nextAcceptedCount :
                (accepted ++ [token]).length = tokenCount + 1 := by
              simp [acceptedCount]
            have recursive := induction token.finish (tokenCount + 1)
              (accepted ++ [token]) (writeToken records tokenCount token)
              nextAcceptedCount
            rw [recursive]
            obtain ⟨tail, emittedEq⟩ := runFromFuel_emitted_prefix source
              capacity fuel token.finish (tokenCount + 1)
              (accepted ++ [token]) (writeToken records tokenCount token)
            rw [emittedEq]
            simp only [List.append_assoc, List.singleton_append]
            have droppedNext :
                (accepted ++ token :: tail).drop (tokenCount + 1) = tail := by
              rw [← acceptedCount]
              simp
            have droppedCurrent :
                (accepted ++ token :: tail).drop tokenCount = token :: tail := by
              rw [← acceptedCount]
              simp
            rw [droppedNext]
            rw [droppedCurrent]
            rfl

theorem run_records (source : List Byte) (capacity : Nat) (records : List Int) :
    (run source capacity records).records =
      writeTokens records 0 (emittedTokens (lexInto source capacity)) := by
  have physical := runFromFuel_records source capacity (source.length + 1) 0 0
    [] records (by simp)
  change (run source capacity records).records =
    writeTokens records 0
      ((emittedTokens (run source capacity records).outcome).drop 0) at physical
  rw [run_outcome] at physical
  simpa using physical

theorem writeToken_indices_in_bounds
    {records : List Int} {capacity tokenIndex : Nat}
    (length : records.length = 3 * capacity)
    (available : tokenIndex < capacity) :
    3 * tokenIndex < records.length ∧
      3 * tokenIndex + 1 < records.length ∧
      3 * tokenIndex + 2 < records.length := by
  rw [length]
  omega

def resultValue : Outcome → Lanius.Core.Value
  | .completed tokens =>
      .structure 4 [.signed .i32 0, .signed .i32 (Int.ofNat tokens.length),
        .signed .i32 0]
  | .lexicalFailure tokens errorOffset =>
      .structure 4 [.signed .i32 1, .signed .i32 (Int.ofNat tokens.length),
        .signed .i32 (Int.ofNat errorOffset)]
  | .outputFull tokens sourceOffset =>
      .structure 4 [.signed .i32 2, .signed .i32 (Int.ofNat tokens.length),
        .signed .i32 (Int.ofNat sourceOffset)]
  | .impossibleFuelExhaustion tokens sourceOffset =>
      .structure 4 [.signed .i32 2, .signed .i32 (Int.ofNat tokens.length),
        .signed .i32 (Int.ofNat sourceOffset)]

theorem lexInto_ne_impossibleFuelExhaustion
    (source : List Byte) (capacity : Nat) :
    ∀ tokens offset,
      lexInto source capacity ≠ .impossibleFuelExhaustion tokens offset := by
  intro tokens offset impossible
  unfold lexInto limitResult at impossible
  cases raw : lexRaw source with
  | success rawTokens =>
      simp only [raw, limitAccepted] at impossible
      split at impossible <;> contradiction
  | failure accepted errorOffset =>
      simp only [raw, limitAccepted] at impossible
      split at impossible <;> contradiction
  | fuelExhausted accepted sourceOffset =>
      exact (lexRaw_ne_exhausted source accepted sourceOffset raw)

theorem emittedTokens_length_le_capacity
    (source : List Byte) (capacity : Nat) :
    (emittedTokens (lexInto source capacity)).length ≤ capacity := by
  unfold lexInto
  cases raw : lexRaw source with
  | success tokens =>
      simp only [limitResult, limitAccepted]
      split
      · assumption
      · simpa [emittedTokens] using Nat.min_le_left capacity tokens.length
  | failure accepted errorOffset =>
      simp only [limitResult, limitAccepted]
      split
      · assumption
      · simpa [emittedTokens] using Nat.min_le_left capacity accepted.length
  | fuelExhausted accepted sourceOffset =>
      exact False.elim (lexRaw_ne_exhausted source accepted sourceOffset raw)

theorem encodedRecords_length
    (outcome : Outcome) :
    (encodedRecords outcome).length = 3 * (emittedTokens outcome).length := by
  unfold encodedRecords
  induction emittedTokens outcome with
  | nil => simp
  | cons token tokens induction =>
      simp [encodeToken, induction]
      omega

theorem encodedRecords_length_le
    (source : List Byte) (capacity : Nat) :
    (encodedRecords (lexInto source capacity)).length ≤ 3 * capacity := by
  rw [encodedRecords_length]
  exact Nat.mul_le_mul_left 3
    (emittedTokens_length_le_capacity source capacity)

theorem successful_unbounded_stream_preserved
    {source : List Byte} {tokens : List RawToken} {capacity : Nat}
    (raw : lexRaw source = .success tokens)
    (fits : tokens.length ≤ capacity) :
    lexInto source capacity = .completed tokens := by
  simp [lexInto, raw, limitResult, limitAccepted, fits]

theorem failed_unbounded_stream_preserved
    {source : List Byte} {accepted : List RawToken} {errorOffset capacity : Nat}
    (raw : lexRaw source = .failure accepted errorOffset)
    (fits : accepted.length ≤ capacity) :
    lexInto source capacity = .lexicalFailure accepted errorOffset := by
  simp [lexInto, raw, limitResult, limitAccepted, fits]

theorem successful_stream_reports_first_unwritten
    {source : List Byte} {tokens : List RawToken} {capacity : Nat}
    (raw : lexRaw source = .success tokens)
    (full : capacity < tokens.length) :
    lexInto source capacity = .outputFull (tokens.take capacity)
      (firstUnwrittenOffset tokens capacity) := by
  simp [lexInto, raw, limitResult, limitAccepted, Nat.not_le.mpr full]

theorem failed_stream_reports_first_unwritten
    {source : List Byte} {accepted : List RawToken} {errorOffset capacity : Nat}
    (raw : lexRaw source = .failure accepted errorOffset)
    (full : capacity < accepted.length) :
    lexInto source capacity = .outputFull (accepted.take capacity)
      (firstUnwrittenOffset accepted capacity) := by
  simp [lexInto, raw, limitResult, limitAccepted, Nat.not_le.mpr full]

end Lanius.Extraction.RawLexer.LexInto.Model
