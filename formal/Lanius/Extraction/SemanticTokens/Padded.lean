import Lanius.Extraction.SemanticTokens.Pipeline
import Lanius.Extraction.Frontend.Capacity.Call

namespace Lanius.Extraction.SemanticTokens
open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.Frontend Lanius.Extraction.ParserTreeSource Collect

variable {checkedProgram : CoreSynthesis.Program.CheckedProgram artifacts}
variable {visit : CheckedVisit checkedProgram} {materializer : CheckedMaterialize visit}

/-- Compose the physical-capacity frontend with the existing collector using
the frontend's actual returned counts and selected parse. Spare source bytes
never become token input; failure branches remain visible. -/
theorem padded_frontend_then_collect {tail : List Int}
    (syntaxChecked : CheckedSyntax materializer) (linked : LinkedSyntax syntaxChecked)
    (fragment : Semantics.Capacity.Fragment.Checked checkedProgram.core allowed)
    (included : allowed syntaxChecked.source.function.id = true)
    (collector : CheckedCollect checkedProgram) (data : SyntaxData) (valid : data.Valid)
    (sourceGrammar : data.sourceCell ≠ data.grammarCell) (kindsFit : data.grammar.grammar.n_kinds ≤ 32768)
    (wellFormed : StateWellFormed before) (owned : data.PaddedOwns tail before)
    (output : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (outputFit : original.length ≤ 2147483647)
    (separate : ∀ cell ∈ frontendCells data, cell ≠ outputCell)
    (argumentsResult : ArgumentsEvaluateTo checkedProgram.core caller arguments (data.paddedValues tail.length) before) :
    ∃ stage detail : Int, ∃ count nodes words : Nat, ∃ position : Int, ∃ extracted,
      Evaluates checkedProgram.core caller (.call syntaxChecked.source.function.id arguments)
        (syntaxResult syntaxChecked.tail.finish.constructor.typeId stage detail data.raw.length count nodes words position) extracted ∧
      data.Post stage detail count nodes words position before extracted ∧ data.PaddedRawOutput tail extracted ∧
      CellEffect data.writes before extracted ∧
      (stage = 0 → CollectionContinuation checkedProgram.core collector.source.function.id data count nodes words
        outputCell original before extracted) := by
  obtain ⟨stage, detail, count, nodes, words, position, extracted, call, post, raw, effect, _⟩ :=
    syntaxChecked.padded_call_evaluates linked fragment included data valid sourceGrammar wellFormed owned argumentsResult
  have grammar := owned (data.grammarCell, data.grammarWords) (by simp [SyntaxData.buffers])
  exact ⟨stage, detail, count, nodes, words, position, extracted, call, post, raw, effect,
    fun success => collect_after_frontend collector valid kindsFit wellFormed grammar output outputFit separate post effect success⟩

end Lanius.Extraction.SemanticTokens
