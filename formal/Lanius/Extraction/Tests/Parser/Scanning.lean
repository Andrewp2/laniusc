import Lanius.Compiler.Parser.Scanning
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Parser.Scanning
open Lanius.Compiler.Parser

-- S → t t | ε | S. Token 9 splits into two t's; token 7 consumes
-- a whole token. The two halves must advance different dot positions.
private def grammar : IndexedGrammar := {
  grammar := {
    n_kinds := 1, n_nonterminals := 1, start_nonterminal := 0
    split_token_kind := 9, split_component_kind := 7, canonical_kinds := [7]
    productions := [⟨0, [0, 0]⟩, ⟨0, []⟩, ⟨0, [1]⟩] }
  productionsByLhs := [[0, 1, 2]] }

private def initial := appendLogical 3 0 (freshSeed 0 0) emptyWorkspace
private def firstSeed := ((freshSeed 0 0).atPosition 0).advanceSeed 0 (.token 0 0)
private def first := appendLogical 3 1 firstSeed initial.2
private def secondSeed := (firstSeed.atPosition 1).advanceSeed 1 (.token 0 0)
private def second := appendLogical 3 2 secondSeed first.2

private theorem initialWF : WorkspaceWellFormed initial.2 :=
  (appendLogical_refines initial rfl).preserves_well_formed emptyWorkspace_wellFormed
private theorem firstWF : WorkspaceWellFormed first.2 :=
  (appendLogical_refines first rfl).preserves_well_formed initialWF
private theorem secondWF : WorkspaceWellFormed second.2 :=
  (appendLogical_refines second rfl).preserves_well_formed firstWF

private theorem firstScanned : ChartScanned grammar [9] first.2 0 := by
  change ScansFor grammar [9] first.2 0 [0]
  apply ScansFor.step (position := 0) (ChartCursor.atHead 0 []) (ChartCursor.atHead 0 [])
    (WorkspaceAppendClosure.single 3 1 firstSeed initial.2) initialWF.chartSound ScansFor.nil
  intro state found
  have same : (freshSeed 0 0).atPosition 0 = state := Option.some.inj found
  subst state
  apply ScansComplete.of_terminal (by decide) rfl
  intro finish matched
  have sameFinish : 1 = finish := Option.some.inj matched
  subst finish
  exact (appendLogical_refines first rfl).containsKey_of_ok (by decide)

private theorem secondScanned : ChartScanned grammar [9] second.2 1 := by
  change ScansFor grammar [9] second.2 1 [1]
  apply ScansFor.step (position := 1) (ChartCursor.atHead 1 []) (ChartCursor.atHead 1 [])
    (WorkspaceAppendClosure.single 3 2 secondSeed first.2) firstWF.chartSound ScansFor.nil
  intro state found
  have same : firstSeed.atPosition 1 = state := Option.some.inj found
  subst state
  apply ScansComplete.of_terminal (by decide) rfl
  intro finish matched
  have sameFinish : 2 = finish := Option.some.inj matched
  subst finish
  exact (appendLogical_refines second rfl).containsKey_of_ok (by decide)

private theorem finalScanned : ChartScanned grammar [9] second.2 2 := by
  intro id listed state found
  have sameId : id = 2 := List.mem_singleton.mp listed
  subst id
  have same : secondSeed.atPosition 2 = state := Option.some.inj found
  subst state
  exact ScansComplete.of_finished (by decide) (by decide)

private theorem allScanned : ScansBefore grammar [9] second.2 3 := by
  have atOne := ScansBefore.advance ScansBefore.zero
    (WorkspaceAppendClosure.single 3 1 firstSeed initial.2) initialWF.chartSound
    ((appendLogical_chartsUnchangedBefore 3 1 firstSeed initial.2).weaken (by decide)) firstScanned
  have atTwo := atOne.advance (WorkspaceAppendClosure.single 3 2 secondSeed first.2) firstWF.chartSound
    ((appendLogical_chartsUnchangedBefore 3 2 secondSeed first.2).weaken (by decide)) secondScanned
  exact atTwo.advance (capacity := 3) (.refl second.2) secondWF.chartSound
    ChartsUnchangedBefore.refl finalScanned

example : second.2.containsKey 2 ⟨0, 2, 0⟩ :=
  (allScanned 1 (by decide)).scan ⟨0, by decide⟩ 1 0 0 2
    ((appendLogical_refines second rfl).preserves_containsKey
      ((appendLogical_refines first rfl).containsKey_of_ok (by decide))) rfl (by decide) rfl

-- A duplicate scan is still complete even when no fresh state can fit.
private def duplicate := appendLogical 2 1 firstSeed first.2
example : duplicate.1.status = .ok := by decide
example : ChartScanned grammar [9] duplicate.2 0 :=
  firstScanned.preserved (WorkspaceAppendClosure.single 2 1 firstSeed first.2)
    firstWF.chartSound rfl

-- Matching without retaining the advanced item is not scan closure. A
-- capacity return leaves exactly that incomplete workspace unchanged.
example : (appendLogical 1 1 firstSeed initial.2).1.status = .full := by decide
example : ¬ ChartScanned grammar [9] initial.2 0 := by
  intro scanned
  obtain ⟨id, state, listed, _, _⟩ := scanned.scan ⟨0, by decide⟩ 0 0 0 1
    ((appendLogical_refines initial rfl).containsKey_of_ok (by decide)) rfl (by decide) rfl
  change id ∈ [] at listed
  cases listed

example : ScansComplete grammar [] initial.2 0 0 0 0 :=
  ScansComplete.of_miss (by decide) rfl rfl
example : ScansComplete grammar [7] initial.2 1 0 0 0 :=
  ScansComplete.of_miss (by decide) rfl rfl
example : ScansComplete grammar [9] initial.2 0 2 0 0 :=
  ScansComplete.of_nonterminal (by decide) rfl (by decide)
example : ScansComplete grammar [9] initial.2 0 1 0 0 :=
  ScansComplete.of_finished (by decide) (by decide)
example : scanTerminal grammar [7] 0 0 = some 2 := rfl
example : scanTerminal grammar [7, 9] 3 0 = some 4 := rfl
example : scanTerminal grammar [9] 2 0 = none := rfl

run_elab do
  for name in #[``ScansComplete.preserved, ``ScansComplete.of_terminal,
      ``ScansComplete.of_miss, ``ScansComplete.of_nonterminal, ``ScansComplete.of_finished,
      ``ScansFor.preserved, ``ScansFor.step, ``ChartScanned.scan, ``ChartScanned.preserved,
      ``ScansBefore.zero, ``ScansBefore.advance] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Scan completeness theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Scan closure covers both split halves, later-chart preservation, duplicates at capacity, missing advances, misses, finished/nonterminal states, and lattice boundaries; pure lemmas use only standard Lean axioms."

end Lanius.Extraction.Tests.Parser.Scanning
