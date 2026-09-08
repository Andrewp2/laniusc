import Lanius.Extraction.RawLexer.LexInto.Spans
import Lanius.Extraction.CanonicalTokens.Compaction.Call
import Lanius.FunctionalViewCoreReadOnly

namespace Lanius.Extraction.RawLexer.LexInto

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler Lanius.Compiler.Lexer
open Lanius.Extraction.CanonicalTokens CanonicalizeModel Compaction

/-- The lexer buffer postcondition suffices for the checked canonicalizer:
no caller-supplied token-span or output-size validation is needed. -/
theorem canonicalize_emitted
    (checked : Compaction.CheckedSource program functionId triviaId kindId keywordId matcher)
    (request : Model.Request) (records : List Int)
    (recordsCapacity : 3 * request.capacity ≤ records.length)
    (recordsBound : records.length ≤ 2147483647)
    (before : State) (sourceCell recordsCell : CellId)
    (distinct : sourceCell ≠ recordsCell)
    (wellFormed : StateWellFormed before)
    (owned : (FunctionalView.Core.ReadOnly.World.owns
      (FunctionalView.Core.ReadOnly.World.pair sourceCell (sourceIntegers request.source)
        recordsCell (encodeTokens (Model.emittedTokens request.outcome) ++
          records.drop (3 * (Model.emittedTokens request.outcome).length)))).holds before)
    (expressions : List Expr)
    (argumentsResult : CallContracts.ArgumentsEvaluateTo program before expressions [
      .slice (.scalar (.signed .i32)) sourceCell [] 0 request.source.length,
      .slice (.scalar (.signed .i32)) recordsCell [] 0 records.length,
      .signed .i32 (Model.emittedTokens request.outcome).length] before) :
    ∃ after, Evaluates program before (.call functionId expressions)
        (.signed .i32 (canonicalizeTokens request.source
          (Model.emittedTokens request.outcome)).length) after ∧
      after.cellEntry? recordsCell = some {
        id := recordsCell, value := some (.array (signedI32Values
          (compactedBuffer (Model.emittedTokens request.outcome)
            (records.drop (3 * (Model.emittedTokens request.outcome).length))
            (canonicalizeTokens request.source (Model.emittedTokens request.outcome))))) } ∧
      CellEffect (CellSet.singleton recordsCell) before after := by
  have countBound := Model.emittedTokens_length_le_capacity request.source request.capacity
  have bufferLength : 3 * (Model.emittedTokens request.outcome).length +
      (records.drop (3 * (Model.emittedTokens request.outcome).length)).length = records.length := by
    simp only [List.length_drop]
    change (Model.emittedTokens request.outcome).length ≤ request.capacity at countBound
    omega
  apply checked.evaluates_call before sourceCell recordsCell request.source
    (Model.emittedTokens request.outcome)
    (records.drop (3 * (Model.emittedTokens request.outcome).length)) expressions wellFormed
  · exact owned _ _ FunctionalView.Core.ReadOnly.World.pair_finds_first
  · exact owned _ _ (FunctionalView.Core.ReadOnly.World.pair_finds_second (Ne.symm distinct))
  · exact distinct
  · have := request.sourceFitsI32; omega
  · rw [bufferLength]
    exact recordsBound
  · exact Model.emittedTokens_validSpans request.source request.capacity
  · simpa only [bufferLength] using argumentsResult

end Lanius.Extraction.RawLexer.LexInto
