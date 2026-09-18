import Lanius.Compiler.Parser.Completion.Closure
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Parser.Completion
open Lanius.Compiler.Parser

-- S → A A; A → ε. Replaying the completed A appends S → A • A
-- to the very chart being visited, which must itself advance to S → A A •.
private def grammar : IndexedGrammar := {
  grammar := {
    n_kinds := 1, n_nonterminals := 2, start_nonterminal := 0
    split_token_kind := 9, split_component_kind := 7, canonical_kinds := [7]
    productions := [⟨0, [2, 2]⟩, ⟨1, []⟩] }
  productionsByLhs := [[0], [1]] }

private def parent := appendLogical 4 0 (freshSeed 0 0) emptyWorkspace
private def child := appendLogical 4 0 (freshSeed 1 0) parent.2
private def firstSeed := ((freshSeed 0 0).atPosition 0).advanceSeed 0 (.state 1)
private def first := appendLogical 4 0 firstSeed child.2
private def secondSeed := (firstSeed.atPosition 0).advanceSeed 2 (.state 1)
private def second := appendLogical 4 0 secondSeed first.2

private theorem childWF : WorkspaceWellFormed child.2 :=
  (appendLogical_refines child rfl).preserves_well_formed
    ((appendLogical_refines parent rfl).preserves_well_formed emptyWorkspace_wellFormed)
private theorem firstWF : WorkspaceWellFormed first.2 :=
  (appendLogical_refines first rfl).preserves_well_formed childWF
private theorem secondWF : WorkspaceWellFormed second.2 :=
  (appendLogical_refines second rfl).preserves_well_formed firstWF

private def oldCursor : ChartCursor (child.2.chart 0) 0 [1] := ChartCursor.atHead 0 [1]
private def grownCursor : ChartCursor (first.2.chart 0) 0 [1, 2] := ChartCursor.atHead 0 [1, 2]
private def childCursor := grownCursor.next (firstWF.chartIdsUnique 0)
private def waitingCursor := childCursor.next (firstWF.chartIdsUnique 0)
private def replayCursor : ChartCursor (second.2.chart 0) 2 [3] :=
  ((ChartCursor.atHead 0 [1, 2, 3]).next (secondWF.chartIdsUnique 0)).next
    (secondWF.chartIdsUnique 0)
private def finalCursor := replayCursor.next (secondWF.chartIdsUnique 0)

private theorem firstAdvanced : ParentsFor grammar first.2 0 1 [0] := by
  apply ParentsFor.step (origin := 0) oldCursor grownCursor
    (WorkspaceAppendClosure.single 4 0 firstSeed child.2) childWF.chartSound ParentsFor.nil
  intro state found
  have same : (freshSeed 0 0).atPosition 0 = state := Option.some.inj found
  subst state
  exact ParentAdvanced.of_inserted (appendLogical_refines first rfl) (by decide) rfl

private theorem childVisited : ParentsFor grammar first.2 0 1 [0, 1] := by
  apply ParentsFor.step (origin := 0) (capacity := 4) childCursor childCursor
    (.refl first.2) firstWF.chartSound firstAdvanced
  intro state found
  have same : (freshSeed 1 0).atPosition 0 = state := Option.some.inj found
  subst state
  intro bound expected
  contradiction

private theorem replayed : ParentsFor grammar second.2 0 1 [0, 1, 2] := by
  apply ParentsFor.step (origin := 0) waitingCursor replayCursor
    (WorkspaceAppendClosure.single 4 0 secondSeed first.2) firstWF.chartSound childVisited
  intro state found
  have same : firstSeed.atPosition 0 = state := Option.some.inj found
  subst state
  exact ParentAdvanced.of_inserted (appendLogical_refines second rfl) (by decide) rfl

private theorem complete : ParentsComplete grammar second.2 0 0 1 := by
  change ParentsFor grammar second.2 0 1 [0, 1, 2, 3]
  apply ParentsFor.step (origin := 0) (capacity := 4) finalCursor finalCursor
    (.refl second.2) secondWF.chartSound replayed
  intro state found
  have same : secondSeed.atPosition 0 = state := Option.some.inj found
  subst state
  intro bound expected
  contradiction

-- The state added during replay must itself be processed before returning.
example : second.2.containsKey 0 ⟨0, 2, 0⟩ :=
  complete.advance ⟨0, by decide⟩ 1 0
    ((appendLogical_refines second rfl).preserves_containsKey
      ((appendLogical_refines first rfl).containsKey_of_ok (by decide))) rfl

example : ¬ Nonempty (ChartCursor (first.2.chart 0) 1 []) := by
  rintro ⟨cursor⟩
  have exhausted := cursor.nextAfter
  contradiction

-- Capacity failure cannot assert coverage for an advance that was dropped.
example : (appendLogical 3 0 secondSeed first.2).1.status = .full := by decide
example : ¬ ParentsComplete grammar first.2 0 0 1 := by
  intro covered
  have advanced := covered.advance ⟨0, by decide⟩ 1 0
    ((appendLogical_refines first rfl).containsKey_of_ok (by decide)) rfl
  exact (first.2.findStateId?_none_iff.mp (by decide)) advanced

-- Conversely, a duplicate advance is complete even at full capacity.
private def duplicate := appendLogical 4 0 secondSeed second.2
example : duplicate.1.status = .ok := by decide
example : ParentAdvanced grammar duplicate.2 0 1 (firstSeed.atPosition 0) :=
  ParentAdvanced.of_inserted (appendLogical_refines duplicate rfl) (by decide) rfl

