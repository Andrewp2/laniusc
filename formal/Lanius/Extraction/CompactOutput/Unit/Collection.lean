import Lanius.Extraction.CompactOutput.Unit.Inputs
import Lanius.Extraction.SemanticTokens.Collect.Call

namespace Lanius.Extraction.SemanticTokens

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser ParserTreeLayout CompactOutput

mutual
  theorem tree_visits_productions
      (recognized : ParseTreeRecognizesSymbol grammar tokens tree symbol start finish)
      (nodeBase wordBase : Nat) :
      ∀ record ∈ (treeVisits grammar tokens nodeBase wordBase start tree).1,
        record.production < grammar.productionCount := by
    cases recognized with
    | terminal _ _ _ => simp [treeVisits]
    | nonterminal nonterminalBound productionBound lhs children =>
      intro record member
      rcases List.mem_append.mp member with earlier | last
      · exact forest_visits_productions children nodeBase (wordBase + 4 + _ * 3) record earlier
      · have same := List.mem_singleton.mp last
        subst record
        exact productionBound

  theorem forest_visits_productions
      (recognized : ParseTreesRecognizeSequence grammar tokens trees symbols start finish)
      (nodeBase wordBase : Nat) :
      ∀ record ∈ (forestVisits grammar tokens nodeBase wordBase start trees).1,
        record.production < grammar.productionCount := by
    cases recognized with
    | empty => simp [forestVisits]
    | @cons tree symbol start middle trees symbols finish head tail =>
      obtain ⟨_, _, _, _, firstFinish, _, _, _⟩ := tree_visits_sound head nodeBase wordBase
      intro record member
      dsimp only [forestVisits] at member
      rw [firstFinish] at member
      rcases List.mem_append.mp member with earlier | later
      · exact tree_visits_productions head nodeBase wordBase record earlier
      · exact forest_visits_productions tail
          (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
          (wordBase + (treeFrom nodeBase wordBase tree).words.length) record later
end

theorem CollectionRecords.assignment_fields (data : CollectionRecords grammar tokens tree nodeBase wordBase)
    (kindsFit : grammar.grammar.n_kinds ≤ 32768) :
    ∀ assignment ∈ data.assignments, assignment.first ≤ 2147483647 ∧
      -1 ≤ Assignments.secondWord assignment ∧ Assignments.secondWord assignment < 2147483647 := by
  intro assignment member
  obtain ⟨index, bound, found⟩ := List.mem_iff_getElem.mp member
  have tokenBound : index < tokens.length := by rw [← data.lengthEq]; exact bound
  obtain ⟨selected, selectedAt, valid⟩ := data.validAssignments index tokens[index]
    (List.getElem?_eq_getElem tokenBound)
  have same : selected = assignment := by
    rw [List.getElem?_eq_getElem bound, found] at selectedAt
    exact (Option.some.inj selectedAt).symm
  exact Assignments.field_bounds assignment (same ▸ valid) kindsFit

/-- The exact array written by collect supplies the semantic emitter input;
its length and numeric field bounds follow from collection validity. -/
def CollectionRecords.semanticInput {original : List Int} (data : CollectionRecords grammar tokens tree nodeBase wordBase)
    (kindsFit : grammar.grammar.n_kinds ≤ 32768)
    (enough : tokens.length * 2 ≤ original.length) (lengthFit : original.length ≤ 2147483647)
    (backing : state.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values
      (data.assignments.flatMap Assignment.words ++ original.drop (tokens.length * 2)))) })
    (inputRead : state.local? 10 = some (.slice i32 cell [] 0 original.length))
    (lengthRead : state.local? 11 = some (.signed .i32 original.length))
    (distinct : outputCell ≠ cell) : Unit.SemanticInput state tokens.length outputCell where
  assignments := data.assignments
  cell := cell
  capacity := original.length
  inputLength := original.length
  input := ⟨original.drop (tokens.length * 2), by rw [data.words_length, List.length_drop]; omega, backing⟩
  inputRead := inputRead
  lengthRead := lengthRead
  countEqual := data.lengthEq
  distinct := distinct
  inputRoom := by rw [data.lengthEq]; omega
  lengthFit := lengthFit
  fields := data.assignment_fields kindsFit

