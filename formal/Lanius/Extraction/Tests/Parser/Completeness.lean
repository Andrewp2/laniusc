import Lanius.Extraction.Parser.Recognize.Root.Selection
import Lanius.Extraction.Frontend.Frame
import Lanius.Extraction.Tests.Parser.Seeding
import Lanius.Extraction.Tests.Parser.Prediction
import Lanius.Extraction.Tests.Parser.Scanning
import Lanius.Extraction.Tests.Parser.Completion
import Lanius.Extraction.Tests.Parser.Nullable
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Parser.Completeness
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserResult

-- S → A t t | S t; A → ε. One physical token 9 splits into two t's.
private def grammar : IndexedGrammar := {
  grammar := {
    n_kinds := 1, n_nonterminals := 2, start_nonterminal := 0
    split_token_kind := 9, split_component_kind := 7, canonical_kinds := [7]
    productions := [⟨0, [2, 0, 0]⟩, ⟨1, []⟩, ⟨0, [1, 0]⟩] }
  productionsByLhs := [[0, 2], [1]] }

private theorem nullable (tokens : List Nat) : RecognizesSymbol grammar tokens 2 0 0 :=
  .nonterminal (nonterminal := 1) (productionId := 1) (by decide) (by decide) rfl .empty

private theorem splitPair (rest : List Nat) : RecognizesSymbol grammar (9 :: rest) 1 0 2 := by
  apply RecognizesSymbol.nonterminal (nonterminal := 0) (productionId := 0) (by decide) (by decide) rfl
  change RecognizesSequence grammar (9 :: rest) [2, 0, 0] 0 2
  exact .cons (nullable _) (.cons (.terminal (by decide) rfl) (.cons (.terminal (by decide) rfl) .empty))

private theorem recursiveInput : RecognizesInput grammar [9, 7] := by
  apply RecognizesSymbol.nonterminal (nonterminal := 0) (productionId := 2) (by decide) (by decide) rfl
  change RecognizesSequence grammar [9, 7] [1, 0] 0 4
  exact .cons (splitPair [7]) (.cons (.terminal (by decide) rfl) .empty)

-- Exercise the general theorem with zero-width and recursive derivations,
-- including a split terminal that starts at an odd lattice position.
example (closed : ChartClosed grammar [9] workspace) :
    ChartClosed.HasRoot grammar [9] workspace := closed.contains_root (splitPair [])

example (closed : ChartClosed grammar [9, 7] workspace) :
    ChartClosed.HasRoot grammar [9, 7] workspace := closed.contains_root recursiveInput

example : scanTerminal grammar [9] 0 0 = some 1 := rfl
example : scanTerminal grammar [9] 1 0 = some 2 := rfl
example : scanTerminal grammar [7] 1 0 = none := rfl

-- The runtime outcome is the existing source-linked root-search result,
-- not a fresh logical recognizer or a caller-assumed successful result.
example (outcome : RecognizerRootStatementOutcome grammar [9, 7] workspace completion)
    (closed : ChartClosed grammar [9, 7] workspace) :
    ∃ root : Nat,
      completion = .returned (some (parseResultValue 0 workspace.states.length root 0)) ∧
      Nonempty (StoredRootParse grammar [9, 7] workspace root) :=
  outcome.success_of_closed closed recursiveInput

private def epsilon : IndexedGrammar := {
  grammar := {
    n_kinds := 1, n_nonterminals := 1, start_nonterminal := 0
    split_token_kind := 9, split_component_kind := 7, canonical_kinds := [7]
    productions := [⟨0, []⟩] }
  productionsByLhs := [[0]] }

private def epsilonChart : LogicalWorkspace := {
  chart := fun position => if position = 0 then [0] else []
  states := [(freshSeed 0 0).atPosition 0] }

private theorem epsilonRhs (production : Fin epsilon.productionCount) :
    (epsilon.productionAt production).rhs = [] := by
  have zero : production.val = 0 := by have bound : production.val < 1 := production.isLt; omega
  obtain ⟨id, bound⟩ := production
  cases zero
  rfl

-- Construct an actual closed finite chart, so the positive tests do not
-- only quantify over an uninhabited closure premise.
private theorem epsilonClosed : ChartClosed epsilon [] epsilonChart where
  seed production lhs := by
    have zero : production.val = 0 := by have bound : production.val < 1 := production.isLt; omega
    refine ⟨0, (freshSeed 0 0).atPosition 0, by decide, rfl, ?_⟩
    simp [EarleyState.key, StateSeed.atPosition, freshSeed, zero]
  predict parent child dot origin position waiting expected := by
    simp only [epsilonRhs, List.getElem?_nil, reduceCtorEq] at expected
  scan production dot origin position kind finish waiting expected bounded scanned := by
    simp only [epsilonRhs, List.getElem?_nil, reduceCtorEq] at expected
  complete parent child dot origin middle finish waiting expected childReady := by
    simp only [epsilonRhs, List.getElem?_nil, reduceCtorEq] at expected