-- Accumulate the two replay orders in the outer state traversal. Processing
-- the waiting parent first adds state 2; processing its child adds state 3.
-- Both appended states remain pending and are then processed in order.
private theorem pairsFirst : CompletionsFor grammar first.2 0 [0] := by
  apply CompletionsFor.step oldCursor grownCursor
    (WorkspaceAppendClosure.single 4 0 firstSeed child.2) childWF.chartSound firstWF.chartSound
    (fun _ earlier => by omega) CompletionsFor.nil
  intro state found
  have same : (freshSeed 0 0).atPosition 0 = state := Option.some.inj found
  subst state
  exact CompletionStep.of_nonterminal (expected := 1) (by decide) rfl
    (NullablesFor.of_advanced ((appendLogical_refines first rfl).containsKey_of_ok (by decide)))

private def grownChildCursor : ChartCursor (second.2.chart 0) 1 [2, 3] :=
  (ChartCursor.atHead 0 [1, 2, 3]).next (secondWF.chartIdsUnique 0)

private theorem pairsChild : CompletionsFor grammar second.2 0 [0, 1] := by
  apply CompletionsFor.step childCursor grownChildCursor
    (WorkspaceAppendClosure.single 4 0 secondSeed first.2) firstWF.chartSound secondWF.chartSound
    (fun _ earlier => by omega) pairsFirst
  intro state found
  have same : (freshSeed 1 0).atPosition 0 = state := Option.some.inj found
  subst state
  exact CompletionStep.of_finished (by decide) rfl complete

private theorem pairsReplay : CompletionsFor grammar second.2 0 [0, 1, 2] := by
  apply CompletionsFor.step replayCursor replayCursor (WorkspaceAppendClosure.refl (capacity := 4) second.2)
    secondWF.chartSound secondWF.chartSound (fun _ earlier => by omega) pairsChild
  intro state found
  have same : firstSeed.atPosition 0 = state := Option.some.inj found
  subst state
  exact CompletionStep.of_nonterminal (expected := 1) (by decide) rfl
    (NullablesFor.of_advanced ((appendLogical_refines second rfl).containsKey_of_ok (by decide)))

private theorem pairsClosed : ChartCompleted grammar second.2 0 := by
  change CompletionsFor grammar second.2 0 [0, 1, 2, 3]
  apply CompletionsFor.step finalCursor finalCursor (WorkspaceAppendClosure.refl (capacity := 4) second.2)
    secondWF.chartSound secondWF.chartSound (fun _ earlier => by omega) pairsReplay
  intro state found
  have same : secondSeed.atPosition 0 = state := Option.some.inj found
  subst state
  apply CompletionStep.of_finished (by decide) rfl
  intro id listed parent found bound expected
  change id ∈ [0, 1, 2, 3] at listed
  simp only [List.mem_cons, List.not_mem_nil, or_false] at listed
  rcases listed with rfl | rfl | rfl | rfl <;>
    (have same := Option.some.inj found; subst parent)
  all_goals first
    | contradiction
    | have impossible : (2 : Nat) = 1 := Option.some.inj expected
      omega

-- A processed child cannot cover a later parent if nullable replay drops
-- the second advance. The full pair invariant detects that omission.
example : ¬ CompletionsFor grammar first.2 0 [0, 1, 2] := by
  intro covered
  have advanced := covered 1 (by decide) ((freshSeed 1 0).atPosition 0) rfl
    (by decide) rfl 2 (by decide) (.inr (by decide)) (firstSeed.atPosition 0) rfl
    (by decide) rfl
  exact (first.2.findStateId?_none_iff.mp (by decide)) advanced

example : second.2.containsKey 0 ⟨0, 2, 0⟩ :=
  pairsClosed.complete ⟨0, by decide⟩ ⟨1, by decide⟩ 1 0 0 (by decide)
    ((appendLogical_refines second rfl).preserves_containsKey
      ((appendLogical_refines first rfl).containsKey_of_ok (by decide))) rfl
    ((appendLogical_refines second rfl).preserves_containsKey
      ((appendLogical_refines first rfl).preserves_containsKey
        ((appendLogical_refines child rfl).containsKey_of_ok (by decide))))

run_elab do
  for name in #[``ParentAdvanced.preserved, ``ParentAdvanced.of_inserted,
      ``ParentsFor.nil, ``ParentsFor.preserved, ``ParentsFor.step, ``ParentsComplete.advance,
      ``CompletionStep.of_terminal, ``CompletionStep.of_nonterminal, ``CompletionStep.of_finished,
      ``CompletionsFor.nil, ``CompletionsFor.preserved, ``CompletionsFor.step,
      ``ChartCompleted.complete, ``ChartCompleted.preserved,
      ``CompletionsBefore.zero, ``CompletionsBefore.advance,
      ``RecognizesSymbol.start_le_finish, ``RecognizesSequence.start_le_finish,
      ``EarleyStateSound.origin_le_position, ``ChartClosed.of_phases] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Parent completion theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Parent completion covers dynamically appended nullable parents, rejects premature exhaustion and missing advances, and accepts duplicates at capacity; pure lemmas use only standard Lean axioms."
  Lean.logInfo "Whole-state completion accumulates both processing orders through a growing nullable chart and rejects omitted replay; phase assembly and span lemmas use only standard Lean axioms."

end Lanius.Extraction.Tests.Parser.Completion
