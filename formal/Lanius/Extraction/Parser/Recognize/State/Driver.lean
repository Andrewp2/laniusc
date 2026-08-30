import Lanius.Extraction.Parser.Recognize.State.Core
import Lanius.Extraction.Parser.Recognize.State.Terminal
import Lanius.Extraction.Parser.Recognize.State.Nonterminal

namespace Lanius.Extraction.ParserRecognize

set_option maxRecDepth 100000

open Lanius.Core
open Lanius.SymbolicCore
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction
open Lanius.Extraction.ParserScan
open Lanius.Extraction.ParserAppend
open Lanius.Extraction.ParserAccessors
open Lanius.Extraction.ParserFind
open Lanius.Extraction.ParserResult
open Lanius.Compiler.Parser
open Lanius.Typing
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Stateful.Reification
/-- Selection of exactly one semantic action for the current Earley item.
    All three cases expose the same workspace-growth contract, so subsequent
    cursor advancement is independent of which action ran. -/
structure RecognizerStateBranchExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)))
    (.ifThenElse (.binary .less (.local 26) (.local 28))
      parserRecognizeStateIncompleteBranch parserRecognizeStateCompleteBranch)
    completion after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell))
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length))) after
  outcome : RecognizerStateOperationOutcome grammarLayout grammar words tokens
    workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell cursorCell position current remaining after completion

/-- Decide and execute terminal scan, nonterminal prediction/nullable replay,
    or completed-state parent replay from the decoded dot position. -/
noncomputable def RecognizerStateCandidateBindings.execute_branch
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound) :
    RecognizerStateBranchExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound bindings := by
  let rhsLength :=
    (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
  by_cases dotBeforeEnd : candidate.dot < rhsLength
  · have incompleteTest : Evaluates verifiedParserCore
        (bindings.afterRhsLengthRead.bindLocal 28
          (.signed .i32 (Int.ofNat rhsLength)))
        (.binary .less (.local 26) (.local 28)) (.boolean true)
        (bindings.afterRhsLengthRead.bindLocal 28
          (.signed .i32 (Int.ofNat rhsLength))) := by
      simpa [rhsLength, dotBeforeEnd] using bindings.evaluate_incomplete_test
    let symbolBinding := bindings.bind_incomplete_symbol (by
      simpa [rhsLength] using dotBeforeEnd)
    let symbol := (grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.get ⟨candidate.dot, by
        simpa [rhsLength] using dotBeforeEnd⟩
    by_cases isTerminal : symbol < grammar.grammar.n_kinds
    · let operation := symbolBinding.execute_terminal (by
        simpa [symbol] using isTerminal)
      exact {
        after := operation.after
        completion := operation.completion
        execution := executesIfTrue incompleteTest operation.execution
        effect := operation.effect
        outcome := operation.outcome
      }
    · let synchronized := symbolBinding.execute_nonterminal_synchronized (by
        simpa [symbol] using isTerminal)
      let operation := synchronized.physical
      exact {
        after := operation.after
        completion := operation.completion
        execution := executesIfTrue incompleteTest operation.execution
        effect := operation.effect
        outcome := synchronized.physicalOutcome
      }
  · have within := bindings.invariant.chartCursor.state_within_grammar
        candidate found
    have dotBound : candidate.dot ≤ rhsLength := by
      simpa [EarleyState.key, rhsLength] using within.dotBound
    have completed : candidate.dot = rhsLength := by omega
    have completeTest : Evaluates verifiedParserCore
        (bindings.afterRhsLengthRead.bindLocal 28
          (.signed .i32 (Int.ofNat rhsLength)))
        (.binary .less (.local 26) (.local 28)) (.boolean false)
        (bindings.afterRhsLengthRead.bindLocal 28
          (.signed .i32 (Int.ofNat rhsLength))) := by
      simpa [rhsLength, dotBeforeEnd] using bindings.evaluate_incomplete_test
    let prepared := bindings.execute_complete (by
      simpa [rhsLength] using completed)
    obtain ⟨completedLhs, entry, operation⟩ := prepared
    exact {
      after := operation.after
      completion := Lanius.FunctionalView.Core.Stateful.toCoreCompletion
        entry.functionalConfig.functional_run.completion
      execution := executesIfFalse completeTest operation.execution
      effect := operation.effect
      outcome := operation.outcome.physical
    }

/-- Result of one complete state-chain iteration after candidate scopes have
    been restored.  Normal completion either exposes the next chart suffix or
    a proved exhausted cursor; capacity exhaustion returns immediately. -/
inductive RecognizerStateStepOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position current : Nat) (remaining : List Nat) :
    State → Completion → Type
  | advanced (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (after : State) (growth : WorkspaceAppendClosure workspaceLayout.capacity
        beforeWorkspace workspace)
      (next : Nat) (nextRemaining : List Nat)
      (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell after position next
        nextRemaining)
      (progress :
        (workspace.states.length = beforeWorkspace.states.length ∧
          next :: nextRemaining = remaining) ∨
        beforeWorkspace.states.length < workspace.states.length) :
      RecognizerStateStepOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell cursorCell position current remaining after .next
  | exhausted (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (after : State) (growth : WorkspaceAppendClosure workspaceLayout.capacity
        beforeWorkspace workspace)
      (invariant : RecognizerStateFinishedInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell after position)
      (progress :
        (workspace.states.length = beforeWorkspace.states.length ∧
          ([] : List Nat) = remaining) ∨
        beforeWorkspace.states.length < workspace.states.length) :
      RecognizerStateStepOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell cursorCell position current remaining after .next
  | full (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (after : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (invariant : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell after)
      (stateCount : Nat) (wellFormed : StateWellFormed after) :
      RecognizerStateStepOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell cursorCell position current remaining after
        (parserCapacityCompletion position stateCount)

structure RecognizerStateStepExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before parserRecognizeStateLoopBody
    completion after
  effect : ModifiesOnly
    (stateLoopMutableCells workspaceCell stateCountCell cursorCell) before after
  outcome : RecognizerStateStepOutcome grammarLayout grammar words tokens
    workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell cursorCell position current remaining after completion

/-- Execute one complete state-chain body: decode the current item, run its
    semantic branch, advance or exhaust the chart cursor, and restore all
    generated candidate locals. -/
noncomputable def RecognizerStateLoopInvariant.execute_step
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining) :
    RecognizerStateStepExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      invariant := by
  let candidate := Classical.choose invariant.chartCursor.state_at_cursor
  have candidateFacts := Classical.choose_spec invariant.chartCursor.state_at_cursor
  have found : workspace.state? current = some candidate := candidateFacts.1
  have within := invariant.chartCursor.state_within_grammar candidate found
  have productionBound : candidate.production < grammar.productionCount := by
    simpa [EarleyState.key] using within.productionBound
  let bindings := invariant.bind_candidate_fields candidate found productionBound
  let branch := bindings.execute_branch
  obtain ⟨branchAfter, branchCompletion, branchExecution, branchEffect,
    branchOutcome⟩ := branch
  let writes := stateLoopMutableCells workspaceCell stateCountCell cursorCell
  have branchEffect' : ModifiesOnly writes
      (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.length))) branchAfter :=
    branchEffect.weaken (by
      intro cell written
      change cell = workspaceCell ∨ cell = stateCountCell at written
      change cell = workspaceCell ∨
        cell = stateCountCell ∨ cell = cursorCell
      exact written.elim (fun same => .inl same)
        (fun same => .inr (.inl same)))
  have existsResult : ∃ result :
      RecognizerStateStepExecution grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell runtime position current
        remaining invariant, True := by
    cases branchOutcome with
    | full nextWorkspace nextValues _ growth terminal stateCount wellFormed =>
        have innerExecution : Executes verifiedParserCore
            (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
              (grammar.productionAt ⟨candidate.production,
                productionBound⟩).rhs.length)))
            parserRecognizeStateAfterBindings
            (parserCapacityCompletion position stateCount) branchAfter := by
          rw [extractedParserRecognize_state_after_bindings_shape]
          exact executesSequenceReturned branchExecution
        let closed := bindings.close_scopes branchAfter
          (parserCapacityCompletion position stateCount) writes innerExecution
          branchEffect' wellFormed
        let restored := closed.restore_recognizer terminal
        exact ⟨{
          after := closed.after
          completion := parserCapacityCompletion position stateCount
          execution := closed.execution
          effect := by simpa [writes] using closed.effect
          outcome := .full nextWorkspace nextValues closed.after growth restored
            stateCount closed.wellFormed
        }, trivial⟩
    | completed nextWorkspace nextValues _ growth frame =>
        cases suffixEq : frame.nextRemaining with
        | nil =>
            have stateInvariant : RecognizerStateLoopInvariant grammarLayout
                grammar words tokens workspaceLayout nextWorkspace nextValues
                grammarCell tokensCell workspaceCell stateCountCell cursorCell
                branchAfter position current [] := by
              simpa [suffixEq] using frame.invariant
            let exhausted := stateInvariant.chartCursor.exhaust
            let innerFinished := stateInvariant.after_cursor_exhaustion
              exhausted.finished exhausted.effect
            have cursorEffect : ModifiesOnly writes branchAfter
                exhausted.after := exhausted.effect.weaken (by
              intro cell written
              change cell = cursorCell at written
              exact .inr (.inr written))
            have innerEffect : ModifiesOnly writes
                (bindings.afterRhsLengthRead.bindLocal 28
                  (.signed .i32 (Int.ofNat
                    (grammar.productionAt ⟨candidate.production,
                      productionBound⟩).rhs.length))) exhausted.after :=
              branchEffect'.trans_same cursorEffect
            have innerExecution : Executes verifiedParserCore
                (bindings.afterRhsLengthRead.bindLocal 28
                  (.signed .i32 (Int.ofNat
                    (grammar.productionAt ⟨candidate.production,
                      productionBound⟩).rhs.length)))
                parserRecognizeStateAfterBindings .next exhausted.after := by
              rw [extractedParserRecognize_state_after_bindings_shape]
              exact executesSequence branchExecution exhausted.execution
            let closed := bindings.close_scopes exhausted.after .next writes
              innerExecution innerEffect
              innerFinished.chartCursor.recognizer.wellFormed
            let restored := closed.restore_finished innerFinished
            have progress :
                (nextWorkspace.states.length = workspace.states.length ∧
                  ([] : List Nat) = remaining) ∨
                workspace.states.length < nextWorkspace.states.length := by
              simpa [suffixEq] using frame.progress
            exact ⟨{
              after := closed.after
              completion := .next
              execution := closed.execution
              effect := by simpa [writes] using closed.effect
              outcome := .exhausted nextWorkspace nextValues closed.after growth
                restored progress
            }, trivial⟩
        | cons next nextRemaining =>
            have stateInvariant : RecognizerStateLoopInvariant grammarLayout
                grammar words tokens workspaceLayout nextWorkspace nextValues
                grammarCell tokensCell workspaceCell stateCountCell cursorCell
                branchAfter position current (next :: nextRemaining) := by
              simpa [suffixEq] using frame.invariant
            let advanced := stateInvariant.chartCursor.advance
            let innerInvariant := stateInvariant.after_cursor_effect
              advanced.invariant advanced.effect
            have cursorEffect : ModifiesOnly writes branchAfter advanced.after :=
              advanced.effect.weaken (by
                intro cell written
                change cell = cursorCell at written
                exact .inr (.inr written))
            have innerEffect : ModifiesOnly writes
                (bindings.afterRhsLengthRead.bindLocal 28
                  (.signed .i32 (Int.ofNat
                    (grammar.productionAt ⟨candidate.production,
                      productionBound⟩).rhs.length))) advanced.after :=
              branchEffect'.trans_same cursorEffect
            have innerExecution : Executes verifiedParserCore
                (bindings.afterRhsLengthRead.bindLocal 28
                  (.signed .i32 (Int.ofNat
                    (grammar.productionAt ⟨candidate.production,
                      productionBound⟩).rhs.length)))
                parserRecognizeStateAfterBindings .next advanced.after := by
              rw [extractedParserRecognize_state_after_bindings_shape]
              exact executesSequence branchExecution advanced.execution
            let closed := bindings.close_scopes advanced.after .next writes
              innerExecution innerEffect
              innerInvariant.chartCursor.recognizer.wellFormed
            let restored := closed.restore_invariant innerInvariant
            have progress :
                (nextWorkspace.states.length = workspace.states.length ∧
                  next :: nextRemaining = remaining) ∨
                workspace.states.length < nextWorkspace.states.length := by
              simpa [suffixEq] using frame.progress
            exact ⟨{
              after := closed.after
              completion := .next
              execution := closed.execution
              effect := by simpa [writes] using closed.effect
              outcome := .advanced nextWorkspace nextValues closed.after growth
                next nextRemaining restored progress
            }, trivial⟩
  exact Classical.choose existsResult
/-- Algorithmic configuration for the state-chain loop.  A finished cursor is
    represented explicitly so the generic loop driver can execute the final
    false condition rather than hiding it inside the last body step. -/
structure RecognizerStateConfig
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position : Nat) where
  workspace : LogicalWorkspace
  workspaceValues : List Int
  runtime : State
  cursor :
    (Sigma fun current : Nat => Sigma fun remaining : List Nat =>
      RecognizerStateLoopInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell runtime position current
        remaining)
    ⊕ RecognizerStateFinishedInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell runtime position

/-- Lexicographic state-loop measure: workspace capacity remaining first,
    chart suffix length second.  Workspace growth decreases the first
    component; otherwise cursor advancement decreases the second. -/
def RecognizerStateConfig.measure
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position) : Nat × Nat :=
  (workspaceLayout.capacity - config.workspace.states.length,
    match config.cursor with
    | .inl active => active.2.1.length + 1
    | .inr _ => 0)

@[simp] def RecognizerStateConfig.candidate
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position) : Int :=
  match config.cursor with
  | .inl active => Int.ofNat active.1
  | .inr _ => -1

/-! ### Inner-loop call models inside the state machine

Each compact traversal was proved against the smallest registry it needs.
The state machine adds terminal-scan and chart-word routes, while preserving
the meaning of every inner call.  These policies state that boundary
explicitly so the generic call-model refinement theorem can compose the
proofs without re-proving their commands.
-/

def traversalCallAllowedInState (function : FunctionId) : Bool :=
  decide (function ≠ extractedParserScanTerminalFunction.id ∧
    function ≠ extractedParserChartWordFunction.id)

def predictionCallAllowedInState (function : FunctionId) : Bool :=
  decide (function ≠ extractedParserScanTerminalFunction.id ∧
    function ≠ extractedParserChartWordFunction.id ∧
    function ≠ extractedParserStateValueFunction.id ∧
    function ≠ extractedParserRhsLengthFunction.id ∧
    function ≠ extractedParserLhsFunction.id ∧
    function ≠ extractedParserRhsSymbolFunction.id)

theorem traversalCalls_agree_state :
    Lanius.FunctionalView.Core.Effectful.CallModel.AgreesWhere
      traversalCallAllowedInState
      (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
        grammarCell)
      (RecognizerStateCallRegistry.calls workspaceLayout grammar words tokens
        grammarCell tokensCell) := by
  intro world function arguments supported
  have routes := of_decide_eq_true supported
  exact (RecognizerStateCallRegistry.calls_at_traversal world function
    arguments routes.1 routes.2).symm

theorem predictionCalls_agree_state :
    Lanius.FunctionalView.Core.Effectful.CallModel.AgreesWhere
      predictionCallAllowedInState
      (RecognizerCallRegistry.calls workspaceLayout words grammarCell)
      (RecognizerStateCallRegistry.calls workspaceLayout grammar words tokens
        grammarCell tokensCell) := by
  intro world function arguments supported
  have routes := of_decide_eq_true supported
  calc
    (RecognizerCallRegistry.calls workspaceLayout words grammarCell).evaluate
        world function arguments =
      (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
        grammarCell).evaluate world function arguments :=
      (RecognizerTraversalCallRegistry.calls_at_base world function
        arguments routes.2.2.1 routes.2.2.2.1 routes.2.2.2.2.1
        routes.2.2.2.2.2).symm
    _ = (RecognizerStateCallRegistry.calls workspaceLayout grammar words tokens
        grammarCell tokensCell).evaluate world function arguments :=
      (RecognizerStateCallRegistry.calls_at_traversal world function arguments
        routes.1 routes.2.1).symm

private theorem predictionLoop_calls_supported :
    Lanius.FunctionalView.Core.Stateful.Command.callsSatisfy
      predictionCallAllowedInState statePredictionLoopCommand = true := by
  native_decide

private theorem nullableLoop_calls_supported :
    Lanius.FunctionalView.Core.Stateful.Command.callsSatisfy
      traversalCallAllowedInState stateNullableLoopCommand = true := by
  native_decide

private theorem parentLoop_calls_supported :
    Lanius.FunctionalView.Core.Stateful.Command.callsSatisfy
      traversalCallAllowedInState stateParentLoopCommand = true := by
  native_decide

/-- Prediction executes under the actual state-loop call registry. -/
private noncomputable def RecognizerPredictionConfig.evaluates_in_state_machine
    (config : RecognizerPredictionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell position first count)
    (beforeLarge : Lanius.FunctionalView.Env 22)
    (related : Lanius.FunctionalView.Env.Extends
      predictionIntoStateEmbedding config.functionalRuntime.environment
      beforeLarge) :
    Lanius.FunctionalView.Stateful.Command.RenameResult
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      Lanius.FunctionalView.Core.Stateful.actionRenamer
      predictionIntoStateEmbedding config.functionalRuntime.world beforeLarge
      predictionLoopCommand config.functional_run.completion
      config.functional_run.after.world
      config.functional_run.after.environment := by
  let embedded := config.evaluates_in_state_environment beforeLarge related
  let first := RecognizerCallRegistry.calls workspaceLayout words grammarCell
  let second := RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell
  have changed :=
    Lanius.FunctionalView.Core.Stateful.Command.Evaluates.changeCallModel
      (program := verifiedParserCore) (first := first) (second := second)
      predictionCalls_agree_state predictionLoop_calls_supported (by
        simpa [predictionTermMachine, predictionStatefulMachine, first,
          Lanius.FunctionalView.Core.Effectful.machine,
          Lanius.FunctionalView.Core.Stateful.termMachine] using embedded.evaluated)
  exact {
    afterLarge := embedded.afterLarge
    evaluated := changed
    related := embedded.related
    preserved := embedded.preserved
  }

/-- Nullable completion executes under the actual state-loop call registry. -/
private noncomputable def RecognizerNullableConfig.evaluates_in_state_machine
    (config : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected)
    (beforeLarge : Lanius.FunctionalView.Env 23)
    (related : Lanius.FunctionalView.Env.Extends
      nullableIntoStateEmbedding config.functionalRuntime.environment
      beforeLarge) :
    Lanius.FunctionalView.Stateful.Command.RenameResult
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      Lanius.FunctionalView.Core.Stateful.actionRenamer nullableIntoStateEmbedding
      config.functionalRuntime.world beforeLarge nullableLoopCommand
      config.functional_run.completion config.functional_run.after.world
      config.functional_run.after.environment := by
  let embedded := config.evaluates_in_state_environment beforeLarge related
  let first := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
    words grammarCell
  let second := RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell
  have changed :=
    Lanius.FunctionalView.Core.Stateful.Command.Evaluates.changeCallModel
      (program := verifiedParserCore) (first := first) (second := second)
      traversalCalls_agree_state nullableLoop_calls_supported (by
        simpa [nullableTermMachine, nullableStatefulMachine, first,
          Lanius.FunctionalView.Core.Effectful.machine,
          Lanius.FunctionalView.Core.Stateful.termMachine] using embedded.evaluated)
  exact {
    afterLarge := embedded.afterLarge
    evaluated := changed
    related := embedded.related
    preserved := embedded.preserved
  }

/-- Parent completion executes under the actual state-loop call registry. -/
private noncomputable def RecognizerParentConfig.evaluates_in_state_machine
    (config : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs parent)
    (beforeLarge : Lanius.FunctionalView.Env 19)
    (related : Lanius.FunctionalView.Env.Extends
      parentIntoStateEmbedding config.functionalRuntime.environment
      beforeLarge) :
    Lanius.FunctionalView.Stateful.Command.RenameResult
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      Lanius.FunctionalView.Core.Stateful.actionRenamer parentIntoStateEmbedding
      config.functionalRuntime.world beforeLarge parentLoopCommand
      config.functional_run.completion config.functional_run.after.world
      config.functional_run.after.environment := by
  let embedded := config.evaluates_in_state_environment beforeLarge related
  let first := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
    words grammarCell
  let second := RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell
  have changed :=
    Lanius.FunctionalView.Core.Stateful.Command.Evaluates.changeCallModel
      (program := verifiedParserCore) (first := first) (second := second)
      traversalCalls_agree_state parentLoop_calls_supported (by
        simpa [parentTermMachine, parentStatefulMachine, first,
          Lanius.FunctionalView.Core.Effectful.machine,
          Lanius.FunctionalView.Core.Stateful.termMachine] using embedded.evaluated)
  exact {
    afterLarge := embedded.afterLarge
    evaluated := changed
    related := embedded.related
    preserved := embedded.preserved
  }

