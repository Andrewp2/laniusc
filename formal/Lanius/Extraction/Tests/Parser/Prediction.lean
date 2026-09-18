import Lanius.Compiler.Parser.Prediction
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Parser.Prediction
open Lanius.Compiler.Parser

-- S → A; A → ε | t A. Prediction must include both the nullable and recursive
-- alternatives, with origins at the current (nonzero) lattice position.
private def grammar : IndexedGrammar := {
  grammar := {
    n_kinds := 1, n_nonterminals := 2, start_nonterminal := 0
    split_token_kind := 9, split_component_kind := 7, canonical_kinds := [7]
    productions := [⟨0, [2]⟩, ⟨1, []⟩, ⟨1, [0, 2]⟩] }
  productionsByLhs := [[0], [1, 2]] }

private def first := appendLogical 2 3 (freshSeed 1 3) emptyWorkspace
private def second := appendLogical 2 3 (freshSeed 2 3) first.2

private theorem seeded : Seeded second.2 3 (grammar.productionIdsFor 1) := by
  have initial : Seeded emptyWorkspace 3 [] := by simp [Seeded]
  have one := initial.append (appendLogical_refines first rfl) (by decide)
  exact one.append (appendLogical_refines second rfl) (by decide)

private theorem predicted : PredictionsComplete grammar second.2 3 0 0 :=
  seeded.predictionsComplete (by decide) rfl

example : second.2.containsKey 3 ⟨1, 0, 3⟩ := predicted (by decide) ⟨1, by decide⟩ rfl
example : second.2.containsKey 3 ⟨2, 0, 3⟩ := predicted (by decide) ⟨2, by decide⟩ rfl

-- A later replay may exhaust capacity without undoing completed prediction.
example : (appendLogical 2 3 (freshSeed 0 3) second.2).1.status = .full := by decide
example : PredictionsComplete grammar (appendLogical 2 3 (freshSeed 0 3) second.2).2 3 0 0 :=
  predicted.preserved (WorkspaceAppendClosure.single 2 3 (freshSeed 0 3) second.2)

-- Scanning/completion into another chart also cannot erase this obligation.
example : PredictionsComplete grammar (appendLogical 3 4 (freshSeed 0 4) second.2).2 3 0 0 :=
  predicted.preserved (WorkspaceAppendClosure.single 3 4 (freshSeed 0 4) second.2)

-- Terminal and completed items require no child predictions.
example : PredictionsComplete grammar emptyWorkspace 3 2 0 :=
  PredictionsComplete.of_terminal (by decide) rfl (by decide)
example : PredictionsComplete grammar emptyWorkspace 3 1 0 :=
  PredictionsComplete.of_finished (by decide) (by decide)

private def missingAlternative : LogicalWorkspace := {
  chart := fun position => if position = 3 then [0] else []
  states := [(freshSeed 1 3).atPosition 3] }

-- Inserting one valid alternative is not enough to claim prediction complete.
example : ¬ PredictionsComplete grammar missingAlternative 3 0 0 := by
  intro complete
  obtain ⟨id, state, listed, found, key⟩ := complete (by decide) ⟨2, by decide⟩ rfl
  have idEq : id = 0 := by simpa [missingAlternative] using listed
  subst id
  have stateEq : (freshSeed 1 3).atPosition 3 = state := Option.some.inj found
  subst state
  have impossible := congrArg StateKey.production key
  simp [EarleyState.key, StateSeed.atPosition, freshSeed] at impossible

-- Start with a one-item chart. Processing its parent appends two children;
-- neither child may be mistaken for an already-visited item or skipped by
-- treating the original tail as the final tail.
private def parent := appendLogical 3 3 (freshSeed 0 3) emptyWorkspace
private def addedOne := appendLogical 3 3 (freshSeed 1 3) parent.2
private def grown := appendLogical 3 3 (freshSeed 2 3) addedOne.2

private theorem growth : WorkspaceAppendClosure 3 parent.2 grown.2 :=
  (WorkspaceAppendClosure.single 3 3 (freshSeed 1 3) parent.2).trans
    (WorkspaceAppendClosure.single 3 3 (freshSeed 2 3) addedOne.2)

private def beforeCursor : ChartCursor (parent.2.chart 3) 0 [] := ChartCursor.atHead 0 []
private def grownCursor : ChartCursor (grown.2.chart 3) 0 [1, 2] := ChartCursor.atHead 0 [1, 2]
private def childCursor := grownCursor.next (by decide)
private def lastCursor := childCursor.next (by decide)

private theorem grownWellFormed : WorkspaceWellFormed grown.2 :=
  growth.preserves_well_formed
    ((appendLogical_refines parent rfl).preserves_well_formed emptyWorkspace_wellFormed)

example : grownCursor.visited = beforeCursor.visited :=
  beforeCursor.visited_eq_of_growth grownCursor growth

example : ¬ Nonempty (ChartCursor (grown.2.chart 3) 0 []) := by
  intro ⟨cursor⟩
  have stopped := cursor.nextAfter
  change some 1 = (none : Option Nat) at stopped
  cases stopped

