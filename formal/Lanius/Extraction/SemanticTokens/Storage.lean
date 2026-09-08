import Lanius.Extraction.SemanticTokens.Traversal

namespace Lanius.Extraction.SemanticTokens

open Lanius.Compiler.Parser ParserTreeLayout

/-- Exact record storage before erasing semantic kinds at the ParseChild
boundary. The buffer may contain other records and an untouched suffix. -/
def RecordVisit.Stored (record : RecordVisit) (wordBase : Nat) (words : List Int) : Prop :=
  ∃ before after, words = before ++ record.words ++ after ∧ record.offset = wordBase + before.length

theorem RecordVisit.Stored.frame {record : RecordVisit} {before words : List Int}
    (stored : record.Stored (wordBase + before.length) words) (after : List Int) :
    record.Stored wordBase (before ++ words ++ after) := by
  obtain ⟨leading, trailing, rfl, offset⟩ := stored
  refine ⟨before ++ leading, trailing ++ after, ?_, ?_⟩
  · simp only [List.append_assoc]
  · simpa only [List.length_append, Nat.add_assoc] using offset

theorem RecordVisit.words_length (record : RecordVisit) :
    record.words.length = 4 + record.children.length * 3 := by
  have same : record.children.flatMap (fun child => derivationChildWords child.reference) =
      (record.children.map ChildVisit.reference).flatMap derivationChildWords := by
    rw [List.flatMap_map]
  simp only [RecordVisit.words, List.length_append, same, child_words_length, List.length_map,
    recordHeader, List.length_cons, List.length_nil]

theorem RecordVisit.Stored.bounds {record : RecordVisit} {words : List Int}
    (stored : record.Stored wordBase words) :
    wordBase ≤ record.offset ∧ record.offset + 4 + record.children.length * 3 ≤ wordBase + words.length := by
  obtain ⟨before, after, rfl, offset⟩ := stored
  simp only [List.length_append, RecordVisit.words_length, offset]
  constructor <;> omega

mutual
  /-- All child triples in the actual word buffer match the semantic visit,
  including the token kinds that the older ParseChild record view erases. -/
  theorem tree_visits_stored (tree : Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase position : Nat) :
      ∀ record ∈ (treeVisits grammar tokens nodeBase wordBase position tree).1,
        record.Stored wordBase (treeFrom nodeBase wordBase tree).words := by
    cases tree with
    | terminal token kind => simp [treeVisits]
    | nonterminal production nonterminal start finish children =>
      let nested := forestFrom nodeBase (wordBase + 4 + children.length * 3) children
      let visits := forestVisits grammar tokens nodeBase (wordBase + 4 + children.length * 3) start children
      let root : RecordVisit := ⟨wordBase, production, start, finish, visits.2⟩
      have roots := (forest_visits_layout (grammar := grammar) (tokens := tokens) children
        nodeBase (wordBase + 4 + children.length * 3) start).2
      have rootWords : root.words = recordHeader production start finish children.length ++
          nested.roots.flatMap derivationChildWords := by
        simp only [RecordVisit.words, root, visits, forest_visits_length]
        rw [← roots]
        simp only [List.flatMap_map]
      have rootLength : root.words.length = 4 + children.length * 3 := by
        rw [RecordVisit.words_length]
        simp only [root, visits, forest_visits_length]
      intro record member
      change record ∈ visits.1 ++ [root] at member
      change record.Stored wordBase (recordHeader production start finish children.length ++
        nested.roots.flatMap derivationChildWords ++ nested.words)
      rw [← rootWords]
      rcases List.mem_append.mp member with earlier | last
      · have stored := forest_visits_stored (grammar := grammar) (tokens := tokens) children
          nodeBase (wordBase + 4 + children.length * 3) start record earlier
        have aligned : record.Stored (wordBase + root.words.length) nested.words := by
          simpa only [rootLength, nested, Nat.add_assoc] using stored
        simpa only [List.append_nil] using aligned.frame (before := root.words) []
      · have same := List.mem_singleton.mp last
        subst record
        exact ⟨[], nested.words, rfl, by simp [root]⟩
  termination_by sizeOf tree

  theorem forest_visits_stored (trees : List Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase position : Nat) :
      ∀ record ∈ (forestVisits grammar tokens nodeBase wordBase position trees).1,
        record.Stored wordBase (forestFrom nodeBase wordBase trees).words := by
    cases trees with
    | nil => simp [forestVisits]
    | cons tree trees =>
      let first := treeFrom nodeBase wordBase tree
      let rest := forestFrom (nodeBase + first.offsets.length) (wordBase + first.words.length) trees
      intro record member
      change record ∈ (treeVisits grammar tokens nodeBase wordBase position tree).1 ++
        (forestVisits grammar tokens (nodeBase + first.offsets.length) (wordBase + first.words.length)
          (treeVisits grammar tokens nodeBase wordBase position tree).2.finish trees).1 at member
      change record.Stored wordBase (first.words ++ rest.words)
      rcases List.mem_append.mp member with head | tail
      · have stored := tree_visits_stored (grammar := grammar) (tokens := tokens) tree nodeBase wordBase position record head
        simpa only [List.length_nil, Nat.add_zero, List.nil_append] using stored.frame (before := []) rest.words
      · have stored := forest_visits_stored (grammar := grammar) (tokens := tokens) trees
          (nodeBase + first.offsets.length) (wordBase + first.words.length)
          (treeVisits grammar tokens nodeBase wordBase position tree).2.finish record tail
        simpa only [List.append_nil] using stored.frame (before := first.words) []
  termination_by sizeOf trees
end

/-- The same index used by collect retrieves this exact semantic record. -/
theorem tree_visit_lookup {index : Nat} (tree : Lanius.Compiler.Parser.ParseTree)
    (nodeBase wordBase position : Nat)
    (found : (treeVisits grammar tokens nodeBase wordBase position tree).1[index]? = some record) :
    (treeFrom nodeBase wordBase tree).offsets[index]? = some record.offset ∧
      record.Stored wordBase (treeFrom nodeBase wordBase tree).words := by
  constructor
  · rw [← (tree_visits_layout (grammar := grammar) (tokens := tokens) tree nodeBase wordBase position).1]
    simp [found]
  · exact tree_visits_stored tree nodeBase wordBase position record (List.mem_of_getElem? found)

end Lanius.Extraction.SemanticTokens
