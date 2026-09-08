import Lanius.Extraction.SemanticTokens.Soundness

namespace Lanius.Extraction.SemanticTokens

open Lanius.Compiler.Parser ParserTreeLayout

/-- A state child refers to an earlier allocated record with the exact span
used by the collector. Token children have no node reference. -/
def ChildVisit.Linked (nodeBase : Nat) (records : List RecordVisit) (limit : Nat) : ChildVisit → Prop
  | .token _ => True
  | .node id start finish => nodeBase ≤ id ∧ id < limit ∧
      ∃ record, records[id - nodeBase]? = some record ∧ record.start = start ∧ record.finish = finish

def RecordsLinked (nodeBase : Nat) (records : List RecordVisit) : Prop :=
  ∀ (index : Nat) (record : RecordVisit), records[index]? = some record →
    ∀ child ∈ record.children, child.Linked nodeBase records (nodeBase + index)

theorem ChildVisit.Linked.mono {child : ChildVisit}
    (linked : child.Linked nodeBase records limit) (bound : limit ≤ more) :
    child.Linked nodeBase records more := by
  cases child with
  | token use => trivial
  | node id start finish => exact ⟨linked.1, Nat.lt_of_lt_of_le linked.2.1 bound, linked.2.2⟩

theorem ChildVisit.Linked.frame {child : ChildVisit} {before records : List RecordVisit}
    (linked : child.Linked (nodeBase + before.length) records limit) (after : List RecordVisit) :
    child.Linked nodeBase (before ++ records ++ after) limit := by
  cases child with
  | token use => trivial
  | node id start finish =>
    obtain ⟨lower, upper, record, found, sameStart, sameFinish⟩ := linked
    refine ⟨by omega, upper, record, ?_, sameStart, sameFinish⟩
    have bound := (List.getElem?_eq_some_iff.mp found).1
    rw [List.getElem?_append_left (by simp only [List.length_append]; omega),
      List.getElem?_append_right (by omega)]
    simpa only [Nat.sub_sub] using found

theorem RecordsLinked.append (left : RecordsLinked nodeBase records)
    (right : RecordsLinked (nodeBase + records.length) more) :
    RecordsLinked nodeBase (records ++ more) := by
  intro index record found child member
  by_cases earlier : index < records.length
  · have original : records[index]? = some record := by
      simpa only [List.getElem?_append_left earlier] using found
    have linked := left index record original child member
    simpa only [List.length_nil, Nat.add_zero, List.nil_append] using linked.frame (before := []) more
  · have original : more[index - records.length]? = some record := by
      simpa only [List.getElem?_append_right (by omega : records.length ≤ index)] using found
    have linked := right (index - records.length) record original child member
    have framed := linked.frame (before := records) []
    have indexEq : nodeBase + records.length + (index - records.length) = nodeBase + index := by omega
    simpa only [List.append_nil, indexEq] using framed

