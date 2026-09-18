import Lanius.Extraction.Entry.Domain.Syntax
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Storage.Parser
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserResult

private def first := appendLogical 1 0 (freshSeed 0 0) emptyWorkspace
private def duplicate := appendLogical 1 0 (freshSeed 0 0) first.2
private def overflow := appendLogical 1 4 (freshSeed 1 4) first.2
private def layout : WorkspaceLayout := ⟨2, 19, by decide, by decide, by decide⟩

-- Insertion at the last available slot succeeds; only an absent item can
-- exhaust it. Repeating an existing item must still succeed at capacity.
example : first.1.status = .ok ∧ first.1.inserted = true ∧ first.1.stateCount = 1 := by decide
example : duplicate.1.status = .ok ∧ duplicate.1.inserted = false ∧ duplicate.1.stateCount = 1 := by decide
example : overflow.1.status = .full ∧ overflow.1.stateCount = 1 := by decide
example : (appendLogical 2 4 (freshSeed 1 4) first.2).1.status = .ok := by decide

private theorem full : WorkspaceFull layout.capacity first.2 1 :=
  appendLogical.full_workspace (show overflow.1.status = .full from by decide)

example : WorkspaceFull 0 emptyWorkspace 0 :=
  appendLogical.full_workspace
    (show (appendLogical 0 0 (freshSeed 0 0) emptyWorkspace).1.status = .full from by decide)

-- Neither an underfull workspace nor a forged diagnostic count can supply
-- the witness, even if the caller writes a capacity status into a result.
example : ¬ WorkspaceFull 2 first.2 1 := fun witness => witness.excludes_bound (by decide)
example : ¬ WorkspaceFull 1 first.2 7 := by
  intro witness
  have count := witness.count
  change 7 = 1 at count
  omega

private def grammar : IndexedGrammar := {
  grammar := {
    n_kinds := 1, n_nonterminals := 1, start_nonterminal := 0,
    split_token_kind := 9, split_component_kind := 7, canonical_kinds := [7],
    productions := [⟨0, []⟩] },
  productionsByLhs := [[0]] }

private theorem firstGenerated : WorkspaceGenerated grammar tokens first.2 :=
  (appendLogical_refines _ rfl).preserves_generated emptyWorkspace_generated
    (GeneratedItem.seed (grammar := grammar) (tokens := tokens) ⟨0, by decide⟩ rfl)

section
variable (grammarLayout : PackedGrammarLayout) (words : List Int) (tokens : List Nat)

private def initial : RecognizerInitialContinuationOutcome grammarLayout grammar words tokens layout
    (parserCapacityCompletion 0 1) := .full 1 first.2 full firstGenerated

private def position : RecognizerInitialContinuationOutcome grammarLayout grammar words tokens layout
    (parserCapacityCompletion 4 1) :=
  .seeded emptyWorkspace [] _ (.full 4 1 first.2 full firstGenerated)

-- Both public exits carry the same actual workspace and the exact result
-- fields. These fixtures exercise the return contract, not native execution.
example : (initial grammarLayout words tokens).resultValue = parseResultValue 2 1 (-1) 0 := rfl
example : (position grammarLayout words tokens).resultValue = parseResultValue 2 1 (-1) 4 := rfl

example : ∃ errorPosition : Nat,
    (initial grammarLayout words tokens).resultValue =
      parseResultValue 2 first.2.states.length (-1) errorPosition ∧
    layout.capacity ≤ first.2.states.length :=
  (initial grammarLayout words tokens).capacity_result rfl rfl

example : ∃ errorPosition : Nat,
    (position grammarLayout words tokens).resultValue =
      parseResultValue 2 first.2.states.length (-1) errorPosition ∧
    layout.capacity ≤ first.2.states.length :=
  (position grammarLayout words tokens).capacity_result rfl rfl

example : ¬ (position grammarLayout words tokens).workspaceAgrees emptyWorkspace := by
  intro agreement
  change first.2 = emptyWorkspace at agreement
  have count := congrArg (fun workspace => workspace.states.length) agreement
  change 1 = 0 at count
  omega
end

run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``WorkspaceFull.capacity_le_states, ``WorkspaceFull.excludes_bound,
      ``appendLogical.full_workspace, ``RecognizerInitialContinuationOutcome.capacity_result,
      ``RecognizerCallExecution.capacity_result, ``RecognizerCallExecution.capacity_exhausted,
      ``Frontend.syntaxPost.capacity_result, ``Frontend.bodyPost.parser_capacity] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Capacity evidence {name} adds unexpected axiom {assumption}"
  let baseline ← Lean.collectAxioms ``Frontend.CheckedSyntax.call_evaluates
  for name in #[``RecognizerInitialConfig.functional_run,
      ``RecognizerPredictionConfig.functional_run, ``RecognizerParentConfig.functional_run,
      ``RecognizerNullableConfig.functional_run, ``RecognizerStateConfig.functional_run,
      ``RecognizerPositionConfig.functional_run, ``executeRecognizerCall] do
    for assumption in ← Lean.collectAxioms name do
      unless baseline.contains assumption || standard.contains assumption do
        throwError "Source capacity evidence {name} adds assumption outside frontend baseline: {assumption}"
  Lean.logInfo "Parser capacity evidence covers zero/last-slot capacity, duplicate insertion, forged counts, both public exits, and wrong-workspace rejection; new theorems use standard Lean axioms."
  Lean.logInfo "Actual source loops and call construction add no assumptions beyond the inherited frontend baseline."

end Lanius.Extraction.Tests.Storage.Parser