@[simp] private theorem
    RecognizerStateParentEntry.functionalConfig_workspaceValues
    (entry : RecognizerStateParentEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs) :
    entry.functionalConfig.workspaceValues = workspaceValues := by
  cases cursorEq : entry.cursor <;>
    simp [RecognizerStateParentEntry.functionalConfig, cursorEq]

@[simp] private theorem RecognizerStateParentEntry.functionalConfig_workspace
    (entry : RecognizerStateParentEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs) :
    entry.functionalConfig.workspace = workspace := by
  cases cursorEq : entry.cursor <;>
    simp [RecognizerStateParentEntry.functionalConfig, cursorEq]

@[simp] private theorem RecognizerStateParentEntry.functionalConfig_runtime
    (entry : RecognizerStateParentEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs) :
    entry.functionalConfig.runtime = entry.chartEntry.bound := by
  cases cursorEq : entry.cursor <;>
    simp [RecognizerStateParentEntry.functionalConfig, cursorEq]

private theorem RecognizerStateParentEntry.functionalConfig_candidate
    (entry : RecognizerStateParentEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs) :
    entry.functionalConfig.candidate =
      chartHeadValue workspace candidate.origin := by
  have sourceValue : entry.chartEntry.bound.local? 30 =
      some (.signed .i32
        (chartHeadValue workspace candidate.origin)) := by
    rw [entry.chartEntry.boundEq]
    exact bindLocal_finds_local entry.chartEntry.headRead.after 30
      (.signed .i32 (chartHeadValue workspace candidate.origin))
      entry.chartEntry.headRead.invariant.wellFormed
  cases cursorEq : entry.cursor with
  | inl active =>
      obtain ⟨parent, parentRemaining, invariant⟩ := active
      have cursorValue : entry.chartEntry.bound.local? 30 =
          some (.signed .i32 (Int.ofNat parent)) :=
        Assertion.localPointsTo_local 30 entry.chartEntry.cursorCell _
          entry.chartEntry.bound invariant.chartCursor.cursorOwned
      have valueEq := Option.some.inj (sourceValue.symm.trans cursorValue)
      have integerEq : chartHeadValue workspace candidate.origin =
          Int.ofNat parent := by injection valueEq
      simpa [RecognizerStateParentEntry.functionalConfig, cursorEq] using
        integerEq.symm
  | inr invariant =>
      have cursorValue : entry.chartEntry.bound.local? 30 =
          some (.signed .i32 (-1)) :=
        Assertion.localPointsTo_local 30 entry.chartEntry.cursorCell _
          entry.chartEntry.bound invariant.chartCursor.cursorOwned
      have valueEq := Option.some.inj (sourceValue.symm.trans cursorValue)
      have integerEq : chartHeadValue workspace candidate.origin = -1 := by
        injection valueEq
      simpa [RecognizerStateParentEntry.functionalConfig, cursorEq] using
        integerEq.symm

private theorem
    RecognizerStateParentEntry.functionalConfig_environment_extends
    (entry : RecognizerStateParentEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs)
    (environment : Lanius.FunctionalView.Env 17)
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment) :
    Lanius.FunctionalView.Env.Extends parentIntoStateEmbedding
      entry.functionalConfig.functionalRuntime.environment
      ((environment.push (.signed .i32 (Int.ofNat completedLhs))).push
        (.signed .i32 (chartHeadValue workspace candidate.origin))) := by
  have candidateEq := entry.functionalConfig_candidate
  have smallEnvironment : entry.functionalConfig.functionalRuntime.environment =
      parentEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout workspace.states.length grammar.grammar.n_kinds
        position current completedLhs
        (chartHeadValue workspace candidate.origin) := by
    change parentEnvironment words entry.functionalConfig.workspaceValues
      grammarCell workspaceCell workspaceLayout
      entry.functionalConfig.workspace.states.length grammar.grammar.n_kinds
      position current completedLhs entry.functionalConfig.candidate = _
    rw [entry.functionalConfig_workspaceValues,
      entry.functionalConfig_workspace, candidateEq]
  let extended : Lanius.FunctionalView.Env 19 :=
    (environment.push (.signed .i32 (Int.ofNat completedLhs))).push
      (.signed .i32 (chartHeadValue workspace candidate.origin))
  change Lanius.FunctionalView.Env.Extends parentIntoStateEmbedding
    entry.functionalConfig.functionalRuntime.environment extended
  intro index
  rw [smallEnvironment]
  have oldSlot (sourceIndex : Fin 17) :
      extended (Fin.castSucc (Fin.castSucc sourceIndex)) =
        environment sourceIndex := by
    exact (Lanius.FunctionalView.Env.push_before
      (environment.push (.signed .i32 (Int.ofNat completedLhs)))
      (.signed .i32 (chartHeadValue workspace candidate.origin))
      (Fin.castSucc sourceIndex)).trans
        (Lanius.FunctionalView.Env.push_before environment
          (.signed .i32 (Int.ofNat completedLhs)) sourceIndex)
  have lhsSlot :
      extended (Fin.castSucc (Fin.last 17)) =
        .signed .i32 (Int.ofNat completedLhs) := by
    exact (Lanius.FunctionalView.Env.push_before
      (environment.push (.signed .i32 (Int.ofNat completedLhs)))
      (.signed .i32 (chartHeadValue workspace candidate.origin))
      (Fin.last 17)).trans
        (Lanius.FunctionalView.Env.push_last environment
          (.signed .i32 (Int.ofNat completedLhs)))
  have headSlot :
      extended (Fin.last 18) =
        .signed .i32 (chartHeadValue workspace candidate.origin) := by
    exact Lanius.FunctionalView.Env.push_last
      (environment.push (.signed .i32 (Int.ofNat completedLhs)))
      (.signed .i32 (chartHeadValue workspace candidate.origin))
  have indexCases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
      index.val = 3 ∨ index.val = 4 ∨ index.val = 5 ∨
      index.val = 6 ∨ index.val = 7 ∨ index.val = 8 ∨
      index.val = 9 := by omega
  rcases indexCases with zero | one | two | three | four | five | six |
      seven | eight | nine
  · have same : index = ⟨0, by omega⟩ := Fin.ext zero
    rw [same]
    change extended ⟨0, by omega⟩ = parserGrammarValue words grammarCell
    exact (oldSlot (⟨0, by omega⟩ : Fin 17)).trans meaning.grammarEq
  · have same : index = ⟨1, by omega⟩ := Fin.ext one
    rw [same]
    change extended ⟨3, by omega⟩ =
      workspaceValue workspaceValues workspaceCell
    exact (oldSlot (⟨3, by omega⟩ : Fin 17)).trans meaning.workspaceEq
  · have same : index = ⟨2, by omega⟩ := Fin.ext two
    rw [same]
    change extended ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))
    exact (oldSlot (⟨4, by omega⟩ : Fin 17)).trans meaning.stateBaseEq
  · have same : index = ⟨3, by omega⟩ := Fin.ext three
    rw [same]
    change extended ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat workspaceLayout.capacity)
    exact (oldSlot (⟨5, by omega⟩ : Fin 17)).trans meaning.capacityEq
  · have same : index = ⟨4, by omega⟩ := Fin.ext four
    rw [same]
    change extended ⟨10, by omega⟩ =
      .signed .i32 (Int.ofNat workspace.states.length)
    exact (oldSlot (⟨10, by omega⟩ : Fin 17)).trans meaning.stateCountEq
  · have same : index = ⟨5, by omega⟩ := Fin.ext five
    rw [same]
    change extended ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat grammar.grammar.n_kinds)
    exact (oldSlot (⟨6, by omega⟩ : Fin 17)).trans meaning.kindCountEq
  · have same : index = ⟨6, by omega⟩ := Fin.ext six
    rw [same]
    change extended ⟨11, by omega⟩ =
      Value.signed .i32 (Int.ofNat position)
    exact (oldSlot (⟨11, by omega⟩ : Fin 17)).trans meaning.positionEq
  · have same : index = ⟨7, by omega⟩ := Fin.ext seven
    rw [same]
    change extended ⟨12, by omega⟩ =
      Value.signed .i32 (Int.ofNat current)
    exact (oldSlot (⟨12, by omega⟩ : Fin 17)).trans meaning.currentEq
  · have same : index = ⟨8, by omega⟩ := Fin.ext eight
    rw [same]
    change extended ⟨17, by omega⟩ =
      Value.signed .i32 (Int.ofNat completedLhs)
    exact lhsSlot
  · have same : index = ⟨9, by omega⟩ := Fin.ext nine
    rw [same]
    change extended ⟨18, by omega⟩ =
      Value.signed .i32 (chartHeadValue workspace candidate.origin)
    exact headSlot

/-- The completed-state branch extracted from `parser.lani::recognize`
    evaluates through the same FunctionalView parent-loop trace as its compact
    source-derived configuration.  This is the first state branch connected
    from its seventeen-slot source frame through a real nested recognizer
    loop, rather than only through a standalone loop theorem. -/
private theorem RecognizerStateParentEntry.functional_complete
    (entry : RecognizerStateParentEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs)
    (environment : Lanius.FunctionalView.Env 17)
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment) :
    ∃ afterParent,
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell)
        environment stateCompleteCommand
        entry.functionalConfig.functional_run.completion
        entry.functionalConfig.functional_run.after.world
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop afterParent)) ∧
      Lanius.FunctionalView.Env.Extends parentIntoStateEmbedding
        entry.functionalConfig.functional_run.after.environment afterParent ∧
      Lanius.FunctionalView.Env.PreservesOutside parentIntoStateEmbedding
        ((environment.push (.signed .i32 (Int.ofNat completedLhs))).push
          (.signed .i32 (chartHeadValue workspace candidate.origin)))
        afterParent := by
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  have lhsResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateLhsTerm ⟨0, by omega⟩ ⟨13, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat completedLhs), world) := by
    have evaluated := stateLhsTerm_evaluates workspaceLayout grammar words
      tokens grammarCell tokensCell world environment ⟨0, by omega⟩
      ⟨13, by omega⟩ candidate.production productionBound meaning.grammarEq
      meaning.productionEq stateWorld_finds_grammar
    simpa [entry.completedLhsEq] using evaluated
  have pushedWorkspace :
      (environment.push (.signed .i32 (Int.ofNat completedLhs)))
          ⟨3, by omega⟩ = workspaceValue workspaceValues workspaceCell :=
    (Lanius.FunctionalView.Env.push_before environment
      (.signed .i32 (Int.ofNat completedLhs)) ⟨3, by omega⟩).trans
      meaning.workspaceEq
  have pushedOrigin :
      (environment.push (.signed .i32 (Int.ofNat completedLhs)))
          ⟨15, by omega⟩ = .signed .i32 (Int.ofNat candidate.origin) :=
    (Lanius.FunctionalView.Env.push_before environment
      (.signed .i32 (Int.ofNat completedLhs)) ⟨15, by omega⟩).trans
      meaning.originEq
  have originBound : candidate.origin ≤
      finalPosition workspaceLayout.tokenCount :=
    bindings.invariant.chartCursor.recognizer.workspaceEncoded.originsBound
      current candidate found
  have chartHeadResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world (environment.push (.signed .i32 (Int.ofNat completedLhs)))
      (stateChartHeadTerm ⟨3, by omega⟩ ⟨15, by omega⟩) =
      .ok (.signed .i32 (chartHeadValue workspace candidate.origin), world) :=
    stateChartHeadTerm_evaluates workspaceLayout grammar words tokens
      grammarCell tokensCell workspaceCell world
      (environment.push (.signed .i32 (Int.ofNat completedLhs)))
      ⟨3, by omega⟩ ⟨15, by omega⟩ workspace workspaceValues candidate.origin
      pushedWorkspace pushedOrigin
      (stateWorld_finds_workspace
        bindings.invariant.chartCursor.recognizer.grammarWorkspaceDistinct
        bindings.invariant.chartCursor.recognizer.tokensWorkspaceDistinct)
      bindings.invariant.chartCursor.recognizer.workspaceLength
      bindings.invariant.chartCursor.recognizer.workspaceEncoded originBound
  let beforeParent : Lanius.FunctionalView.Env 19 :=
    (environment.push (.signed .i32 (Int.ofNat completedLhs))).push
      (.signed .i32 (chartHeadValue workspace candidate.origin))
  have related : Lanius.FunctionalView.Env.Extends parentIntoStateEmbedding
      entry.functionalConfig.functionalRuntime.environment beforeParent := by
    simpa [beforeParent] using
      entry.functionalConfig_environment_extends environment meaning
  obtain ⟨afterParent, parentResult, relatedAfter, preservedAfter⟩ :=
    entry.functionalConfig.evaluates_in_state_machine beforeParent related
  have parentWorldEq :
      entry.functionalConfig.functionalRuntime.world = world := by
    change recognizerWorld words tokens
      entry.functionalConfig.workspaceValues grammarCell tokensCell
      workspaceCell = _
    rw [entry.functionalConfig_workspaceValues]
    rfl
  have parentResult' : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world beforeParent stateParentLoopCommand
      entry.functionalConfig.functional_run.completion
      entry.functionalConfig.functional_run.after.world afterParent := by
    rw [parentWorldEq] at parentResult
    simpa [beforeParent] using parentResult
  refine ⟨afterParent, ?_, relatedAfter, ?_⟩
  · exact stateCompleteCommand_evaluates_of_parent world
      entry.functionalConfig.functional_run.after.world environment completedLhs
      (chartHeadValue workspace candidate.origin) afterParent
      entry.functionalConfig.functional_run.completion lhsResult chartHeadResult
      parentResult'
  · simpa [beforeParent] using preservedAfter

/-- Interpret the enclosing seventeen-slot state frame after a parent replay
    and its two source-local bindings have closed.  Parent-owned slots come
    from the compact synchronized environment; all other source locals come
    from the renaming frame theorem. -/
private theorem StateAfterBindingsEnvironment.after_parent_projection
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell position current production dot origin rhsLength
      environment)
    (completedLhs : Nat) (chartHead : Int)
    (workspace : LogicalWorkspace) (workspaceValues : List Int)
    (afterParent : Lanius.FunctionalView.Env 19)
    (related : Lanius.FunctionalView.Env.Extends parentIntoStateEmbedding
      (parentEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout workspace.states.length grammar.grammar.n_kinds
        position current completedLhs (-1)) afterParent)
    (preserved : Lanius.FunctionalView.Env.PreservesOutside
      parentIntoStateEmbedding
      ((environment.push (.signed .i32 (Int.ofNat completedLhs))).push
        (.signed .i32 chartHead)) afterParent) :
    StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current production dot origin rhsLength
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop afterParent)) := by
  let beforeParent : Lanius.FunctionalView.Env 19 :=
    (environment.push (.signed .i32 (Int.ofNat completedLhs))).push
      (.signed .i32 chartHead)
  let afterEnvironment : Lanius.FunctionalView.Env 17 :=
    Lanius.FunctionalView.Stateful.Env.pop
      (Lanius.FunctionalView.Stateful.Env.pop afterParent)
  have beforeOld (index : Fin 17) :
      beforeParent ⟨index.val, by omega⟩ = environment index := by
    exact (Lanius.FunctionalView.Env.push_before
      (environment.push (.signed .i32 (Int.ofNat completedLhs)))
      (.signed .i32 chartHead) ⟨index.val, by omega⟩).trans
        (Lanius.FunctionalView.Env.push_before environment
          (.signed .i32 (Int.ofNat completedLhs)) index)
  have preservedOld (index : Fin 17)
      (outside : ∀ sourceIndex,
        parentIntoStateEmbedding.slot sourceIndex ≠
          (⟨index.val, by omega⟩ : Fin 19)) :
      afterEnvironment index = environment index := by
    calc
      afterEnvironment index = afterParent ⟨index.val, by omega⟩ := rfl
      _ = beforeParent ⟨index.val, by omega⟩ := by
        exact preserved ⟨index.val, by omega⟩ outside
      _ = environment index := beforeOld index
  have mapped (small : Fin 10) (large : Fin 19)
      (slotEq : parentIntoStateEmbedding.slot small = large) :
      afterParent large =
        parentEnvironment words workspaceValues grammarCell workspaceCell
          workspaceLayout workspace.states.length grammar.grammar.n_kinds
          position current completedLhs (-1) small := by
    rw [← slotEq]
    exact related small
  exact {
    grammarEq := by
      change afterParent 0 = parserGrammarValue words grammarCell
      simpa [parentEnvironment] using mapped 0 0 (by native_decide)
    tokensEq := (preservedOld 1 (by native_decide)).trans meaning.tokensEq
    tokenCountEq :=
      (preservedOld 2 (by native_decide)).trans meaning.tokenCountEq
    workspaceEq := by
      change afterParent 3 = workspaceValue workspaceValues workspaceCell
      simpa [parentEnvironment] using mapped 1 3 (by native_decide)
    stateBaseEq := by
      change afterParent 4 =
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))
      simpa [parentEnvironment] using mapped 2 4 (by native_decide)
    capacityEq := by
      change afterParent 5 =
        .signed .i32 (Int.ofNat workspaceLayout.capacity)
      simpa [parentEnvironment] using mapped 3 5 (by native_decide)
    kindCountEq := by
      change afterParent 6 =
        .signed .i32 (Int.ofNat grammar.grammar.n_kinds)
      simpa [parentEnvironment] using mapped 5 6 (by native_decide)
    lhsOffsetsEq :=
      (preservedOld 7 (by native_decide)).trans meaning.lhsOffsetsEq
    lhsCountsEq :=
      (preservedOld 8 (by native_decide)).trans meaning.lhsCountsEq
    lhsProductionsEq :=
      (preservedOld 9 (by native_decide)).trans meaning.lhsProductionsEq
    stateCountEq := by
      change afterParent 10 =
        .signed .i32 (Int.ofNat workspace.states.length)
      simpa [parentEnvironment] using mapped 4 10 (by native_decide)
    positionEq := by
      change afterParent 11 = .signed .i32 (Int.ofNat position)
      simpa [parentEnvironment] using mapped 6 11 (by native_decide)
    currentEq := by
      change afterParent 12 = .signed .i32 (Int.ofNat current)
      simpa [parentEnvironment] using mapped 7 12 (by native_decide)
    productionEq :=
      (preservedOld 13 (by native_decide)).trans meaning.productionEq
    dotEq := (preservedOld 14 (by native_decide)).trans meaning.dotEq
    originEq := (preservedOld 15 (by native_decide)).trans meaning.originEq
    rhsLengthEq :=
      (preservedOld 16 (by native_decide)).trans meaning.rhsLengthEq
  }

/-- The completed recognizer-state branch viewed once through the exact
    source-derived FunctionalView command and once through the extracted Core
    statement.  The synchronized outcome shares the workspace witness used by
    both executions. -/
private structure RecognizerStateCompleteFunctionalExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell stateCursorCell : CellId)
    (before : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound)
    (completedLhs : Nat)
    (entry : RecognizerStateParentEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs)
    (environment : Lanius.FunctionalView.Env 17) where
  afterWorld : Lanius.FunctionalView.Core.ReadOnly.World
  afterEnvironment : Lanius.FunctionalView.Env 17
  completion : Lanius.FunctionalView.Stateful.Completion
  physicalAfter : State
  functionalExecution : Lanius.FunctionalView.Stateful.Command.Evaluates
    (stateTermMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell)
    environment stateCompleteCommand completion afterWorld afterEnvironment
  physicalExecution : Executes verifiedParserCore
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)))
    parserRecognizeStateCompleteBranch
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
    physicalAfter
  physicalEffect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell))
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length))) physicalAfter
  outcome : RecognizerStateBranchSynchronizedOutcome grammarLayout grammar
    words tokens workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell stateCursorCell position current remaining candidate.production
    candidate.dot candidate.origin
    (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
    afterWorld afterEnvironment physicalAfter
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)

/-- Execute the source completed-state command and the extracted Core branch
    from one parent replay.  Normal completion projects the compact parent
    environment back into the seventeen source locals; returned capacity
    completion deliberately has no post-environment obligation. -/