example : ChartClosed.HasRoot epsilon [] epsilonChart :=
  epsilonClosed.contains_root
    (.nonterminal (nonterminal := 0) (productionId := 0) (by decide) (by decide) rfl .empty)

-- For an empty start rule on empty input, the actual seeding guarantee alone
-- excludes rejection. This regression supplies no chart-closure or successful
-- execution premise; capacity exhaustion remains explicitly separate.
example (outcome : RecognizerInitialContinuationOutcome grammarLayout epsilon words [] workspaceLayout completion)
    (agreement : outcome.workspaceAgrees finalWorkspace)
    (notFull : parseResultStatus? outcome.resultValue ≠ some 2) :
    parseResultStatus? outcome.resultValue ≠ some 1 := by
  have seeded := outcome.startSeeded agreement notFull
  have root : ChartClosed.HasRoot epsilon [] finalWorkspace :=
    ⟨⟨0, by decide⟩, rfl, seeded ⟨0, by decide⟩ rfl⟩
  intro rejected
  exact (outcome.rejected_noRoot agreement rejected).not_hasRoot root

-- Omitting the required chart item must not become a complete chart merely
-- because the input has a valid grammar derivation.
example : ¬ ChartClosed grammar [9, 7] emptyWorkspace := by
  intro closed
  have absent : NoRootIn grammar emptyWorkspace (emptyWorkspace.chart (finalPosition 2)) := by
    intro id listed
    simp only [emptyWorkspace_chart, List.not_mem_nil] at listed
  exact absent.not_hasRoot (closed.contains_root recursiveInput)

private def terminals : IndexedGrammar := {
  grammar := {
    n_kinds := 1, n_nonterminals := 1, start_nonterminal := 0
    split_token_kind := 9, split_component_kind := 7, canonical_kinds := [7]
    productions := [⟨0, [0, 0]⟩] }
  productionsByLhs := [[0]] }

-- Seeding plus the actual whole-parser scan guarantee already excludes
-- rejection for this terminal-only language. This uses neither full chart
-- closure nor a pre-assumed successful result; capacity remains separate.
example (outcome : RecognizerInitialContinuationOutcome grammarLayout terminals words [9] workspaceLayout completion)
    (agreement : outcome.workspaceAgrees finalWorkspace)
    (notFull : parseResultStatus? outcome.resultValue ≠ some 2) :
    parseResultStatus? outcome.resultValue ≠ some 1 := by
  have start := outcome.startSeeded agreement notFull ⟨0, by decide⟩ rfl
  have scanned := outcome.scansComplete agreement notFull
  have first := (scanned 0 (by decide)).scan ⟨0, by decide⟩ 0 0 0 1 start rfl (by decide) rfl
  have second := (scanned 1 (by decide)).scan ⟨0, by decide⟩ 1 0 0 2 first rfl (by decide) rfl
  have root : ChartClosed.HasRoot terminals [9] finalWorkspace := ⟨⟨0, by decide⟩, rfl, second⟩
  intro rejected
  exact (outcome.rejected_noRoot agreement rejected).not_hasRoot root

-- Every normal source result, including rejection, supplies prediction at
-- any input position. No caller-provided chart-closure premise is needed.
example (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words tokens workspaceLayout completion)
    (agreement : outcome.workspaceAgrees finalWorkspace)
    (notFull : parseResultStatus? outcome.resultValue ≠ some 2)
    (position : Nat) (bound : position ≤ finalPosition tokens.length)
    (parent child : Fin grammar.productionCount) (dot origin : Nat)
    (waiting : finalWorkspace.containsKey position ⟨parent, dot, origin⟩)
    (expected : (grammar.productionAt parent).rhs[dot]? =
      some (grammar.grammar.n_kinds + (grammar.productionAt child).lhs)) :
    finalWorkspace.containsKey position ⟨child, 0, position⟩ :=
  (outcome.predictionsComplete agreement notFull position (by omega)).predict
    parent child dot origin waiting expected

-- A matching scan itself supplies the position bound; the public source
-- result supplies the advanced item in the actual final workspace.
example (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words tokens workspaceLayout completion)
    (agreement : outcome.workspaceAgrees finalWorkspace)
    (notFull : parseResultStatus? outcome.resultValue ≠ some 2)
    (production : Fin grammar.productionCount) (position dot origin kind finish : Nat)
    (waiting : finalWorkspace.containsKey position ⟨production, dot, origin⟩)
    (expected : (grammar.productionAt production).rhs[dot]? = some kind)
    (terminal : kind < grammar.grammar.n_kinds)
    (matched : scanTerminal grammar tokens position kind = some finish) :
    finalWorkspace.containsKey finish ⟨production, dot + 1, origin⟩ := by
  have upper := scanTerminal_some_le_finalPosition grammar tokens position kind finish matched
  have lower := scanTerminal_some_gt matched
  exact (outcome.scansComplete agreement notFull position (by omega)).scan
    production dot origin kind finish waiting expected terminal matched

