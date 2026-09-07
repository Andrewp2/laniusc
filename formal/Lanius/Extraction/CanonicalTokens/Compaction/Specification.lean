import Lanius.Extraction.CanonicalTokens.Compaction.Filter
import Lanius.Extraction.CanonicalTokens.Compaction.Invariant
import Lanius.Extraction.CanonicalTokens.Kind.Specification

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Compiler Lanius.Compiler.Lexer CanonicalizeModel

theorem trivia_code (kind : TokenKind) : Trivia.result (Int.ofNat kind.gpuCode) = isTriviaKind kind := by
  cases kind <;> decide

theorem filtered_length (source : List Byte) (tokens : List RawToken) :
    (filterRetagTokens source tokens).length ≤ tokens.length := by
  induction tokens with
  | nil => exact Nat.le_refl _
  | cons token rest ih =>
      simp only [filterRetagTokens]
      cases canonicalizeToken source token <;> simp_all <;> omega

theorem filtered_append (source : List Byte) (left right : List RawToken) :
    filterRetagTokens source (left ++ right) = filterRetagTokens source left ++ filterRetagTokens source right := by
  induction left with
  | nil => rfl
  | cons token rest ih =>
      simp only [List.cons_append, filterRetagTokens]
      cases canonicalizeToken source token <;> simp [ih]

theorem filtered_records_refine (source : List Byte) (raw completed : List RawToken) (unused : List Int)
    (token : RawToken) (ordered : token.start ≤ token.finish) (room : completed.length < raw.length) :
    filteredRecords (sourceIntegers source) (compactedBuffer raw unused completed)
      (Int.ofNat token.kind.gpuCode) token.start (token.finish - token.start) completed.length =
      compactedBuffer raw unused (completed ++ (canonicalizeToken source token).toList) := by
  unfold filteredRecords
  rw [trivia_code]
  cases kept : isTriviaKind token.kind with
  | true => simp [kept, canonicalizeToken]
  | false =>
      simp only [kept, Bool.false_eq_true, if_false]
      have classified := Kind.result_canonicalKind source token
      change Kind.result (sourceIntegers source) _ _ _ = _ at classified
      rw [classified]
      have endpoint : token.start + (token.finish - token.start) = token.finish := by omega
      have endpointInt : (token.start : Int) + (token.finish - token.start : Nat) = (token.finish : Int) := by
        rw [← Int.natCast_add, endpoint]
      simp only [Int.ofNat_eq_natCast, endpointInt]
      have emitted := compactedBuffer_emit raw completed unused { token with kind := canonicalKind source token } room
      simpa [canonicalizeToken, kept] using emitted

theorem filtered_count_refine (token : RawToken) (output : Nat) (source : List Byte) :
    filteredCount (Int.ofNat token.kind.gpuCode) output = output + (canonicalizeToken source token).toList.length := by
  unfold filteredCount canonicalizeToken
  rw [trivia_code]
  cases isTriviaKind token.kind <;> simp

end Lanius.Extraction.CanonicalTokens.Compaction
