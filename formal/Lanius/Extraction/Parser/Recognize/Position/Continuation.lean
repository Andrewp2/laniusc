import Lanius.Extraction.Parser.Recognize.Root.Selection
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
inductive RecognizerPositionStatementOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace) :
    Completion → Type
  | full (position stateCount : Nat) :
      RecognizerPositionStatementOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace
        (parserCapacityCompletion position stateCount)
  | completed (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace) (completion : Completion)
      (root : RecognizerRootStatementOutcome grammar tokens workspace completion) :
      RecognizerPositionStatementOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace completion

/-- The only caller-owned cells mutated by the position/root continuation.
    The loop's position and furthest-position cells are lexical temporaries
    and disappear when `parserRecognizePositionStatement` closes its scopes. -/
def recognizerPositionStatementWrites
    (workspaceCell stateCountCell : CellId) : CellSet :=
  CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton stateCountCell)

/-- Result of closing the two lexical counters around the position/root body.
    This is the physical refinement boundary shared by every terminal semantic
    outcome of the statement. -/
private structure RecognizerPositionScopeClosure
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (first count : Nat)
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell before first count count)
    (completion : Completion) (bodyAfter : State) where
  after : State
  execution : Executes verifiedParserCore before parserRecognizePositionStatement
    completion after
  effect : ModifiesOnly
    (recognizerPositionStatementWrites workspaceCell stateCountCell)
    before after
  wellFormed : StateWellFormed after
  cellsEq : after.cells = bodyAfter.cells

/-- Close locals `23` and `22` once, independently of the terminal result
    produced by the position/root body.  Previously each semantic branch
    replayed this store-and-frame argument separately. -/
private noncomputable def closeRecognizerPositionScopes
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell before first count count)
    (bodyAfter : State) (completion : Completion)
    (bodyExecution : Executes verifiedParserCore
      ((before.bindLocal 22 (.signed .i32 0)).bindLocal 23
        (.signed .i32 0))
      (.sequence parserRecognizePositionLoop parserRecognizeRootStatement)
      completion bodyAfter)
    (bodyEffect : ModifiesOnly
      (positionLoopMutableCells workspaceCell stateCountCell
        (before.bindLocal 22 (.signed .i32 0)).nextCell before.nextCell)
      ((before.bindLocal 22 (.signed .i32 0)).bindLocal 23
        (.signed .i32 0)) bodyAfter)
    (bodyWellFormed : StateWellFormed bodyAfter) :
    RecognizerPositionScopeClosure grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell before first count invariant
      completion bodyAfter := by
  let furthestState := before.bindLocal 22 (.signed .i32 0)
  let positionState := furthestState.bindLocal 23 (.signed .i32 0)
  have positionInitializer : Evaluates verifiedParserCore furthestState
      (.value (.signed .i32 0)) (.signed .i32 0) furthestState := ⟨1, rfl⟩
  let positionRetained := CellSet.union
    (recognizerPositionStatementWrites workspaceCell stateCountCell)
    (CellSet.singleton before.nextCell)
  have positionBodyEffect : ModifiesOnly
      (CellSet.union positionRetained
        (CellSet.singleton furthestState.nextCell))
      positionState bodyAfter := by
    have writesEqual :
        positionLoopMutableCells workspaceCell stateCountCell
          furthestState.nextCell before.nextCell =
        CellSet.union positionRetained
          (CellSet.singleton furthestState.nextCell) := by
      funext cell
      simp [positionRetained, recognizerPositionStatementWrites,
        positionLoopMutableCells, CellSet.union, CellSet.singleton]
      constructor
      · rintro (rfl | rfl | rfl | rfl)
        · exact .inl (.inl (.inl rfl))
        · exact .inl (.inl (.inr rfl))
        · exact .inr rfl
        · exact .inl (.inr rfl)
      · rintro (((rfl | rfl) | rfl) | rfl)
        · exact .inl rfl
        · exact .inr (.inl rfl)
        · exact .inr (.inr (.inr rfl))
        · exact .inr (.inr (.inl rfl))
    rw [← writesEqual]
    simpa [furthestState, positionState] using bodyEffect
  let positionClosed := closesFreshLocalExcept (id := 23)
    (type := parserI32Type) positionRetained
    (bindLocal_preserves_well_formed before 22 (.signed .i32 0)
      invariant.frame.recognizer.wellFormed)
    positionInitializer bodyExecution positionBodyEffect bodyWellFormed
  have furthestInitializer : Evaluates verifiedParserCore before
      (.value (.signed .i32 0)) (.signed .i32 0) before := ⟨1, rfl⟩
  have furthestBodyEffect : ModifiesOnly
      (CellSet.union
        (recognizerPositionStatementWrites workspaceCell stateCountCell)
        (CellSet.singleton before.nextCell))
      furthestState positionClosed.after := by
    simpa [positionRetained] using positionClosed.effect
  let furthestClosed := closesFreshLocalExcept (id := 22)
    (type := parserI32Type)
    (recognizerPositionStatementWrites workspaceCell stateCountCell)
    invariant.frame.recognizer.wellFormed furthestInitializer
    positionClosed.execution furthestBodyEffect positionClosed.wellFormed
  have positionCells : positionClosed.after.cells = bodyAfter.cells := by
    simp [positionClosed]
  have furthestCells : furthestClosed.after.cells =
      positionClosed.after.cells := by
    simp [furthestClosed]
  exact {
    after := furthestClosed.after
    execution := by
      rw [extractedParserRecognize_position_statement_shape]
      simpa [furthestState, positionState] using furthestClosed.execution
    effect := furthestClosed.effect
    wellFormed := furthestClosed.wellFormed
    cellsEq := furthestCells.trans positionCells
  }