private noncomputable def RecognizerStateParentEntry.functional_execute_complete
    (entry : RecognizerStateParentEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs)
    (environment : Lanius.FunctionalView.Env 17)
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment) :
    RecognizerStateCompleteFunctionalExecution grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs entry environment := by
  let operation := entry.execute
  let functionalResult := entry.functional_complete environment meaning
  let afterParent := Classical.choose functionalResult
  have functionalFacts := Classical.choose_spec functionalResult
  rcases functionalFacts with
    ⟨functionalExecution, relatedAfter, preservedAfter⟩
  have physicalExecution : Executes verifiedParserCore
      (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.length)))
      parserRecognizeStateCompleteBranch
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
        entry.functionalConfig.functional_run.completion)
      operation.after := by
    exact operation.execution
  have existsResult : ∃ result :
      RecognizerStateCompleteFunctionalExecution grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell stateCursorCell before position current
        remaining beforeInvariant candidate found productionBound bindings
        completedLhs entry environment, True := by
    rcases operation.outcome.view with completedResult | fullResult
    · rcases completedResult with ⟨completionEq, nextWorkspace, nextValues,
        growth, frame, worldEq, environmentEq⟩
      have relatedFinal : Lanius.FunctionalView.Env.Extends
          parentIntoStateEmbedding
          (parentEnvironment words nextValues grammarCell workspaceCell
            workspaceLayout nextWorkspace.states.length grammar.grammar.n_kinds
            position current completedLhs (-1)) afterParent := by
        simpa [afterParent, environmentEq] using relatedAfter
      change entry.functionalConfig.functional_run.after.world =
        stateWorld words tokens nextValues grammarCell tokensCell workspaceCell
        at worldEq
      have afterMeaning := meaning.after_parent_projection completedLhs
        (chartHeadValue workspace candidate.origin) nextWorkspace nextValues
        afterParent relatedFinal preservedAfter
      exact ⟨{
        afterWorld := entry.functionalConfig.functional_run.after.world
        afterEnvironment := Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop afterParent)
        completion := entry.functionalConfig.functional_run.completion
        physicalAfter := operation.after
        functionalExecution := functionalExecution
        physicalExecution := physicalExecution
        physicalEffect := operation.effect
        outcome := by
          have shared : RecognizerStateBranchSynchronizedOutcome grammarLayout
              grammar words tokens workspaceLayout workspace grammarCell
              tokensCell workspaceCell stateCountCell stateCursorCell position
              current remaining candidate.production candidate.dot
              candidate.origin
              (grammar.productionAt ⟨candidate.production,
                productionBound⟩).rhs.length
              entry.functionalConfig.functional_run.after.world
              (Lanius.FunctionalView.Stateful.Env.pop
                (Lanius.FunctionalView.Stateful.Env.pop afterParent))
              operation.after .next :=
            .completed nextWorkspace nextValues operation.after growth frame
              worldEq afterMeaning
          simpa [completionEq] using shared
      }, trivial⟩
    · rcases fullResult with ⟨finalWorkspace, finalValues, growth, terminal,
        stateCount, wellFormed, completionEq⟩
      exact ⟨{
        afterWorld := entry.functionalConfig.functional_run.after.world
        afterEnvironment := Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop afterParent)
        completion := entry.functionalConfig.functional_run.completion
        physicalAfter := operation.after
        functionalExecution := functionalExecution
        physicalExecution := physicalExecution
        physicalEffect := operation.effect
        outcome := by
          have shared : RecognizerStateBranchSynchronizedOutcome grammarLayout
              grammar words tokens workspaceLayout workspace grammarCell
              tokensCell workspaceCell stateCountCell stateCursorCell position
              current remaining candidate.production candidate.dot
              candidate.origin
              (grammar.productionAt ⟨candidate.production,
                productionBound⟩).rhs.length
              entry.functionalConfig.functional_run.after.world
              (Lanius.FunctionalView.Stateful.Env.pop
                (Lanius.FunctionalView.Stateful.Env.pop afterParent))
              operation.after
              (parserCapacityCompletion position stateCount) :=
            .full finalWorkspace finalValues operation.after growth terminal
              stateCount wellFormed
          simpa [completionEq] using shared
      }, trivial⟩
  exact Classical.choose existsResult

/-! #### Prediction in the source nonterminal branch -/

/-- The exact twenty-two-slot source frame at prediction-loop entry.  The
    symbol local remains outside the compact prediction embedding, while the
    nonterminal row bounds and loop cursor occupy the four newest slots. -/
private def statePredictionEnvironmentOf
    (environment : Lanius.FunctionalView.Env 17)
    (symbol nonterminal first count : Nat) :
    Lanius.FunctionalView.Env 22 :=
  (((((environment.push (.signed .i32 (Int.ofNat symbol))).push
    (.signed .i32 (Int.ofNat nonterminal))).push
    (.signed .i32 (Int.ofNat first))).push
    (.signed .i32 (Int.ofNat count))).push (.signed .i32 0))

/-- The source trace fixes the prediction interval's first row uniquely. -/
private theorem RecognizerStatePredictionEntry.first_eq
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding) :
    entry.first = grammar.lhsOffsets.get
      ⟨nonterminalBinding.nonterminal, by
        simpa [grammar.lhsOffsets_length,
          nonterminalBinding.invariant.chartCursor.recognizer.grammarWellFormed
            |>.lhsIndexCount] using nonterminalBinding.nonterminalBound⟩ := by
  have canonical := nonterminalBinding.invariant.read_lhs_offset
    nonterminalBinding.nonterminal nonterminalBinding.nonterminalBound
    nonterminalBinding.nonterminalLocal
  have same := Lanius.Fuel.evaluates_deterministic entry.firstEvaluation
    canonical
  injection same.1 with _ valueEq
  exact Int.ofNat.inj valueEq

/-- The source trace likewise fixes the prediction interval's row count. -/
private theorem RecognizerStatePredictionEntry.count_eq
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding) :
    entry.count = grammar.lhsCounts.get
      ⟨nonterminalBinding.nonterminal, by
        simpa [grammar.lhsCounts_length,
          nonterminalBinding.invariant.chartCursor.recognizer.grammarWellFormed
            |>.lhsIndexCount] using nonterminalBinding.nonterminalBound⟩ := by
  let firstState := nonterminalBinding.bound.bindLocal 31
    (.signed .i32 (Int.ofNat entry.first))
  let firstInvariant := nonterminalBinding.invariant.after_bind_local 31
    (.signed .i32 (Int.ofNat entry.first)) (by decide)
  have nonterminalAtFirst : firstState.local? 30 =
      some (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal)) := by
    exact (bindLocal_preserves_other_local
      nonterminalBinding.invariant.chartCursor.recognizer.wellFormed
      (by decide : 31 ≠ 30)).trans nonterminalBinding.nonterminalLocal
  have canonical := firstInvariant.read_lhs_count
    nonterminalBinding.nonterminal nonterminalBinding.nonterminalBound
    nonterminalAtFirst
  have countEvaluation : Evaluates verifiedParserCore firstState
      (.index (.local 0) (.binary .add (.local 14) (.local 30)))
      (.signed .i32 (Int.ofNat entry.count)) firstState := by
    simpa [firstState] using entry.countEvaluation
  have same := Lanius.Fuel.evaluates_deterministic countEvaluation canonical
  injection same.1 with _ valueEq
  exact Int.ofNat.inj valueEq

@[simp] private theorem
    RecognizerStatePredictionEntry.functionalConfig_workspace
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding) :
    entry.functionalConfig.workspace = workspace := rfl

@[simp] private theorem
    RecognizerStatePredictionEntry.functionalConfig_workspaceValues
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding) :
    entry.functionalConfig.workspaceValues = workspaceValues := rfl

@[simp] private theorem
    RecognizerStatePredictionEntry.functionalConfig_runtime
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding) :
    entry.functionalConfig.runtime = entry.predictionState := rfl

/-- The compact prediction environment is exactly the projection of the real
    source frame.  This includes the mutable prediction index at zero and
    deliberately excludes the unrelated symbol/nonterminal temporaries. -/
private theorem
    RecognizerStatePredictionEntry.functionalConfig_environment_extends
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding)
    (environment : Lanius.FunctionalView.Env 17)
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment) :
    let symbol := (grammar.productionAt
      ⟨candidate.production, productionBound⟩).rhs.get
        ⟨candidate.dot, dotBeforeEnd⟩
    Lanius.FunctionalView.Env.Extends predictionIntoStateEmbedding
      entry.functionalConfig.functionalRuntime.environment
      (statePredictionEnvironmentOf environment symbol
        nonterminalBinding.nonterminal entry.first entry.count) := by
  dsimp only
  let symbol := (grammar.productionAt
    ⟨candidate.production, productionBound⟩).rhs.get
      ⟨candidate.dot, dotBeforeEnd⟩
  let extended := statePredictionEnvironmentOf environment symbol
    nonterminalBinding.nonterminal entry.first entry.count
  have smallEnvironment :
      entry.functionalConfig.functionalRuntime.environment =
        predictionEnvironment words workspaceValues grammarCell workspaceCell
          workspaceLayout grammarLayout.lhsProductionsOffset position
          entry.first entry.count 0 workspace.states.length := by
    rfl
  change Lanius.FunctionalView.Env.Extends predictionIntoStateEmbedding
    entry.functionalConfig.functionalRuntime.environment extended
  intro index
  rw [smallEnvironment]
  have oldSlot (sourceIndex : Fin 17) :
      extended
        (Fin.castSucc (Fin.castSucc (Fin.castSucc
          (Fin.castSucc (Fin.castSucc sourceIndex))))) =
        environment sourceIndex := by
    unfold extended statePredictionEnvironmentOf
    exact (Lanius.FunctionalView.Env.push_before _ _ _).trans
      ((Lanius.FunctionalView.Env.push_before _ _ _).trans
        ((Lanius.FunctionalView.Env.push_before _ _ _).trans
          ((Lanius.FunctionalView.Env.push_before _ _ _).trans
            (Lanius.FunctionalView.Env.push_before _ _ sourceIndex))))
  have firstSlot : extended ⟨19, by omega⟩ =
      .signed .i32 (Int.ofNat entry.first) := by
    unfold extended statePredictionEnvironmentOf
    exact (Lanius.FunctionalView.Env.push_before _ _ _).trans
      ((Lanius.FunctionalView.Env.push_before _ _ _).trans
        (Lanius.FunctionalView.Env.push_last _ _))
  have countSlot : extended ⟨20, by omega⟩ =
      .signed .i32 (Int.ofNat entry.count) := by
    unfold extended statePredictionEnvironmentOf
    exact (Lanius.FunctionalView.Env.push_before _ _ _).trans
      (Lanius.FunctionalView.Env.push_last _ _)
  have indexSlot : extended ⟨21, by omega⟩ = .signed .i32 0 := by
    unfold extended statePredictionEnvironmentOf
    exact Lanius.FunctionalView.Env.push_last _ _
  have indexCases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
      index.val = 3 ∨ index.val = 4 ∨ index.val = 5 ∨
      index.val = 6 ∨ index.val = 7 ∨ index.val = 8 ∨
      index.val = 9 := by omega
  rcases indexCases with zero | one | two | three | four | five | six |
      seven | eight | nine
  · have same : index = ⟨0, by omega⟩ := Fin.ext zero
    rw [same]
    change extended ⟨0, by omega⟩ = parserGrammarValue words grammarCell
    exact (oldSlot (⟨0, by omega⟩ : Fin 17)).trans meaning.grammarEq
  · have same : index = ⟨1, by omega⟩ := Fin.ext one
    rw [same]
    change extended ⟨3, by omega⟩ =
      workspaceValue workspaceValues workspaceCell
    exact (oldSlot (⟨3, by omega⟩ : Fin 17)).trans meaning.workspaceEq
  · have same : index = ⟨2, by omega⟩ := Fin.ext two
    rw [same]
    change extended ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))
    exact (oldSlot (⟨4, by omega⟩ : Fin 17)).trans meaning.stateBaseEq
  · have same : index = ⟨3, by omega⟩ := Fin.ext three
    rw [same]
    change extended ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat workspaceLayout.capacity)
    exact (oldSlot (⟨5, by omega⟩ : Fin 17)).trans meaning.capacityEq
  · have same : index = ⟨4, by omega⟩ := Fin.ext four
    rw [same]
    change extended ⟨9, by omega⟩ =
      .signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset)
    exact (oldSlot (⟨9, by omega⟩ : Fin 17)).trans meaning.lhsProductionsEq
  · have same : index = ⟨5, by omega⟩ := Fin.ext five
    rw [same]
    change extended ⟨10, by omega⟩ =
      .signed .i32 (Int.ofNat workspace.states.length)
    exact (oldSlot (⟨10, by omega⟩ : Fin 17)).trans meaning.stateCountEq
  · have same : index = ⟨6, by omega⟩ := Fin.ext six
    rw [same]
    change extended ⟨11, by omega⟩ = .signed .i32 (Int.ofNat position)
    exact (oldSlot (⟨11, by omega⟩ : Fin 17)).trans meaning.positionEq
  · have same : index = ⟨7, by omega⟩ := Fin.ext seven
    rw [same]
    change extended ⟨19, by omega⟩ = .signed .i32 (Int.ofNat entry.first)
    exact firstSlot
  · have same : index = ⟨8, by omega⟩ := Fin.ext eight
    rw [same]
    change extended ⟨20, by omega⟩ = .signed .i32 (Int.ofNat entry.count)
    exact countSlot
  · have same : index = ⟨9, by omega⟩ := Fin.ext nine
    rw [same]
    change extended ⟨21, by omega⟩ = .signed .i32 0
    exact indexSlot

/-- Functional evaluation of the nonterminal-index subtraction in the exact
    source frame preceding prediction. -/
private theorem RecognizerStatePredictionEntry.functional_nonterminal
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding)
    (environment : Lanius.FunctionalView.Env 17)
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment) :
    let symbol := (grammar.productionAt
      ⟨candidate.production, productionBound⟩).rhs.get
        ⟨candidate.dot, dotBeforeEnd⟩
    let symbolEnvironment := environment.push
      (.signed .i32 (Int.ofNat symbol))
    let world := stateWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world symbolEnvironment
      (stateSubtractTerm ⟨17, by omega⟩ ⟨6, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal), world) := by
  dsimp only
  let symbol := (grammar.productionAt
    ⟨candidate.production, productionBound⟩).rhs.get
      ⟨candidate.dot, dotBeforeEnd⟩
  let symbolEnvironment := environment.push
    (.signed .i32 (Int.ofNat symbol))
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  have symbolEq : symbolEnvironment ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat symbol) := by
    exact Lanius.FunctionalView.Env.push_last _ _
  have kindCountEq : symbolEnvironment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat grammar.grammar.n_kinds) :=
    (Lanius.FunctionalView.Env.push_before environment
      (.signed .i32 (Int.ofNat symbol)) ⟨6, by omega⟩).trans
      meaning.kindCountEq
  have kindCountLe : grammar.grammar.n_kinds ≤ symbol :=
    Nat.le_of_not_gt (by simpa [symbol] using isNonterminal)
  have bounded : symbol - grammar.grammar.n_kinds ≤ 2147483647 := by
    have domainFits :=
      bindings.invariant.chartCursor.recognizer.grammarWellFormed
        |>.symbolDomainFitsI32
    have symbolMember : symbol ∈
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).rhs := by
      simpa [symbol] using List.get_mem
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).rhs
        ⟨candidate.dot, dotBeforeEnd⟩
    have symbolBound :=
      bindings.invariant.chartCursor.recognizer.grammarWellFormed
        |>.production_validation.rhsSymbolsInBounds
          ⟨candidate.production, productionBound⟩ symbol symbolMember
    omega
  have evaluated := stateSubtractTerm_evaluates workspaceLayout grammar words
    tokens grammarCell tokensCell world symbolEnvironment
    ⟨17, by omega⟩ ⟨6, by omega⟩ symbol grammar.grammar.n_kinds symbolEq
    kindCountEq kindCountLe bounded
  simpa [world, symbolEnvironment, nonterminalBinding.nonterminalEq, symbol]
    using evaluated

/-- Functional evaluation of the packed LHS-offset lookup that seeds the
    prediction interval. -/
private theorem RecognizerStatePredictionEntry.functional_first
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding)
    (environment : Lanius.FunctionalView.Env 17)
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment) :
    let symbol := (grammar.productionAt
      ⟨candidate.production, productionBound⟩).rhs.get
        ⟨candidate.dot, dotBeforeEnd⟩
    let firstEnvironment := (environment.push
      (.signed .i32 (Int.ofNat symbol))).push
      (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal))
    let world := stateWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world firstEnvironment
      (stateIndexAddTerm ⟨0, by omega⟩ ⟨7, by omega⟩ ⟨18, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat entry.first), world) := by
  dsimp only
  let symbol := (grammar.productionAt
    ⟨candidate.production, productionBound⟩).rhs.get
      ⟨candidate.dot, dotBeforeEnd⟩
  let firstEnvironment := (environment.push
    (.signed .i32 (Int.ofNat symbol))).push
    (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal))
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  have oldSlot (sourceIndex : Fin 17) :
      firstEnvironment (Fin.castSucc (Fin.castSucc sourceIndex)) =
        environment sourceIndex := by
    exact (Lanius.FunctionalView.Env.push_before _ _ _).trans
      (Lanius.FunctionalView.Env.push_before _ _ sourceIndex)
  have grammarEq : firstEnvironment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell :=
    (oldSlot ⟨0, by omega⟩).trans meaning.grammarEq
  have baseEq : firstEnvironment ⟨7, by omega⟩ =
      .signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset) :=
    (oldSlot ⟨7, by omega⟩).trans meaning.lhsOffsetsEq
  have rowEq : firstEnvironment ⟨18, by omega⟩ =
      .signed .i32 (Int.ofNat nonterminalBinding.nonterminal) := by
    exact Lanius.FunctionalView.Env.push_last _ _
  have rowBound : nonterminalBinding.nonterminal <
      grammar.lhsOffsets.length := by
    simpa [grammar.lhsOffsets_length,
      bindings.invariant.chartCursor.recognizer.grammarWellFormed
        |>.lhsIndexCount] using nonterminalBinding.nonterminalBound
  have indexBound : grammarLayout.lhsOffsetsOffset +
      nonterminalBinding.nonterminal < words.length :=
    bindings.invariant.chartCursor.recognizer.grammarEncoded.lhsOffsets
      |>.row_in_bounds rowBound
  have sumBound : grammarLayout.lhsOffsetsOffset +
      nonterminalBinding.nonterminal ≤ 2147483647 := by
    have wordsFit := bindings.invariant.chartCursor.recognizer.wordsI32
    omega
  have evaluated := stateIndexAddTerm_evaluates workspaceLayout grammar words
    tokens grammarCell tokensCell grammarCell world firstEnvironment
    ⟨0, by omega⟩ ⟨7, by omega⟩ ⟨18, by omega⟩ words
    grammarLayout.lhsOffsetsOffset nonterminalBinding.nonterminal grammarEq
    baseEq rowEq stateWorld_finds_grammar sumBound indexBound
  have physical :=
    bindings.invariant.chartCursor.recognizer.grammarEncoded.lhsOffsets.get
      rowBound
  rw [physical] at evaluated
  simpa [world, firstEnvironment, symbol, entry.first_eq] using evaluated

/-- Functional evaluation of the packed LHS-count lookup that completes the
    prediction interval. -/
private theorem RecognizerStatePredictionEntry.functional_count
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding)
    (environment : Lanius.FunctionalView.Env 17)
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment) :
    let symbol := (grammar.productionAt
      ⟨candidate.production, productionBound⟩).rhs.get
        ⟨candidate.dot, dotBeforeEnd⟩
    let countEnvironment := ((environment.push
      (.signed .i32 (Int.ofNat symbol))).push
      (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal))).push
      (.signed .i32 (Int.ofNat entry.first))
    let world := stateWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world countEnvironment
      (stateIndexAddTerm ⟨0, by omega⟩ ⟨8, by omega⟩ ⟨18, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat entry.count), world) := by
  dsimp only
  let symbol := (grammar.productionAt
    ⟨candidate.production, productionBound⟩).rhs.get
      ⟨candidate.dot, dotBeforeEnd⟩
  let countEnvironment := ((environment.push
    (.signed .i32 (Int.ofNat symbol))).push
    (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal))).push
    (.signed .i32 (Int.ofNat entry.first))
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  have oldSlot (sourceIndex : Fin 17) :
      countEnvironment
          (Fin.castSucc (Fin.castSucc (Fin.castSucc sourceIndex))) =
        environment sourceIndex := by
    exact (Lanius.FunctionalView.Env.push_before _ _ _).trans
      ((Lanius.FunctionalView.Env.push_before _ _ _).trans
        (Lanius.FunctionalView.Env.push_before _ _ sourceIndex))
  have nonterminalSlot : countEnvironment ⟨18, by omega⟩ =
      .signed .i32 (Int.ofNat nonterminalBinding.nonterminal) := by
    exact (Lanius.FunctionalView.Env.push_before _ _ _).trans
      (Lanius.FunctionalView.Env.push_last _ _)
  have grammarEq : countEnvironment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell :=
    (oldSlot ⟨0, by omega⟩).trans meaning.grammarEq
  have baseEq : countEnvironment ⟨8, by omega⟩ =
      .signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset) :=
    (oldSlot ⟨8, by omega⟩).trans meaning.lhsCountsEq
  have rowBound : nonterminalBinding.nonterminal < grammar.lhsCounts.length := by
    simpa [grammar.lhsCounts_length,
      bindings.invariant.chartCursor.recognizer.grammarWellFormed
        |>.lhsIndexCount] using nonterminalBinding.nonterminalBound
  have indexBound : grammarLayout.lhsCountsOffset +
      nonterminalBinding.nonterminal < words.length :=
    bindings.invariant.chartCursor.recognizer.grammarEncoded.lhsCounts
      |>.row_in_bounds rowBound
  have sumBound : grammarLayout.lhsCountsOffset +
      nonterminalBinding.nonterminal ≤ 2147483647 := by
    have wordsFit := bindings.invariant.chartCursor.recognizer.wordsI32
    omega
  have evaluated := stateIndexAddTerm_evaluates workspaceLayout grammar words
    tokens grammarCell tokensCell grammarCell world countEnvironment
    ⟨0, by omega⟩ ⟨8, by omega⟩ ⟨18, by omega⟩ words
    grammarLayout.lhsCountsOffset nonterminalBinding.nonterminal grammarEq
    baseEq nonterminalSlot stateWorld_finds_grammar sumBound indexBound
  have physical :=
    bindings.invariant.chartCursor.recognizer.grammarEncoded.lhsCounts.get
      rowBound
  rw [physical] at evaluated
  simpa [world, countEnvironment, symbol, entry.count_eq] using evaluated