theorem CollectionRecords.node_fields (parse : MaterializedParse grammar (tokens.map Token.kind))
    (data : CollectionRecords grammar tokens parse.tree 0 0)
    (productionFit : grammar.productionCount ≤ 2147483647)
    (tokensFit : tokens.length * 2 ≤ 2147483647) :
    ∀ record ∈ data.records, record.production ≤ 2147483647 ∧
      record.start ≤ 2147483647 ∧ record.finish ≤ 2147483647 := by
  intro record member
  have production := tree_visits_productions parse.recognizes 0 0 record (data.recordsEq ▸ member)
  have upper := data.bounded record member
  have monotone := (data.valid record member).monotone
  simp only [finalPosition] at upper
  omega

theorem CollectionRecords.nonempty (parse : MaterializedParse grammar (tokens.map Token.kind))
    (data : CollectionRecords grammar tokens parse.tree 0 0) : 0 < data.records.length := by
  have recognized := parse.recognizes
  rw [data.recordsEq]
  cases treeEqual : parse.tree with
  | terminal token kind =>
    rw [treeEqual] at recognized
    cases recognized with
    | terminal index bound scanned => omega
  | nonterminal production nonterminal start finish children =>
    simp only [treeVisits, List.length_append, List.length_cons, List.length_nil]
    omega

/-- Node serializer preconditions from the selected parse and its materialized
arrays. Production and span bounds, child links, and counts are derived. -/
def CollectionRecords.nodeInput (grammarData : Collect.GrammarData)
    (parse : MaterializedParse grammarData.grammar (tokens.map Token.kind))
    (data : CollectionRecords grammarData.grammar tokens parse.tree 0 0)
    (tokensFit : tokens.length * 2 ≤ 2147483647)
    (input : I32Prefix state cell inputCapacity (treeFrom 0 0 parse.tree).words)
    (offsets : I32Prefix state offsetCell offsetCapacity ((treeFrom 0 0 parse.tree).offsets.map Int.ofNat))
    (inputRead : state.local? 12 = some (.slice i32 cell [] 0 inputCapacity))
    (lengthRead : state.local? 13 = some (.signed .i32 inputCapacity))
    (offsetRead : state.local? 14 = some (.slice i32 offsetCell [] 0 offsetCapacity))
    (nodesRead : state.local? 15 = some (.signed .i32 (treeFrom 0 0 parse.tree).offsets.length))
    (distinctInput : outputCell ≠ cell) (distinctOffsets : outputCell ≠ offsetCell)
    (inputFit : inputCapacity ≤ 2147483647) (offsetFit : offsetCapacity ≤ 2147483647) :
    Unit.NodeInput state tokens.length outputCell := by
  have countEqual : data.records.length = (treeFrom 0 0 parse.tree).offsets.length := by
    simpa only [List.length_map] using congrArg List.length data.offsets
  have offsetWords : data.records.map (fun record => (record.offset : Int)) =
      (treeFrom 0 0 parse.tree).offsets.map Int.ofNat := by
    rw [← data.offsets, List.map_map]
    rfl
  have productionFit : grammarData.grammar.productionCount ≤ 2147483647 := by
    have range := (grammarData.encoded.validation_prelude grammarData.wellFormed).productionLhsRange
    have fit := grammarData.wordsFit
    dsimp only [PackedRangeValid] at range
    omega
  exact {
    records := data.records, words := (treeFrom 0 0 parse.tree).words
    cell := cell, capacity := inputCapacity, offsetCell := offsetCell, offsetCapacity := offsetCapacity
    inputLength := inputCapacity, input := input
    offsets := by rw [offsetWords]; exact offsets
    inputRead := inputRead, lengthRead := lengthRead, offsetRead := offsetRead
    nodesRead := by rw [countEqual]; exact nodesRead
    distinctInput := distinctInput, distinctOffsets := distinctOffsets
    inputRoom := input.length_le, inputFit := inputFit
    nodesFit := by
      have bound := offsets.length_le
      rw [List.length_map] at bound
      rw [countEqual]
      omega
    stored := data.stored
    fields := data.node_fields parse productionFit tokensFit
    linked := by simpa only [RecordsLinked, Nat.zero_add] using data.linked
    tokenBound := by
      intro record member child childMember use same
      subst child
      exact (data.token_child member childMember).2.2.1
  }

end Lanius.Extraction.SemanticTokens