mutual
  theorem tree_visits_linked (tree : Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase position : Nat) :
      let visits := treeVisits grammar tokens nodeBase wordBase position tree
      RecordsLinked nodeBase visits.1 ∧
      visits.2.Linked nodeBase visits.1 (nodeBase + visits.1.length) := by
    cases tree with
    | terminal token kind =>
      exact ⟨by intro index record found; simp [treeVisits] at found, trivial⟩
    | nonterminal production nonterminal start finish children =>
      let nested := forestVisits grammar tokens nodeBase (wordBase + 4 + children.length * 3) start children
      let layout := forestFrom nodeBase (wordBase + 4 + children.length * 3) children
      let root : RecordVisit := ⟨wordBase, production, start, finish, nested.2⟩
      obtain ⟨records, references⟩ := forest_visits_linked (grammar := grammar) (tokens := tokens)
        children nodeBase (wordBase + 4 + children.length * 3) start
      have lengthEq : nested.1.length = layout.offsets.length := by
        have count := congrArg List.length (forest_visits_layout (grammar := grammar) (tokens := tokens)
          children nodeBase (wordBase + 4 + children.length * 3) start).1
        simpa only [List.length_map] using count
      change RecordsLinked nodeBase (nested.1 ++ [root]) ∧
        ChildVisit.Linked nodeBase (nested.1 ++ [root])
          (nodeBase + (nested.1 ++ [root]).length) (.node (nodeBase + layout.offsets.length) start finish)
      constructor
      · intro index record found child member
        by_cases earlier : index < nested.1.length
        · have original : nested.1[index]? = some record := by
            simpa only [List.getElem?_append_left earlier] using found
          have linked := records index record original child member
          simpa only [List.length_nil, Nat.add_zero, List.nil_append] using linked.frame (before := []) [root]
        · have bound := (List.getElem?_eq_some_iff.mp found).1
          have last : index = nested.1.length := by simp only [List.length_append, List.length_singleton] at bound; omega
          subst index
          have same : root = record := by simpa using found
          subst record
          have linked := references child member
          simpa only [List.length_nil, Nat.add_zero, List.nil_append] using linked.frame (before := []) [root]
      · refine ⟨by omega, ?_, root, ?_, rfl, rfl⟩
        · simp only [List.length_append, List.length_singleton]
          omega
        · simp [← lengthEq]
  termination_by sizeOf tree

  theorem forest_visits_linked (trees : List Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase position : Nat) :
      let visits := forestVisits grammar tokens nodeBase wordBase position trees
      RecordsLinked nodeBase visits.1 ∧
      (∀ child ∈ visits.2, child.Linked nodeBase visits.1 (nodeBase + visits.1.length)) := by
    cases trees with
    | nil => exact ⟨by intro index record found; simp [forestVisits] at found, by simp [forestVisits]⟩
    | cons tree trees =>
      let first := treeVisits grammar tokens nodeBase wordBase position tree
      let layout := treeFrom nodeBase wordBase tree
      let rest := forestVisits grammar tokens (nodeBase + layout.offsets.length)
        (wordBase + layout.words.length) first.2.finish trees
      obtain ⟨headRecords, headRef⟩ := tree_visits_linked (grammar := grammar) (tokens := tokens)
        tree nodeBase wordBase position
      obtain ⟨tailRecords, tailRefs⟩ := forest_visits_linked (grammar := grammar) (tokens := tokens)
        trees (nodeBase + layout.offsets.length) (wordBase + layout.words.length) first.2.finish
      have lengthEq : first.1.length = layout.offsets.length := by
        have count := congrArg List.length (tree_visits_layout (grammar := grammar) (tokens := tokens)
          tree nodeBase wordBase position).1
        simpa only [List.length_map] using count
      have tailAligned : RecordsLinked (nodeBase + first.1.length) rest.1 := by
        rw [lengthEq]
        exact tailRecords
      change RecordsLinked nodeBase (first.1 ++ rest.1) ∧
        (∀ child ∈ first.2 :: rest.2,
          child.Linked nodeBase (first.1 ++ rest.1) (nodeBase + (first.1 ++ rest.1).length))
      refine ⟨headRecords.append tailAligned, ?_⟩
      intro child member
      rcases List.mem_cons.mp member with same | later
      · subst child
        have framed : first.2.Linked nodeBase (first.1 ++ rest.1) (nodeBase + first.1.length) := by
          simpa only [List.length_nil, Nat.add_zero, List.nil_append] using headRef.frame (before := []) rest.1
        exact framed.mono (by simp only [List.length_append]; omega)
      · have linked : child.Linked (nodeBase + first.1.length) rest.1
            (nodeBase + first.1.length + rest.1.length) := by
          rw [lengthEq]
          exact tailRefs child later
        simpa only [List.append_nil, List.length_append, Nat.add_assoc] using linked.frame (before := first.1) []
  termination_by sizeOf trees
end

/-- Following an actual state-child ID reaches its earlier stored record,
with the exact start/end cursor values. Neither span equality is assumed. -/
theorem tree_visit_child_lookup (tree : Lanius.Compiler.Parser.ParseTree)
    (nodeBase wordBase position index : Nat)
    (found : (treeVisits grammar tokens nodeBase wordBase position tree).1[index]? = some record)
    (member : ChildVisit.node childId start finish ∈ record.children) :
    nodeBase ≤ childId ∧ childId < nodeBase + index ∧
      ∃ child : RecordVisit, (treeFrom nodeBase wordBase tree).offsets[childId - nodeBase]? = some child.offset ∧
        child.Stored wordBase (treeFrom nodeBase wordBase tree).words ∧
        child.start = start ∧ child.finish = finish := by
  have linked := (tree_visits_linked (grammar := grammar) (tokens := tokens) tree nodeBase wordBase position).1
    index record found (.node childId start finish) member
  obtain ⟨lower, earlier, child, lookup, sameStart, sameFinish⟩ := linked
  obtain ⟨offset, stored⟩ := tree_visit_lookup tree nodeBase wordBase position lookup
  exact ⟨lower, earlier, child, offset, stored, sameStart, sameFinish⟩

end Lanius.Extraction.SemanticTokens