/-- If prediction exhausts capacity, the real extracted nonterminal command
    returns immediately with the prediction loop's completion. -/
private theorem RecognizerStatePredictionEntry.functional_prediction_stop
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding)
    (environment : Lanius.FunctionalView.Env 17)
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment)
    (stops : entry.functionalConfig.functional_run.completion ≠ .next) :
    let symbol := (grammar.productionAt
      ⟨candidate.production, productionBound⟩).rhs.get
        ⟨candidate.dot, dotBeforeEnd⟩
    ∃ afterPrediction,
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell)
        (environment.push (.signed .i32 (Int.ofNat symbol)))
        stateNonterminalCommand
        entry.functionalConfig.functional_run.completion
        entry.functionalConfig.functional_run.after.world
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.pop
              (Lanius.FunctionalView.Stateful.Env.pop afterPrediction)))) := by
  dsimp only
  let symbol := (grammar.productionAt
    ⟨candidate.production, productionBound⟩).rhs.get
      ⟨candidate.dot, dotBeforeEnd⟩
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let symbolEnvironment := environment.push
    (.signed .i32 (Int.ofNat symbol))
  let beforePrediction := statePredictionEnvironmentOf environment symbol
    nonterminalBinding.nonterminal entry.first entry.count
  have nonterminalResult := entry.functional_nonterminal environment meaning
  have firstResult := entry.functional_first environment meaning
  have countResult := entry.functional_count environment meaning
  have related : Lanius.FunctionalView.Env.Extends predictionIntoStateEmbedding
      entry.functionalConfig.functionalRuntime.environment beforePrediction := by
    simpa [beforePrediction, symbol] using
      entry.functionalConfig_environment_extends environment meaning
  obtain ⟨afterPrediction, predictionResult, _, _⟩ :=
    entry.functionalConfig.evaluates_in_state_machine beforePrediction related
  have predictionWorldEq :
      entry.functionalConfig.functionalRuntime.world = world := by
    change recognizerWorld words tokens
      entry.functionalConfig.workspaceValues grammarCell tokensCell
      workspaceCell = _
    rw [entry.functionalConfig_workspaceValues]
    rfl
  rw [predictionWorldEq] at predictionResult
  have predictionResult' :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        world
        ((((symbolEnvironment.push
          (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal))).push
          (.signed .i32 (Int.ofNat entry.first))).push
          (.signed .i32 (Int.ofNat entry.count))).push (.signed .i32 0))
        statePredictionLoopCommand
        entry.functionalConfig.functional_run.completion
        entry.functionalConfig.functional_run.after.world afterPrediction := by
    simpa [beforePrediction, symbolEnvironment,
      statePredictionEnvironmentOf] using predictionResult
  refine ⟨afterPrediction, ?_⟩
  apply stateNonterminalCommand_evaluates_of_prediction_stop world
    entry.functionalConfig.functional_run.after.world symbolEnvironment
    nonterminalBinding.nonterminal entry.first entry.count afterPrediction
    entry.functionalConfig.functional_run.completion stops
  · simpa [world, symbolEnvironment, symbol] using nonterminalResult
  · simpa [world, symbolEnvironment, symbol] using firstResult
  · simpa [world, symbolEnvironment, symbol] using countResult
  · exact predictionResult'

/-! #### Nullable replay in the source nonterminal branch -/

@[simp] private theorem
    RecognizerStateNullableEntry.functionalConfig_workspace
    (entry : RecognizerStateNullableEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry completed) :
    entry.functionalConfig.workspace = completed.workspace := by
  cases cursorEq : entry.cursor <;>
    simp [RecognizerStateNullableEntry.functionalConfig, cursorEq]

@[simp] private theorem
    RecognizerStateNullableEntry.functionalConfig_workspaceValues
    (entry : RecognizerStateNullableEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry completed) :
    entry.functionalConfig.workspaceValues = completed.workspaceValues := by
  cases cursorEq : entry.cursor <;>
    simp [RecognizerStateNullableEntry.functionalConfig, cursorEq]

@[simp] private theorem
    RecognizerStateNullableEntry.functionalConfig_runtime
    (entry : RecognizerStateNullableEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry completed) :
    entry.functionalConfig.runtime = entry.bound := by
  cases cursorEq : entry.cursor <;>
    simp [RecognizerStateNullableEntry.functionalConfig, cursorEq]

/-- The compact nullable cursor is the value bound by the real chart-head
    source expression.  This rules out a second, independently chosen logical
    cursor at the source-to-FunctionalView boundary. -/
private theorem RecognizerStateNullableEntry.functionalConfig_candidate
    (entry : RecognizerStateNullableEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry completed) :
    entry.functionalConfig.candidate =
      chartHeadValue completed.workspace position := by
  have headLocal : entry.bound.local? 36 = some (.signed .i32
      (chartHeadValue completed.workspace position)) := by
    rw [entry.boundEq]
    exact bindLocal_finds_local entry.headRead.after 36
      (.signed .i32 (chartHeadValue completed.workspace position))
      entry.headRead.invariant.wellFormed
  cases cursorEq : entry.cursor with
  | inl active =>
      obtain ⟨nullableCurrent, nullableRemaining, invariant⟩ := active
      have cursorLocal : entry.bound.local? 36 =
          some (.signed .i32 (Int.ofNat nullableCurrent)) :=
        Assertion.localPointsTo_local 36 entry.nullableCursorCell
          (.signed .i32 (Int.ofNat nullableCurrent)) entry.bound
          invariant.chartCursor.cursorOwned
      have valueEq : Int.ofNat nullableCurrent =
          chartHeadValue completed.workspace position := by
        have same := Option.some.inj (cursorLocal.symm.trans headLocal)
        injection same
      simpa only [RecognizerStateNullableEntry.functionalConfig, cursorEq,
        RecognizerNullableConfig.candidate] using valueEq
  | inr invariant =>
      have cursorLocal : entry.bound.local? 36 =
          some (.signed .i32 (-1)) :=
        Assertion.localPointsTo_local 36 entry.nullableCursorCell
          (.signed .i32 (-1)) entry.bound invariant.chartCursor.cursorOwned
      have valueEq : (-1 : Int) =
          chartHeadValue completed.workspace position := by
        have same := Option.some.inj (cursorLocal.symm.trans headLocal)
        injection same
      simpa only [RecognizerStateNullableEntry.functionalConfig, cursorEq,
        RecognizerNullableConfig.candidate] using valueEq

/-- After prediction, the compact nullable environment is exactly the
    projection of the real source frame with its chart-head local appended.
    Mutable prediction slots come from the prediction postcondition; parent
    fields outside that embedding come from its frame-preservation theorem. -/
private theorem
    RecognizerStateNullableEntry.functionalConfig_environment_extends
    (entry : RecognizerStateNullableEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry completed)
    (environment : Lanius.FunctionalView.Env 17)
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment)
    (afterPrediction : Lanius.FunctionalView.Env 22)
    (predictionRelated : Lanius.FunctionalView.Env.Extends
      predictionIntoStateEmbedding
      (predictionEnvironment words completed.workspaceValues grammarCell
        workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset
        position predictionEntry.first predictionEntry.count
        predictionEntry.count completed.workspace.states.length)
      afterPrediction)
    (predictionPreserved : Lanius.FunctionalView.Env.PreservesOutside
      predictionIntoStateEmbedding
      (statePredictionEnvironmentOf environment
        ((grammar.productionAt
          ⟨candidate.production, productionBound⟩).rhs.get
            ⟨candidate.dot, dotBeforeEnd⟩)
        nonterminalBinding.nonterminal predictionEntry.first
        predictionEntry.count)
      afterPrediction) :
    Lanius.FunctionalView.Env.Extends nullableIntoStateEmbedding
      entry.functionalConfig.functionalRuntime.environment
      (afterPrediction.push (.signed .i32
        (chartHeadValue completed.workspace position))) := by
  let symbol := (grammar.productionAt
    ⟨candidate.production, productionBound⟩).rhs.get
      ⟨candidate.dot, dotBeforeEnd⟩
  let beforePrediction := statePredictionEnvironmentOf environment symbol
    nonterminalBinding.nonterminal predictionEntry.first predictionEntry.count
  let afterNullable := afterPrediction.push (.signed .i32
    (chartHeadValue completed.workspace position))
  have compactEnvironment :
      entry.functionalConfig.functionalRuntime.environment =
        nullableEnvironment words completed.workspaceValues grammarCell
          workspaceCell workspaceLayout completed.workspace.states.length
          position current candidate.production candidate.dot candidate.origin
          nonterminalBinding.nonterminal
          (chartHeadValue completed.workspace position) := by
    change nullableEnvironment words entry.functionalConfig.workspaceValues
      grammarCell workspaceCell workspaceLayout
      entry.functionalConfig.workspace.states.length position current
      candidate.production candidate.dot candidate.origin
      nonterminalBinding.nonterminal entry.functionalConfig.candidate = _
    rw [entry.functionalConfig_workspaceValues,
      entry.functionalConfig_workspace, entry.functionalConfig_candidate]
  have oldAfter (sourceIndex : Fin 22) :
      afterNullable (Fin.castSucc sourceIndex) =
        afterPrediction sourceIndex := by
    exact Lanius.FunctionalView.Env.push_before _ _ sourceIndex
  have beforeOld (sourceIndex : Fin 17) :
      beforePrediction
          (Fin.castSucc (Fin.castSucc (Fin.castSucc
            (Fin.castSucc (Fin.castSucc sourceIndex))))) =
        environment sourceIndex := by
    unfold beforePrediction statePredictionEnvironmentOf
    exact (Lanius.FunctionalView.Env.push_before _ _ _).trans
      ((Lanius.FunctionalView.Env.push_before _ _ _).trans
        ((Lanius.FunctionalView.Env.push_before _ _ _).trans
          ((Lanius.FunctionalView.Env.push_before _ _ _).trans
            (Lanius.FunctionalView.Env.push_before _ _ sourceIndex))))
  have mappedGrammar : afterNullable ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell := by
    exact (oldAfter ⟨0, by omega⟩).trans (by
      simpa [predictionIntoStateEmbedding, predictionEnvironment] using
        predictionRelated ⟨0, by omega⟩)
  have mappedWorkspace : afterNullable ⟨3, by omega⟩ =
      workspaceValue completed.workspaceValues workspaceCell := by
    exact (oldAfter ⟨3, by omega⟩).trans (by
      simpa [predictionIntoStateEmbedding, predictionEnvironment] using
        predictionRelated ⟨1, by omega⟩)
  have mappedStateBase : afterNullable ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)) := by
    exact (oldAfter ⟨4, by omega⟩).trans (by
      simpa [predictionIntoStateEmbedding, predictionEnvironment] using
        predictionRelated ⟨2, by omega⟩)
  have mappedCapacity : afterNullable ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat workspaceLayout.capacity) := by
    have related := predictionRelated ⟨3, by omega⟩
    change afterPrediction ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat workspaceLayout.capacity) at related
    exact (oldAfter ⟨5, by omega⟩).trans related
  have mappedStateCount : afterNullable ⟨10, by omega⟩ =
      .signed .i32 (Int.ofNat completed.workspace.states.length) := by
    have related := predictionRelated ⟨5, by omega⟩
    change afterPrediction ⟨10, by omega⟩ =
      .signed .i32 (Int.ofNat completed.workspace.states.length) at related
    exact (oldAfter ⟨10, by omega⟩).trans related
  have mappedPosition : afterNullable ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat position) := by
    have related := predictionRelated ⟨6, by omega⟩
    change afterPrediction ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat position) at related
    exact (oldAfter ⟨11, by omega⟩).trans related
  let source12 : Fin 22 := ⟨12, by omega⟩
  let source13 : Fin 22 := ⟨13, by omega⟩
  let source14 : Fin 22 := ⟨14, by omega⟩
  let source15 : Fin 22 := ⟨15, by omega⟩
  let source18 : Fin 22 := ⟨18, by omega⟩
  have outsideOf (target : Fin 22)
      (targetOutside : target.val ≠ 0 ∧ target.val ≠ 3 ∧
        target.val ≠ 4 ∧ target.val ≠ 5 ∧ target.val ≠ 9 ∧
        target.val ≠ 10 ∧ target.val ≠ 11 ∧ target.val ≠ 19 ∧
        target.val ≠ 20 ∧ target.val ≠ 21) :
      ∀ sourceIndex, predictionIntoStateEmbedding.slot sourceIndex ≠
        target := by
    intro sourceIndex same
    have sourceCases : sourceIndex.val = 0 ∨ sourceIndex.val = 1 ∨
        sourceIndex.val = 2 ∨ sourceIndex.val = 3 ∨ sourceIndex.val = 4 ∨
        sourceIndex.val = 5 ∨ sourceIndex.val = 6 ∨ sourceIndex.val = 7 ∨
        sourceIndex.val = 8 ∨ sourceIndex.val = 9 := by omega
    have sameVal := congrArg Fin.val same
    rcases sourceCases with zero | one | two | three | four | five | six |
        seven | eight | nine
    · have sourceEq : sourceIndex = ⟨0, by omega⟩ := Fin.ext zero
      rw [sourceEq] at sameVal
      simp [predictionIntoStateEmbedding] at sameVal
      exact targetOutside.1 sameVal.symm
    · have sourceEq : sourceIndex = ⟨1, by omega⟩ := Fin.ext one
      rw [sourceEq] at sameVal
      simp [predictionIntoStateEmbedding] at sameVal
      exact targetOutside.2.1 sameVal.symm
    · have sourceEq : sourceIndex = ⟨2, by omega⟩ := Fin.ext two
      rw [sourceEq] at sameVal
      simp [predictionIntoStateEmbedding] at sameVal
      exact targetOutside.2.2.1 sameVal.symm
    · have sourceEq : sourceIndex = ⟨3, by omega⟩ := Fin.ext three
      rw [sourceEq] at sameVal
      change 5 = target.val at sameVal
      exact targetOutside.2.2.2.1 sameVal.symm
    · have sourceEq : sourceIndex = ⟨4, by omega⟩ := Fin.ext four
      rw [sourceEq] at sameVal
      change 9 = target.val at sameVal
      exact targetOutside.2.2.2.2.1 sameVal.symm
    · have sourceEq : sourceIndex = ⟨5, by omega⟩ := Fin.ext five
      rw [sourceEq] at sameVal
      change 10 = target.val at sameVal
      exact targetOutside.2.2.2.2.2.1 sameVal.symm
    · have sourceEq : sourceIndex = ⟨6, by omega⟩ := Fin.ext six
      rw [sourceEq] at sameVal
      change 11 = target.val at sameVal
      exact targetOutside.2.2.2.2.2.2.1 sameVal.symm
    · have sourceEq : sourceIndex = ⟨7, by omega⟩ := Fin.ext seven
      rw [sourceEq] at sameVal
      change 19 = target.val at sameVal
      exact targetOutside.2.2.2.2.2.2.2.1 sameVal.symm
    · have sourceEq : sourceIndex = ⟨8, by omega⟩ := Fin.ext eight
      rw [sourceEq] at sameVal
      change 20 = target.val at sameVal
      exact targetOutside.2.2.2.2.2.2.2.2.1 sameVal.symm
    · have sourceEq : sourceIndex = ⟨9, by omega⟩ := Fin.ext nine
      rw [sourceEq] at sameVal
      change 21 = target.val at sameVal
      exact targetOutside.2.2.2.2.2.2.2.2.2 sameVal.symm
  have outside12 : ∀ sourceIndex,
      predictionIntoStateEmbedding.slot sourceIndex ≠ source12 := by
    apply outsideOf
    simp [source12]
  have outside13 : ∀ sourceIndex,
      predictionIntoStateEmbedding.slot sourceIndex ≠ source13 := by
    apply outsideOf
    simp [source13]
  have outside14 : ∀ sourceIndex,
      predictionIntoStateEmbedding.slot sourceIndex ≠ source14 := by
    apply outsideOf
    simp [source14]
  have outside15 : ∀ sourceIndex,
      predictionIntoStateEmbedding.slot sourceIndex ≠ source15 := by
    apply outsideOf
    simp [source15]
  have outside18 : ∀ sourceIndex,
      predictionIntoStateEmbedding.slot sourceIndex ≠ source18 := by
    apply outsideOf
    simp [source18]
  have preservedCurrent : afterNullable ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat current) := by
    calc
      afterNullable ⟨12, by omega⟩ = afterPrediction ⟨12, by omega⟩ :=
        oldAfter ⟨12, by omega⟩
      _ = beforePrediction ⟨12, by omega⟩ :=
        by
          have preserved := predictionPreserved source12 outside12
          change afterPrediction ⟨12, by omega⟩ =
            beforePrediction ⟨12, by omega⟩ at preserved
          exact preserved
      _ = _ := (beforeOld ⟨12, by omega⟩).trans meaning.currentEq
  have preservedProduction : afterNullable ⟨13, by omega⟩ =
      .signed .i32 (Int.ofNat candidate.production) := by
    calc
      afterNullable ⟨13, by omega⟩ = afterPrediction ⟨13, by omega⟩ :=
        oldAfter ⟨13, by omega⟩
      _ = beforePrediction ⟨13, by omega⟩ :=
        by
          have preserved := predictionPreserved source13 outside13
          change afterPrediction ⟨13, by omega⟩ =
            beforePrediction ⟨13, by omega⟩ at preserved
          exact preserved
      _ = _ := (beforeOld ⟨13, by omega⟩).trans meaning.productionEq
  have preservedDot : afterNullable ⟨14, by omega⟩ =
      .signed .i32 (Int.ofNat candidate.dot) := by
    calc
      afterNullable ⟨14, by omega⟩ = afterPrediction ⟨14, by omega⟩ :=
        oldAfter ⟨14, by omega⟩
      _ = beforePrediction ⟨14, by omega⟩ :=
        by
          have preserved := predictionPreserved source14 outside14
          change afterPrediction ⟨14, by omega⟩ =
            beforePrediction ⟨14, by omega⟩ at preserved
          exact preserved
      _ = _ := (beforeOld ⟨14, by omega⟩).trans meaning.dotEq
  have preservedOrigin : afterNullable ⟨15, by omega⟩ =
      .signed .i32 (Int.ofNat candidate.origin) := by
    calc
      afterNullable ⟨15, by omega⟩ = afterPrediction ⟨15, by omega⟩ :=
        oldAfter ⟨15, by omega⟩
      _ = beforePrediction ⟨15, by omega⟩ :=
        by
          have preserved := predictionPreserved source15 outside15
          change afterPrediction ⟨15, by omega⟩ =
            beforePrediction ⟨15, by omega⟩ at preserved
          exact preserved
      _ = _ := (beforeOld ⟨15, by omega⟩).trans meaning.originEq
  have beforeExpected : beforePrediction ⟨18, by omega⟩ =
      .signed .i32 (Int.ofNat nonterminalBinding.nonterminal) := by
    unfold beforePrediction statePredictionEnvironmentOf
    exact (Lanius.FunctionalView.Env.push_before _ _ _).trans
      ((Lanius.FunctionalView.Env.push_before _ _ _).trans
        ((Lanius.FunctionalView.Env.push_before _ _ _).trans
          (Lanius.FunctionalView.Env.push_last _ _)))
  have preservedExpected : afterNullable ⟨18, by omega⟩ =
      .signed .i32 (Int.ofNat nonterminalBinding.nonterminal) := by
    calc
      afterNullable ⟨18, by omega⟩ = afterPrediction ⟨18, by omega⟩ :=
        oldAfter ⟨18, by omega⟩
      _ = beforePrediction ⟨18, by omega⟩ :=
        by
          have preserved := predictionPreserved source18 outside18
          change afterPrediction ⟨18, by omega⟩ =
            beforePrediction ⟨18, by omega⟩ at preserved
          exact preserved
      _ = _ := beforeExpected
  have chartHeadSlot : afterNullable ⟨22, by omega⟩ =
      .signed .i32 (chartHeadValue completed.workspace position) := by
    exact Lanius.FunctionalView.Env.push_last _ _
  change Lanius.FunctionalView.Env.Extends nullableIntoStateEmbedding
    entry.functionalConfig.functionalRuntime.environment afterNullable
  rw [compactEnvironment]
  intro index
  have indexCases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
      index.val = 3 ∨ index.val = 4 ∨ index.val = 5 ∨
      index.val = 6 ∨ index.val = 7 ∨ index.val = 8 ∨
      index.val = 9 ∨ index.val = 10 ∨ index.val = 11 := by omega
  rcases indexCases with zero | one | two | three | four | five | six |
      seven | eight | nine | ten | eleven
  · have same : index = ⟨0, by omega⟩ := Fin.ext zero
    rw [same]
    change afterNullable ⟨0, by omega⟩ = _
    exact mappedGrammar
  · have same : index = ⟨1, by omega⟩ := Fin.ext one
    rw [same]
    change afterNullable ⟨3, by omega⟩ = _
    exact mappedWorkspace
  · have same : index = ⟨2, by omega⟩ := Fin.ext two
    rw [same]
    change afterNullable ⟨4, by omega⟩ = _
    exact mappedStateBase
  · have same : index = ⟨3, by omega⟩ := Fin.ext three
    rw [same]
    change afterNullable ⟨5, by omega⟩ = _
    exact mappedCapacity
  · have same : index = ⟨4, by omega⟩ := Fin.ext four
    rw [same]
    change afterNullable ⟨10, by omega⟩ = _
    exact mappedStateCount
  · have same : index = ⟨5, by omega⟩ := Fin.ext five
    rw [same]
    change afterNullable ⟨11, by omega⟩ = _
    exact mappedPosition
  · have same : index = ⟨6, by omega⟩ := Fin.ext six
    rw [same]
    change afterNullable ⟨12, by omega⟩ = _
    exact preservedCurrent
  · have same : index = ⟨7, by omega⟩ := Fin.ext seven
    rw [same]
    change afterNullable ⟨13, by omega⟩ = _
    exact preservedProduction
  · have same : index = ⟨8, by omega⟩ := Fin.ext eight
    rw [same]
    change afterNullable ⟨14, by omega⟩ = _
    exact preservedDot
  · have same : index = ⟨9, by omega⟩ := Fin.ext nine
    rw [same]
    change afterNullable ⟨15, by omega⟩ = _
    exact preservedOrigin
  · have same : index = ⟨10, by omega⟩ := Fin.ext ten
    rw [same]
    change afterNullable ⟨18, by omega⟩ = _
    exact preservedExpected
  · have same : index = ⟨11, by omega⟩ := Fin.ext eleven
    rw [same]
    change afterNullable ⟨22, by omega⟩ = _
    exact chartHeadSlot

