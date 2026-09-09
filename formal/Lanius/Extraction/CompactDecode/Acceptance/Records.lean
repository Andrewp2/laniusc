import Lanius.Extraction.CompactDecode.Acceptance.Symbols

namespace Lanius.Extraction.CompactDecode

open Lanius.Compiler.Parser SemanticTokens ParserTreeLayout

def RecordSymbols (grammar : IndexedGrammar) (records : List RecordVisit)
    (nodeBase : Nat) (record : RecordVisit) : Prop :=
  ∃ production, grammar.grammar.production? record.production = some production ∧
    ChildSymbols grammar records nodeBase production.rhs record.children

theorem RecordSymbols.frame {before records : List RecordVisit}
    (typed : RecordSymbols grammar records (nodeBase + before.length) record)
    (after : List RecordVisit) :
    RecordSymbols grammar (before ++ records ++ after) nodeBase record := by
  obtain ⟨production, found, children⟩ := typed
  exact ⟨production, found, children.frame after⟩

mutual
  theorem tree_record_symbols
      (recognized : ParseTreeRecognizesSymbol grammar tokens tree symbol start finish)
      (nodeBase wordBase : Nat) :
      ∀ record ∈ (treeVisits grammar tokens nodeBase wordBase start tree).1,
        RecordSymbols grammar (treeVisits grammar tokens nodeBase wordBase start tree).1 nodeBase record := by
    cases recognized with
    | terminal _ _ _ => simp [treeVisits]
    | nonterminal ntBound prodBound lhs children =>
      rename_i nonterminal production trees
      let nested := forestVisits grammar tokens nodeBase (wordBase + 4 + trees.length * 3) start trees
      let root : RecordVisit := ⟨wordBase, production, start, finish, nested.2⟩
      intro record member
      rcases List.mem_append.mp member with earlier | last
      · have typed := forest_record_symbols children nodeBase (wordBase + 4 + trees.length * 3) record earlier
        simpa only [List.length_nil, Nat.add_zero, List.nil_append, treeVisits, root, nested] using
          typed.frame (before := []) [root]
      · have same := List.mem_singleton.mp last
        subst record
        refine ⟨grammar.productionAt ⟨production, prodBound⟩, List.getElem?_eq_getElem prodBound, ?_⟩
        have typed := forest_reference_symbols children nodeBase (wordBase + 4 + trees.length * 3)
        simpa only [List.length_nil, Nat.add_zero, List.nil_append, treeVisits, root, nested] using
          typed.frame (before := []) [root]
  termination_by (sizeOf tree, finish)

  theorem forest_record_symbols
      (recognized : ParseTreesRecognizeSequence grammar tokens trees symbols start finish)
      (nodeBase wordBase : Nat) :
      ∀ record ∈ (forestVisits grammar tokens nodeBase wordBase start trees).1,
        RecordSymbols grammar (forestVisits grammar tokens nodeBase wordBase start trees).1 nodeBase record := by
    cases recognized with
    | empty => simp [forestVisits]
    | @cons tree symbol start middle trees symbols finish head tail =>
      let first := treeVisits grammar tokens nodeBase wordBase start tree
      let layout := treeFrom nodeBase wordBase tree
      let rest := forestVisits grammar tokens (nodeBase + layout.offsets.length)
        (wordBase + layout.words.length) middle trees
      obtain ⟨_, _, _, _, firstFinish, _, _, _⟩ := tree_visits_sound head nodeBase wordBase
      have lengthEq : first.1.length = layout.offsets.length := by
        have lengths := congrArg List.length (tree_visits_layout (grammar := grammar) (tokens := tokens)
          tree nodeBase wordBase start).1
        simpa only [List.length_map] using lengths
      intro record member
      dsimp only [forestVisits] at member ⊢
      rw [firstFinish] at member ⊢
      rcases List.mem_append.mp member with earlier | later
      · have typed := tree_record_symbols head nodeBase wordBase record earlier
        simpa only [List.length_nil, Nat.add_zero, List.nil_append] using
          typed.frame (before := []) rest.1
      · have typed : RecordSymbols grammar rest.1 (nodeBase + first.1.length) record := by
          rw [lengthEq]
          exact forest_record_symbols tail (nodeBase + layout.offsets.length)
            (wordBase + layout.words.length) record later
        simpa only [List.append_nil] using typed.frame (before := first.1) []
  termination_by (sizeOf trees, finish)
end

theorem collection_record_symbols
    (parse : MaterializedParse grammar (tokens.map Token.kind))
    (collection : CollectionRecords grammar tokens parse.tree 0 0)
    (member : record ∈ collection.records) :
    RecordSymbols grammar collection.records 0 record := by
  rw [collection.recordsEq]
  exact tree_record_symbols parse.recognizes 0 0 record (collection.recordsEq ▸ member)

end Lanius.Extraction.CompactDecode
