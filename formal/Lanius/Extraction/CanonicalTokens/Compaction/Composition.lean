import Lanius.Extraction.CanonicalTokens.Compaction.InputLoop
import Lanius.Extraction.CanonicalTokens.Compaction.Range.Finish

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler Lanius.Compiler.Lexer CanonicalizeModel

/-- Compose both source passes and the return. The result is the complete
independent token-canonicalization specification, with unused capacity intact. -/
theorem executes_passes (trivia : Trivia.Checked program triviaId)
    (kind : Kind.Checked program kindId keywordId matcher) (table : Range.Table program tokens)
    (request : Request) (invariant : LoopState request [] before) :
    ∃ after, Executes program before (.sequence (inputLoop triviaId kindId) (finish tokens))
        (.returned (some (.signed .i32 (canonicalizeTokens request.source request.raw).length))) after ∧
      after.cellEntry? request.recordsCell = some {
        id := request.recordsCell, value := some (.array
          (signedI32Values (compactedBuffer request.raw request.unused (canonicalizeTokens request.source request.raw)))) } ∧
      CellEffect request.writes before after := by
  obtain ⟨filtered, firstPass, filteredInvariant, firstEffect⟩ := executes_input_loop trivia kind request
    [] request.raw before (by simp) invariant
  let tail := (encodeTokens request.raw ++ request.unused).drop (3 * (request.output request.raw).length)
  have bufferBridge : request.buffer request.raw = Range.buffer [] (request.output request.raw) tail := by
    simp [Request.buffer, compactedBuffer, replacePrefix, Range.buffer, tail]
  have rangeStorage : Storage filtered request.sourceCell request.recordsCell (sourceIntegers request.source)
      (Range.buffer [] (request.output request.raw) tail) := by
    simpa only [bufferBridge] using filteredInvariant.storage
  have countLocal := Assertion.localPointsTo_local _ _ _ _ filteredInvariant.output
  obtain ⟨after, secondPass, finalContents, secondEffect⟩ := Range.executes_finish table rangeStorage
    request.sourceDistinct.1 countLocal
  have outputLength : (request.output request.raw).length = (canonicalizeTokens request.source request.raw).length :=
    (Range.retag_length (request.output request.raw)).symm
  have finalBuffer : Range.buffer [] (retagInclusiveRanges (request.output request.raw)) tail =
      compactedBuffer request.raw request.unused (canonicalizeTokens request.source request.raw) := by
    simp [Range.buffer, compactedBuffer, replacePrefix, tail, canonicalizeTokens, Request.output, Range.retag_length]
  have framed : CellEffect request.writes filtered after := secondEffect.weaken (by
    intro cell selected
    exact Or.inl (Or.inl selected))
  refine ⟨after, ?_, ?_, firstEffect.trans framed⟩
  · simpa only [outputLength] using executesSequence firstPass secondPass
  · simpa only [finalBuffer] using finalContents

end Lanius.Extraction.CanonicalTokens.Compaction
