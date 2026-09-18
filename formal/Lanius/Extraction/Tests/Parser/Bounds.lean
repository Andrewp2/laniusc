import Lanius.Extraction.Frontend.Frame
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Parser.Bounds
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

-- Only production 0 is reachable. Production 1 has a valid empty prefix
-- but no initialization/prediction path from the start nonterminal.
private def grammar : IndexedGrammar := {
  grammar := {
    n_kinds := 1, n_nonterminals := 2, start_nonterminal := 0,
    split_token_kind := 9, split_component_kind := 7, canonical_kinds := [7],
    productions := [⟨0, []⟩, ⟨1, []⟩] },
  productionsByLhs := [[0], [1]] }

private def one := (appendLogical 1 0 (freshSeed 0 0) emptyWorkspace).2
private theorem oneValid : WorkspaceWellFormed one :=
  (appendLogical_refines _ rfl).preserves_well_formed emptyWorkspace_wellFormed
private theorem oneGenerated : WorkspaceGenerated grammar [] one :=
  (appendLogical_refines _ rfl).preserves_generated emptyWorkspace_generated
    (GeneratedItem.seed (grammar := grammar) (tokens := []) ⟨0, by decide⟩ rfl)

private theorem rhsEmpty (production : Fin grammar.productionCount) :
    (grammar.productionAt production).rhs = [] := by
  rcases production with ⟨id, bound⟩
  have small : id < 2 := bound
  match id with
  | 0 => rfl
  | 1 => rfl
  | _ + 2 => omega

private theorem oneClosed : ChartClosed grammar [] one where
  seed production start := by
    rcases production with ⟨id, bound⟩
    have small : id < 2 := bound
    match id with
    | 0 => exact ⟨0, (freshSeed 0 0).atPosition 0, by decide, rfl, rfl⟩
    | 1 => change 1 = 0 at start; omega
    | _ + 2 => omega
  predict parent child dot origin position waiting expected := by
    simp only [rhsEmpty, List.getElem?_nil, reduceCtorEq] at expected
  scan production dot origin position kind finish waiting expected terminal scanned := by
    simp only [rhsEmpty, List.getElem?_nil, reduceCtorEq] at expected
  complete parent child dot origin middle finish waiting expected finished := by
    simp only [rhsEmpty, List.getElem?_nil, reduceCtorEq] at expected

example : one.states.length ≤ 1 :=
  oneGenerated.length_le oneValid oneClosed oneValid.chartSound

example : EarleyStateSound grammar [] ((freshSeed 1 0).atPosition 0) :=
  freshSeed_sound (by decide)

-- This distinguishes the new source-generation requirement from the old,
-- overly permissive language-sound-prefix bound.
example : ¬ GeneratedItem grammar [] 0 ⟨1, 0, 0⟩ := by
  intro generated
  have absent := LogicalWorkspace.findStateId?_none_iff.mp
    (show one.findStateId? 0 ⟨1, 0, 0⟩ = none from by decide)
  exact absent (generated one oneClosed)

example : ¬ GeneratedItem grammar [] 4 ⟨0, 0, 4⟩ := by
  intro generated
  have absent := LogicalWorkspace.findStateId?_none_iff.mp
    (show one.findStateId? 4 ⟨0, 0, 4⟩ = none from by decide)
  exact absent (generated one oneClosed)

-- A real source call on this language succeeds if the one-state envelope
-- fits. The caller supplies neither source-parser success nor chart closure
-- for the returned workspace.
example (execution : RecognizerCallExecution grammarLayout grammar words []
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (fits : 1 < workspaceLayout.capacity) :
    parseResultStatus? execution.outcome.resultValue = some 0 := by
  apply execution.success_of_closed_bound
    (.nonterminal (nonterminal := 0) (productionId := 0) (by decide) (by decide) rfl .empty)
    oneClosed oneValid.chartSound
  exact fits

run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``GeneratedItem.seed, ``GeneratedItem.predict, ``GeneratedItem.scan,
      ``GeneratedItem.complete, ``Append.preserves_generated,
      ``WorkspaceWellFormed.itemKeys_nodup, ``WorkspaceGenerated.length_le,
      ``WorkspaceBackpointersSound.generated, ``RecognizerInitialContinuationOutcome.generated,
      ``RecognizerCallExecution.generated, ``RecognizerCallExecution.states_le_closed,
      ``RecognizerCallExecution.not_full_of_closed_bound, ``RecognizerCallExecution.success_of_closed_bound,
      ``Frontend.syntaxPost.capacity_generated, ``Frontend.bodyPost.no_parser_capacity_of_closed_bound] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Closed-chart bound {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Closed charts bound source-generated states; unreachable productions/positions cannot masquerade as generated items, and a concrete small envelope guarantees source-parser success."

end Lanius.Extraction.Tests.Parser.Bounds
