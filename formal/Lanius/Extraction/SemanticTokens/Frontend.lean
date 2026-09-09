import Lanius.Extraction.SemanticTokens.Collect.Call
import Lanius.Extraction.Frontend.Call

namespace Lanius.Extraction.SemanticTokens

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser
open Lanius.Compiler.Lexer Lanius.Extraction.Frontend Lanius.Extraction.ParserTreeSource
open Collect ParserTreeLayout
open Lanius.CallContracts

/-- Per-unit artifact tokens retain the canonical lexer's byte spans. Only
the kind representation changes from the lexer enum to its encoded number. -/
def artifactTokens (tokens : List RawToken) : List Token :=
  tokens.map (fun token => ⟨token.kind.gpuCode, ⟨0, token.start, token.finish⟩⟩)

theorem artifactTokens_kinds (tokens : List RawToken) :
    (artifactTokens tokens).map Token.kind = tokens.map (fun token => token.kind.gpuCode) := by
  simp only [artifactTokens, List.map_map, Function.comp_def]

theorem artifactTokens_words (tokens : List RawToken) :
    (artifactTokens tokens).map (Int.ofNat ∘ Token.kind) = BufferCopy.tokenKinds tokens := by
  simp only [artifactTokens, List.map_map, Function.comp_def, BufferCopy.tokenKinds]

/-- The successful frontend's selected parse and exact physical buffers,
with the original capacities retained for the collector call. -/
structure FrontendResult (data : SyntaxData) (count nodes words : Nat) (state : State) where
  parse : MaterializedParse data.grammar ((artifactTokens data.tokens).map Token.kind)
  countEq : count = (artifactTokens data.tokens).length
  nodesEq : nodes = (treeFrom 0 0 parse.tree).offsets.length
  wordsEq : words = (treeFrom 0 0 parse.tree).words.length
  tokensFit : (artifactTokens data.tokens).length * 2 ≤ 2147483647
  kinds : I32Prefix state data.kindsCell data.kinds.length ((artifactTokens data.tokens).map (Int.ofNat ∘ Token.kind))
  records : I32Prefix state data.recordsCell data.treeRecords.length (treeFrom 0 0 parse.tree).words
  offsets : I32Prefix state data.offsetsCell data.treeOffsets.length ((treeFrom 0 0 parse.tree).offsets.map Int.ofNat)

/-- Recover the collector inputs from the public frontend postcondition.
No independent token buffer, valid parse, or output-bounds premise is needed. -/
theorem frontend_result {data : SyntaxData} (valid : data.Valid)
    (post : data.Post stage detail count nodes words position before after) (success : stage = 0) :
    Nonempty (FrontendResult data count nodes words after) := by
  rcases post with early | ⟨completed, canonicalCapacity, countEq, _, storage | ⟨kindsCapacity, kinds, completion, outcome, workspace, _, parsed, _⟩⟩
  · rcases early.1.stage with failed | failed <;> omega
  · have failed := storage.2.1
    omega
  · rcases parsed with failure | ⟨root, stageEq, _, output⟩
    · have failed := failure.1
      omega
    · have zero : detail = 0 := by
        by_cases zero : detail = 0
        · exact zero
        · simp only [extractionTreeStage, if_neg zero, success] at stageEq
          contradiction
      have nodesBound : nodes ≤ data.treeOffsets.length := output.2.2.1
      have wordsBound : words ≤ data.treeRecords.length := output.2.2.2.2.1
      obtain ⟨nodesEq, wordsEq, records, offsets⟩ := output.2.2.2.2.2 zero
      let parse : MaterializedParse data.grammar ((artifactTokens data.tokens).map Token.kind) := {
        tree := root.stored.tree
        recognizes := by simpa only [artifactTokens_kinds, SyntaxData.tokens] using root.stored.recognizes
      }
      have nodesSame : nodes = (treeFrom 0 0 parse.tree).offsets.length := by
        simpa only [materializeRuntime, Nat.zero_add] using nodesEq
      have wordsSame : words = (treeFrom 0 0 parse.tree).words.length := by
        simpa only [materializeRuntime, Nat.zero_add] using wordsEq
      have tokenBound : data.tokens.length ≤ data.raw.length := by
        simpa only [SyntaxData.tokens, canonicalizeTokens, CanonicalTokens.Compaction.Range.retag_length] using
          CanonicalTokens.Compaction.filtered_length data.request.source data.raw
      refine ⟨⟨parse, by simpa only [artifactTokens, List.length_map, SyntaxData.tokens] using countEq,
        nodesSame, wordsSame, ?_, ?_, ?_, ?_⟩⟩
      · simp only [artifactTokens, List.length_map]
        have := valid.canonicalFit
        change 3 * data.raw.length ≤ data.canonical.length at canonicalCapacity
        omega
      · refine ⟨data.kinds.drop data.tokens.length, ?_, ?_⟩
        · simp only [artifactTokens, List.length_map, List.length_drop]
          change data.tokens.length ≤ data.kinds.length at kindsCapacity
          omega
        · simpa only [artifactTokens_words, SyntaxData.tokens] using kinds
      · refine ⟨data.treeRecords.drop words, ?_, ?_⟩
        · rw [← wordsSame, List.length_drop]
          omega
        · simpa only [materializeRuntime, Nat.zero_add, List.take_zero, List.nil_append, State.cellEntry?] using records
      · refine ⟨data.treeOffsets.drop nodes, ?_, ?_⟩
        · rw [List.length_map, ← nodesSame, List.length_drop]
          omega
        · simpa only [materializeRuntime, Nat.zero_add, List.take_zero, List.nil_append, State.cellEntry?] using offsets

