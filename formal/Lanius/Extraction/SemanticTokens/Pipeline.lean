import Lanius.Extraction.SemanticTokens.Frontend

namespace Lanius.Extraction.SemanticTokens

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.Frontend Lanius.Extraction.ParserTreeSource Collect

def frontendCells (data : SyntaxData) : List CellId :=
  [data.sourceCell, data.rawCell, data.canonicalCell, data.kindsCell, data.grammarCell,
    data.workspaceCell, data.recordsCell, data.offsetsCell]

private theorem grammar_untouched {data : SyntaxData} (valid : data.Valid) : ¬ data.writes data.grammarCell := by
  intro changed
  rcases changed with ((raw | canonical) | (kinds | workspace)) | (records | offsets)
  · exact valid.grammarRaw raw
  · exact valid.grammarCanonical canonical
  · exact valid.grammarKinds kinds
  · exact valid.grammarWorkspace workspace
  · exact (valid.outputSeparation data.grammarCell (by simp)).1 records
  · exact (valid.outputSeparation data.grammarCell (by simp)).2 offsets

private theorem output_untouched {data : SyntaxData}
    (separate : ∀ cell ∈ frontendCells data, cell ≠ outputCell) : ¬ data.writes outputCell := by
  intro changed
  rcases changed with ((raw | canonical) | (kinds | workspace)) | (records | offsets)
  · exact separate _ (by simp [frontendCells]) raw.symm
  · exact separate _ (by simp [frontendCells]) canonical.symm
  · exact separate _ (by simp [frontendCells]) kinds.symm
  · exact separate _ (by simp [frontendCells]) workspace.symm
  · exact separate _ (by simp [frontendCells]) records.symm
  · exact separate _ (by simp [frontendCells]) offsets.symm

private theorem literal_arguments (program : Program) (state : State) (values : List Value) :
    ArgumentsEvaluateTo program state (values.map Expr.value) values state := by
  induction values with
  | nil => exact .nil _ _
  | cons value values ih => exact .cons ⟨1, rfl⟩ ih

/-- The callable continuation after extract_syntax succeeds. Argument values
use that call's returned counts, not independently supplied parser metadata. -/
def CollectionContinuation (program : Program) (functionId : FunctionId) (data : SyntaxData)
    (count nodes words : Nat) (outputCell : CellId) (original : List Int) (before extracted : State) : Prop :=
  ∃ result : FrontendResult data count nodes words extracted,
  ∃ collection : CollectionRecords data.grammar (artifactTokens data.tokens) result.parse.tree 0 0, ∃ after,
    count = (artifactTokens data.tokens).length ∧ nodes = collection.records.length ∧
    words = (ParserTreeLayout.treeFrom 0 0 result.parse.tree).words.length ∧
    Evaluates program extracted (.call functionId ((collectorValues data count nodes words outputCell original).map Expr.value))
      (.signed .i32 (if count * 2 ≤ original.length then 0 else -2)) after ∧
    after.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values
        (if count * 2 ≤ original.length then collection.assignments.flatMap Assignment.words ++ original.drop (count * 2) else original))) } ∧
    CellEffect (CellSet.singleton outputCell) extracted after ∧
    CellEffect (CellSet.union data.writes (CellSet.singleton outputCell)) before after

/-- Derive preserved grammar/output storage and all semantic collector inputs
from the frontend postcondition and write footprint. -/
theorem collect_after_frontend {checkedProgram : CoreSynthesis.Program.CheckedProgram artifacts}
    (checked : CheckedCollect checkedProgram) {data : SyntaxData} (valid : data.Valid)
    (kindsFit : data.grammar.grammar.n_kinds ≤ 32768)
    (wellFormed : StateWellFormed before) (owned : data.Owns before)
    (output : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (outputFit : original.length ≤ 2147483647)
    (separate : ∀ cell ∈ frontendCells data, cell ≠ outputCell)
    (post : data.Post stage detail count nodes words position before extracted)
    (effect : CellEffect data.writes before extracted) (success : stage = 0) :
    CollectionContinuation checkedProgram.core checked.source.function.id data count nodes words outputCell original before extracted := by
  obtain ⟨result⟩ := frontend_result valid post success
  have grammarAfter := effect.preserves_entry wellFormed owned.grammar (grammar_untouched valid)
  have outputAfter := effect.preserves_entry wellFormed output (output_untouched separate)
  have collectorSeparate : ∀ cell ∈ [data.grammarCell, data.kindsCell, data.recordsCell, data.offsetsCell], cell ≠ outputCell := by
    intro cell member
    apply separate cell
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl <;> simp [frontendCells]
  obtain ⟨collection, after, call, contents, collectorEffect⟩ := result.collect checked valid kindsFit
    effect.wellFormed grammarAfter outputAfter outputFit collectorSeparate
    (literal_arguments checkedProgram.core extracted (collectorValues data count nodes words outputCell original))
  have nodesEqual : nodes = collection.records.length := by
    have same := congrArg List.length collection.offsets
    simpa only [List.length_map, ← result.nodesEq] using same.symm
  exact ⟨result, collection, after, result.countEq, nodesEqual, result.wordsEq, call, contents, collectorEffect,
    (effect.weaken CellSet.subset_union_left).trans (collectorEffect.weaken CellSet.subset_union_right)⟩

variable {checkedProgram : CoreSynthesis.Program.CheckedProgram artifacts}
variable {visit : CheckedVisit checkedProgram} {materializer : CheckedMaterialize visit}

/-- Execute the actual frontend call, then supply an executable collector
continuation for its successful result. All frontend failures are retained;
success is tested after executing the frontend, never assumed at entry.
This composes public calls, not yet the surrounding extractor main body. -/
theorem frontend_then_collect (syntaxChecked : CheckedSyntax materializer) (linked : LinkedSyntax syntaxChecked)
    (collector : CheckedCollect checkedProgram) (data : SyntaxData) (valid : data.Valid)
    (kindsFit : data.grammar.grammar.n_kinds ≤ 32768)
    (wellFormed : StateWellFormed before) (owned : data.Owns before)
    (output : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (outputFit : original.length ≤ 2147483647)
    (separate : ∀ cell ∈ frontendCells data, cell ≠ outputCell)
    (argumentsResult : ArgumentsEvaluateTo checkedProgram.core caller arguments data.values before) :
    ∃ stage detail : Int, ∃ count nodes words : Nat, ∃ position : Int, ∃ extracted,
      Evaluates checkedProgram.core caller (.call syntaxChecked.source.function.id arguments)
        (syntaxResult syntaxChecked.tail.finish.constructor.typeId stage detail data.raw.length count nodes words position) extracted ∧
      data.Post stage detail count nodes words position before extracted ∧ data.RawOutput extracted ∧
      CellEffect data.writes before extracted ∧
      (stage = 0 → CollectionContinuation checkedProgram.core collector.source.function.id data count nodes words
        outputCell original before extracted) := by
  obtain ⟨stage, detail, count, nodes, words, position, extracted, call, post, raw, effect⟩ :=
    syntaxChecked.call_evaluates linked data valid wellFormed owned argumentsResult
  exact ⟨stage, detail, count, nodes, words, position, extracted, call, post, raw, effect,
    fun success => collect_after_frontend collector valid kindsFit wellFormed owned output outputFit separate post effect success⟩

end Lanius.Extraction.SemanticTokens