/-- Project the two embedded nonterminal loops back to the decoded-state
    source frame.  Nullable-owned slots come from its compact postcondition;
    the LHS-production slot comes from prediction; every remaining source slot
    is preserved by both embeddings. -/
private theorem StateAfterBindingsEnvironment.after_nonterminal_projection
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell position current production dot origin rhsLength
      environment)
    (symbol nonterminal first count : Nat) (chartHead : Int)
    (predictionWorkspace : LogicalWorkspace) (predictionValues : List Int)
    (finalWorkspace : LogicalWorkspace) (finalValues : List Int)
    (afterPrediction : Lanius.FunctionalView.Env 22)
    (afterNullable : Lanius.FunctionalView.Env 23)
    (predictionRelated : Lanius.FunctionalView.Env.Extends
      predictionIntoStateEmbedding
      (predictionEnvironment words predictionValues grammarCell workspaceCell
        workspaceLayout grammarLayout.lhsProductionsOffset position first count
        count predictionWorkspace.states.length) afterPrediction)
    (predictionPreserved : Lanius.FunctionalView.Env.PreservesOutside
      predictionIntoStateEmbedding
      (statePredictionEnvironmentOf environment symbol nonterminal first count)
      afterPrediction)
    (nullableRelated : Lanius.FunctionalView.Env.Extends
      nullableIntoStateEmbedding
      (nullableEnvironment words finalValues grammarCell workspaceCell
        workspaceLayout finalWorkspace.states.length position current
        production dot origin nonterminal (-1)) afterNullable)
    (nullablePreserved : Lanius.FunctionalView.Env.PreservesOutside
      nullableIntoStateEmbedding
      (afterPrediction.push (.signed .i32 chartHead)) afterNullable) :
    StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout finalWorkspace finalValues grammarCell tokensCell
      workspaceCell position current production dot origin rhsLength
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.pop
              (Lanius.FunctionalView.Stateful.Env.pop
                (Lanius.FunctionalView.Stateful.Env.pop afterNullable)))))) := by
  let beforePrediction := statePredictionEnvironmentOf environment symbol
    nonterminal first count
  let beforeNullable := afterPrediction.push (.signed .i32 chartHead)
  let afterEnvironment : Lanius.FunctionalView.Env 17 :=
    Lanius.FunctionalView.Stateful.Env.pop
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.pop
              (Lanius.FunctionalView.Stateful.Env.pop afterNullable)))))
  have beforePredictionOld (index : Fin 17) :
      beforePrediction ⟨index.val, by omega⟩ = environment index := by
    unfold beforePrediction statePredictionEnvironmentOf
    exact (Lanius.FunctionalView.Env.push_before _ _ _).trans
      ((Lanius.FunctionalView.Env.push_before _ _ _).trans
        ((Lanius.FunctionalView.Env.push_before _ _ _).trans
          ((Lanius.FunctionalView.Env.push_before _ _ _).trans
            (Lanius.FunctionalView.Env.push_before _ _ index))))
  have nullablePreservedAt (index : Fin 17)
      (outside : ∀ sourceIndex,
        nullableIntoStateEmbedding.slot sourceIndex ≠
          (⟨index.val, by omega⟩ : Fin 23)) :
      afterEnvironment index = afterPrediction ⟨index.val, by omega⟩ := by
    calc
      afterEnvironment index = afterNullable ⟨index.val, by omega⟩ := rfl
      _ = beforeNullable ⟨index.val, by omega⟩ :=
        nullablePreserved ⟨index.val, by omega⟩ outside
      _ = afterPrediction ⟨index.val, by omega⟩ := by
        simpa [beforeNullable] using
          (Lanius.FunctionalView.Env.push_before afterPrediction
            (.signed .i32 chartHead) (⟨index.val, by omega⟩ : Fin 22))
  have preservedOld (index : Fin 17)
      (outsideNullable : ∀ sourceIndex,
        nullableIntoStateEmbedding.slot sourceIndex ≠
          (⟨index.val, by omega⟩ : Fin 23))
      (outsidePrediction : ∀ sourceIndex,
        predictionIntoStateEmbedding.slot sourceIndex ≠
          (⟨index.val, by omega⟩ : Fin 22)) :
      afterEnvironment index = environment index := by
    calc
      afterEnvironment index = afterPrediction ⟨index.val, by omega⟩ :=
        nullablePreservedAt index outsideNullable
      _ = beforePrediction ⟨index.val, by omega⟩ :=
        predictionPreserved ⟨index.val, by omega⟩ outsidePrediction
      _ = environment index := beforePredictionOld index
  have nullableMapped (small : Fin 12) (large : Fin 23)
      (slotEq : nullableIntoStateEmbedding.slot small = large) :
      afterNullable large =
        nullableEnvironment words finalValues grammarCell workspaceCell
          workspaceLayout finalWorkspace.states.length position current
          production dot origin nonterminal (-1) small := by
    rw [← slotEq]
    exact nullableRelated small
  have predictionMapped (small : Fin 10) (large : Fin 22)
      (slotEq : predictionIntoStateEmbedding.slot small = large) :
      afterPrediction large =
        predictionEnvironment words predictionValues grammarCell workspaceCell
          workspaceLayout grammarLayout.lhsProductionsOffset position first count
          count predictionWorkspace.states.length small := by
    rw [← slotEq]
    exact predictionRelated small
  exact {
    grammarEq := by
      change afterNullable 0 = parserGrammarValue words grammarCell
      simpa [nullableEnvironment] using nullableMapped 0 0 (by native_decide)
    tokensEq := (preservedOld 1 (by native_decide) (by native_decide)).trans
      meaning.tokensEq
    tokenCountEq :=
      (preservedOld 2 (by native_decide) (by native_decide)).trans
        meaning.tokenCountEq
    workspaceEq := by
      change afterNullable 3 = workspaceValue finalValues workspaceCell
      simpa [nullableEnvironment] using nullableMapped 1 3 (by native_decide)
    stateBaseEq := by
      change afterNullable 4 =
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))
      simpa [nullableEnvironment] using nullableMapped 2 4 (by native_decide)
    capacityEq := by
      change afterNullable 5 =
        .signed .i32 (Int.ofNat workspaceLayout.capacity)
      simpa [nullableEnvironment] using nullableMapped 3 5 (by native_decide)
    kindCountEq :=
      (preservedOld 6 (by native_decide) (by native_decide)).trans
        meaning.kindCountEq
    lhsOffsetsEq :=
      (preservedOld 7 (by native_decide) (by native_decide)).trans
        meaning.lhsOffsetsEq
    lhsCountsEq :=
      (preservedOld 8 (by native_decide) (by native_decide)).trans
        meaning.lhsCountsEq
    lhsProductionsEq := by
      calc
        afterEnvironment 9 = afterPrediction 9 :=
          nullablePreservedAt 9 (by native_decide)
        _ = .signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset) := by
          simpa [predictionEnvironment] using
            predictionMapped 4 9 (by native_decide)
    stateCountEq := by
      change afterNullable 10 =
        .signed .i32 (Int.ofNat finalWorkspace.states.length)
      simpa [nullableEnvironment] using nullableMapped 4 10 (by native_decide)
    positionEq := by
      change afterNullable 11 = .signed .i32 (Int.ofNat position)
      simpa [nullableEnvironment] using nullableMapped 5 11 (by native_decide)
    currentEq := by
      change afterNullable 12 = .signed .i32 (Int.ofNat current)
      simpa [nullableEnvironment] using nullableMapped 6 12 (by native_decide)
    productionEq := by
      change afterNullable 13 = .signed .i32 (Int.ofNat production)
      simpa [nullableEnvironment] using nullableMapped 7 13 (by native_decide)
    dotEq := by
      change afterNullable 14 = .signed .i32 (Int.ofNat dot)
      simpa [nullableEnvironment] using nullableMapped 8 14 (by native_decide)
    originEq := by
      change afterNullable 15 = .signed .i32 (Int.ofNat origin)
      simpa [nullableEnvironment] using nullableMapped 9 15 (by native_decide)
    rhsLengthEq :=
      (preservedOld 16 (by native_decide) (by native_decide)).trans
        meaning.rhsLengthEq
  }

/-- Computational result of the complete nonterminal command.  This lives in
    `Type`, because the synchronized branch is consumed by the enclosing
    FunctionalView executor rather than merely asserted as a proposition. -/
private structure RecognizerStateFunctionalNonterminalBranch
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound)
    (symbolBinding : RecognizerStateSymbolBinding grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isNonterminal : ¬
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩ <
        grammar.grammar.n_kinds)
    (nonterminalBinding : RecognizerStateNonterminalIndexBinding grammarLayout
      grammar words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal)
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding)
    (environment : Lanius.FunctionalView.Env 17) where
  completion : Lanius.FunctionalView.Stateful.Completion
  afterWorld : Lanius.FunctionalView.Core.ReadOnly.World
  afterEnvironment : Lanius.FunctionalView.Env 18
  execution : Lanius.FunctionalView.Stateful.Command.Evaluates
    (stateTermMachine workspaceLayout grammar words tokens grammarCell tokensCell)
    (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    (environment.push (.signed .i32 (Int.ofNat
      ((grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))))
    stateNonterminalCommand completion afterWorld afterEnvironment
  completionEq : Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion =
    entry.execute_nonterminal_inner.completion
  restored : entry.execute_nonterminal_inner.outcome.flatten.FunctionalRestored
    afterWorld (Lanius.FunctionalView.Stateful.Env.pop afterEnvironment)

/-- The complete nonterminal command in the real source frame executes via
    the synchronized prediction and nullable FunctionalView loops. -/
private noncomputable def
    RecognizerStatePredictionEntry.functional_nonterminal_branch
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding)
    (environment : Lanius.FunctionalView.Env 17)
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment) :
    RecognizerStateFunctionalNonterminalBranch grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell workspaceCell
      stateCountCell cursorCell before position current remaining beforeInvariant
      candidate found productionBound dotBeforeEnd bindings symbolBinding
      isNonterminal nonterminalBinding entry environment := by
  let symbol := (grammar.productionAt
    ⟨candidate.production, productionBound⟩).rhs.get
      ⟨candidate.dot, dotBeforeEnd⟩
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  generalize innerEq : entry.execute_nonterminal_inner = inner
  obtain ⟨innerAfter, innerCompletion, innerExecution, innerEffect,
    innerOutcome⟩ := inner
  generalize sourceOutcomeEq : innerOutcome.flatten = sourceOutcome
  let symbolEnvironment := environment.push
    (.signed .i32 (Int.ofNat symbol))
  let beforePrediction := statePredictionEnvironmentOf environment symbol
    nonterminalBinding.nonterminal entry.first entry.count
  have nonterminalResult := entry.functional_nonterminal environment meaning
  have firstResult := entry.functional_first environment meaning
  have countResult := entry.functional_count environment meaning
  have related : Lanius.FunctionalView.Env.Extends predictionIntoStateEmbedding
      entry.functionalConfig.functionalRuntime.environment beforePrediction := by
    simpa [beforePrediction, symbol] using
      entry.functionalConfig_environment_extends environment meaning
  obtain ⟨afterPrediction, predictionResult, relatedAfter, preservedAfter⟩ :=
    entry.functionalConfig.evaluates_in_state_machine beforePrediction related
  have predictionWorldEq :
      entry.functionalConfig.functionalRuntime.world = world := by
    change recognizerWorld words tokens
      entry.functionalConfig.workspaceValues grammarCell tokensCell
      workspaceCell = _
    rw [entry.functionalConfig_workspaceValues]
    rfl
  rw [predictionWorldEq] at predictionResult
  have predictionResult' :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        world
        ((((symbolEnvironment.push
          (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal))).push
          (.signed .i32 (Int.ofNat entry.first))).push
          (.signed .i32 (Int.ofNat entry.count))).push (.signed .i32 0))
        statePredictionLoopCommand
        entry.functionalConfig.functional_run.completion
        entry.functionalConfig.functional_run.after.world afterPrediction := by
    simpa [beforePrediction, symbolEnvironment,
      statePredictionEnvironmentOf] using predictionResult
  cases sourceOutcome with
  | completed predictionFrame predictionCompletionEq predictionAfterWorldEq
      predictionAfterEnvironmentEq nullableEntry nullableCompletionEq
      finalWorkspace finalValues innerAfter growth frame nullableAfterWorldEq
      nullableAfterEnvironmentEq =>
    rw [predictionCompletionEq] at predictionResult'
    have relatedAfter' : Lanius.FunctionalView.Env.Extends
        predictionIntoStateEmbedding
        (predictionEnvironment words predictionFrame.workspaceValues grammarCell
          workspaceCell
          workspaceLayout grammarLayout.lhsProductionsOffset position
          entry.first entry.count entry.count
          predictionFrame.workspace.states.length)
        afterPrediction := by
      rw [← predictionAfterEnvironmentEq]
      exact relatedAfter
    have workspaceSlot : afterPrediction ⟨3, by omega⟩ =
        workspaceValue predictionFrame.workspaceValues workspaceCell := by
      have mapped := relatedAfter' ⟨1, by omega⟩
      change afterPrediction ⟨3, by omega⟩ =
        workspaceValue predictionFrame.workspaceValues workspaceCell at mapped
      exact mapped
    have positionSlot : afterPrediction ⟨11, by omega⟩ =
        .signed .i32 (Int.ofNat position) := by
      have mapped := relatedAfter' ⟨6, by omega⟩
      change afterPrediction ⟨11, by omega⟩ =
        .signed .i32 (Int.ofNat position) at mapped
      exact mapped
    have workspaceFound :
        entry.functionalConfig.functional_run.after.world.i32Slice?
          workspaceCell = some predictionFrame.workspaceValues := by
      rw [predictionAfterWorldEq]
      exact stateWorld_finds_workspace
        predictionFrame.predictionInvariant.frame.recognizer.grammarWorkspaceDistinct
        predictionFrame.predictionInvariant.frame.recognizer.tokensWorkspaceDistinct
    have chartHeadResult : Lanius.FunctionalView.Term.evaluate
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        entry.functionalConfig.functional_run.after.world afterPrediction
        (stateChartHeadTerm ⟨3, by omega⟩ ⟨11, by omega⟩) =
        .ok (.signed .i32 (chartHeadValue predictionFrame.workspace position),
          entry.functionalConfig.functional_run.after.world) :=
      stateChartHeadTerm_evaluates workspaceLayout grammar words tokens
        grammarCell tokensCell workspaceCell
        entry.functionalConfig.functional_run.after.world afterPrediction
        ⟨3, by omega⟩ ⟨11, by omega⟩ predictionFrame.workspace
        predictionFrame.workspaceValues position
        workspaceSlot positionSlot workspaceFound
        predictionFrame.predictionInvariant.frame.recognizer.workspaceLength
        predictionFrame.predictionInvariant.frame.recognizer.workspaceEncoded
        predictionFrame.predictionInvariant.frame.positionBound
    have nullableRelated : Lanius.FunctionalView.Env.Extends
        nullableIntoStateEmbedding
        nullableEntry.functionalConfig.functionalRuntime.environment
        (afterPrediction.push (.signed .i32
          (chartHeadValue predictionFrame.workspace position))) := by
      exact nullableEntry.functionalConfig_environment_extends environment
        meaning afterPrediction relatedAfter' preservedAfter
    obtain ⟨afterNullable, nullableResult, nullableRelatedAfter,
      nullablePreservedAfter⟩ :=
      nullableEntry.functionalConfig.evaluates_in_state_machine
        (afterPrediction.push (.signed .i32
          (chartHeadValue predictionFrame.workspace position))) nullableRelated
    have nullableWorldEq :
        nullableEntry.functionalConfig.functionalRuntime.world =
          entry.functionalConfig.functional_run.after.world := by
      change nullableWorld words tokens
        nullableEntry.functionalConfig.workspaceValues grammarCell tokensCell
        workspaceCell = _
      rw [nullableEntry.functionalConfig_workspaceValues,
        predictionAfterWorldEq]
      rfl
    rw [nullableWorldEq] at nullableResult
    let afterEnvironment := Lanius.FunctionalView.Stateful.Env.pop
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.pop afterNullable))))
    have functionalExecution := stateNonterminalCommand_evaluates_of_nullable world
      entry.functionalConfig.functional_run.after.world
      nullableEntry.functionalConfig.functional_run.after.world
      symbolEnvironment nonterminalBinding.nonterminal entry.first entry.count
      (chartHeadValue predictionFrame.workspace position) afterPrediction
      afterNullable
      nullableEntry.functionalConfig.functional_run.completion
      (by simpa [world, symbolEnvironment, symbol] using nonterminalResult)
      (by simpa [world, symbolEnvironment, symbol] using firstResult)
      (by simpa [world, symbolEnvironment, symbol] using countResult)
      predictionResult' chartHeadResult nullableResult
    have nullableRelatedFinal : Lanius.FunctionalView.Env.Extends
        nullableIntoStateEmbedding
        (nullableEnvironment words finalValues grammarCell workspaceCell
          workspaceLayout finalWorkspace.states.length position current
          candidate.production candidate.dot candidate.origin
          nonterminalBinding.nonterminal (-1)) afterNullable := by
      rw [← nullableAfterEnvironmentEq]
      exact nullableRelatedAfter
    have finalWorldEq :
        nullableEntry.functionalConfig.functional_run.after.world =
          stateWorld words tokens finalValues grammarCell tokensCell
            workspaceCell := by
      change nullableEntry.functionalConfig.functional_run.after.world =
        stateWorld words tokens finalValues grammarCell tokensCell workspaceCell
        at nullableAfterWorldEq
      exact nullableAfterWorldEq
    have afterMeaning := meaning.after_nonterminal_projection symbol
      nonterminalBinding.nonterminal entry.first entry.count
      (chartHeadValue predictionFrame.workspace position)
      predictionFrame.workspace predictionFrame.workspaceValues finalWorkspace
      finalValues afterPrediction afterNullable relatedAfter' preservedAfter
      nullableRelatedFinal nullablePreservedAfter
    refine ⟨nullableEntry.functionalConfig.functional_run.completion,
      nullableEntry.functionalConfig.functional_run.after.world,
      afterEnvironment, functionalExecution, ?_, ?_⟩
    · simpa [innerEq, nullableCompletionEq,
        Lanius.FunctionalView.Core.Stateful.toCoreCompletion]
    · rw [innerEq, sourceOutcomeEq]
      exact ⟨finalWorldEq, by simpa [afterEnvironment] using afterMeaning⟩
  | nullableFull predictionFrame predictionCompletionEq
      predictionAfterWorldEq predictionAfterEnvironmentEq nullableEntry
      finalWorkspace finalValues innerAfter growth terminal stateCount wellFormed
      nullableCompletionEq nullableStops =>
    rw [predictionCompletionEq] at predictionResult'
    have relatedAfter' : Lanius.FunctionalView.Env.Extends
        predictionIntoStateEmbedding
        (predictionEnvironment words predictionFrame.workspaceValues grammarCell
          workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset
          position entry.first entry.count entry.count
          predictionFrame.workspace.states.length) afterPrediction := by
      rw [← predictionAfterEnvironmentEq]
      exact relatedAfter
    have workspaceSlot : afterPrediction ⟨3, by omega⟩ =
        workspaceValue predictionFrame.workspaceValues workspaceCell := by
      have mapped := relatedAfter' ⟨1, by omega⟩
      exact mapped
    have positionSlot : afterPrediction ⟨11, by omega⟩ =
        .signed .i32 (Int.ofNat position) := by
      have mapped := relatedAfter' ⟨6, by omega⟩
      exact mapped
    have workspaceFound :
        entry.functionalConfig.functional_run.after.world.i32Slice?
          workspaceCell = some predictionFrame.workspaceValues := by
      rw [predictionAfterWorldEq]
      exact stateWorld_finds_workspace
        predictionFrame.predictionInvariant.frame.recognizer.grammarWorkspaceDistinct
        predictionFrame.predictionInvariant.frame.recognizer.tokensWorkspaceDistinct
    have chartHeadResult := stateChartHeadTerm_evaluates workspaceLayout grammar
      words tokens grammarCell tokensCell workspaceCell
      entry.functionalConfig.functional_run.after.world afterPrediction
      ⟨3, by omega⟩ ⟨11, by omega⟩ predictionFrame.workspace
      predictionFrame.workspaceValues position workspaceSlot positionSlot
      workspaceFound
      predictionFrame.predictionInvariant.frame.recognizer.workspaceLength
      predictionFrame.predictionInvariant.frame.recognizer.workspaceEncoded
      predictionFrame.predictionInvariant.frame.positionBound
    have nullableRelated : Lanius.FunctionalView.Env.Extends
        nullableIntoStateEmbedding
        nullableEntry.functionalConfig.functionalRuntime.environment
        (afterPrediction.push (.signed .i32
          (chartHeadValue predictionFrame.workspace position))) :=
      nullableEntry.functionalConfig_environment_extends environment meaning
        afterPrediction relatedAfter' preservedAfter
    obtain ⟨afterNullable, nullableResult, _, _⟩ :=
      nullableEntry.functionalConfig.evaluates_in_state_machine
        (afterPrediction.push (.signed .i32
          (chartHeadValue predictionFrame.workspace position))) nullableRelated
    have nullableWorldEq :
        nullableEntry.functionalConfig.functionalRuntime.world =
          entry.functionalConfig.functional_run.after.world := by
      change nullableWorld words tokens
        nullableEntry.functionalConfig.workspaceValues grammarCell tokensCell
        workspaceCell = _
      rw [nullableEntry.functionalConfig_workspaceValues,
        predictionAfterWorldEq]
      rfl
    rw [nullableWorldEq] at nullableResult
    let afterEnvironment := Lanius.FunctionalView.Stateful.Env.pop
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.pop afterNullable))))
    have functionalExecution := stateNonterminalCommand_evaluates_of_nullable
      world entry.functionalConfig.functional_run.after.world
      nullableEntry.functionalConfig.functional_run.after.world
      symbolEnvironment nonterminalBinding.nonterminal entry.first entry.count
      (chartHeadValue predictionFrame.workspace position) afterPrediction
      afterNullable nullableEntry.functionalConfig.functional_run.completion
      (by simpa [world, symbolEnvironment, symbol] using nonterminalResult)
      (by simpa [world, symbolEnvironment, symbol] using firstResult)
      (by simpa [world, symbolEnvironment, symbol] using countResult)
      predictionResult' chartHeadResult nullableResult
    refine ⟨nullableEntry.functionalConfig.functional_run.completion,
      nullableEntry.functionalConfig.functional_run.after.world,
      afterEnvironment, functionalExecution, ?_, ?_⟩
    · simpa [innerEq] using nullableCompletionEq
    · rw [innerEq, sourceOutcomeEq]
      trivial
  | predictionFull finalWorkspace finalValues innerAfter growth terminal
      stateCount wellFormed predictionCompletionEq predictionStops =>
    let afterEnvironment := Lanius.FunctionalView.Stateful.Env.pop
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop afterPrediction)))
    have functionalExecution := stateNonterminalCommand_evaluates_of_prediction_stop
      world entry.functionalConfig.functional_run.after.world symbolEnvironment
      nonterminalBinding.nonterminal entry.first entry.count afterPrediction
      entry.functionalConfig.functional_run.completion predictionStops
      (by simpa [world, symbolEnvironment, symbol] using nonterminalResult)
      (by simpa [world, symbolEnvironment, symbol] using firstResult)
      (by simpa [world, symbolEnvironment, symbol] using countResult)
      predictionResult'
    refine ⟨entry.functionalConfig.functional_run.completion,
      entry.functionalConfig.functional_run.after.world, afterEnvironment,
      functionalExecution, ?_, ?_⟩
    · simpa [innerEq] using predictionCompletionEq
    · rw [innerEq, sourceOutcomeEq]
      trivial

