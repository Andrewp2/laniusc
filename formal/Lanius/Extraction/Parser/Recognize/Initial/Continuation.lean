import Lanius.Extraction.Parser.Recognize.Initial.Loop
import Lanius.Extraction.Parser.Recognize.Position.Continuation
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
/-! ## Artifact-derived FunctionalView for final root selection -/
inductive RecognizerInitialContinuationOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) : Completion → Type
  | full (stateCount : Nat) :
      RecognizerInitialContinuationOutcome grammarLayout grammar words tokens
        workspaceLayout
        (.returned (some (parseResultValue 2 (Int.ofNat stateCount) (-1) 0)))
  | seeded (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (completion : Completion)
      (continuation : RecognizerPositionStatementOutcome grammarLayout grammar
        words tokens workspaceLayout workspace completion) :
      RecognizerInitialContinuationOutcome grammarLayout grammar words tokens
        workspaceLayout completion

structure RecognizerInitialContinuationExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (first count index : Nat)
    (beforeInvariant : RecognizerInitialLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell before first count
      index) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before
    parserRecognizeAfterInitialIndexBinding completion after
  effect : ModifiesOnly
    (recognizerInitialWrites workspaceCell stateCountCell indexCell)
    before after
  wellFormed : StateWellFormed after
  finalWorkspace : LogicalWorkspace
  finalWorkspaceValues : List Int
  growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
    finalWorkspace
  workspaceArtifact : RecognizerWorkspaceArtifact workspaceLayout
    finalWorkspace finalWorkspaceValues workspaceCell after
  outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
    tokens workspaceLayout completion

/-- One complete FunctionalView execution of the initial-seeding loop followed
    by the position/root statement, paired with its physical Core refinement.
    The functional command is the mechanically reified source continuation. -/
structure RecognizerInitialContinuationFunctionalExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (first count index : Nat)
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell before first count index) where
  resultValue : Value
  afterWorld : Lanius.FunctionalView.Core.ReadOnly.World
  afterEnvironment : Lanius.FunctionalView.Env 16
  execution : Lanius.FunctionalView.Stateful.Command.Evaluates
    (positionTermMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    (initialContinuationEnvironment words tokens workspaceValues grammarCell
      tokensCell workspaceCell workspaceLayout grammar grammarLayout first count
      workspace.states.length index)
    initialContinuationCommand (.returned (some resultValue)) afterWorld
    afterEnvironment
  physicalAfter : State
  physicalExecution : Executes verifiedParserCore before
    parserRecognizeAfterInitialIndexBinding (.returned (some resultValue))
    physicalAfter
  physicalEffect : ModifiesOnly
    (recognizerInitialWrites workspaceCell stateCountCell indexCell)
    before physicalAfter
  physicalWellFormed : StateWellFormed physicalAfter
  finalWorkspace : LogicalWorkspace
  finalWorkspaceValues : List Int
  growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
    finalWorkspace
  workspaceArtifact : RecognizerWorkspaceArtifact workspaceLayout
    finalWorkspace finalWorkspaceValues workspaceCell physicalAfter
  outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
    tokens workspaceLayout (.returned (some resultValue))

/-- Execute the complete mechanically reified continuation through
    FunctionalView.  Initial seeding is transported into the full recognizer
    call registry, then the position statement is lexically embedded and
    sequenced without introducing another semantic driver. -/
noncomputable def
    RecognizerInitialLoopInvariant.functional_execute_continuation
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell before first count index) :
    RecognizerInitialContinuationFunctionalExecution grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell before first count index
      invariant := by
  let initial : RecognizerInitialConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell first count := {
    workspace := workspace
    workspaceValues := workspaceValues
    runtime := before
    index := index
    invariant := invariant
  }
  generalize runEq : initial.functional_run = assembled
  obtain ⟨completion, functionalAfter, trace, result⟩ := assembled
  have sourceCompletionEq : initial.functional_run.completion = completion := by
    simpa using congrArg (fun run => run.completion) runEq
  have sourceAfterEq : initial.functional_run.after = functionalAfter := by
    simpa using congrArg (fun run => run.after) runEq
  have loopBase := initial.functional_run_evaluates
  have sourceLoopExecution := initialLoopExecution_in_position_machine
    (grammar := grammar) (tokens := tokens) (tokensCell := tokensCell) loopBase
  have loopExecution : Lanius.FunctionalView.Stateful.Command.Evaluates
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      initial.functionalRuntime.world initial.functionalRuntime.environment
      initialLoopCommand completion functionalAfter.world
      functionalAfter.environment := by
    simpa only [sourceCompletionEq, sourceAfterEq] using sourceLoopExecution
  have initialWorldEq : initial.functionalRuntime.world =
      stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell := by
    rfl
  have initialEnvironmentEq : initial.functionalRuntime.environment =
      initialContinuationEnvironment words tokens workspaceValues grammarCell
        tokensCell workspaceCell workspaceLayout grammar grammarLayout first count
        workspace.states.length index := by
    rfl
  have loopExecutionAtSource :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (positionTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell)
        (initialContinuationEnvironment words tokens workspaceValues grammarCell
          tokensCell workspaceCell workspaceLayout grammar grammarLayout first
          count workspace.states.length index)
        initialLoopCommand completion functionalAfter.world
        functionalAfter.environment := by
    simpa only [initialWorldEq, initialEnvironmentEq] using loopExecution
  cases result.outcome with
  | full finalWorkspace finalValues physicalAfter initialGrowth terminal
      stateCount loopWellFormed =>
      have functionalWhole : Lanius.FunctionalView.Stateful.Command.Evaluates
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (positionStatefulMachine workspaceLayout grammar words tokens
            grammarCell tokensCell)
          (stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell)
          (initialContinuationEnvironment words tokens workspaceValues
            grammarCell tokensCell workspaceCell workspaceLayout grammar
            grammarLayout first count workspace.states.length index)
          initialContinuationCommand
          (.returned (some
            (parseResultValue 2 (Int.ofNat stateCount) (-1) 0)))
          functionalAfter.world functionalAfter.environment := by
        rw [initialContinuationCommand_shape,
          initialExpectedContinuationCommand]
        exact .sequenceStop loopExecutionAtSource
          (by intro impossible; cases impossible)
      have physicalWhole : Executes verifiedParserCore before
          parserRecognizeAfterInitialIndexBinding
          (.returned (some
            (parseResultValue 2 (Int.ofNat stateCount) (-1) 0)))
          result.physicalAfter := by
        rw [extractedParserRecognize_after_initial_index_shape]
        simpa [initial,
          Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
            executesSequenceReturned result.execution
      exact {
        resultValue := parseResultValue 2 (Int.ofNat stateCount) (-1) 0
        afterWorld := functionalAfter.world
        afterEnvironment := functionalAfter.environment
        execution := functionalWhole
        physicalAfter := result.physicalAfter
        physicalExecution := physicalWhole
        physicalEffect := by
          simpa [initial, recognizerInitialWrites] using result.effect
        physicalWellFormed := loopWellFormed
        finalWorkspace := finalWorkspace
        finalWorkspaceValues := finalValues
        growth := initialGrowth
        workspaceArtifact := terminal.workspaceArtifact
        outcome := .full stateCount
      }
  | completed nextWorkspace nextValues physicalAfter initialGrowth
      completedInvariant worldEq environmentEq =>
      let position := completedInvariant.functional_execute_position_statement
      have related : Lanius.FunctionalView.Env.Extends
          positionStatementIntoInitialEmbedding
          (positionStatementEnvironment words tokens nextValues grammarCell
            tokensCell workspaceCell workspaceLayout grammar grammarLayout
            nextWorkspace.states.length)
          functionalAfter.environment := by
        rw [environmentEq]
        exact positionStatementEnvironment_extends_initialContinuation words
          tokens nextValues grammarCell tokensCell workspaceCell workspaceLayout
          grammar grammarLayout first count nextWorkspace.states.length count
      let positionLarge := positionStatementExecution_in_initial_environment
        position.execution functionalAfter.environment related
      have loopExecution' : Lanius.FunctionalView.Stateful.Command.Evaluates
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (positionStatefulMachine workspaceLayout grammar words tokens
            grammarCell tokensCell)
          (stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell)
          (initialContinuationEnvironment words tokens workspaceValues
            grammarCell tokensCell workspaceCell workspaceLayout grammar
            grammarLayout first count workspace.states.length index)
          initialLoopCommand .next
          (stateWorld words tokens nextValues grammarCell tokensCell workspaceCell)
          functionalAfter.environment := by
        simpa only [worldEq, stateWorld, predictionWorld] using
          loopExecutionAtSource
      have functionalWhole : Lanius.FunctionalView.Stateful.Command.Evaluates
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (positionStatefulMachine workspaceLayout grammar words tokens
            grammarCell tokensCell)
          (stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell)
          (initialContinuationEnvironment words tokens workspaceValues
            grammarCell tokensCell workspaceCell workspaceLayout grammar
            grammarLayout first count workspace.states.length index)
          initialContinuationCommand
          (.returned (some position.resultValue)) position.afterWorld
          positionLarge.afterLarge := by
        rw [initialContinuationCommand_shape,
          initialExpectedContinuationCommand]
        exact .sequenceNext loopExecution' positionLarge.evaluated
      have physicalWhole : Executes verifiedParserCore before
          parserRecognizeAfterInitialIndexBinding
          (.returned (some position.resultValue)) position.physicalAfter := by
        rw [extractedParserRecognize_after_initial_index_shape]
        exact executesSequence (by
          simpa [initial,
            Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
              result.execution) position.physicalExecution
      have continuationWrites : CellSet.Subset
          (recognizerPositionStatementWrites workspaceCell stateCountCell)
          (recognizerInitialWrites workspaceCell stateCountCell indexCell) := by
        intro cell written
        change cell = workspaceCell ∨ cell = stateCountCell at written
        change cell = workspaceCell ∨ cell = stateCountCell ∨ cell = indexCell
        exact written.elim Or.inl (fun found => Or.inr (Or.inl found))
      have initialEffect : ModifiesOnly
          (recognizerInitialWrites workspaceCell stateCountCell indexCell)
          before result.physicalAfter := by
        simpa [initial, recognizerInitialWrites] using result.effect
      exact {
        resultValue := position.resultValue
        afterWorld := position.afterWorld
        afterEnvironment := positionLarge.afterLarge
        execution := functionalWhole
        physicalAfter := position.physicalAfter
        physicalExecution := physicalWhole
        physicalEffect := initialEffect.trans_same
          (position.physicalEffect.weaken continuationWrites)
        physicalWellFormed := position.physicalWellFormed
        finalWorkspace := position.finalWorkspace
        finalWorkspaceValues := position.finalWorkspaceValues
        growth := initialGrowth.trans position.growth
        workspaceArtifact := position.workspaceArtifact
        outcome := .seeded nextWorkspace nextValues
          (.returned (some position.resultValue)) position.outcome
      }

/-- Compose the complete start-production loop with the already verified
    position/root continuation. -/
noncomputable def RecognizerInitialLoopInvariant.execute_continuation
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell before first count index) :
    RecognizerInitialContinuationExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell before first count index
      invariant := by
  let synchronized := invariant.functional_execute_continuation
  exact {
    after := synchronized.physicalAfter
    completion := .returned (some synchronized.resultValue)
    execution := synchronized.physicalExecution
    effect := synchronized.physicalEffect
    wellFormed := synchronized.physicalWellFormed
    finalWorkspace := synchronized.finalWorkspace
    finalWorkspaceValues := synchronized.finalWorkspaceValues
    growth := synchronized.growth
    workspaceArtifact := synchronized.workspaceArtifact
    outcome := synchronized.outcome
  }


end Lanius.Extraction.ParserRecognize