/-- One execution shared by the mechanically reified FunctionalView position
    statement and its physical Core refinement.  The returned workspace
    artifact is attached after the two lexical counters have been closed. -/
structure RecognizerPositionStatementFunctionalExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (first count : Nat)
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell before first count count) where
  resultValue : Value
  afterWorld : Lanius.FunctionalView.Core.ReadOnly.World
  afterEnvironment : Lanius.FunctionalView.Env 13
  execution : Lanius.FunctionalView.Stateful.Command.Evaluates
    (positionTermMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    (positionStatementEnvironment words tokens workspaceValues grammarCell
      tokensCell workspaceCell workspaceLayout grammar grammarLayout
      workspace.states.length)
    positionStatementCommand (.returned (some resultValue)) afterWorld
    afterEnvironment
  physicalAfter : State
  physicalExecution : Executes verifiedParserCore before
    parserRecognizePositionStatement (.returned (some resultValue)) physicalAfter
  physicalEffect : ModifiesOnly
    (recognizerPositionStatementWrites workspaceCell stateCountCell)
    before physicalAfter
  physicalWellFormed : StateWellFormed physicalAfter
  finalWorkspace : LogicalWorkspace
  finalWorkspaceValues : List Int
  growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
    finalWorkspace
  workspaceArtifact : RecognizerWorkspaceArtifact workspaceLayout
    finalWorkspace finalWorkspaceValues workspaceCell physicalAfter
  outcome : RecognizerPositionStatementOutcome grammarLayout grammar words
    tokens workspaceLayout workspace (.returned (some resultValue))

/-- Execute both scoped initializers, the total position loop, and final root
    classification through one FunctionalView statement.  Physical Core state
    is carried only as the refinement witness needed by callers. -/
noncomputable def
    RecognizerInitialLoopInvariant.functional_execute_position_statement
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell before first count count) :
    RecognizerPositionStatementFunctionalExecution grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell before first count invariant := by
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let baseEnvironment := positionStatementEnvironment words tokens
    workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
    grammarLayout workspace.states.length
  let furthestState := before.bindLocal 22 (.signed .i32 0)
  let positionState := furthestState.bindLocal 23 (.signed .i32 0)
  let positionInvariant := invariant.enter_position_loop
  let initial : RecognizerPositionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      furthestState.nextCell before.nextCell := {
    workspace := workspace
    workspaceValues := workspaceValues
    runtime := positionState
    cursor := .active 0 0 positionInvariant
  }
  generalize runEq : initial.functional_run = assembled
  obtain ⟨completion, functionalAfter, trace, result⟩ := assembled
  have sourceCompletionEq : initial.functional_run.completion = completion := by
    simpa using congrArg (fun run => run.completion) runEq
  have sourceAfterEq : initial.functional_run.after = functionalAfter := by
    simpa using congrArg (fun run => run.after) runEq
  have initialFurthestEq : initial.currentFurthest = 0 := by
    rfl
  have initialPositionEq : initial.currentPosition = 0 := by
    rfl
  have loopExecution : Lanius.FunctionalView.Stateful.Command.Evaluates
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world
      (positionEnvironment words tokens workspaceValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar grammarLayout
        workspace.states.length 0 0)
      positionLoopCommand completion functionalAfter.world
      functionalAfter.environment := by
    simpa only [initial, RecognizerPositionConfig.functionalRuntime, world,
      sourceCompletionEq, sourceAfterEq, initialFurthestEq, initialPositionEq,
      positionLoopCommand,
      Lanius.FunctionalView.Stateful.Loop.Runtime.world,
      Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
        initial.functional_run.trace.evaluates
  have boundEnvironmentEq :
      ((baseEnvironment.push (.signed .i32 0)).push (.signed .i32 0)) =
        positionEnvironment words tokens workspaceValues grammarCell tokensCell
          workspaceCell workspaceLayout grammar grammarLayout
          workspace.states.length 0 0 := by
    exact positionStatementEnvironment_push_zeroes words tokens workspaceValues
      grammarCell tokensCell workspaceCell workspaceLayout grammar grammarLayout
      workspace.states.length
  cases completion with
  | returned returnedValue =>
    cases result.outcome with
    | full position stateCount physicalAfter finalWorkspace finalValues growth
        terminal fullWellFormed =>
      have bodyExecution : Lanius.FunctionalView.Stateful.Command.Evaluates
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (positionStatefulMachine workspaceLayout grammar words tokens
            grammarCell tokensCell)
          world ((baseEnvironment.push (.signed .i32 0)).push
            (.signed .i32 0))
          (.sequence positionLoopCommand positionStatementRootCommand)
          (.returned (some (parseResultValue 2 (Int.ofNat stateCount) (-1)
            (Int.ofNat position))))
          functionalAfter.world functionalAfter.environment := by
        rw [boundEnvironmentEq]
        exact .sequenceStop loopExecution (by intro impossible; cases impossible)
      have positionPhysical : Executes verifiedParserCore positionState
          parserRecognizePositionLoop
          (parserCapacityCompletion position stateCount)
          result.physicalAfter := by
        simpa only [initial, positionState, parserCapacityCompletion,
          Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
            result.execution
      have physicalBody : Executes verifiedParserCore positionState
          (.sequence parserRecognizePositionLoop parserRecognizeRootStatement)
          (parserCapacityCompletion position stateCount) result.physicalAfter :=
        executesSequenceReturned positionPhysical
      have physicalBodyEffect : ModifiesOnly
          (positionLoopMutableCells workspaceCell stateCountCell
            furthestState.nextCell before.nextCell)
          positionState result.physicalAfter := by
        simpa only [initial, furthestState, positionState] using result.effect
      let closed := closeRecognizerPositionScopes invariant result.physicalAfter
        (parserCapacityCompletion position stateCount) physicalBody
        physicalBodyEffect fullWellFormed
      have artifact : RecognizerWorkspaceArtifact workspaceLayout finalWorkspace
          finalValues workspaceCell closed.after :=
        terminal.workspaceArtifact.transfer_cells closed.cellsEq
      exact {
        resultValue := parseResultValue 2 (Int.ofNat stateCount) (-1)
          (Int.ofNat position)
        afterWorld := functionalAfter.world
        afterEnvironment :=
          Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.pop
              functionalAfter.environment)
        execution := by
          rw [positionStatementCommand_shape,
            positionExpectedStatementCommand]
          exact .letValue (by rfl) (.letValue (by rfl) bodyExecution)
        physicalAfter := closed.after
        physicalExecution := closed.execution
        physicalEffect := closed.effect
        physicalWellFormed := closed.wellFormed
        finalWorkspace := finalWorkspace
        finalWorkspaceValues := finalValues
        growth := growth
        workspaceArtifact := artifact
        outcome := .full position stateCount
      }
  | next =>
    cases result.outcome with
    | completed nextWorkspace nextValues physicalAfter growth furthest finished
        worldEq environmentEq =>
      let rootEntry := finished.enter_root_loop
      let root := rootEntry.functional_execute_statement
      have loopExecution' : Lanius.FunctionalView.Stateful.Command.Evaluates
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (positionStatefulMachine workspaceLayout grammar words tokens
            grammarCell tokensCell)
          world
          (positionEnvironment words tokens workspaceValues grammarCell
            tokensCell workspaceCell workspaceLayout grammar grammarLayout
            workspace.states.length 0 0)
          positionLoopCommand .next
          (stateWorld words tokens nextValues grammarCell tokensCell
            workspaceCell)
          functionalAfter.environment := by
        simpa only [worldEq] using loopExecution
      have related : Lanius.FunctionalView.Env.Extends
          rootStatementIntoPositionEmbedding
          (rootStatementEnvironment words nextValues grammarCell workspaceCell
            workspaceLayout grammar nextWorkspace.states.length furthest)
          functionalAfter.environment := by
        rw [environmentEq]
        exact rootStatementEnvironment_extends_positionEnvironment words tokens
          nextValues grammarCell tokensCell workspaceCell workspaceLayout grammar
          grammarLayout nextWorkspace.states.length furthest
          (finalPosition workspaceLayout.tokenCount + 1)
      let rootLarge := rootStatementExecution_in_position_environment
        (tokens := tokens) (tokensCell := tokensCell) root.execution
        functionalAfter.environment related
      have bodyExecution : Lanius.FunctionalView.Stateful.Command.Evaluates
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (positionStatefulMachine workspaceLayout grammar words tokens
            grammarCell tokensCell)
          world ((baseEnvironment.push (.signed .i32 0)).push
            (.signed .i32 0))
          (.sequence positionLoopCommand positionStatementRootCommand)
          (.returned (some root.resultValue)) root.afterWorld
          rootLarge.afterLarge := by
        rw [boundEnvironmentEq]
        exact .sequenceNext loopExecution' rootLarge.evaluated
      have positionPhysical : Executes verifiedParserCore positionState
          parserRecognizePositionLoop .next result.physicalAfter := by
        simpa only [initial, positionState,
          Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
            result.execution
      have physicalBody : Executes verifiedParserCore positionState
          (.sequence parserRecognizePositionLoop parserRecognizeRootStatement)
          (.returned (some root.resultValue)) root.physicalAfter :=
        executesSequence positionPhysical root.physicalExecution
      have physicalBodyEffect : ModifiesOnly
          (positionLoopMutableCells workspaceCell stateCountCell
            furthestState.nextCell before.nextCell)
          positionState root.physicalAfter := by
        have positionEffect : ModifiesOnly
            (positionLoopMutableCells workspaceCell stateCountCell
              furthestState.nextCell before.nextCell)
            positionState result.physicalAfter := by
          simpa only [initial, furthestState, positionState] using result.effect
        exact positionEffect.trans_same
          (root.physicalEffect.weaken CellSet.empty_subset)
      let closed := closeRecognizerPositionScopes invariant root.physicalAfter
        (.returned (some root.resultValue)) physicalBody physicalBodyEffect
        root.physicalWellFormed
      have rootArtifact : RecognizerWorkspaceArtifact workspaceLayout
          nextWorkspace nextValues workspaceCell root.physicalAfter := {
        workspaceLength := finished.frame.appendFrame.recognizer.workspaceLength
        workspaceEncoded := finished.frame.appendFrame.recognizer.workspaceEncoded
        workspaceBacking := root.physicalEffect.empty_preserves_entry
          finished.frame.appendFrame.recognizer.wellFormed
          finished.frame.appendFrame.recognizer.workspaceBacking
      }
      have artifact : RecognizerWorkspaceArtifact workspaceLayout nextWorkspace
          nextValues workspaceCell closed.after :=
        rootArtifact.transfer_cells closed.cellsEq
      exact {
        resultValue := root.resultValue
        afterWorld := root.afterWorld
        afterEnvironment :=
          Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.pop rootLarge.afterLarge)
        execution := by
          rw [positionStatementCommand_shape,
            positionExpectedStatementCommand]
          exact .letValue (by rfl) (.letValue (by rfl) bodyExecution)
        physicalAfter := closed.after
        physicalExecution := closed.execution
        physicalEffect := closed.effect
        physicalWellFormed := closed.wellFormed
        finalWorkspace := nextWorkspace
        finalWorkspaceValues := nextValues
        growth := growth
        workspaceArtifact := artifact
        outcome := .completed nextWorkspace nextValues growth
          (.returned (some root.resultValue)) root.outcome
      }
  | breakLoop => cases result.outcome
  | continueLoop => cases result.outcome

structure RecognizerPositionStatementExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (first count : Nat)
    (beforeInvariant : RecognizerInitialLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell before first count
      count) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before parserRecognizePositionStatement
    completion after
  effect : ModifiesOnly
    (recognizerPositionStatementWrites workspaceCell stateCountCell)
    before after
  wellFormed : StateWellFormed after
  finalWorkspace : LogicalWorkspace
  finalWorkspaceValues : List Int
  growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
    finalWorkspace
  workspaceArtifact : RecognizerWorkspaceArtifact workspaceLayout
    finalWorkspace finalWorkspaceValues workspaceCell after
  outcome : RecognizerPositionStatementOutcome grammarLayout grammar words
    tokens workspaceLayout workspace completion

/-- Execute the entire recognizer continuation after successful initial-state
    seeding: the scoped position loop followed by final root classification. -/
noncomputable def RecognizerInitialLoopInvariant.execute_position_statement
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell before first count count) :
    RecognizerPositionStatementExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell before first count invariant := by
  let synchronized := invariant.functional_execute_position_statement
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