/-- The real nonterminal incomplete-state command and its extracted Core branch
    share one prediction/nullable run and one logical workspace outcome. -/
private structure RecognizerStateNonterminalFunctionalExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (runtime : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound)
    (symbolBinding : RecognizerStateSymbolBinding grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isNonterminal : ¬
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩ <
        grammar.grammar.n_kinds)
    (environment : Lanius.FunctionalView.Env 17) where
  afterWorld : Lanius.FunctionalView.Core.ReadOnly.World
  afterEnvironment : Lanius.FunctionalView.Env 17
  completion : Lanius.FunctionalView.Stateful.Completion
  physicalAfter : State
  functionalExecution : Lanius.FunctionalView.Stateful.Command.Evaluates
    (stateTermMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    environment stateIncompleteCommand completion afterWorld afterEnvironment
  physicalExecution : Executes verifiedParserCore
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)))
    parserRecognizeStateIncompleteBranch
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
    physicalAfter
  physicalEffect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell))
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length))) physicalAfter
  outcome : RecognizerStateBranchSynchronizedOutcome grammarLayout grammar
    words tokens workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell cursorCell position current remaining candidate.production
    candidate.dot candidate.origin
    (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
    afterWorld afterEnvironment physicalAfter
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)

/-- Execute the source-derived nonterminal branch once and retain both views. -/
private noncomputable def
    RecognizerStateSymbolBinding.functional_execute_nonterminal
    (symbolBinding : RecognizerStateSymbolBinding grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (environment : Lanius.FunctionalView.Env 17)
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment)
    (isNonterminal : ¬
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩ <
        grammar.grammar.n_kinds) :
    RecognizerStateNonterminalFunctionalExecution grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal environment := by
  let symbol := (grammar.productionAt ⟨candidate.production,
    productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
  let synchronized := symbolBinding.execute_nonterminal_synchronized isNonterminal
  let entry := synchronized.predictionEntry
  let operation := synchronized.physical
  obtain ⟨completion, afterWorld, branchEnvironment, branchExecution,
    completionEq, functionalRestored⟩ :=
      entry.functional_nonterminal_branch environment meaning
  have notLess : ¬ symbol < grammar.grammar.n_kinds := by
    simpa [symbol] using isNonterminal
  have functionalExecution := stateIncompleteCommand_evaluates_of_symbol
    workspaceLayout grammar words tokens grammarCell tokensCell
    (stateWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    environment candidate.production candidate.dot symbol productionBound
    dotBeforeEnd rfl grammar.grammar.n_kinds meaning.grammarEq
    meaning.productionEq meaning.dotEq meaning.kindCountEq
    stateWorld_finds_grammar false (by simp [notLess]) branchExecution
  have physicalCompletionEq :
      Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion =
        operation.completion := completionEq.trans synchronized.completionEq.symm
  have functionalRestored' : synchronized.sourceOutcome.FunctionalRestored
      afterWorld (Lanius.FunctionalView.Stateful.Env.pop branchEnvironment) := by
    change (entry.execute_nonterminal_inner.outcome.flatten).FunctionalRestored
      afterWorld (Lanius.FunctionalView.Stateful.Env.pop branchEnvironment)
    exact functionalRestored
  exact {
    afterWorld := afterWorld
    afterEnvironment := Lanius.FunctionalView.Stateful.Env.pop branchEnvironment
    completion := completion
    physicalAfter := operation.after
    functionalExecution := functionalExecution
    physicalExecution := by
      rw [physicalCompletionEq]
      exact operation.execution
    physicalEffect := operation.effect
    outcome := by
      have shared := synchronized.sourceOutcome.branchSynchronized
        synchronized.restored functionalRestored'
      rw [synchronized.sourceCompletionEq, ← completionEq] at shared
      exact shared
  }

/-- One decoded Earley item through the source semantic conditional and the
    extracted Core conditional.  Cursor advancement is deliberately left to
    the enclosing state-step synchronization. -/
private structure RecognizerStateSemanticFunctionalExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (runtime : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound)
    (environment : Lanius.FunctionalView.Env 17) where
  afterWorld : Lanius.FunctionalView.Core.ReadOnly.World
  afterEnvironment : Lanius.FunctionalView.Env 17
  completion : Lanius.FunctionalView.Stateful.Completion
  physicalAfter : State
  functionalExecution : Lanius.FunctionalView.Stateful.Command.Evaluates
    (stateTermMachine workspaceLayout grammar words tokens grammarCell tokensCell)
    (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    environment
    (.ifThenElse (stateLessTerm ⟨14, by omega⟩ ⟨16, by omega⟩)
      stateIncompleteCommand stateCompleteCommand)
    completion afterWorld afterEnvironment
  physicalExecution : Executes verifiedParserCore
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)))
    (.ifThenElse (.binary .less (.local 26) (.local 28))
      parserRecognizeStateIncompleteBranch parserRecognizeStateCompleteBranch)
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
    physicalAfter
  physicalEffect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell))
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length))) physicalAfter
  outcome : RecognizerStateBranchSynchronizedOutcome grammarLayout grammar
    words tokens workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell cursorCell position current remaining candidate.production
    candidate.dot candidate.origin
    (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
    afterWorld afterEnvironment physicalAfter
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)

/-- Select exactly one synchronized semantic action for the decoded item. -/
private noncomputable def
    RecognizerStateCandidateBindings.functional_execute_semantic
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound)
    (environment : Lanius.FunctionalView.Env 17)
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current candidate.production candidate.dot
      candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      environment) :
    RecognizerStateSemanticFunctionalExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound bindings environment := by
  let rhsLength :=
    (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
  have sourceCondition := stateLessTerm_evaluates workspaceLayout grammar words
    tokens grammarCell tokensCell
    (stateWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    environment ⟨14, by omega⟩ ⟨16, by omega⟩ candidate.dot rhsLength
    meaning.dotEq meaning.rhsLengthEq
  by_cases dotBeforeEnd : candidate.dot < rhsLength
  · have sourceTrue : Lanius.FunctionalView.Term.evaluate
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell) environment
        (stateLessTerm ⟨14, by omega⟩ ⟨16, by omega⟩) =
        .ok (.boolean true,
          stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell) := by
      simpa [dotBeforeEnd] using sourceCondition
    have physicalTrue : Evaluates verifiedParserCore
        (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32
          (Int.ofNat rhsLength)))
        (.binary .less (.local 26) (.local 28)) (.boolean true)
        (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32
          (Int.ofNat rhsLength))) := by
      simpa [rhsLength, dotBeforeEnd] using bindings.evaluate_incomplete_test
    let symbolBinding := bindings.bind_incomplete_symbol (by
      simpa [rhsLength] using dotBeforeEnd)
    let symbol := (grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.get ⟨candidate.dot, by
        simpa [rhsLength] using dotBeforeEnd⟩
    by_cases isTerminal : symbol < grammar.grammar.n_kinds
    · let operation := symbolBinding.functional_execute_terminal environment
        meaning (by simpa [symbol] using isTerminal)
      exact {
        afterWorld := operation.afterWorld
        afterEnvironment := operation.afterEnvironment
        completion := operation.completion
        physicalAfter := operation.physicalAfter
        functionalExecution := .ifTrue sourceTrue operation.functionalExecution
        physicalExecution := executesIfTrue physicalTrue
          operation.physicalExecution
        physicalEffect := operation.physicalEffect
        outcome := operation.outcome
      }
    · let operation := symbolBinding.functional_execute_nonterminal
        environment meaning (by simpa [symbol] using isTerminal)
      exact {
        afterWorld := operation.afterWorld
        afterEnvironment := operation.afterEnvironment
        completion := operation.completion
        physicalAfter := operation.physicalAfter
        functionalExecution := .ifTrue sourceTrue operation.functionalExecution
        physicalExecution := executesIfTrue physicalTrue
          operation.physicalExecution
        physicalEffect := operation.physicalEffect
        outcome := operation.outcome
      }
  · have sourceFalse : Lanius.FunctionalView.Term.evaluate
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell) environment
        (stateLessTerm ⟨14, by omega⟩ ⟨16, by omega⟩) =
        .ok (.boolean false,
          stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell) := by
      simpa [dotBeforeEnd] using sourceCondition
    have physicalFalse : Evaluates verifiedParserCore
        (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32
          (Int.ofNat rhsLength)))
        (.binary .less (.local 26) (.local 28)) (.boolean false)
        (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32
          (Int.ofNat rhsLength))) := by
      simpa [rhsLength, dotBeforeEnd] using bindings.evaluate_incomplete_test
    have within := bindings.invariant.chartCursor.state_within_grammar
      candidate found
    have dotBound : candidate.dot ≤ rhsLength := by
      simpa [EarleyState.key, rhsLength] using within.dotBound
    have completedDot : candidate.dot = rhsLength := by omega
    let prepared := bindings.execute_complete (by
      simpa [rhsLength] using completedDot)
    obtain ⟨completedLhs, entry, physical⟩ := prepared
    let operation := entry.functional_execute_complete environment meaning
    exact {
      afterWorld := operation.afterWorld
      afterEnvironment := operation.afterEnvironment
      completion := operation.completion
      physicalAfter := operation.physicalAfter
      functionalExecution := .ifFalse sourceFalse operation.functionalExecution
      physicalExecution := executesIfFalse physicalFalse
        operation.physicalExecution
      physicalEffect := operation.physicalEffect
      outcome := operation.outcome
    }

noncomputable def RecognizerStateConfig.functionalRuntime
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position) :
    Lanius.FunctionalView.Stateful.Loop.Runtime
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell) 13 :=
  (stateWorld words tokens config.workspaceValues grammarCell tokensCell
      workspaceCell,
    stateEnvironment words tokens config.workspaceValues grammarCell tokensCell
      workspaceCell workspaceLayout grammar.grammar.n_kinds
      grammarLayout.lhsOffsetsOffset grammarLayout.lhsCountsOffset
      grammarLayout.lhsProductionsOffset config.workspace.states.length
      position config.candidate)

private noncomputable def RecognizerStateConfig.afterBindingsEnvironment
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position)
    (candidate : EarleyState) (productionBound :
      candidate.production < grammar.productionCount) :
    Lanius.FunctionalView.Env 17 :=
  ((((config.functionalRuntime.environment.push
    (.signed .i32 (Int.ofNat candidate.production))).push
    (.signed .i32 (Int.ofNat candidate.dot))).push
    (.signed .i32 (Int.ofNat candidate.origin))).push
    (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)))

/-- The four source-derived candidate bindings have the exact decoded-item
    meaning expected by every synchronized semantic branch. -/
private theorem RecognizerStateConfig.afterBindingsMeaning
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position)
    (current : Nat) (remaining : List Nat)
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words tokens
      workspaceLayout config.workspace config.workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell config.runtime position
      current remaining)
    (cursorEq : config.cursor = .inl ⟨current, remaining, invariant⟩)
    (candidate : EarleyState)
    (productionBound : candidate.production < grammar.productionCount) :
    StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout config.workspace config.workspaceValues grammarCell
      tokensCell workspaceCell position current candidate.production
      candidate.dot candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      (config.afterBindingsEnvironment candidate productionBound) := by
  have candidateEq : config.candidate = Int.ofNat current := by
    simp [RecognizerStateConfig.candidate, cursorEq]
  constructor <;>
    simp [RecognizerStateConfig.afterBindingsEnvironment,
      RecognizerStateConfig.functionalRuntime, stateEnvironment,
      Lanius.FunctionalView.Stateful.Loop.Runtime.environment,
      Lanius.FunctionalView.Env.push, Fin.ext_iff, candidateEq, cursorEq]

/-- Closing the four decoded-item locals after cursor assignment yields the
    canonical thirteen-slot state-loop environment. -/
private theorem StateAfterBindingsEnvironment.advance_pop_eq
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell position current production dot origin rhsLength
      environment)
    (nextCurrent : Int) :
    Lanius.FunctionalView.Stateful.Env.pop
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.set environment
              ⟨12, by omega⟩ (.signed .i32 nextCurrent))))) =
      stateEnvironment words tokens workspaceValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar.grammar.n_kinds
        grammarLayout.lhsOffsetsOffset grammarLayout.lhsCountsOffset
        grammarLayout.lhsProductionsOffset workspace.states.length position
        nextCurrent := by
  let updated := Lanius.FunctionalView.Stateful.Env.set environment
    (⟨12, by omega⟩ : Fin 17) (.signed .i32 nextCurrent)
  have unchanged (index : Fin 13) (different : index.val ≠ 12) :
      updated ⟨index.val, by omega⟩ = environment ⟨index.val, by omega⟩ := by
    apply Lanius.FunctionalView.Stateful.Env.set_other
    intro same
    exact different (congrArg Fin.val same)
  funext index
  have indexCases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
      index.val = 3 ∨ index.val = 4 ∨ index.val = 5 ∨
      index.val = 6 ∨ index.val = 7 ∨ index.val = 8 ∨
      index.val = 9 ∨ index.val = 10 ∨ index.val = 11 ∨
      index.val = 12 := by omega
  rcases indexCases with zero | one | two | three | four | five | six |
      seven | eight | nine | ten | eleven | twelve
  · have same : index = ⟨0, by omega⟩ := Fin.ext zero
    rw [same]
    exact (unchanged 0 (by decide)).trans meaning.grammarEq
  · have same : index = ⟨1, by omega⟩ := Fin.ext one
    rw [same]
    exact (unchanged 1 (by decide)).trans meaning.tokensEq
  · have same : index = ⟨2, by omega⟩ := Fin.ext two
    rw [same]
    exact (unchanged 2 (by decide)).trans meaning.tokenCountEq
  · have same : index = ⟨3, by omega⟩ := Fin.ext three
    rw [same]
    exact (unchanged 3 (by decide)).trans meaning.workspaceEq
  · have same : index = ⟨4, by omega⟩ := Fin.ext four
    rw [same]
    exact (unchanged 4 (by decide)).trans meaning.stateBaseEq
  · have same : index = ⟨5, by omega⟩ := Fin.ext five
    rw [same]
    exact (unchanged 5 (by decide)).trans meaning.capacityEq
  · have same : index = ⟨6, by omega⟩ := Fin.ext six
    rw [same]
    exact (unchanged 6 (by decide)).trans meaning.kindCountEq
  · have same : index = ⟨7, by omega⟩ := Fin.ext seven
    rw [same]
    exact (unchanged 7 (by decide)).trans meaning.lhsOffsetsEq
  · have same : index = ⟨8, by omega⟩ := Fin.ext eight
    rw [same]
    exact (unchanged 8 (by decide)).trans meaning.lhsCountsEq
  · have same : index = ⟨9, by omega⟩ := Fin.ext nine
    rw [same]
    exact (unchanged 9 (by decide)).trans meaning.lhsProductionsEq
  · have same : index = ⟨10, by omega⟩ := Fin.ext ten
    rw [same]
    exact (unchanged 10 (by decide)).trans meaning.stateCountEq
  · have same : index = ⟨11, by omega⟩ := Fin.ext eleven
    rw [same]
    exact (unchanged 11 (by decide)).trans meaning.positionEq
  · have same : index = ⟨12, by omega⟩ := Fin.ext twelve
    rw [same]
    exact Lanius.FunctionalView.Stateful.Env.set_same environment
      (⟨12, by omega⟩ : Fin 17) (.signed .i32 nextCurrent)

/-- One complete state-body iteration synchronized after all decoded-item
    locals have closed. -/
private inductive RecognizerStateStepSynchronizedOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position current : Nat) (remaining : List Nat)
    (afterWorld : Lanius.FunctionalView.Core.ReadOnly.World)
    (afterEnvironment : Lanius.FunctionalView.Env 13) :
    State → Lanius.FunctionalView.Stateful.Completion → Type where
  | advanced (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (next : Nat) (nextRemaining : List Nat)
      (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell physicalAfter position next
        nextRemaining)
      (progress :
        (workspace.states.length = beforeWorkspace.states.length ∧
          next :: nextRemaining = remaining) ∨
        beforeWorkspace.states.length < workspace.states.length)
      (worldEq : afterWorld = stateWorld words tokens workspaceValues grammarCell
        tokensCell workspaceCell)
      (environmentEq : afterEnvironment =
        stateEnvironment words tokens workspaceValues grammarCell tokensCell
          workspaceCell workspaceLayout grammar.grammar.n_kinds
          grammarLayout.lhsOffsetsOffset grammarLayout.lhsCountsOffset
          grammarLayout.lhsProductionsOffset workspace.states.length position
          (Int.ofNat next)) :
      RecognizerStateStepSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell cursorCell position current remaining afterWorld
        afterEnvironment physicalAfter .next
  | exhausted (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (invariant : RecognizerStateFinishedInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell physicalAfter position)
      (progress :
        (workspace.states.length = beforeWorkspace.states.length ∧
          ([] : List Nat) = remaining) ∨
        beforeWorkspace.states.length < workspace.states.length)
      (worldEq : afterWorld = stateWorld words tokens workspaceValues grammarCell
        tokensCell workspaceCell)
      (environmentEq : afterEnvironment =
        stateEnvironment words tokens workspaceValues grammarCell tokensCell
          workspaceCell workspaceLayout grammar.grammar.n_kinds
          grammarLayout.lhsOffsetsOffset grammarLayout.lhsCountsOffset
          grammarLayout.lhsProductionsOffset workspace.states.length position
          (-1)) :
      RecognizerStateStepSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell cursorCell position current remaining afterWorld
        afterEnvironment physicalAfter .next
  | full (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (invariant : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter) :
      RecognizerStateStepSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell cursorCell position current remaining afterWorld
        afterEnvironment physicalAfter
        (.returned (some (parseResultValue 2 (Int.ofNat stateCount) (-1)
          (Int.ofNat position))))

private def RecognizerStateStepSynchronizedOutcome.physical
    (outcome : RecognizerStateStepSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position current remaining
      afterWorld afterEnvironment physicalAfter completion) :
    RecognizerStateStepOutcome grammarLayout grammar words tokens workspaceLayout
      beforeWorkspace grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position current remaining physicalAfter
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion) := by
  cases outcome with
  | advanced workspace workspaceValues physicalAfter growth next nextRemaining
      invariant progress _ _ =>
      exact .advanced workspace workspaceValues physicalAfter growth next
        nextRemaining invariant progress
  | exhausted workspace workspaceValues physicalAfter growth invariant progress
      _ _ =>
      exact .exhausted workspace workspaceValues physicalAfter growth invariant
        progress
  | full workspace workspaceValues physicalAfter growth invariant stateCount
      wellFormed =>
      exact .full workspace workspaceValues physicalAfter growth invariant
        stateCount wellFormed

private structure RecognizerStateStepFunctionalExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (runtime : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining)
    (beforeEnvironment : Lanius.FunctionalView.Env 13) where
  afterWorld : Lanius.FunctionalView.Core.ReadOnly.World
  afterEnvironment : Lanius.FunctionalView.Env 13
  completion : Lanius.FunctionalView.Stateful.Completion
  physicalAfter : State
  functionalExecution : Lanius.FunctionalView.Stateful.Command.Evaluates
    (stateTermMachine workspaceLayout grammar words tokens grammarCell tokensCell)
    (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    beforeEnvironment stateBodyCommand completion afterWorld afterEnvironment
  physicalExecution : Executes verifiedParserCore runtime
    parserRecognizeStateLoopBody
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
    physicalAfter
  physicalEffect : ModifiesOnly
    (stateLoopMutableCells workspaceCell stateCountCell cursorCell) runtime
    physicalAfter
  outcome : RecognizerStateStepSynchronizedOutcome grammarLayout grammar words
    tokens workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell cursorCell position current remaining afterWorld
    afterEnvironment physicalAfter completion

/-- An active algorithmic state configuration supplies every resource fact
    needed by the generic four-binding FunctionalView prefix. -/
private theorem RecognizerStateConfig.functional_body_of_afterBindings
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position)
    (current : Nat) (remaining : List Nat)
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words tokens
      workspaceLayout config.workspace config.workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell config.runtime position
      current remaining)
    (cursorEq : config.cursor = .inl ⟨current, remaining, invariant⟩)
    (candidate : EarleyState)
    (foundState : config.workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (branchResult : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      config.functionalRuntime.world
      ((((config.functionalRuntime.environment.push
          (.signed .i32 (Int.ofNat candidate.production))).push
        (.signed .i32 (Int.ofNat candidate.dot))).push
        (.signed .i32 (Int.ofNat candidate.origin))).push
        (.signed .i32 (Int.ofNat
          (grammar.productionAt
            ⟨candidate.production, productionBound⟩).rhs.length)))
      stateAfterBindingsCommand completion afterWorld afterEnvironment) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      config.functionalRuntime.world config.functionalRuntime.environment
      stateBodyCommand completion afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.pop afterEnvironment)))) := by
  apply stateBodyCommand_evaluates_of_afterBindings
    (workspace := config.workspace) (candidate := candidate)
    (workspaceValues := config.workspaceValues) (current := current)
    (productionBound := productionBound) (foundState := foundState)
    (branchResult := branchResult)
  · rfl
  · rfl
  · have candidateEq : config.candidate = Int.ofNat current := by
      simp [RecognizerStateConfig.candidate, cursorEq]
    simp only [RecognizerStateConfig.functionalRuntime,
      Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
    rw [candidateEq]
    rfl
  · rfl
  · exact stateWorld_finds_workspace
      invariant.chartCursor.recognizer.grammarWorkspaceDistinct
      invariant.chartCursor.recognizer.tokensWorkspaceDistinct
  · exact stateWorld_finds_grammar
  · exact invariant.chartCursor.recognizer.workspaceLength
  · exact invariant.chartCursor.recognizer.workspaceEncoded

private theorem stateful_toCoreCompletion_injective : Function.Injective
    Lanius.FunctionalView.Core.Stateful.toCoreCompletion := by
  intro left right same
  cases left <;> cases right <;>
    simp_all [Lanius.FunctionalView.Core.Stateful.toCoreCompletion]

/-- Execute one exact state-loop body through FunctionalView and Core from the
    same decoded item and semantic outcome. -/
private noncomputable def RecognizerStateConfig.functional_execute_step
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position)
    (current : Nat) (remaining : List Nat)
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words tokens
      workspaceLayout config.workspace config.workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell config.runtime position
      current remaining)
    (cursorEq : config.cursor = .inl ⟨current, remaining, invariant⟩) :
    RecognizerStateStepFunctionalExecution grammarLayout grammar words tokens
      workspaceLayout config.workspace config.workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell config.runtime position
      current remaining invariant config.functionalRuntime.environment := by
  let candidate := Classical.choose invariant.chartCursor.state_at_cursor
  have candidateFacts :=
    Classical.choose_spec invariant.chartCursor.state_at_cursor
  have found : config.workspace.state? current = some candidate :=
    candidateFacts.1
  have within := invariant.chartCursor.state_within_grammar candidate found
  have productionBound : candidate.production < grammar.productionCount := by
    simpa [EarleyState.key] using within.productionBound
  let bindings := invariant.bind_candidate_fields candidate found productionBound
  let decodedEnvironment := config.afterBindingsEnvironment candidate
    productionBound
  have decodedMeaning := config.afterBindingsMeaning current remaining invariant
    cursorEq candidate productionBound
  let semantic := bindings.functional_execute_semantic decodedEnvironment
    decodedMeaning
  let writes := stateLoopMutableCells workspaceCell stateCountCell cursorCell
  have semanticEffect : ModifiesOnly writes
      (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.length))) semantic.physicalAfter :=
    semantic.physicalEffect.weaken (by
      intro cell written
      change cell = workspaceCell ∨ cell = stateCountCell at written
      change cell = workspaceCell ∨ cell = stateCountCell ∨ cell = cursorCell
      exact written.elim (fun same => .inl same)
        (fun same => .inr (.inl same)))
  have existsResult : ∃ result :
      RecognizerStateStepFunctionalExecution grammarLayout grammar words tokens
        workspaceLayout config.workspace config.workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell cursorCell config.runtime
        position current remaining invariant config.functionalRuntime.environment,
      True := by
    rcases semantic.outcome.view with fullResult | completedResult
    ·
        rcases fullResult with ⟨finalWorkspace, finalValues, stateCount,
          growth, terminal, wellFormed, coreCompletionEq⟩
        have sourceStops : semantic.completion ≠ .next := by
          intro sourceNext
          rw [sourceNext] at coreCompletionEq
          simp [Lanius.FunctionalView.Core.Stateful.toCoreCompletion,
            parserCapacityCompletion] at coreCompletionEq
        have sourceCompletionEq : semantic.completion =
            .returned (some (parseResultValue 2 (Int.ofNat stateCount) (-1)
              (Int.ofNat position))) := by
          apply stateful_toCoreCompletion_injective
          simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion,
            parserCapacityCompletion] using coreCompletionEq
        have afterBindingsExecution :
            Lanius.FunctionalView.Stateful.Command.Evaluates
              (stateTermMachine workspaceLayout grammar words tokens grammarCell
                tokensCell)
              (stateStatefulMachine workspaceLayout grammar words tokens
                grammarCell tokensCell)
              config.functionalRuntime.world decodedEnvironment
              stateAfterBindingsCommand semantic.completion semantic.afterWorld
              semantic.afterEnvironment := by
          rw [stateAfterBindingsCommand_shape]
          exact .sequenceStop semantic.functionalExecution sourceStops
        have functionalExecution := config.functional_body_of_afterBindings
          current remaining invariant cursorEq candidate found productionBound
          afterBindingsExecution
        have innerExecution : Executes verifiedParserCore
            (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
              (grammar.productionAt ⟨candidate.production,
                productionBound⟩).rhs.length)))
            parserRecognizeStateAfterBindings
            (parserCapacityCompletion position stateCount)
            semantic.physicalAfter := by
          rw [extractedParserRecognize_state_after_bindings_shape]
          have semanticPhysical := semantic.physicalExecution
          rw [coreCompletionEq] at semanticPhysical
          exact executesSequenceReturned semanticPhysical
        let closed := bindings.close_scopes semantic.physicalAfter
          (parserCapacityCompletion position stateCount) writes innerExecution
          semanticEffect wellFormed
        let restored := closed.restore_recognizer terminal
        exact ⟨{
          afterWorld := semantic.afterWorld
          afterEnvironment :=
            Lanius.FunctionalView.Stateful.Env.pop
              (Lanius.FunctionalView.Stateful.Env.pop
                (Lanius.FunctionalView.Stateful.Env.pop
                  (Lanius.FunctionalView.Stateful.Env.pop
                    semantic.afterEnvironment)))
          completion := semantic.completion
          physicalAfter := closed.after
          functionalExecution := functionalExecution
          physicalExecution := by
            simpa [coreCompletionEq] using closed.execution
          physicalEffect := by simpa [writes] using closed.effect
          outcome := by
            have synchronized : RecognizerStateStepSynchronizedOutcome
                grammarLayout grammar words tokens workspaceLayout
                config.workspace grammarCell tokensCell workspaceCell
                stateCountCell cursorCell position current remaining
                semantic.afterWorld
                (Lanius.FunctionalView.Stateful.Env.pop
                  (Lanius.FunctionalView.Stateful.Env.pop
                    (Lanius.FunctionalView.Stateful.Env.pop
                      (Lanius.FunctionalView.Stateful.Env.pop
                        semantic.afterEnvironment))))
                closed.after
                (.returned (some (parseResultValue 2 (Int.ofNat stateCount)
                  (-1) (Int.ofNat position)))) :=
              .full finalWorkspace finalValues closed.after growth restored
                stateCount closed.wellFormed
            simpa [sourceCompletionEq] using synchronized
        }, trivial⟩
    ·
        rcases completedResult with ⟨nextWorkspace, nextValues,
          growth, frame, coreCompletionEq, worldEq, environmentMeaning⟩
        have sourceCompletionEq : semantic.completion = .next := by
          apply stateful_toCoreCompletion_injective
          simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
            coreCompletionEq
        have semanticExecutionNext := semantic.functionalExecution
        rw [sourceCompletionEq] at semanticExecutionNext
        cases suffixEq : frame.nextRemaining with
        | nil =>
            have stateInvariant : RecognizerStateLoopInvariant grammarLayout
                grammar words tokens workspaceLayout nextWorkspace nextValues
                grammarCell tokensCell workspaceCell stateCountCell cursorCell
                semantic.physicalAfter position current [] := by
              simpa [suffixEq] using frame.invariant
            let exhausted := stateInvariant.chartCursor.exhaust
            let innerFinished := stateInvariant.after_cursor_exhaustion
              exhausted.finished exhausted.effect
            have cursorEffect : ModifiesOnly writes semantic.physicalAfter
                exhausted.after := exhausted.effect.weaken (by
              intro cell written
              change cell = cursorCell at written
              exact .inr (.inr written))
            have innerEffect : ModifiesOnly writes
                (bindings.afterRhsLengthRead.bindLocal 28
                  (.signed .i32 (Int.ofNat
                    (grammar.productionAt ⟨candidate.production,
                      productionBound⟩).rhs.length))) exhausted.after :=
              semanticEffect.trans_same cursorEffect
            have sourceAdvanceCanonical := stateInvariant.functional_advance
              semantic.afterEnvironment environmentMeaning.workspaceEq
              environmentMeaning.stateBaseEq environmentMeaning.currentEq
            have sourceAdvance :
                Lanius.FunctionalView.Stateful.Command.Evaluates
                  (stateTermMachine workspaceLayout grammar words tokens
                    grammarCell tokensCell)
                  (stateStatefulMachine workspaceLayout grammar words tokens
                    grammarCell tokensCell)
                  semantic.afterWorld semantic.afterEnvironment
                  stateAdvanceCommand .next
                  (stateWorld words tokens nextValues grammarCell tokensCell
                    workspaceCell)
                  (Lanius.FunctionalView.Stateful.Env.set
                    semantic.afterEnvironment ⟨12, by omega⟩
                    (.signed .i32 (-1))) := by
              simpa [worldEq, suffixEq, encodeStateId] using
                sourceAdvanceCanonical
            have afterBindingsExecution :
                Lanius.FunctionalView.Stateful.Command.Evaluates
                  (stateTermMachine workspaceLayout grammar words tokens
                    grammarCell tokensCell)
                  (stateStatefulMachine workspaceLayout grammar words tokens
                    grammarCell tokensCell)
                  config.functionalRuntime.world decodedEnvironment
                  stateAfterBindingsCommand .next
                  (stateWorld words tokens nextValues grammarCell tokensCell
                    workspaceCell)
                  (Lanius.FunctionalView.Stateful.Env.set
                    semantic.afterEnvironment ⟨12, by omega⟩
                    (.signed .i32 (-1))) := by
              rw [stateAfterBindingsCommand_shape]
              exact .sequenceNext semanticExecutionNext sourceAdvance
            have functionalExecution := config.functional_body_of_afterBindings
              current remaining invariant cursorEq candidate found
              productionBound afterBindingsExecution
            have finalEnvironmentEq := environmentMeaning.advance_pop_eq (-1)
            rw [finalEnvironmentEq] at functionalExecution
            have innerExecution : Executes verifiedParserCore
                (bindings.afterRhsLengthRead.bindLocal 28
                  (.signed .i32 (Int.ofNat
                    (grammar.productionAt ⟨candidate.production,
                      productionBound⟩).rhs.length)))
                parserRecognizeStateAfterBindings .next exhausted.after := by
              rw [extractedParserRecognize_state_after_bindings_shape]
              exact executesSequence
                (by simpa [sourceCompletionEq,
                  Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
                  semantic.physicalExecution)
                exhausted.execution
            let closed := bindings.close_scopes exhausted.after .next writes
              innerExecution innerEffect
              innerFinished.chartCursor.recognizer.wellFormed
            let restored := closed.restore_finished innerFinished
            have progress :
                (nextWorkspace.states.length = config.workspace.states.length ∧
                  ([] : List Nat) = remaining) ∨
                config.workspace.states.length < nextWorkspace.states.length := by
              simpa [suffixEq] using frame.progress
            exact ⟨{
              afterWorld := stateWorld words tokens nextValues grammarCell
                tokensCell workspaceCell
              afterEnvironment := stateEnvironment words tokens nextValues
                grammarCell tokensCell workspaceCell workspaceLayout
                grammar.grammar.n_kinds grammarLayout.lhsOffsetsOffset
                grammarLayout.lhsCountsOffset grammarLayout.lhsProductionsOffset
                nextWorkspace.states.length position (-1)
              completion := .next
              physicalAfter := closed.after
              functionalExecution := functionalExecution
              physicalExecution := closed.execution
              physicalEffect := by simpa [writes] using closed.effect
              outcome := .exhausted nextWorkspace nextValues closed.after growth
                restored progress rfl rfl
            }, trivial⟩
        | cons next nextRemaining =>
            have stateInvariant : RecognizerStateLoopInvariant grammarLayout
                grammar words tokens workspaceLayout nextWorkspace nextValues
                grammarCell tokensCell workspaceCell stateCountCell cursorCell
                semantic.physicalAfter position current (next :: nextRemaining) := by
              simpa [suffixEq] using frame.invariant
            let advanced := stateInvariant.chartCursor.advance
            let innerInvariant := stateInvariant.after_cursor_effect
              advanced.invariant advanced.effect
            have cursorEffect : ModifiesOnly writes semantic.physicalAfter
                advanced.after := advanced.effect.weaken (by
              intro cell written
              change cell = cursorCell at written
              exact .inr (.inr written))
            have innerEffect : ModifiesOnly writes
                (bindings.afterRhsLengthRead.bindLocal 28
                  (.signed .i32 (Int.ofNat
                    (grammar.productionAt ⟨candidate.production,
                      productionBound⟩).rhs.length))) advanced.after :=
              semanticEffect.trans_same cursorEffect
            have sourceAdvanceCanonical := stateInvariant.functional_advance
              semantic.afterEnvironment environmentMeaning.workspaceEq
              environmentMeaning.stateBaseEq environmentMeaning.currentEq
            have sourceAdvance :
                Lanius.FunctionalView.Stateful.Command.Evaluates
                  (stateTermMachine workspaceLayout grammar words tokens
                    grammarCell tokensCell)
                  (stateStatefulMachine workspaceLayout grammar words tokens
                    grammarCell tokensCell)
                  semantic.afterWorld semantic.afterEnvironment
                  stateAdvanceCommand .next
                  (stateWorld words tokens nextValues grammarCell tokensCell
                    workspaceCell)
                  (Lanius.FunctionalView.Stateful.Env.set
                    semantic.afterEnvironment ⟨12, by omega⟩
                    (.signed .i32 (Int.ofNat next))) := by
              simpa [worldEq, suffixEq, encodeStateId] using
                sourceAdvanceCanonical
            have afterBindingsExecution :
                Lanius.FunctionalView.Stateful.Command.Evaluates
                  (stateTermMachine workspaceLayout grammar words tokens
                    grammarCell tokensCell)
                  (stateStatefulMachine workspaceLayout grammar words tokens
                    grammarCell tokensCell)
                  config.functionalRuntime.world decodedEnvironment
                  stateAfterBindingsCommand .next
                  (stateWorld words tokens nextValues grammarCell tokensCell
                    workspaceCell)
                  (Lanius.FunctionalView.Stateful.Env.set
                    semantic.afterEnvironment ⟨12, by omega⟩
                    (.signed .i32 (Int.ofNat next))) := by
              rw [stateAfterBindingsCommand_shape]
              exact .sequenceNext semanticExecutionNext sourceAdvance
            have functionalExecution := config.functional_body_of_afterBindings
              current remaining invariant cursorEq candidate found
              productionBound afterBindingsExecution
            have finalEnvironmentEq :=
              environmentMeaning.advance_pop_eq (Int.ofNat next)
            rw [finalEnvironmentEq] at functionalExecution
            have innerExecution : Executes verifiedParserCore
                (bindings.afterRhsLengthRead.bindLocal 28
                  (.signed .i32 (Int.ofNat
                    (grammar.productionAt ⟨candidate.production,
                      productionBound⟩).rhs.length)))
                parserRecognizeStateAfterBindings .next advanced.after := by
              rw [extractedParserRecognize_state_after_bindings_shape]
              exact executesSequence
                (by simpa [sourceCompletionEq,
                  Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
                  semantic.physicalExecution)
                advanced.execution
            let closed := bindings.close_scopes advanced.after .next writes
              innerExecution innerEffect
              innerInvariant.chartCursor.recognizer.wellFormed
            let restored := closed.restore_invariant innerInvariant
            have progress :
                (nextWorkspace.states.length = config.workspace.states.length ∧
                  next :: nextRemaining = remaining) ∨
                config.workspace.states.length < nextWorkspace.states.length := by
              simpa [suffixEq] using frame.progress
            exact ⟨{
              afterWorld := stateWorld words tokens nextValues grammarCell
                tokensCell workspaceCell
              afterEnvironment := stateEnvironment words tokens nextValues
                grammarCell tokensCell workspaceCell workspaceLayout
                grammar.grammar.n_kinds grammarLayout.lhsOffsetsOffset
                grammarLayout.lhsCountsOffset grammarLayout.lhsProductionsOffset
                nextWorkspace.states.length position (Int.ofNat next)
              completion := .next
              physicalAfter := closed.after
              functionalExecution := functionalExecution
              physicalExecution := closed.execution
              physicalEffect := by simpa [writes] using closed.effect
              outcome := .advanced nextWorkspace nextValues closed.after growth
                next nextRemaining restored progress rfl rfl
            }, trivial⟩
  exact Classical.choose existsResult

private theorem RecognizerStateConfig.functional_condition
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      config.functionalRuntime.world config.functionalRuntime.environment
      stateLoopCondition =
      .ok (.boolean (decide (config.candidate ≥ 0)),
        config.functionalRuntime.world) := by
  cases cursorShape : config.cursor with
  | inl active =>
      obtain ⟨current, remaining, invariant⟩ := active
      have candidateEq : config.candidate = Int.ofNat current := by
        simp [RecognizerStateConfig.candidate, cursorShape]
      have environmentEq : config.functionalRuntime.environment
          ⟨12, by omega⟩ = .signed .i32 (Int.ofNat current) := by
        simp only [RecognizerStateConfig.functionalRuntime,
          Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
        rw [candidateEq]
        rfl
      have evaluated := stateLoopCondition_evaluates workspaceLayout grammar
        words tokens grammarCell tokensCell config.functionalRuntime.world
        config.functionalRuntime.environment (Int.ofNat current) environmentEq
      rw [candidateEq]
      simpa using evaluated
  | inr finished =>
      have candidateEq : config.candidate = -1 := by
        simp [RecognizerStateConfig.candidate, cursorShape]
      have environmentEq : config.functionalRuntime.environment
          ⟨12, by omega⟩ = .signed .i32 (-1) := by
        simp only [RecognizerStateConfig.functionalRuntime,
          Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
        rw [candidateEq]
        rfl
      have evaluated := stateLoopCondition_evaluates workspaceLayout grammar
        words tokens grammarCell tokensCell config.functionalRuntime.world
        config.functionalRuntime.environment (-1) environmentEq
      rw [candidateEq]
      simpa using evaluated

/-- Final state-loop outcomes retain the one FunctionalView runtime that was
    produced by the same loop trace as the physical Core execution. -/
inductive RecognizerStateSynchronizedOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position : Nat)
    (functionalAfter : Lanius.FunctionalView.Stateful.Loop.Runtime
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell) 13) :
    State → Lanius.FunctionalView.Stateful.Completion → Type where
  | completed (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (invariant : RecognizerStateFinishedInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell physicalAfter position)
      (worldEq : functionalAfter.world =
        stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell)
      (environmentEq : functionalAfter.environment =
        stateEnvironment words tokens workspaceValues grammarCell tokensCell
          workspaceCell workspaceLayout grammar.grammar.n_kinds
          grammarLayout.lhsOffsetsOffset grammarLayout.lhsCountsOffset
          grammarLayout.lhsProductionsOffset workspace.states.length position
          (-1)) :
      RecognizerStateSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell cursorCell position functionalAfter physicalAfter .next
  | full (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (invariant : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter) :
      RecognizerStateSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell cursorCell position functionalAfter physicalAfter
        (.returned (some (parseResultValue 2 (Int.ofNat stateCount) (-1)
          (Int.ofNat position))))

def RecognizerStateSynchronizedOutcome.prepend_growth
    (outcome : RecognizerStateSynchronizedOutcome grammarLayout grammar words
      tokens workspaceLayout middleWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position functionalAfter
      physicalAfter completion)
    (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
      middleWorkspace) :
    RecognizerStateSynchronizedOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position functionalAfter physicalAfter
      completion := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter suffix invariant worldEq
      environmentEq =>
      exact .completed workspace workspaceValues physicalAfter
        (growth.trans suffix) invariant worldEq environmentEq
  | full workspace workspaceValues physicalAfter suffix invariant stateCount
      wellFormed =>
      exact .full workspace workspaceValues physicalAfter (growth.trans suffix)
        invariant stateCount wellFormed

abbrev RecognizerStateLoopOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position : Nat) : State → Completion → Prop :=
  WorkspaceLoopOutcome workspaceLayout.capacity beforeWorkspace
    (parserCapacityCompletion position)
    (fun workspace workspaceValues after =>
      RecognizerStateFinishedInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell after position)
    (fun workspace workspaceValues after =>
      RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
        workspace workspaceValues grammarCell tokensCell workspaceCell after)

abbrev RecognizerStateResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position : Nat) :
    RecognizerStateConfig grammarLayout grammar words tokens workspaceLayout
      grammarCell tokensCell workspaceCell stateCountCell cursorCell position →
      Completion → State → Prop :=
  fun config completion after =>
    RecognizerStateLoopOutcome grammarLayout grammar words tokens
      workspaceLayout config.workspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position after completion

def RecognizerStateSynchronizedOutcome.physical
    (outcome : RecognizerStateSynchronizedOutcome grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position functionalAfter
      physicalAfter completion) :
    RecognizerStateLoopOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position physicalAfter
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion) := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter growth invariant _ _ =>
      exact .completed workspace workspaceValues physicalAfter growth invariant
  | full workspace workspaceValues physicalAfter growth invariant stateCount
      wellFormed =>
      exact .full workspace workspaceValues physicalAfter growth invariant
        stateCount wellFormed

/-- Result transported by the synchronized FunctionalView state-loop driver.
    The functional trace owns control flow; the physical execution is its
    refinement evidence for the enclosing recognizer proof. -/
structure RecognizerStateFunctionalResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position : Nat)
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (functionalAfter : Lanius.FunctionalView.Stateful.Loop.Runtime
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell) 13) where
  physicalAfter : State
  execution : Executes verifiedParserCore config.runtime
    parserRecognizeStateLoop
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
    physicalAfter
  effect : ModifiesOnly
    (stateLoopMutableCells workspaceCell stateCountCell cursorCell)
    config.runtime physicalAfter
  outcome : RecognizerStateSynchronizedOutcome grammarLayout grammar words
    tokens workspaceLayout config.workspace grammarCell tokensCell workspaceCell
    stateCountCell cursorCell position functionalAfter physicalAfter completion