/-- Actual collector arguments after the frontend returns its logical counts.
Input slices retain the frontend's original physical capacities. -/
def collectorValues (data : SyntaxData) (count nodes words : Nat) (outputCell : CellId) (original : List Int) : List Value :=
  argumentValues (.slice i32 data.grammarCell [] 0 data.grammarWords.length)
    (.slice i32 data.kindsCell [] 0 data.kinds.length)
    (.slice i32 data.recordsCell [] 0 data.treeRecords.length)
    (.slice i32 data.offsetsCell [] 0 data.treeOffsets.length)
    (.slice i32 outputCell [] 0 original.length) data.grammarWords.length count words nodes original.length

/-- The public collector consumes the exact selected frontend outputs. Both
sufficient and insufficient output capacity are covered, without assuming the
collector succeeds or its assignment vector passes a check. -/
theorem FrontendResult.collect {checkedProgram : CoreSynthesis.Program.CheckedProgram artifacts}
    (checked : CheckedCollect checkedProgram) {data : SyntaxData}
    (result : FrontendResult data count nodes words before) (valid : data.Valid)
    (kindsFit : data.grammar.grammar.n_kinds ≤ 32768) (wellFormed : StateWellFormed before)
    (grammar : before.cellEntry? data.grammarCell = some {
      id := data.grammarCell, value := some (.array (signedI32Values data.grammarWords)) })
    (output : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (outputFit : original.length ≤ 2147483647)
    (separate : ∀ cell ∈ [data.grammarCell, data.kindsCell, data.recordsCell, data.offsetsCell], cell ≠ outputCell)
    (argumentsResult : ArgumentsEvaluateTo checkedProgram.core caller arguments
      (collectorValues data count nodes words outputCell original) before) :
    ∃ collection : CollectionRecords data.grammar (artifactTokens data.tokens) result.parse.tree 0 0, ∃ after,
      Evaluates checkedProgram.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (if count * 2 ≤ original.length then 0 else -2)) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (if count * 2 ≤ original.length then collection.assignments.flatMap Assignment.words ++ original.drop (count * 2) else original))) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  obtain ⟨collection⟩ := selected_collection_records (artifactTokens data.tokens) result.parse kindsFit 0 0
  by_cases enough : count * 2 ≤ original.length
  · let grammarData : GrammarData := ⟨data.grammarLayout, data.grammar, data.grammarWords,
      valid.grammarEncoded, valid.grammarWellFormed, valid.wordsFit, kindsFit⟩
    let traversal : TraversalData := {
      grammar := grammarData
      tokens := artifactTokens data.tokens
      tree := result.parse.tree
      collection
      grammarCell := data.grammarCell
      kindsCell := data.kindsCell
      recordsCell := data.recordsCell
      offsetsCell := data.offsetsCell
      outputCell
      original
      capacity := by simpa only [result.countEq] using enough
      tokensFit := result.tokensFit
      wordsFit := Nat.le_trans result.records.length_le valid.treeRecordsFit
    }
    have recordCount : collection.records.length = nodes := by
      have same := congrArg List.length collection.offsets
      simpa only [List.length_map, ← result.nodesEq] using same
    let storage : CallStorage traversal before := {
      grammarCapacity := data.grammarWords.length
      kindsCapacity := data.kinds.length
      recordsCapacity := data.treeRecords.length
      offsetsCapacity := data.treeOffsets.length
      grammar := ⟨[], by simp only [List.length_nil, Nat.add_zero]; rfl,
        by simpa only [List.append_nil] using grammar⟩
      kinds := result.kinds
      records := result.records
      offsets := result.offsets
      output
    }
    have values : storage.values = collectorValues data count nodes words outputCell original := by
      simp only [CallStorage.values, collectorValues, storage, traversal, grammarData,
        ← result.countEq, ← result.wordsEq, recordCount]
    have nodeBound : collection.records.length ≤ 2147483647 := by
      have bound := result.offsets.length_le
      simp only [List.length_map, ← result.nodesEq] at bound
      rw [recordCount]
      exact Nat.le_trans bound valid.treeOffsetsFit
    obtain ⟨after, call, contents, effect⟩ := checked.call_evaluates storage wellFormed nodeBound outputFit separate
      (by simpa only [values] using argumentsResult)
    refine ⟨collection, after, ?_, ?_, effect⟩
    · simpa only [if_pos enough] using call
    · simpa only [traversal, result.countEq, if_pos (by simpa only [result.countEq] using enough)] using contents
  · have header : 16 < data.grammarWords.length := by
      have present := valid.grammarEncoded.headerPresent
      simp only [grammarHeaderWords] at present
      omega
    obtain ⟨after, call, effect⟩ := checked.short_capacity_call
      (.slice i32 data.grammarCell [] 0 data.grammarWords.length)
      (.slice i32 data.kindsCell [] 0 data.kinds.length)
      (.slice i32 data.recordsCell [] 0 data.treeRecords.length)
      (.slice i32 data.offsetsCell [] 0 data.treeOffsets.length)
      (.slice i32 outputCell [] 0 original.length) data.grammarWords.length count words nodes original.length
      wellFormed header (by simpa only [result.countEq] using result.tokensFit) outputFit (by omega) argumentsResult
    exact ⟨collection, after, by simpa only [if_neg enough] using call,
      by simpa only [if_neg enough] using effect.empty_preserves_entry wellFormed output,
      effect.weaken CellSet.empty_subset⟩

end Lanius.Extraction.SemanticTokens
