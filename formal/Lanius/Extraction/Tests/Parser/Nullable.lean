import Lanius.Compiler.Parser.Completion.Pairs
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Parser.Nullable
open Lanius.Compiler.Parser

-- S → A; A → ε | t; B → ε. The empty child is already present
-- when the waiting parent is processed.
private def grammar : IndexedGrammar := {
  grammar := {
    n_kinds := 1, n_nonterminals := 3, start_nonterminal := 0
    split_token_kind := 9, split_component_kind := 7, canonical_kinds := [7]
    productions := [⟨0, [2]⟩, ⟨1, []⟩, ⟨1, [0]⟩, ⟨2, []⟩] }
  productionsByLhs := [[0], [1, 2], [3]] }

private def child := appendLogical 3 0 (freshSeed 1 0) emptyWorkspace
private def parent := appendLogical 3 0 (freshSeed 0 0) child.2
private def advancedSeed := ((freshSeed 0 0).atPosition 0).advanceSeed 1 (.state 0)
private def replayed := appendLogical 3 0 advancedSeed parent.2
private def advanced : StateKey := ⟨0, 1, 0⟩

private theorem covered : NullablesComplete grammar replayed.2 0 1 advanced :=
  NullablesFor.of_advanced ((appendLogical_refines replayed rfl).containsKey_of_ok (by decide))

-- The child has already been processed before the waiting parent is even
-- inserted. Its processed-prefix guarantee remains true, without pretending
-- it already covers that future parent. The parent's own replay closes the pair.
private theorem processedChild : CompletionsFor grammar child.2 0 [0] := by
  let cursor : ChartCursor (child.2.chart 0) 0 [] := ChartCursor.atHead 0 []
  apply CompletionsFor.step (position := 0) cursor cursor
    (WorkspaceAppendClosure.refl (capacity := 3) child.2)
    ((appendLogical_refines child rfl).preserves_well_formed emptyWorkspace_wellFormed).chartSound
    ((appendLogical_refines child rfl).preserves_well_formed emptyWorkspace_wellFormed).chartSound
    (fun _ earlier => by omega) CompletionsFor.nil
  intro state found
  have same : (freshSeed 1 0).atPosition 0 = state := Option.some.inj found
  subst state
  apply CompletionStep.of_finished (by decide) rfl
  intro id listed parent found bound expected
  have sameId : id = 0 := List.mem_singleton.mp listed
  subst id
  have same := Option.some.inj found
  subst parent
  contradiction

example : CompletionsFor grammar replayed.2 0 [0, 1] := by
  have childWF := (appendLogical_refines child rfl).preserves_well_formed emptyWorkspace_wellFormed
  have parentWF := (appendLogical_refines parent rfl).preserves_well_formed childWF
  have replayedWF := (appendLogical_refines replayed rfl).preserves_well_formed parentWF
  have retained := processedChild.preserved (WorkspaceAppendClosure.single 3 0 (freshSeed 0 0) child.2)
    childWF.chartSound parentWF.chartSound (fun _ listed => listed) (fun _ earlier => by omega)
  let beforeCursor : ChartCursor (parent.2.chart 0) 1 [] :=
    (ChartCursor.atHead 0 [1]).next (parentWF.chartIdsUnique 0)
  let afterCursor : ChartCursor (replayed.2.chart 0) 1 [2] :=
    (ChartCursor.atHead 0 [1, 2]).next (replayedWF.chartIdsUnique 0)
  apply CompletionsFor.step (position := 0) beforeCursor afterCursor
    (WorkspaceAppendClosure.single 3 0 advancedSeed parent.2)
    parentWF.chartSound replayedWF.chartSound (fun _ earlier => by omega) retained
  intro state found
  have same : (freshSeed 0 0).atPosition 0 = state := Option.some.inj found
  subst state
  exact CompletionStep.of_nonterminal (expected := 1) (by decide) rfl covered

example : replayed.2.containsKey 0 advanced :=
  covered.advance ⟨1, by decide⟩
    ((appendLogical_refines replayed rfl).preserves_containsKey
      ((appendLogical_refines parent rfl).preserves_containsKey
        ((appendLogical_refines child rfl).containsKey_of_ok (by decide)))) rfl

-- A skipped match is not complete; exhausting capacity does not repair it.
example : ¬ NullablesComplete grammar parent.2 0 1 advanced := by
  intro complete
  have present := complete.advance ⟨1, by decide⟩
    ((appendLogical_refines parent rfl).preserves_containsKey
      ((appendLogical_refines child rfl).containsKey_of_ok (by decide))) rfl
  exact (parent.2.findStateId?_none_iff.mp (by decide)) present
example : (appendLogical 2 0 advancedSeed parent.2).1.status = .full := by decide

private def duplicate := appendLogical 3 0 advancedSeed replayed.2
example : duplicate.1.status = .ok := by decide
example : NullablesComplete grammar duplicate.2 0 1 advanced :=
  NullablesFor.of_advanced ((appendLogical_refines duplicate rfl).containsKey_of_ok (by decide))

-- Further chart growth does not invalidate a replay that retained the key.
private def later := appendLogical 4 0 (freshSeed 3 0) replayed.2
example : NullablesComplete grammar later.2 0 1 advanced :=
  NullablesFor.of_advanced ((appendLogical_refines later rfl).preserves_containsKey
    ((appendLogical_refines replayed rfl).containsKey_of_ok (by decide)))

example : NullableChild grammar 0 1 ((freshSeed 1 0).atPosition 0) :=
  ⟨by decide, rfl, rfl, rfl⟩
example : ¬ NullableChild grammar 0 1 ((freshSeed 3 0).atPosition 0) := by
  rintro ⟨bound, _, _, wrongLhs⟩
  change 2 = 1 at wrongLhs
  contradiction
example : ¬ NullableChild grammar 0 1 ((freshSeed 2 0).atPosition 0) := by
  rintro ⟨bound, _, unfinished, _⟩
  contradiction
example : ¬ NullableChild grammar 2 1
    ((((freshSeed 2 0).atPosition 0).advanceSeed 0 (.token 0 0)).atPosition 2) := by
  rintro ⟨bound, nonzeroWidth, _, _⟩
  contradiction

-- An exhausted traversal containing only a nonmatching waiting item needs
-- no advanced key. This exercises the negative-predicate accumulation path.
private def waiting := appendLogical 1 0 (freshSeed 0 0) emptyWorkspace
example : NullablesComplete grammar waiting.2 0 1 advanced := by
  change NullablesFor grammar waiting.2 0 1 advanced [0]
  apply NullablesFor.step (position := 0) (capacity := 1)
    (ChartCursor.atHead 0 []) (ChartCursor.atHead 0 []) (.refl waiting.2)
    ((appendLogical_refines waiting rfl).preserves_well_formed emptyWorkspace_wellFormed).chartSound
    NullablesFor.nil
  intro state found ⟨bound, origin, finished, lhs⟩
  have same : (freshSeed 0 0).atPosition 0 = state := Option.some.inj found
  subst state
  contradiction

run_elab do
  for name in #[``NullablesFor.nil, ``NullablesFor.of_advanced, ``NullablesFor.preserved,
      ``NullablesFor.step, ``NullablesComplete.advance] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Nullable replay theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Nullable replay covers earlier children, duplicate/full capacity, later growth, nonmatches, wrong nonterminals, unfinished states, and nonzero-width children; pure lemmas use only standard Lean axioms."

end Lanius.Extraction.Tests.Parser.Nullable
