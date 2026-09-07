import Lanius.Extraction.CanonicalTokens.Compaction.Range.Mark
import Lanius.Extraction.CanonicalTokens.Compaction.Invariant

namespace Lanius.Extraction.CanonicalTokens.Compaction.Range

open Lanius.Compiler Lanius.Compiler.Lexer CanonicalizeModel

private theorem range_code (kind : TokenKind) :
    ((kind.gpuCode : Int) == 182) = decide (kind = .dotDot) := by cases kind <;> decide

private theorem assign_code (kind : TokenKind) :
    ((kind.gpuCode : Int) == 8) = decide (kind = .assign) := by cases kind <;> decide

theorem pair_specification (current next : RawToken) :
    isPair current.kind.gpuCode next.kind.gpuCode next.start current.finish = isInclusiveRangePair current next := by
  simp only [isPair, isInclusiveRangePair, range_code, assign_code]
  simp [Bool.beq_eq_decide_eq, Int.natCast_inj]

def retag (current next : RawToken) : RawToken :=
  if isInclusiveRangePair current next then { current with kind := .dotDotEqual } else current

def buffer (completed remaining : List RawToken) (unused : List Int) : List Int :=
  encodeTokens (completed ++ remaining) ++ unused

@[simp] theorem buffer_length (completed remaining : List RawToken) (unused : List Int) :
    (buffer completed remaining unused).length = 3 * (completed.length + remaining.length) + unused.length := by
  simp [buffer]
  omega

private theorem set_kind (completed : List RawToken) (current : RawToken) (rest : List RawToken)
    (unused : List Int) (kind : TokenKind) :
    (buffer completed (current :: rest) unused).set (3 * completed.length) kind.gpuCode =
      buffer completed ({ current with kind } :: rest) unused := by
  unfold buffer
  rw [encoded_append, encoded_append]
  have boundary : 3 * completed.length = (encodeTokens completed).length := (encoded_length completed).symm
  rw [boundary]
  simp [encodeTokens, encodeToken, List.append_assoc, List.set_append_right]

theorem marked_buffer (completed : List RawToken) (current next : RawToken) (rest : List RawToken)
    (unused : List Int) :
    marked (buffer completed (current :: next :: rest) unused) (3 * completed.length)
      current.kind.gpuCode next.kind.gpuCode next.start current.finish =
      buffer (completed ++ [retag current next]) (next :: rest) unused := by
  unfold marked
  rw [pair_specification]
  cases pair : isInclusiveRangePair current next with
  | false => simp [pair, retag, buffer, List.append_assoc]
  | true =>
      simp only [Bool.true_eq, if_true]
      have updated := set_kind completed current (next :: rest) unused .dotDotEqual
      simpa [retag, pair, buffer, List.append_assoc, TokenKind.gpuCode] using updated

theorem retag_specification (current next : RawToken) (rest : List RawToken) :
    retagInclusiveRanges (current :: next :: rest) = retag current next :: retagInclusiveRanges (next :: rest) := rfl

theorem retag_length (tokens : List RawToken) : (retagInclusiveRanges tokens).length = tokens.length := by
  cases tokens with
  | nil => rfl
  | cons current rest =>
      cases rest with
      | nil => rfl
      | cons next rest =>
          simpa only [retag_specification, List.length_cons] using congrArg (fun n => n + 1) (retag_length (next :: rest))
termination_by tokens.length

end Lanius.Extraction.CanonicalTokens.Compaction.Range