private theorem grownPredictions : ChartPredicted grammar grown.2 3 := by
  have parentWellFormed := (appendLogical_refines parent rfl).preserves_well_formed emptyWorkspace_wellFormed
  have grownWellFormed := growth.preserves_well_formed parentWellFormed
  have initial : Seeded parent.2 3 [] := by simp [Seeded]
  have one := initial.append (appendLogical_refines addedOne rfl) (by decide)
  have both : Seeded grown.2 3 (grammar.productionIdsFor 1) :=
    one.append (appendLogical_refines grown rfl) (by decide)
  have processedParent : PredictionsFor grammar grown.2 3 childCursor.visited := by
    apply PredictionsFor.step beforeCursor grownCursor growth parentWellFormed.chartSound PredictionsFor.nil
    intro state found
    have same : (freshSeed 0 3).atPosition 3 = state := Option.some.inj found
    subst state
    exact both.predictionsComplete (by decide) rfl
  have processedChild : PredictionsFor grammar grown.2 3 lastCursor.visited := by
    apply PredictionsFor.step (capacity := 3) childCursor childCursor (.refl grown.2)
      grownWellFormed.chartSound processedParent
    intro state found
    have same : (freshSeed 1 3).atPosition 3 = state := Option.some.inj found
    subst state
    exact PredictionsComplete.of_finished (by decide) (by decide)
  apply PredictionsFor.step (capacity := 3) lastCursor lastCursor (.refl grown.2)
    grownWellFormed.chartSound processedChild
  intro state found
  have same : (freshSeed 2 3).atPosition 3 = state := Option.some.inj found
  subst state
  exact PredictionsComplete.of_terminal (by decide) rfl (by decide)

example : grown.2.containsKey 3 ⟨2, 0, 3⟩ :=
  grownPredictions.predict ⟨0, by decide⟩ ⟨2, by decide⟩ 0 3
    ⟨0, (freshSeed 0 3).atPosition 3, by decide, rfl, rfl⟩ rfl

-- Completing a later chart must preserve the full earlier-chart guarantee,
-- not just the states that happened to exist before prediction began.
private theorem grownStable : ChartsUnchangedBefore 3 emptyWorkspace grown.2 :=
  (appendLogical_chartsUnchangedBefore 3 3 (freshSeed 0 3) emptyWorkspace).trans
    ((appendLogical_chartsUnchangedBefore 3 3 (freshSeed 1 3) parent.2).trans
      (appendLogical_chartsUnchangedBefore 3 3 (freshSeed 2 3) addedOne.2))

private theorem throughThree : PredictionsBefore grammar grown.2 4 := by
  have earlier : PredictionsBefore grammar grown.2 3 := by
    intro position bound
    unfold ChartPredicted
    rw [grownStable position bound]
    exact PredictionsFor.nil
  exact earlier.advance (capacity := 3) (.refl grown.2) grownWellFormed.chartSound
    ChartsUnchangedBefore.refl grownPredictions

private def later := appendLogical 4 4 (freshSeed 1 4) grown.2

private theorem laterPredicted : ChartPredicted grammar later.2 4 := by
  intro id listed state found
  have sameId : id = 3 := List.mem_singleton.mp listed
  subst id
  have same : (freshSeed 1 4).atPosition 4 = state := Option.some.inj found
  subst state
  exact PredictionsComplete.of_finished (by decide) (by decide)

private theorem throughFour : PredictionsBefore grammar later.2 5 :=
  throughThree.advance (WorkspaceAppendClosure.single 4 4 (freshSeed 1 4) grown.2)
    grownWellFormed.chartSound (appendLogical_chartsUnchangedBefore 4 4 (freshSeed 1 4) grown.2)
    laterPredicted

example : ChartPredicted grammar later.2 3 := throughFour 3 (by decide)
example : ChartPredicted grammar later.2 4 := throughFour 4 (by decide)

-- The current chart is allowed to grow; an earlier chart is not. A unique
-- backward insertion must be caught even though it preserves all old items.
example : later.2.chart 4 ≠ grown.2.chart 4 := by decide
example : ¬ ChartsUnchangedBefore 4 grown.2
    (appendLogical 4 3 (freshSeed 0 2) grown.2).2 := by
  intro stable
  have unchanged := stable 3 (by decide)
  change [0, 1, 2, 3] = [0, 1, 2] at unchanged
  contradiction

run_elab do
  for name in #[``PredictionsComplete.preserved, ``Seeded.predictionsComplete,
      ``PredictionsComplete.of_terminal, ``PredictionsComplete.of_finished,
      ``Append.chart_prefix, ``WorkspaceAppendClosure.chart_prefix,
      ``ChartCursor.visited_eq_takeWhile, ``ChartCursor.visited_eq,
      ``ChartCursor.visited_nil_of_head, ``ChartCursor.visited_eq_of_growth,
      ``PredictionsFor.preserved, ``PredictionsFor.step, ``ChartPredicted.predict,
      ``ChartsUnchangedBefore.refl, ``ChartsUnchangedBefore.trans,
      ``ChartsUnchangedBefore.weaken, ``Append.chartsUnchangedBefore,
      ``appendLogical_chartsUnchangedBefore, ``ChartPredicted.preserved,
      ``PredictionsBefore.zero, ``PredictionsBefore.advance] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Prediction completeness theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Prediction checks cover nullable/recursive alternatives, nonzero origins, later capacity failure, remote growth, and an omitted alternative; pure lemmas use only standard Lean axioms."
  Lean.logInfo "Growing-chart regression processes both newly appended children and rejects stopping at the old tail; prefix accumulation and chart-wide prediction use only standard Lean axioms."
  Lean.logInfo "Later-position accumulation preserves complete earlier charts, allows current-chart growth, and rejects backward insertion; the preservation lemmas use only standard Lean axioms."

end Lanius.Extraction.Tests.Parser.Prediction
