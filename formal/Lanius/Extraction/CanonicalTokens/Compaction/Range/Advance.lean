import Lanius.Extraction.CanonicalTokens.Compaction.Range.LoopState

namespace Lanius.Extraction.CanonicalTokens.Compaction.Range

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler Lanius.Compiler.Lexer CanonicalizeModel

theorem advances (table : Table program tokens) (request : Request)
    (completed : List RawToken) (current next : RawToken) (rest : List RawToken)
    (invariant : LoopState request completed (current :: next :: rest) before) :
    ∃ after, Executes program before (rangeBody tokens) .next after ∧
      LoopState request (completed ++ [retag current next]) (next :: rest) after ∧
      CellEffect request.writes before after := by
  have selectedCurrent : (completed ++ current :: next :: rest)[completed.length]? = some current := by simp
  have selectedNext : (completed ++ current :: next :: rest)[completed.length + 1]? = some next := by simp
  obtain ⟨currentKind, _, currentEnd⟩ := encoded_row (completed ++ current :: next :: rest)
    request.unused completed.length current selectedCurrent
  obtain ⟨nextKind, nextStart, _⟩ := encoded_row (completed ++ current :: next :: rest)
    request.unused (completed.length + 1) next selectedNext
  obtain ⟨after, run, contents, cursor, effect⟩ := executes_body table invariant.storage completed.length
    request.cursorCell current.kind.gpuCode next.kind.gpuCode next.start current.finish invariant.cursor request.distinct
    (by rw [buffer_length]; simp; omega) currentKind
    (by simpa [buffer, Nat.mul_succ, Int.ofNat_eq_natCast] using nextKind)
    (by simpa [buffer, Nat.mul_succ, Nat.add_assoc, Int.ofNat_eq_natCast] using nextStart) currentEnd
  have nextLength : (completed ++ [retag current next]).length + (next :: rest).length = request.count := by
    have length := invariant.length
    simp_all
    omega
  have afterContents : after.cellEntry? request.recordsCell = some {
      id := request.recordsCell
      value := some (.array (signedI32Values (buffer (completed ++ [retag current next]) (next :: rest) request.unused))) } := by
    simpa only [marked_buffer] using contents
  have cursorNext : (Assertion.localPointsTo 10 request.cursorCell
      (some (.signed .i32 (completed ++ [retag current next]).length))).holds after := by simpa using cursor
  exact ⟨after, run, invariant.advance _ _ nextLength effect afterContents cursorNext, effect⟩

end Lanius.Extraction.CanonicalTokens.Compaction.Range