/-- One state-loop decision shared by the FunctionalView command and the
    exact extracted Core loop. -/
private noncomputable def RecognizerStateConfig.functional_decide
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position) :
    Lanius.FunctionalView.Stateful.Loop.Decision
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      stateLoopCondition stateBodyCommand
      (RecognizerStateConfig grammarLayout grammar words tokens workspaceLayout
        grammarCell tokensCell workspaceCell stateCountCell cursorCell position)
      RecognizerStateConfig.functionalRuntime RecognizerStateConfig.measure
      (RecognizerStateFunctionalResult grammarLayout grammar words tokens
        workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
        cursorCell position) config := by
  cases cursorShape : config.cursor with
  | inr finished =>
      have functionalFalse : Lanius.FunctionalView.Term.evaluate
          (stateTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          config.functionalRuntime.world config.functionalRuntime.environment
          stateLoopCondition =
          .ok (.boolean false, config.functionalRuntime.world) := by
        simpa [RecognizerStateConfig.candidate, cursorShape] using
          config.functional_condition
      apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
      exact {
        completion := .next
        after := config.functionalRuntime
        edge := .conditionFalse functionalFalse
        result := {
          physicalAfter := config.runtime
          execution := by
            rw [extractedParserRecognize_state_loop_shape]
            exact executesWhileFalse finished.condition_negative
          effect := ModifiesOnly.reflAny
            (stateLoopMutableCells workspaceCell stateCountCell cursorCell)
            config.runtime
          outcome := by
            apply RecognizerStateSynchronizedOutcome.completed config.workspace
              config.workspaceValues config.runtime (.refl config.workspace)
              finished
            · rfl
            · simp only [RecognizerStateConfig.functionalRuntime,
                Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
              have candidateEq : config.candidate = -1 := by
                simp [RecognizerStateConfig.candidate, cursorShape]
              rw [candidateEq]
        }
      }
  | inl active =>
      obtain ⟨current, remaining, invariant⟩ := active
      let step := config.functional_execute_step current remaining invariant
        cursorShape
      obtain ⟨stepAfterWorld, stepAfterEnvironment, stepCompletion,
        stepPhysicalAfter, stepFunctionalExecution, stepPhysicalExecution,
        stepPhysicalEffect, stepOutcome⟩ := step
      have functionalTrue : Lanius.FunctionalView.Term.evaluate
          (stateTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          config.functionalRuntime.world config.functionalRuntime.environment
          stateLoopCondition =
          .ok (.boolean true, config.functionalRuntime.world) := by
        simpa [RecognizerStateConfig.candidate, cursorShape] using
          config.functional_condition
      have physicalTrue := invariant.chartCursor.condition_nonnegative
      cases stepOutcome with
      | advanced nextWorkspace nextValues physicalAfter growth next
          nextRemaining nextInvariant progress worldEq environmentEq =>
          let nextConfig : RecognizerStateConfig grammarLayout grammar words
              tokens workspaceLayout grammarCell tokensCell workspaceCell
              stateCountCell cursorCell position := {
            workspace := nextWorkspace
            workspaceValues := nextValues
            runtime := stepPhysicalAfter
            cursor := .inl ⟨next, nextRemaining, nextInvariant⟩
          }
          have functionalBody := stepFunctionalExecution
          rw [worldEq, environmentEq] at functionalBody
          have physicalBody : Executes verifiedParserCore config.runtime
              parserRecognizeStateLoopBody .next stepPhysicalAfter := by
            simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
                stepPhysicalExecution
          apply Lanius.FunctionalView.Stateful.Loop.Decision.next nextConfig
          · apply Lanius.FunctionalView.Stateful.Loop.Iteration.next
              functionalTrue
            simpa [nextConfig, RecognizerStateConfig.functionalRuntime,
              RecognizerStateConfig.candidate,
              Lanius.FunctionalView.Stateful.Loop.Runtime.world,
              Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                functionalBody
          · rcases progress with unchanged | grew
            · simp only [WellFoundedRelation.rel,
                RecognizerStateConfig.measure, nextConfig]
              rw [unchanged.1]
              apply Prod.Lex.right
              have suffixDecrease :
                  nextRemaining.length + 1 < remaining.length + 1 := by
                rw [← unchanged.2]
                simp only [List.length_cons]
                omega
              show sizeOf (nextRemaining.length + 1) < sizeOf
                (match config.cursor with
                | .inl active => active.2.1.length + 1
                | .inr _ => 0)
              simpa [cursorShape] using suffixDecrease
            · simp only [WellFoundedRelation.rel,
                RecognizerStateConfig.measure, nextConfig]
              have afterFits :=
                nextInvariant.chartCursor.recognizer.workspaceEncoded
                  |>.stateCountFits
              exact Prod.Lex.left _ _
                (Nat.sub_lt_sub_left
                  (Nat.lt_of_lt_of_le grew afterFits) grew)
          · intro completion after result
            exact {
              physicalAfter := result.physicalAfter
              execution := by
                rw [extractedParserRecognize_state_loop_shape]
                exact executesWhileTrueThen physicalTrue physicalBody
                  result.execution
              effect := stepPhysicalEffect.trans_same result.effect
              outcome := result.outcome.prepend_growth growth
            }
      | exhausted nextWorkspace nextValues physicalAfter growth nextInvariant
          progress worldEq environmentEq =>
          let nextConfig : RecognizerStateConfig grammarLayout grammar words
              tokens workspaceLayout grammarCell tokensCell workspaceCell
              stateCountCell cursorCell position := {
            workspace := nextWorkspace
            workspaceValues := nextValues
            runtime := stepPhysicalAfter
            cursor := .inr nextInvariant
          }
          have functionalBody := stepFunctionalExecution
          rw [worldEq, environmentEq] at functionalBody
          have physicalBody : Executes verifiedParserCore config.runtime
              parserRecognizeStateLoopBody .next stepPhysicalAfter := by
            simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
                stepPhysicalExecution
          apply Lanius.FunctionalView.Stateful.Loop.Decision.next nextConfig
          · apply Lanius.FunctionalView.Stateful.Loop.Iteration.next
              functionalTrue
            simpa [nextConfig, RecognizerStateConfig.functionalRuntime,
              RecognizerStateConfig.candidate,
              Lanius.FunctionalView.Stateful.Loop.Runtime.world,
              Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                functionalBody
          · rcases progress with unchanged | grew
            · simp only [WellFoundedRelation.rel,
                RecognizerStateConfig.measure, nextConfig]
              rw [unchanged.1]
              apply Prod.Lex.right
              show sizeOf 0 < sizeOf
                (match config.cursor with
                | .inl active => active.2.1.length + 1
                | .inr _ => 0)
              simpa [cursorShape] using Nat.zero_lt_succ remaining.length
            · simp only [WellFoundedRelation.rel,
                RecognizerStateConfig.measure, nextConfig]
              have afterFits :=
                nextInvariant.chartCursor.recognizer.workspaceEncoded
                  |>.stateCountFits
              exact Prod.Lex.left _ _
                (Nat.sub_lt_sub_left
                  (Nat.lt_of_lt_of_le grew afterFits) grew)
          · intro completion after result
            exact {
              physicalAfter := result.physicalAfter
              execution := by
                rw [extractedParserRecognize_state_loop_shape]
                exact executesWhileTrueThen physicalTrue physicalBody
                  result.execution
              effect := stepPhysicalEffect.trans_same result.effect
              outcome := result.outcome.prepend_growth growth
            }
      | full nextWorkspace nextValues physicalAfter growth nextInvariant
          stateCount wellFormed =>
          have functionalBody := stepFunctionalExecution
          have physicalBody : Executes verifiedParserCore config.runtime
              parserRecognizeStateLoopBody
              (parserCapacityCompletion position stateCount)
              stepPhysicalAfter := by
            simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion,
              parserCapacityCompletion] using
                stepPhysicalExecution
          apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
          exact {
            completion := .returned (some (parseResultValue 2
              (Int.ofNat stateCount) (-1) (Int.ofNat position)))
            after := (stepAfterWorld, stepAfterEnvironment)
            edge := .returned functionalTrue functionalBody
            result := {
              physicalAfter := stepPhysicalAfter
              execution := by
                rw [extractedParserRecognize_state_loop_shape]
                exact executesWhileReturned physicalTrue physicalBody
              effect := stepPhysicalEffect
              outcome := .full nextWorkspace nextValues stepPhysicalAfter
                growth nextInvariant stateCount wellFormed
            }
          }

/-- The one synchronized state-loop run consumed both by the standalone state
    execution and by the enclosing position scope. -/
noncomputable def RecognizerStateConfig.functional_run
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position) :=
  Lanius.FunctionalView.Stateful.Loop.run
    (stateTermMachine workspaceLayout grammar words tokens grammarCell tokensCell)
    (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    stateLoopCondition stateBodyCommand
    (RecognizerStateConfig grammarLayout grammar words tokens workspaceLayout
      grammarCell tokensCell workspaceCell stateCountCell cursorCell position)
    RecognizerStateConfig.functionalRuntime RecognizerStateConfig.measure
    (RecognizerStateFunctionalResult grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position)
    RecognizerStateConfig.functional_decide config

theorem RecognizerStateConfig.functional_run_evaluates
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      config.functionalRuntime.world config.functionalRuntime.environment
      stateLoopCommand config.functional_run.completion
      config.functional_run.after.world config.functional_run.after.environment :=
  config.functional_run.trace.evaluates

noncomputable def
    RecognizerStateConfig.evaluates_in_position_environment
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position)
    (beforeLarge : Lanius.FunctionalView.Env 16)
    (related : Lanius.FunctionalView.Env.Extends stateIntoPositionEmbedding
      config.functionalRuntime.environment beforeLarge) :
    Lanius.FunctionalView.Stateful.Command.RenameResult
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      Lanius.FunctionalView.Core.Stateful.actionRenamer
      stateIntoPositionEmbedding config.functionalRuntime.world beforeLarge
      stateLoopCommand config.functional_run.completion
      config.functional_run.after.world config.functional_run.after.environment := by
  let calls := RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell
  have actionSound :
      @Lanius.FunctionalView.Stateful.ActionRenamer.Sound
        Lanius.FunctionalView.Core.signature
        Lanius.FunctionalView.Core.Stateful.actions
        Lanius.FunctionalView.Core.Stateful.actionRenamer
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell) := by
    intro source target embedding world small large related action
    exact
      Lanius.FunctionalView.Core.Stateful.actionRenamer_sound verifiedParserCore
        (Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedParserCore calls)
        embedding world small large related action
  exact config.functional_run_evaluates.renameResult actionSound
    stateIntoPositionEmbedding beforeLarge related

/-- One local decision for the generic state-loop driver. -/
noncomputable def RecognizerStateConfig.decide
    (config : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position) :
    LoopVerification.Decision verifiedParserCore
      (.binary .greaterEqual (.local 24) (.value (.signed .i32 0)))
      parserRecognizeStateLoopBody
      (stateLoopMutableCells workspaceCell stateCountCell cursorCell)
      (RecognizerStateConfig grammarLayout grammar words tokens workspaceLayout
        grammarCell tokensCell workspaceCell stateCountCell cursorCell position)
      RecognizerStateConfig.runtime RecognizerStateConfig.measure
      (RecognizerStateResult grammarLayout grammar words tokens workspaceLayout
        grammarCell tokensCell workspaceCell stateCountCell cursorCell position)
      config := by
  cases cursorShape : config.cursor with
  | inr finished =>
      apply LoopVerification.Decision.exit
      exact {
        completion := .next
        after := config.runtime
        edge := {
          semantic := .conditionFalse finished.condition_negative
          effect := ModifiesOnly.reflAny
            (stateLoopMutableCells workspaceCell stateCountCell cursorCell)
            config.runtime
        }
        result := .completed config.workspace config.workspaceValues
          config.runtime (.refl config.workspace) finished
      }
  | inl active =>
      obtain ⟨current, remaining, invariant⟩ := active
      let step := invariant.execute_step
      obtain ⟨stepAfter, stepCompletion, stepExecution, stepEffect,
        stepOutcome⟩ := step
      have condition := invariant.chartCursor.condition_nonnegative
      cases stepOutcome with
      | full nextWorkspace nextValues _ growth terminal stateCount wellFormed =>
          apply LoopVerification.Decision.exit
          exact {
            completion := parserCapacityCompletion position stateCount
            after := stepAfter
            edge := {
              semantic := .returned condition stepExecution
              effect := stepEffect
            }
            result := .full nextWorkspace nextValues stepAfter growth terminal
              stateCount wellFormed
          }
      | advanced nextWorkspace nextValues _ growth next nextRemaining
          nextInvariant progress =>
          let nextConfig : RecognizerStateConfig grammarLayout grammar words
              tokens workspaceLayout grammarCell tokensCell workspaceCell
              stateCountCell cursorCell position := {
            workspace := nextWorkspace
            workspaceValues := nextValues
            runtime := stepAfter
            cursor := .inl ⟨next, nextRemaining, nextInvariant⟩
          }
          apply LoopVerification.Decision.next nextConfig
          · exact {
              semantic := .next condition stepExecution
              effect := stepEffect
            }
          · rcases progress with unchanged | grew
            · simp only [WellFoundedRelation.rel,
                RecognizerStateConfig.measure, nextConfig]
              rw [unchanged.1]
              apply Prod.Lex.right
              have suffixDecrease :
                  nextRemaining.length + 1 < remaining.length + 1 := by
                rw [← unchanged.2]
                simp only [List.length_cons]
                omega
              show sizeOf (nextRemaining.length + 1) < sizeOf
                (match config.cursor with
                | .inl active => active.2.1.length + 1
                | .inr _ => 0)
              simpa [cursorShape] using suffixDecrease
            · simp only [WellFoundedRelation.rel,
                RecognizerStateConfig.measure, nextConfig]
              have afterFits :=
                nextInvariant.chartCursor.recognizer.workspaceEncoded
                  |>.stateCountFits
              exact Prod.Lex.left _ _
                (Nat.sub_lt_sub_left
                  (Nat.lt_of_lt_of_le grew afterFits) grew)
          · intro completion after outcome
            exact outcome.prepend_growth growth
      | exhausted nextWorkspace nextValues _ growth nextFinished progress =>
          let nextConfig : RecognizerStateConfig grammarLayout grammar words
              tokens workspaceLayout grammarCell tokensCell workspaceCell
              stateCountCell cursorCell position := {
            workspace := nextWorkspace
            workspaceValues := nextValues
            runtime := stepAfter
            cursor := .inr nextFinished
          }
          apply LoopVerification.Decision.next nextConfig
          · exact {
              semantic := .next condition stepExecution
              effect := stepEffect
            }
          · rcases progress with unchanged | grew
            · simp only [WellFoundedRelation.rel,
                RecognizerStateConfig.measure, nextConfig]
              rw [unchanged.1]
              apply Prod.Lex.right
              show sizeOf 0 < sizeOf
                (match config.cursor with
                | .inl active => active.2.1.length + 1
                | .inr _ => 0)
              simpa [cursorShape] using Nat.zero_lt_succ remaining.length
            · simp only [WellFoundedRelation.rel,
                RecognizerStateConfig.measure, nextConfig]
              have afterFits :=
                nextFinished.chartCursor.recognizer.workspaceEncoded
                  |>.stateCountFits
              exact Prod.Lex.left _ _
                (Nat.sub_lt_sub_left
                  (Nat.lt_of_lt_of_le grew afterFits) grew)
          · intro completion after outcome
            exact outcome.prepend_growth growth

structure RecognizerStateLoopExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before parserRecognizeStateLoop
    completion after
  effect : ModifiesOnly
    (stateLoopMutableCells workspaceCell stateCountCell cursorCell) before after
  outcome : RecognizerStateLoopOutcome grammarLayout grammar words tokens
    workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell cursorCell position after completion

/-- Total execution of the exact extracted state-chain loop.  FunctionalView
    owns the loop trace; the physical Core execution is its refinement result. -/
noncomputable def RecognizerStateLoopInvariant.execute_loop
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining) :
    RecognizerStateLoopExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      invariant := by
  let initial : RecognizerStateConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position := {
    workspace := workspace
    workspaceValues := workspaceValues
    runtime := runtime
    cursor := .inl ⟨current, remaining, invariant⟩
  }
  let assembled := initial.functional_run
  exact {
    after := assembled.result.physicalAfter
    completion := Lanius.FunctionalView.Core.Stateful.toCoreCompletion
      assembled.completion
    execution := by simpa [initial] using assembled.result.execution
    effect := by simpa [initial] using assembled.result.effect
    outcome := by simpa [initial] using assembled.result.outcome.physical
  }



end Lanius.Extraction.ParserRecognize
