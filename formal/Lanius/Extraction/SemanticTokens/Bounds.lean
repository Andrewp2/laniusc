import Lanius.Extraction.SemanticTokens.Links

namespace Lanius.Extraction.SemanticTokens

open Lanius.Compiler.Parser ParserTreeLayout

theorem ChildVisit.Valid.monotone {child : ChildVisit} (valid : child.Valid grammar tokens) :
    child.start ≤ child.finish := by
  cases child with
  | token use => exact Nat.le_of_lt valid.advances
  | node id start finish => exact valid

theorem VisitPath.monotone (path : VisitPath grammar tokens children start finish) : start ≤ finish := by
  induction path with
  | nil => exact Nat.le_refl _
  | cons valid tail ih => exact Nat.le_trans valid.monotone ih

theorem VisitPath.member (path : VisitPath grammar tokens children start finish) (member : child ∈ children) :
    child.Valid grammar tokens ∧ start ≤ child.start ∧ child.finish ≤ finish := by
  induction path with
  | nil => simp at member
  | cons valid tail ih =>
    rcases List.mem_cons.mp member with rfl | later
    · exact ⟨valid, Nat.le_refl _, tail.monotone⟩
    · obtain ⟨validChild, lower, upper⟩ := ih later
      exact ⟨validChild, Nat.le_trans valid.monotone lower, upper⟩

mutual
  /-- Every record remains inside its enclosing derivation's lattice span,
  including empty nonterminals with no terminal assignment of their own. -/
  theorem tree_visits_bounded
      (recognized : ParseTreeRecognizesSymbol grammar tokens tree symbol start finish)
      (nodeBase wordBase : Nat) :
      ∀ record ∈ (treeVisits grammar tokens nodeBase wordBase start tree).1,
        start ≤ record.start ∧ record.finish ≤ finish := by
    cases recognized with
    | terminal _ _ _ => simp [treeVisits]
    | nonterminal nonterminalBound productionBound lhs children =>
      intro record member
      rcases List.mem_append.mp member with earlier | last
      · exact forest_visits_bounded children nodeBase (wordBase + 4 + _ * 3) record earlier
      · have same := List.mem_singleton.mp last
        subst record
        exact ⟨Nat.le_refl _, Nat.le_refl _⟩

  theorem forest_visits_bounded
      (recognized : ParseTreesRecognizeSequence grammar tokens trees symbols start finish)
      (nodeBase wordBase : Nat) :
      ∀ record ∈ (forestVisits grammar tokens nodeBase wordBase start trees).1,
        start ≤ record.start ∧ record.finish ≤ finish := by
    cases recognized with
    | empty => simp [forestVisits]
    | @cons tree symbol start middle trees symbols finish head tail =>
      obtain ⟨_, firstPath, _, _, firstFinish, _, _, _⟩ := tree_visits_sound head nodeBase wordBase
      obtain ⟨_, restPath, _⟩ := forest_scan tail
      intro record member
      dsimp only [forestVisits] at member
      rw [firstFinish] at member
      rcases List.mem_append.mp member with earlier | later
      · obtain ⟨lower, upper⟩ := tree_visits_bounded head nodeBase wordBase record earlier
        exact ⟨lower, Nat.le_trans upper restPath.monotone⟩
      · obtain ⟨lower, upper⟩ := forest_visits_bounded tail
          (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
          (wordBase + (treeFrom nodeBase wordBase tree).words.length) record later
        exact ⟨Nat.le_trans firstPath.monotone lower, upper⟩
end

end Lanius.Extraction.SemanticTokens