-- The restored actual parent-loop outcome supplies coverage itself. The
-- caller selects a child from the input workspace but does not assume that
-- replay visited every parent or that any matching append succeeded.
example (outcome : RecognizerStateParentSynchronizedOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell stateCountCell cursorCell
      position current remaining completedLhs after physicalAfter .next)
    (selected : beforeWorkspace.state? current = some child) :
    ∃ workspace, WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace workspace ∧
      ∀ (parent : Fin grammar.productionCount) (dot origin : Nat),
        workspace.containsKey child.origin ⟨parent, dot, origin⟩ →
        (grammar.productionAt parent).rhs[dot]? = some (grammar.grammar.n_kinds + completedLhs) →
        workspace.containsKey position ⟨parent, dot + 1, origin⟩ := by
  rcases outcome.view with done | full
  · obtain ⟨_, workspace, values, growth, frame, worldEq, environmentEq, stable, parents⟩ := done
    exact ⟨workspace, growth, (parents child selected).advance⟩
  · obtain ⟨workspace, values, growth, terminal, count, wellFormed, _, impossible⟩ := full
    contradiction

-- The opposite processing order is covered by the actual nullable scope:
-- every already-finished zero-width child advances this waiting parent.
example (outcome : RecognizerStateNullableSynchronizedOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell stateCountCell cursorCell
      position current remaining parentProduction parentDot parentOrigin expected sourceCompletion
      after physicalAfter .next) :
    ∃ workspace, WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace workspace ∧
      ∀ child : Fin grammar.productionCount,
        workspace.containsKey position ⟨child, (grammar.productionAt child).rhs.length, position⟩ →
        (grammar.productionAt child).lhs = expected →
        workspace.containsKey position ⟨parentProduction, parentDot + 1, parentOrigin⟩ := by
  cases outcome with
  | completed workspace values physical growth frame sourceCompletionEq worldEq environmentEq seeded stable nullables =>
      exact ⟨workspace, growth, nullables.advance⟩

-- Full source closure now handles nullable and recursive productions,
-- not only the terminal-only special case above. No caller supplies a
-- closed workspace, successful parse, or root-existence assumption.
example (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words [9, 7] workspaceLayout completion)
    (notFull : parseResultStatus? outcome.resultValue ≠ some 2) :
    parseResultStatus? outcome.resultValue = some 0 :=
  outcome.success_of_recognizes recursiveInput notFull

example (execution : RecognizerCallExecution grammarLayout grammar words [9, 7]
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments) :
    parseResultStatus? execution.outcome.resultValue = some 0 ∨
      parseResultStatus? execution.outcome.resultValue = some 2 :=
  execution.success_or_capacity recursiveInput

