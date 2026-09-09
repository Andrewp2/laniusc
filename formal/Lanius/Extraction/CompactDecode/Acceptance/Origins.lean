import Lanius.Extraction.CompactDecode.Acceptance.Nodes

namespace Lanius.Extraction.CompactDecode

open Lanius.Compiler.Parser SemanticTokens ParserTreeLayout

/-- A record retains the actual recognized children of its production. This
is derived from traversal, not a new premise imposed on the collector. -/
def RecordOrigin (grammar : IndexedGrammar) (tokens : List Nat) (record : RecordVisit) : Prop :=
  ∃ trees nodeBase, ∃ bound : record.production < grammar.productionCount,
    ParseTreesRecognizeSequence grammar tokens trees
      (grammar.productionAt ⟨record.production, bound⟩).rhs record.start record.finish ∧
    record.children = (forestVisits grammar tokens nodeBase
      (record.offset + 4 + trees.length * 3) record.start trees).2

mutual
  theorem tree_record_origins
      (recognized : ParseTreeRecognizesSymbol grammar tokens tree symbol start finish)
      (nodeBase wordBase : Nat) :
      ∀ record ∈ (treeVisits grammar tokens nodeBase wordBase start tree).1,
        RecordOrigin grammar tokens record := by
    cases recognized with
    | terminal _ _ _ => simp [treeVisits]
    | nonterminal nonterminalBound productionBound lhs children =>
      intro record member
      rcases List.mem_append.mp member with earlier | last
      · exact forest_record_origins children nodeBase (wordBase + 4 + _ * 3) record earlier
      · have same := List.mem_singleton.mp last
        subst record
        exact ⟨_, nodeBase, productionBound, children, rfl⟩

  theorem forest_record_origins
      (recognized : ParseTreesRecognizeSequence grammar tokens trees symbols start finish)
      (nodeBase wordBase : Nat) :
      ∀ record ∈ (forestVisits grammar tokens nodeBase wordBase start trees).1,
        RecordOrigin grammar tokens record := by
    cases recognized with
    | empty => simp [forestVisits]
    | @cons tree symbol start middle trees symbols finish head tail =>
      obtain ⟨_, _, _, _, firstFinish, _, _, _⟩ := tree_visits_sound head nodeBase wordBase
      intro record member
      dsimp only [forestVisits] at member
      rw [firstFinish] at member
      rcases List.mem_append.mp member with earlier | later
      · exact tree_record_origins head nodeBase wordBase record earlier
      · exact forest_record_origins tail
          (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
          (wordBase + (treeFrom nodeBase wordBase tree).words.length) record later
end

theorem collection_record_origins
    (parse : MaterializedParse grammar (tokens.map Token.kind))
    (collection : CollectionRecords grammar tokens parse.tree 0 0)
    (member : record ∈ collection.records) :
    RecordOrigin grammar (tokens.map Token.kind) record :=
  tree_record_origins parse.recognizes 0 0 record (collection.recordsEq ▸ member)

end Lanius.Extraction.CompactDecode
