import Lanius.Compiler.Parser.Seeding
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Parser.Seeding
open Lanius.Compiler.Parser

private def first := appendLogical 1 0 (freshSeed 4 0) emptyWorkspace
private def duplicate := appendLogical 1 0 (freshSeed 4 0) first.2
private def overflow := appendLogical 1 0 (freshSeed 5 0) first.2

-- Full capacity must not prevent a duplicate from satisfying the next row.
example : first.1.status = .ok := by decide
example : duplicate.1.status = .ok ∧ duplicate.1.inserted = false := by decide
example : overflow.1.status = .full := by decide
example : (appendLogical 0 0 (freshSeed 4 0) emptyWorkspace).1.status = .full := by decide

private theorem initial : Seeded emptyWorkspace 0 [] := by simp [Seeded]
private theorem firstSeeded : Seeded first.2 0 [4] :=
  initial.append (appendLogical_refines _ rfl) (by decide)

example : Seeded duplicate.2 0 [4, 4] :=
  firstSeeded.append (appendLogical_refines _ rfl) (by decide)

example : Seeded overflow.2 0 [4] :=
  firstSeeded.preserved (WorkspaceAppendClosure.single 1 0 (freshSeed 5 0) first.2)

-- A nonzero packed-row offset and repeated production exercise exact prefix
-- accounting independently of the physical i32 access proof.
private def rows : List Nat := [99, 4, 4, 100]
example : Seeded first.2 0 ((rows.drop 1).take 1) :=
  (show Seeded emptyWorkspace 0 ((rows.drop 1).take 0) from initial).next (by decide) (by decide)

example : Seeded duplicate.2 0 ((rows.drop 1).take 2) :=
  (show Seeded first.2 0 ((rows.drop 1).take 1) from firstSeeded).next (by decide) (by decide)

-- Growth in another chart preserves the original chart item and its id.
example : Seeded (appendLogical 2 3 (freshSeed 8 3) first.2).2 0 [4] :=
  firstSeeded.preserved (WorkspaceAppendClosure.single 2 3 (freshSeed 8 3) first.2)

private def grammar : IndexedGrammar := {
  grammar := {
    n_kinds := 1, n_nonterminals := 4, start_nonterminal := 1
    split_token_kind := 9, split_component_kind := 7, canonical_kinds := [7]
    productions := [⟨0, []⟩, ⟨1, [0]⟩, ⟨3, []⟩, ⟨1, []⟩] }
  productionsByLhs := [[0], [1, 3], [], [2]] }

-- The packed-interval theorem applies to every row, including empty ones.
-- Grammar-index well-formedness is a separate obligation for source setup.
example : (grammar.lhsProductions.drop 1).take 2 = [1, 3] :=
  grammar.lhsProductions_row ⟨1, by decide⟩
example : (grammar.lhsProductions.drop 3).take 0 = [] :=
  grammar.lhsProductions_row ⟨2, by decide⟩
example : (3 : Nat) ∈ grammar.productionIdsFor 1 :=
  IndexedGrammar.productionIdsFor_contains ⟨3, by decide⟩ rfl

run_elab do
  for name in #[``Append.preserves_containsKey, ``Append.containsKey_of_ok,
      ``WorkspaceAppendClosure.preserves_containsKey, ``Seeded.preserved,
      ``Seeded.append, ``Seeded.next, ``IndexedGrammar.productionIdsFor_contains,
      ``IndexedGrammar.lhsProductions_row, ``Seeded.start, ``StartSeeded.preserved] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Seeding theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Seeding prefix, duplicate/full capacity, remote-chart growth, and packed-row boundaries checked with standard Lean axioms."

end Lanius.Extraction.Tests.Parser.Seeding