example (execution : RecognizerCallExecution grammarLayout grammar words [9, 7]
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (notFull : parseResultStatus? execution.outcome.resultValue ≠ some 2) :
    ∃ root : Nat, Nonempty (StoredRootParse grammar [9, 7] execution.finalWorkspace root) ∧
      execution.outcome.resultValue = parseResultValue 0 execution.finalWorkspace.states.length root 0 := by
  let result := execution.root_of_recognizes recursiveInput notFull
  exact ⟨result.rootState, ⟨result.stored⟩, result.resultEq⟩

-- Completion comes from the public source result even when the parent is
-- in an earlier chart; callers need not supply an independent span bound.
example (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (notFull : parseResultStatus? execution.outcome.resultValue ≠ some 2)
    (parent child : Fin grammar.productionCount) (dot origin middle finish : Nat)
    (waiting : execution.finalWorkspace.containsKey middle ⟨parent, dot, origin⟩)
    (expected : (grammar.productionAt parent).rhs[dot]? =
      some (grammar.grammar.n_kinds + (grammar.productionAt child).lhs))
    (finished : execution.finalWorkspace.containsKey finish ⟨child, (grammar.productionAt child).rhs.length, middle⟩) :
    execution.finalWorkspace.containsKey finish ⟨parent, dot + 1, origin⟩ :=
  (execution.chartClosed notFull).complete parent child dot origin middle finish waiting expected finished

run_elab do
  for name in #[``ChartClosed.advance_symbol, ``ChartClosed.advance_sequence,
      ``ChartClosed.contains_root, ``NoRootIn.not_hasRoot,
      ``RecognizerRootStatementOutcome.success_of_closed,
      ``RecognizerInitialContinuationOutcome.rejected_noRoot,
      ``RecognizerCallExecution.rejected_noRoot,
      ``RecognizerInitialContinuationOutcome.startSeeded, ``RecognizerCallExecution.startSeeded,
      ``RecognizerInitialContinuationOutcome.predictionsComplete,
      ``RecognizerCallExecution.predictionsComplete,
      ``RecognizerInitialContinuationOutcome.scansComplete, ``RecognizerCallExecution.scansComplete,
      ``RecognizerInitialContinuationOutcome.chartClosed, ``RecognizerCallExecution.chartClosed,
      ``RecognizerInitialContinuationOutcome.success_of_recognizes,
      ``RecognizerCallExecution.success_of_recognizes, ``RecognizerCallExecution.success_or_capacity,
      ``RecognizerCallExecution.root_of_recognizes,
      ``Frontend.syntaxPost.rejected_chart, ``Frontend.bodyPost.parser_rejected,
      ``Frontend.syntaxPost.rejected_not_recognizes, ``Frontend.bodyPost.parser_rejected_invalid,
      ``Lanius.Semantics.executesSequenceSkip] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Parser completeness theorem {name} adds unexpected axiom {assumption}"
  let baseline ← Lean.collectAxioms ``Frontend.CheckedSyntax.call_evaluates
  for name in #[``RecognizerInitialLoopInvariant.startSeeded,
      ``RecognizerStateNonterminalIndexBinding.expected,
      ``RecognizerStatePredictionCompletedFrame.seeded,
      ``RecognizerStatePredictionNullableSynchronizedOutcome.predictions,
      ``RecognizerStateNonterminalSynchronizedExecution.predictions,
      ``RecognizerStateConfig.predictionsReady_of_head,
      ``RecognizerStateConfig.processedPrefix_empty_of_head, ``RecognizerStateConfig.scansReady_of_head,
      ``RecognizerStateFunctionalResult.predictions,
      ``RecognizerStateFunctionalResult.scans,
      ``RecognizerStateConfig.completionsReady_of_head,
      ``RecognizerStateFunctionalResult.completions,
      ``RecognizerPositionFunctionalResult.predictions,
      ``RecognizerPositionFunctionalResult.scans,
      ``RecognizerPositionFunctionalResult.completions,
      ``RecognizerPositionPostFrame.completedPairs,
      ``RecognizerInitialLoopInvariant.functional_execute_position_statement,
      ``RecognizerPositionPostFrame.predicted, ``RecognizerPositionPostFrame.scanned,
      ``RecognizerParentConfig.parentsReady_of_head, ``RecognizerParentFunctionalResult.parents,
      ``RecognizerStateParentEntry.functionalConfig_candidate,
      ``RecognizerStateParentEntry.execute_inner, ``RecognizerStateParentEntry.execute,
      ``RecognizerStateParentSynchronizedOutcome.view,
      ``RecognizerNullableConfig.nullablesReady_of_head, ``RecognizerNullableFunctionalResult.nullables,
      ``RecognizerStateNullableEntry.functionalConfig_candidate,
      ``RecognizerStateNullableEntry.execute_inner, ``RecognizerStateNullableEntry.execute,
      ``RecognizerStatePredictionNullableSynchronizedOutcome.nullables,
      ``RecognizerStateNonterminalSynchronizedExecution.nullables] do
    for assumption in ← Lean.collectAxioms name do
      unless baseline.contains assumption || #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Source seeding/prediction theorem {name} adds an assumption outside the existing frontend baseline: {assumption}"
  Lean.logInfo "Chart completeness and root-rejection exclusion use only standard Lean axioms; nullable, recursion, split-token, and missing-root cases checked."
  Lean.logInfo "Actual source seeding and prediction add no assumptions beyond the existing frontend baseline; final-chart seeding projections use only standard Lean axioms."
  Lean.logInfo "Public non-capacity parser outcomes retain prediction for every final-workspace chart, including the final position; frontend rejection retains the same workspace evidence."
  Lean.logInfo "Public non-capacity parser outcomes retain every matching terminal advance in the final workspace; source construction stays within the existing frontend assumption baseline."
  Lean.logInfo "Seeding and scanning exclude actual parser rejection of a terminal-only split-token input, without assuming full chart closure or parser success."
  Lean.logInfo "The actual chart-head parent entry and restored source outcome retain complete origin-chart replay, including appended parents, without a caller-supplied coverage premise or new frontend assumptions."
  Lean.logInfo "The actual nullable chart-head entry, prediction composition, and restored nonterminal branch retain replay for every matching zero-width child, with no assumed accepted parse or new frontend assumptions."
  Lean.logInfo "Actual state and position traversal completion yields full final-chart closure; every declaratively valid input succeeds or reports capacity, and syntax rejection proves invalidity."

end Lanius.Extraction.Tests.Parser.Completeness
