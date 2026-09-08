import Lanius.Extraction.SemanticTokens.Storage

namespace Lanius.Extraction.SemanticTokens

open Lanius.Compiler.Parser ParserTreeLayout

def ChildVisit.Valid (grammar : IndexedGrammar) (tokens : List Nat) : ChildVisit → Prop
  | .token use => use.Valid grammar tokens
  | .node _ start finish => start ≤ finish

/-- The cursor traverses a record's immediate children without gaps. Nested
nodes skip their entire span; token children make the corresponding scan. -/
inductive VisitPath (grammar : IndexedGrammar) (tokens : List Nat) : List ChildVisit → Nat → Nat → Prop
  | nil : VisitPath grammar tokens [] position position
  | cons (valid : child.Valid grammar tokens)
      (tail : VisitPath grammar tokens children child.finish finish) :
      VisitPath grammar tokens (child :: children) child.start finish

def RecordVisit.Valid (grammar : IndexedGrammar) (tokens : List Nat) (record : RecordVisit) : Prop :=
  VisitPath grammar tokens record.children record.start record.finish

private theorem regroup (a b c d : List Use) : ((a ++ b) ++ (c ++ d)).Perm ((a ++ c) ++ (b ++ d)) := by
  simpa only [List.append_assoc] using
    ((List.perm_append_comm (l₁ := b) (l₂ := c)).append_right d).append_left a

mutual
  /-- The visit model is derived from the same recognized tree. In particular,
  its postorder assignments are a permutation of a valid source-order scan. -/
  theorem tree_visits_sound
      (recognized : ParseTreeRecognizesSymbol grammar tokens tree symbol start finish)
      (nodeBase wordBase : Nat) :
      let visits := treeVisits grammar tokens nodeBase wordBase start tree
      ∃ uses, ScanPath grammar tokens uses start finish ∧
        uses.map Use.leaf = treeLeaves tree ∧
        visits.2.start = start ∧ visits.2.finish = finish ∧ visits.2.Valid grammar tokens ∧
        (∀ record ∈ visits.1, record.Valid grammar tokens) ∧
        uses.Perm (visits.1.flatMap RecordVisit.uses ++ visits.2.uses) := by
    cases recognized with
    | terminal tokenEq kindBound scanned =>
      simp only [treeVisits, scanned, Option.getD_some]
      refine ⟨[⟨start, finish, _, _⟩], .cons ⟨tokenEq, kindBound, scanned⟩ .nil,
        rfl, rfl, rfl, ⟨tokenEq, kindBound, scanned⟩, ?_, List.Perm.refl _⟩
      intro record member
      simp at member
    | nonterminal nonterminalBound productionBound lhs children =>
      obtain ⟨uses, path, leaves, childPath, valid, order⟩ :=
        forest_visits_sound children nodeBase (wordBase + 4 + _ * 3)
      refine ⟨uses, path, leaves, rfl, rfl, path.monotone, ?_, ?_⟩
      · intro record member
        rcases List.mem_append.mp member with earlier | last
        · exact valid record earlier
        · have same := List.mem_singleton.mp last
          subst record
          exact childPath
      · simpa only [treeVisits, List.flatMap_append, List.flatMap_cons, List.flatMap_nil,
          List.append_nil, ChildVisit.uses, RecordVisit.uses] using order

  theorem forest_visits_sound
      (recognized : ParseTreesRecognizeSequence grammar tokens trees symbols start finish)
      (nodeBase wordBase : Nat) :
      let visits := forestVisits grammar tokens nodeBase wordBase start trees
      ∃ uses, ScanPath grammar tokens uses start finish ∧
        uses.map Use.leaf = forestLeaves trees ∧
        VisitPath grammar tokens visits.2 start finish ∧
        (∀ record ∈ visits.1, record.Valid grammar tokens) ∧
        uses.Perm (visits.1.flatMap RecordVisit.uses ++ visits.2.flatMap ChildVisit.uses) := by
    cases recognized with
    | empty => exact ⟨[], .nil, rfl, .nil, by simp [forestVisits], .refl _⟩
    | @cons tree symbol start middle trees symbols finish head tail =>
      obtain ⟨first, firstPath, firstLeaves, firstStart, firstFinish, firstValid, firstRecords, firstOrder⟩ :=
        tree_visits_sound head nodeBase wordBase
      obtain ⟨rest, restPath, restLeaves, restVisits, restRecords, restOrder⟩ :=
        forest_visits_sound tail (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
          (wordBase + (treeFrom nodeBase wordBase tree).words.length)
      dsimp only [forestVisits]
      rw [firstFinish]
      refine ⟨first ++ rest, firstPath.append restPath,
        by simp only [List.map_append, firstLeaves, restLeaves, forestLeaves], ?_, ?_, ?_⟩
      · have tailAligned : VisitPath grammar tokens
            (forestVisits grammar tokens (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
              (wordBase + (treeFrom nodeBase wordBase tree).words.length) middle trees).2
            (treeVisits grammar tokens nodeBase wordBase start tree).2.finish finish := by
          rw [firstFinish]
          exact restVisits
        have next := VisitPath.cons firstValid tailAligned
        simpa only [firstStart] using next
      · intro record member
        rcases List.mem_append.mp member with earlier | later
        · exact firstRecords record earlier
        · exact restRecords record later
      · exact (firstOrder.append restOrder).trans (by
          simpa only [List.flatMap_append, List.flatMap_cons, List.append_assoc] using regroup
            _ _ _ _)
end

/-- A selected parse has a nonterminal root, so every terminal assignment is
in an allocated record. No detached root-terminal exception reaches collect. -/
theorem selected_tree_visits (parse : MaterializedParse grammar tokens) (nodeBase wordBase : Nat) :
    let visits := treeVisits grammar tokens nodeBase wordBase 0 parse.tree
    ∃ uses, ScanPath grammar tokens uses 0 (finalPosition tokens.length) ∧
      uses.map Use.leaf = treeLeaves parse.tree ∧
      uses.Perm (visits.1.flatMap RecordVisit.uses) ∧
      (∀ record ∈ visits.1, record.Valid grammar tokens) ∧
      ((visits.1.flatMap RecordVisit.uses).map Use.slot).Nodup := by
  obtain ⟨uses, path, leaves, _, _, _, valid, order⟩ := tree_visits_sound parse.recognizes nodeBase wordBase
  have rootEmpty : (treeVisits grammar tokens nodeBase wordBase 0 parse.tree).2.uses = [] := by
    cases parse with
    | mk tree recognized =>
      cases tree with
      | terminal token kind =>
        cases recognized with
        | terminal _ bound _ => omega
      | nonterminal production nonterminal start finish children => rfl
  rw [rootEmpty, List.append_nil] at order
  exact ⟨uses, path, leaves, order, valid, (order.map Use.slot).nodup path.slots_unique⟩

end Lanius.Extraction.SemanticTokens
