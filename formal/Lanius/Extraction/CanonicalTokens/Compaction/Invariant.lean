import Lanius.Extraction.CanonicalTokens.Compaction.Buffer
import Lanius.Extraction.CanonicalTokens.CanonicalizeModel

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Compiler Lanius.Compiler.Lexer CanonicalizeModel

@[simp] theorem encoded_length (tokens : List RawToken) :
    (encodeTokens tokens).length = 3 * tokens.length := by
  induction tokens with
  | nil => rfl
  | cons token rest ih => simp [encodeTokens, encodeToken] at *; omega

@[simp] theorem encoded_append (left right : List RawToken) :
    encodeTokens (left ++ right) = encodeTokens left ++ encodeTokens right := by
  simp [encodeTokens]

theorem encoded_row (tokens : List RawToken) (unused : List Int) (index : Nat) (token : RawToken)
    (selected : tokens[index]? = some token) :
    (encodeTokens tokens ++ unused)[3 * index]? = some (Int.ofNat token.kind.gpuCode) ∧
    (encodeTokens tokens ++ unused)[3 * index + 1]? = some (Int.ofNat token.start) ∧
    (encodeTokens tokens ++ unused)[3 * index + 2]? = some (Int.ofNat token.finish) := by
  induction tokens generalizing index with
  | nil => simp at selected
  | cons head rest ih =>
      cases index with
      | zero =>
          have same : head = token := by simpa using selected
          subst head
          simp [encodeTokens, encodeToken]
      | succ index =>
          have next : rest[index]? = some token := by simpa using selected
          simpa [encodeTokens, encodeToken, Nat.mul_succ, List.getElem?_cons_succ] using ih index next

/-- Logical contents throughout the first pass. `unused` is genuine caller
capacity, not additional input tokens. Only completed output rows are replaced. -/
def compactedBuffer (raw : List RawToken) (unused : List Int) (completed : List RawToken) : List Int :=
  replacePrefix (encodeTokens raw ++ unused) (encodeTokens completed)

@[simp] theorem compactedBuffer_initial (raw : List RawToken) (unused : List Int) :
    compactedBuffer raw unused [] = encodeTokens raw ++ unused := rfl

theorem compactedBuffer_length (raw completed : List RawToken) (unused : List Int)
    (notOvertaken : completed.length ≤ raw.length) :
    (compactedBuffer raw unused completed).length = 3 * raw.length + unused.length := by
  unfold compactedBuffer
  rw [replacePrefix_length]
  · simp
  · simp; omega

theorem compactedBuffer_unread (raw completed : List RawToken) (unused : List Int)
    (input offset : Nat) (notOvertaken : completed.length ≤ input) :
    (compactedBuffer raw unused completed)[3 * input + offset]? =
      (encodeTokens raw ++ unused)[3 * input + offset]? := by
  apply replacePrefix_unread
  simp
  omega

theorem compactedBuffer_emit (raw completed : List RawToken) (unused : List Int)
    (next : RawToken) (room : completed.length < raw.length) :
    writeRow (compactedBuffer raw unused completed) (3 * completed.length)
      next.kind.gpuCode next.start next.finish = compactedBuffer raw unused (completed ++ [next]) := by
  unfold compactedBuffer
  rw [encoded_append]
  have fit : (encodeTokens completed).length + 3 ≤ (encodeTokens raw ++ unused).length := by
    simp
    omega
  have pushed := replacePrefix_push_row
    (encodeTokens raw ++ unused) (encodeTokens completed) next.kind.gpuCode next.start next.finish fit
  rw [encoded_length] at pushed
  exact pushed

end Lanius.Extraction.CanonicalTokens.Compaction
