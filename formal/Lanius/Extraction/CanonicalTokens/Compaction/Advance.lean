import Lanius.Extraction.CanonicalTokens.Compaction.LoopState

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler Lanius.Compiler.Lexer CanonicalizeModel

/-- A concrete iteration advances the independent specification's processed
prefix, retaining the capacity-aware invariant for the next iteration. -/
theorem advances (trivia : Trivia.Checked program triviaId)
    (kind : Kind.Checked program kindId keywordId matcher)
    (request : Request) (processed : List RawToken) (token : RawToken) (rest : List RawToken)
    (shape : request.raw = processed ++ token :: rest)
    (invariant : LoopState request processed before) :
    ∃ after, Executes program before (inputBody triviaId kindId) .next after ∧
      LoopState request (processed ++ [token]) after ∧ CellEffect request.writes before after := by
  have rawLength : request.raw.length = processed.length + (rest.length + 1) := by simp [shape]
  have prefixBound : processed.length ≤ request.raw.length := by omega
  have nextBound : (processed ++ [token]).length ≤ request.raw.length := by simp; omega
  have outputBound : (request.output processed).length ≤ processed.length := filtered_length request.source processed
  have selected : request.raw[processed.length]? = some token := by simp [shape]
  have member : token ∈ request.raw := by simp [shape]
  obtain ⟨ordered, bounded⟩ := request.spans token member
  have endpoint : token.start + (token.finish - token.start) = token.finish := by omega
  obtain ⟨kindOriginal, startOriginal, endOriginal⟩ := encoded_row request.raw request.unused processed.length token selected
  have unread (offset : Nat) : (request.buffer processed)[3 * processed.length + offset]? =
      (encodeTokens request.raw ++ request.unused)[3 * processed.length + offset]? :=
    compactedBuffer_unread request.raw (request.output processed) request.unused processed.length offset outputBound
  have kindSelected : (request.buffer processed)[3 * processed.length]? = some (Int.ofNat token.kind.gpuCode) :=
    (unread 0).trans kindOriginal
  have startSelected := (unread 1).trans startOriginal
  have endSelected : (request.buffer processed)[3 * processed.length + 2]? =
      some (Int.ofNat (token.start + (token.finish - token.start))) := by rw [endpoint]; exact (unread 2).trans endOriginal
  have bufferLength := request.buffer_length processed prefixBound
  obtain ⟨after, run, contents, inputAfter, outputAfter, effect⟩ := executes_input_body trivia kind invariant.storage
    (Int.ofNat token.kind.gpuCode) token.start (token.finish - token.start) processed.length
    (request.output processed).length request.inputCell request.outputCell
    kindSelected startSelected endSelected invariant.input invariant.output
    request.recordsOutput request.recordsInput request.inputOutput
    (by simpa [endpoint, sourceIntegers] using bounded)
    (by rw [bufferLength]; omega) (by rw [bufferLength]; omega)
  have bufferStep := filtered_records_refine request.source request.raw (request.output processed)
    request.unused token ordered (by omega)
  have afterContents : after.cellEntry? request.recordsCell = some {
      id := request.recordsCell, value := some (.array (signedI32Values (request.buffer (processed ++ [token])))) } := by
    simpa only [Request.buffer, request.output_step, bufferStep] using contents
  have inputNext : (Assertion.localPointsTo 3 request.inputCell
      (some (.signed .i32 (processed ++ [token]).length))).holds after := by simpa using inputAfter
  have outputNext : (Assertion.localPointsTo 4 request.outputCell
      (some (.signed .i32 (request.output (processed ++ [token])).length))).holds after := by
    simpa only [filtered_count_refine token _ request.source, request.output_step, List.length_append] using outputAfter
  exact ⟨after, run, invariant.advance _ prefixBound nextBound effect afterContents inputNext outputNext, effect⟩

end Lanius.Extraction.CanonicalTokens.Compaction
