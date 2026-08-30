import Lanius.Extraction.Parser.Recognize.State.Driver

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
/-! ## Enclosing chart-position loop -/

/-- Persistent resources at the start of one chart-position iteration.  The
    workspace and state count form the append frame; `position` and
    `furthest_position` are separately owned loop scalars. -/
structure RecognizerPositionLoopInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (runtime : State) (position furthest : Nat) : Prop where
  appendFrame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime position
  workspaceWithinGrammar : WorkspaceWithinGrammar grammar workspace
  finalPositionLocal : runtime.local? 6 = some
    (.signed .i32 (Int.ofNat (finalPosition workspaceLayout.tokenCount)))
  kindCountLocal : runtime.local? 11 = some
    (.signed .i32 (Int.ofNat grammar.grammar.n_kinds))
  startNonterminalLocal : runtime.local? 12 = some
    (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal))
  lhsOffsetsOffsetLocal : runtime.local? 13 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset))
  lhsCountsOffsetLocal : runtime.local? 14 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset))
  lhsProductionsOffsetLocal : runtime.local? 15 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset))
  positionOwned : (Assertion.localPointsTo 23 positionCell
    (some (.signed .i32 (Int.ofNat position)))).holds runtime
  furthestOwned : (Assertion.localPointsTo 22 furthestCell
    (some (.signed .i32 (Int.ofNat furthest)))).holds runtime
  furthestBound : furthest ≤ position
  positionFurthestDistinct : positionCell ≠ furthestCell
  positionStateCountDistinct : positionCell ≠ stateCountCell
  furthestStateCountDistinct : furthestCell ≠ stateCountCell
  positionGrammarDistinct : positionCell ≠ grammarCell
  positionTokensDistinct : positionCell ≠ tokensCell
  furthestGrammarDistinct : furthestCell ≠ grammarCell
  furthestTokensDistinct : furthestCell ≠ tokensCell
  positionWorkspaceDistinct : positionCell ≠ workspaceCell
  furthestWorkspaceDistinct : furthestCell ≠ workspaceCell
  preservedSeparate : PositionLoopFrameSeparated runtime workspaceCell
    stateCountCell positionCell furthestCell

theorem PositionLoopPreservedLocal.to_initial
    {id : VarId} (preserved : PositionLoopPreservedLocal id) :
    InitialLoopPersistentLocal id := by
  rcases preserved with parameter | framed
  · exact Or.inl parameter
  · right
    rw [mem_verifiedParserPositionLoopPreservedFrameIds_iff] at framed
    rw [mem_verifiedParserInitialLoopSharedFrameIds_iff]
    rcases framed with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
      rfl | rfl | rfl | rfl <;> simp

/-- Introduce the two source locals immediately following successful initial
    seeding and obtain the exact position-loop invariant.  Their cells are
    fresh by construction; every other position-loop local is protected by
    the initial loop's artifact-derived live frame. -/
theorem RecognizerInitialLoopInvariant.enter_position_loop
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count count) :
    RecognizerPositionLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell
      (runtime.bindLocal 22 (.signed .i32 0) |>.nextCell)
      runtime.nextCell
      ((runtime.bindLocal 22 (.signed .i32 0)).bindLocal 23
        (.signed .i32 0)) 0 0 := by
  let furthestState := runtime.bindLocal 22 (.signed .i32 0)
  let positionState := furthestState.bindLocal 23 (.signed .i32 0)
  let furthestCell := runtime.nextCell
  let positionCell := furthestState.nextCell
  let atFurthest := invariant.frame.after_bind_local 22 (.signed .i32 0)
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide) (by decide) (by decide)
  let appendFrame := atFurthest.after_bind_local 23 (.signed .i32 0)
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide) (by decide) (by decide)
  have furthestOwnedAtFurthest : (Assertion.localPointsTo 22 furthestCell
      (some (.signed .i32 0))).holds furthestState := by
    simpa [furthestState, furthestCell] using
      bindLocal_owns_fresh runtime 22 (.signed .i32 0)
        invariant.frame.recognizer.wellFormed
  have furthestOwned : (Assertion.localPointsTo 22 furthestCell
      (some (.signed .i32 0))).holds positionState := by
    simpa [positionState] using bindLocal_preserves_localPointsTo_of_ne
      furthestState 23 22 (.signed .i32 0) furthestCell
      (some (.signed .i32 0)) atFurthest.recognizer.wellFormed
      (by decide) furthestOwnedAtFurthest
  have positionOwned : (Assertion.localPointsTo 23 positionCell
      (some (.signed .i32 0))).holds positionState := by
    simpa [positionState, positionCell] using
      bindLocal_owns_fresh furthestState 23 (.signed .i32 0)
        atFurthest.recognizer.wellFormed
  have preserveLocal (id : VarId) (idBefore : id < 22) (value : Value)
      (found : runtime.local? id = some value) :
      positionState.local? id = some value := by
    have atFirst := (bindLocal_preserves_other_local
      (value := .signed .i32 0) invariant.frame.recognizer.wellFormed
      (Nat.ne_of_gt idBefore)).trans found
    exact (bindLocal_preserves_other_local atFurthest.recognizer.wellFormed
      (value := .signed .i32 0)
      (Nat.ne_of_gt (Nat.lt_trans idBefore (by decide)))).trans atFirst
  have furthestDifferent (cell : CellId) {cellValue : Option Value}
      (entry : runtime.cellEntry? cell = some {
        id := cell, value := cellValue }) : furthestCell ≠ cell :=
    StateWellFormed.nextCell_ne_of_entry
      invariant.frame.recognizer.wellFormed entry
  have positionDifferent (cell : CellId) {cellValue : Option Value}
      (entry : furthestState.cellEntry? cell = some {
        id := cell, value := cellValue }) : positionCell ≠ cell :=
    StateWellFormed.nextCell_ne_of_entry atFurthest.recognizer.wellFormed entry
  have initialEntryAtFurthest (cell : CellId) {cellValue : Option Value}
      (entry : runtime.cellEntry? cell = some {
        id := cell, value := cellValue }) :
      furthestState.cellEntry? cell = some {
        id := cell, value := cellValue } := by
    have old := StateWellFormed.cell_lt_next_of_entry
      invariant.frame.recognizer.wellFormed entry
    exact ((bindLocal_effect runtime 22 (.signed .i32 0)).oldCells cell old
      (by simp [CellSet.empty])).trans entry
  exact {
    appendFrame := by simpa [furthestState, positionState] using appendFrame
    workspaceWithinGrammar := invariant.workspaceWithinGrammar
    finalPositionLocal := preserveLocal 6 (by decide) _
      invariant.finalPositionLocal
    kindCountLocal := preserveLocal 11 (by decide) _ invariant.kindCountLocal
    startNonterminalLocal := preserveLocal 12 (by decide) _
      invariant.startNonterminalLocal
    lhsOffsetsOffsetLocal := preserveLocal 13 (by decide) _
      invariant.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal := preserveLocal 14 (by decide) _
      invariant.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal := preserveLocal 15 (by decide) _
      invariant.lhsProductionsOffsetLocal
    positionOwned := by simpa [positionState, positionCell] using positionOwned
    furthestOwned := by simpa [positionState, furthestCell] using furthestOwned
    furthestBound := by decide
    positionFurthestDistinct := positionDifferent furthestCell
      furthestOwnedAtFurthest.2
    positionStateCountDistinct := positionDifferent stateCountCell
      (initialEntryAtFurthest stateCountCell invariant.frame.stateCountOwned.2)
    furthestStateCountDistinct := furthestDifferent stateCountCell
      invariant.frame.stateCountOwned.2
    positionGrammarDistinct := positionDifferent grammarCell
      (initialEntryAtFurthest grammarCell
        invariant.frame.recognizer.grammarBacking)
    positionTokensDistinct := positionDifferent tokensCell
      (initialEntryAtFurthest tokensCell invariant.frame.recognizer.tokensBacking)
    furthestGrammarDistinct := furthestDifferent grammarCell
      invariant.frame.recognizer.grammarBacking
    furthestTokensDistinct := furthestDifferent tokensCell
      invariant.frame.recognizer.tokensBacking
    positionWorkspaceDistinct := positionDifferent workspaceCell
      (initialEntryAtFurthest workspaceCell
        invariant.frame.recognizer.workspaceBacking)
    furthestWorkspaceDistinct := furthestDifferent workspaceCell
      invariant.frame.recognizer.workspaceBacking
    preservedSeparate := by
      unfold PositionLoopFrameSeparated
      intro cell framed written
      obtain ⟨id, idBound, cellId⟩ := framed
      have preserved :=
        (PositionLoopPreservedLocal_source_frame id).mpr idBound
      have initialPersistent := preserved.to_initial
      have idBefore : id < 22 := Nat.lt_trans initialPersistent.lt18 (by decide)
      have atFurthestId : furthestState.cellId? id = runtime.cellId? id :=
        bindLocal_preserves_other_cellId runtime 22 id (.signed .i32 0)
          (Nat.ne_of_gt idBefore)
      have atPositionId : positionState.cellId? id = furthestState.cellId? id :=
        bindLocal_preserves_other_cellId furthestState 23 id (.signed .i32 0)
          (Nat.ne_of_gt (Nat.lt_trans idBefore (by decide)))
      have originalCell : runtime.cellId? id = some cell := by
        exact (atPositionId.trans atFurthestId).symm.trans cellId
      rcases written with workspaceWritten | stateCountWritten |
          positionWritten | furthestWritten
      · subst cell
        exact invariant.persistentSeparate workspaceCell
          ⟨id, (InitialLoopPersistentLocal_source_frame id).mp
            initialPersistent, originalCell⟩ (by exact Or.inl rfl)
      · subst cell
        exact invariant.persistentSeparate stateCountCell
          ⟨id, (InitialLoopPersistentLocal_source_frame id).mp
            initialPersistent, originalCell⟩ (by exact Or.inr (Or.inl rfl))
      · subst cell
        exact bindLocal_other_cellId_ne_fresh furthestState 23 id
          (.signed .i32 0) atFurthest.recognizer.wellFormed
          (Nat.ne_of_gt (Nat.lt_trans idBefore (by decide))) cellId
      · subst cell
        exact bindLocal_other_cellId_ne_fresh runtime 22 id
          (.signed .i32 0) invariant.frame.recognizer.wellFormed
          (Nat.ne_of_gt idBefore) (atFurthestId.trans originalCell)
  }

theorem RecognizerPositionLoopInvariant.positionLocal
    (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest) :
    runtime.local? 23 = some (.signed .i32 (Int.ofNat position)) :=
  Assertion.localPointsTo_local 23 positionCell _ runtime
    invariant.positionOwned

theorem RecognizerPositionLoopInvariant.condition_true
    (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest) :
    Evaluates verifiedParserCore runtime
      (.binary .lessEqual (.local 23) (.local 6)) (.boolean true) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 23)
      (.signed .i32 (Int.ofNat position)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 23 _
      invariant.positionLocal⟩
  have right : Evaluates verifiedParserCore runtime (.local 6)
      (.signed .i32
        (Int.ofNat (finalPosition workspaceLayout.tokenCount))) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 6 _
      invariant.finalPositionLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_le,
    invariant.appendFrame.positionBound]

theorem RecognizerPositionLoopInvariant.positionAdvanceI32
    (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest) :
    position + 2 ≤ 2147483647 := by
  have positionBound := invariant.appendFrame.positionBound
  have tokenBound := workspaceLayout.tokenBound
  simp only [finalPosition, maxTokenCount] at positionBound tokenBound
  omega

theorem RecognizerPositionLoopInvariant.preservedLocalsSeparate
    (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest) :
    ∀ id, PositionLoopPreservedLocal id →
      runtime.cellId? id ≠ some workspaceCell ∧
      runtime.cellId? id ≠ some stateCountCell ∧
      runtime.cellId? id ≠ some positionCell ∧
      runtime.cellId? id ≠ some furthestCell := by
  intro id preserved
  have framed := (PositionLoopPreservedLocal_source_frame id).mp preserved
  refine ⟨?_, ?_, ?_, ?_⟩ <;> intro cellId
  · exact invariant.preservedSeparate workspaceCell
      ⟨id, framed, cellId⟩ (by exact Or.inl rfl)
  · exact invariant.preservedSeparate stateCountCell
      ⟨id, framed, cellId⟩ (by exact Or.inr (Or.inl rfl))
  · exact invariant.preservedSeparate positionCell
      ⟨id, framed, cellId⟩ (by exact Or.inr (Or.inr (Or.inl rfl)))
  · exact invariant.preservedSeparate furthestCell
      ⟨id, framed, cellId⟩ (by exact Or.inr (Or.inr (Or.inr rfl)))

/-- Reframe the position loop after the optional write to
    `furthest_position`.  This is the only scalar mutation before the state
    cursor's temporary scope is entered. -/
theorem RecognizerPositionLoopInvariant.after_furthest_effect
    (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell before position
      furthest)
    (effect : ModifiesOnly (CellSet.singleton furthestCell) before after)
    (afterWellFormed : StateWellFormed after)
    (afterFurthestOwned : (Assertion.localPointsTo 22 furthestCell
      (some (.signed .i32 (Int.ofNat nextFurthest)))).holds after)
    (nextFurthestBound : nextFurthest ≤ position) :
    RecognizerPositionLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell after position
      nextFurthest := by
  have parameterFrameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        verifiedParserRecognizerParameterFrame)
      (CellSet.singleton furthestCell) := by
    intro cell framed written
    obtain ⟨id, member, cellId⟩ := framed
    have preserved : PositionLoopPreservedLocal id := Or.inl member
    exact invariant.preservedLocalsSeparate id preserved |>.2.2.2
      (cellId.trans (by simpa [CellSet.singleton] using written))
  let recognizer := invariant.appendFrame.recognizer
    |>.after_disjoint_scalar_effect furthestCell effect afterWellFormed
      invariant.furthestGrammarDistinct.symm
      invariant.furthestTokensDistinct.symm
      invariant.furthestWorkspaceDistinct.symm parameterFrameDisjoint
  let appendFrame := invariant.appendFrame.after_scalar_effect furthestCell
    effect recognizer
    (invariant.preservedLocalsSeparate 8 (by
      simp [PositionLoopPreservedLocal]) |>.2.2.2)
    (invariant.preservedLocalsSeparate 9 (by
      simp [PositionLoopPreservedLocal]) |>.2.2.2)
    invariant.furthestStateCountDistinct.symm
  have enlarged : ModifiesOnly
      (positionLoopMutableCells workspaceCell stateCountCell positionCell
        furthestCell) before after := effect.weaken (by
    intro cell written
    change cell = furthestCell at written
    exact Or.inr (Or.inr (Or.inr written)))
  have preserveLocal (id : VarId) (preserved : PositionLoopPreservedLocal id)
      (value : Value) (found : before.local? id = some value) :
      after.local? id = some value :=
    enlarged.preserves_local_of_disjoint
      invariant.appendFrame.recognizer.wellFormed invariant.preservedSeparate
      ((PositionLoopPreservedLocal_source_frame id).mp preserved) found
  exact {
    appendFrame := appendFrame
    workspaceWithinGrammar := invariant.workspaceWithinGrammar
    finalPositionLocal := preserveLocal 6 (by
      simp [PositionLoopPreservedLocal]) _ invariant.finalPositionLocal
    kindCountLocal := preserveLocal 11 (by
      simp [PositionLoopPreservedLocal]) _ invariant.kindCountLocal
    startNonterminalLocal := preserveLocal 12 (by
      simp [PositionLoopPreservedLocal]) _ invariant.startNonterminalLocal
    lhsOffsetsOffsetLocal := preserveLocal 13 (by
      simp [PositionLoopPreservedLocal]) _ invariant.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal := preserveLocal 14 (by
      simp [PositionLoopPreservedLocal]) _ invariant.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal := preserveLocal 15 (by
      simp [PositionLoopPreservedLocal]) _
      invariant.lhsProductionsOffsetLocal
    positionOwned := effect.preserves_localPointsTo
      invariant.appendFrame.recognizer.wellFormed invariant.positionOwned (by
        simpa [CellSet.singleton] using invariant.positionFurthestDistinct)
    furthestOwned := afterFurthestOwned
    furthestBound := nextFurthestBound
    positionFurthestDistinct := invariant.positionFurthestDistinct
    positionStateCountDistinct := invariant.positionStateCountDistinct
    furthestStateCountDistinct := invariant.furthestStateCountDistinct
    positionGrammarDistinct := invariant.positionGrammarDistinct
    positionTokensDistinct := invariant.positionTokensDistinct
    furthestGrammarDistinct := invariant.furthestGrammarDistinct
    furthestTokensDistinct := invariant.furthestTokensDistinct
    positionWorkspaceDistinct := invariant.positionWorkspaceDistinct
    furthestWorkspaceDistinct := invariant.furthestWorkspaceDistinct
    preservedSeparate := by
      unfold PositionLoopFrameSeparated
      rw [enlarged.localBindingFrameFootprint_eq
        verifiedParserPositionLoopPreservedBindings]
      exact invariant.preservedSeparate
  }

structure RecognizerPositionActivityExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (before : State) (position furthest : Nat)
    (beforeInvariant : RecognizerPositionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell before
      position furthest) where
  after : State
  nextFurthest : Nat
  nextFurthestEq : nextFurthest =
    if workspace.chart position = [] then furthest else position
  execution : Executes verifiedParserCore before
    parserRecognizePositionActivity .next after
  effect : ModifiesOnly (CellSet.singleton furthestCell) before after
  invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell positionCell furthestCell after position
    nextFurthest

/-- Execute the exact chart-presence test.  A nonempty chart records the
    current position; an empty chart leaves the prior furthest position
    untouched. -/
noncomputable def RecognizerPositionLoopInvariant.execute_activity
    (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest) :
    RecognizerPositionActivityExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest invariant := by
  let headRead := invariant.appendFrame.recognizer.read_chart_head 23 position
    invariant.positionLocal invariant.appendFrame.positionBound
  have zeroResult : Evaluates verifiedParserCore headRead.after
      (.value (.signed .i32 0)) (.signed .i32 0) headRead.after := ⟨1, rfl⟩
  have furthestAfterRead : (Assertion.localPointsTo 22 furthestCell
      (some (.signed .i32 (Int.ofNat furthest)))).holds headRead.after :=
    headRead.effect.empty_preserves_assertion
      invariant.appendFrame.recognizer.wellFormed _ invariant.furthestOwned
  cases chartShape : workspace.chart position with
  | nil =>
      have conditionFalse : Evaluates verifiedParserCore runtime
          (.binary .greaterEqual (parserRecognizeChartHeadExpr 23)
            (.value (.signed .i32 0))) (.boolean false) headRead.after := by
        apply evaluatesEagerBinary (by decide) (by decide)
          headRead.evaluation zeroResult
        simp [chartHeadValue, chartShape, encodeStateId, evalBinaryValue,
          evalSignedBinary]
      have effect : ModifiesOnly (CellSet.singleton furthestCell) runtime
          headRead.after := headRead.effect.weaken CellSet.empty_subset
      exact {
        after := headRead.after
        nextFurthest := furthest
        nextFurthestEq := by simp [chartShape]
        execution := by
          rw [extractedParserRecognize_position_activity_shape]
          exact executesIfFalse conditionFalse
            (executesSkip verifiedParserCore headRead.after)
        effect := effect
        invariant := invariant.after_furthest_effect effect
          headRead.invariant.wellFormed furthestAfterRead
          invariant.furthestBound
      }
  | cons current remaining =>
      have conditionTrue : Evaluates verifiedParserCore runtime
          (.binary .greaterEqual (parserRecognizeChartHeadExpr 23)
            (.value (.signed .i32 0))) (.boolean true) headRead.after := by
        apply evaluatesEagerBinary (by decide) (by decide)
          headRead.evaluation zeroResult
        simp [chartHeadValue, chartShape, encodeStateId, evalBinaryValue,
          evalSignedBinary]
      have positionAfterRead : headRead.after.local? 23 =
          some (.signed .i32 (Int.ofNat position)) :=
        headRead.effect.empty_preserves_local
          invariant.appendFrame.recognizer.wellFormed invariant.positionLocal
      have positionResult : Evaluates verifiedParserCore headRead.after
          (.local 23) (.signed .i32 (Int.ofNat position)) headRead.after :=
        ⟨1, evalLocal_of_local 1 verifiedParserCore headRead.after 23 _
          positionAfterRead⟩
      let assigned := evaluatesSetOwnedLocalFromEmpty 22 furthestCell
        headRead.invariant.wellFormed furthestAfterRead positionResult
        headRead.invariant.wellFormed (ModifiesOnly.refl headRead.after)
      let after := Classical.choose assigned
      have assignmentFacts := Classical.choose_spec assigned
      have effect : ModifiesOnly (CellSet.singleton furthestCell) runtime
          after := by
        have combined := headRead.effect.trans assignmentFacts.2.2.2
        have writesEqual :
            CellSet.union CellSet.empty (CellSet.singleton furthestCell) =
              CellSet.singleton furthestCell := by
          funext cell
          simp [CellSet.union, CellSet.empty]
        rw [writesEqual] at combined
        exact combined
      exact {
        after := after
        nextFurthest := position
        nextFurthestEq := by simp [chartShape]
        execution := by
          rw [extractedParserRecognize_position_activity_shape]
          exact executesIfTrue conditionTrue
            (executesSequence (executesExpression assignmentFacts.1)
              (executesSkip verifiedParserCore after))
        effect := effect
        invariant := invariant.after_furthest_effect effect
          assignmentFacts.2.1 assignmentFacts.2.2.1
          (Nat.le_refl position)
      }

/-- Functional execution of the same checked chart-activity command.  Its
    result environment is canonical for the selected next furthest position,
    making it directly composable with the state-scope proof. -/
private structure RecognizerPositionActivityFunctionalExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (runtime : State) (position furthest : Nat)
    (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest) where
  nextFurthest : Nat
  nextFurthestEq : nextFurthest =
    if workspace.chart position = [] then furthest else position
  execution : Lanius.FunctionalView.Stateful.Command.Evaluates
    (positionTermMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    (positionEnvironment words tokens workspaceValues grammarCell tokensCell
      workspaceCell workspaceLayout grammar grammarLayout workspace.states.length
      furthest position)
    positionActivityCommand .next
    (stateWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    (positionEnvironment words tokens workspaceValues grammarCell tokensCell
      workspaceCell workspaceLayout grammar grammarLayout workspace.states.length
      nextFurthest position)

private noncomputable def
    RecognizerPositionLoopInvariant.functional_execute_activity
    (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest) :
    RecognizerPositionActivityFunctionalExecution grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest invariant := by
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let environment := positionEnvironment words tokens workspaceValues grammarCell
    tokensCell workspaceCell workspaceLayout grammar grammarLayout
    workspace.states.length furthest position
  have condition := positionActivityCondition_evaluates grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell workspace.states.length furthest position
    (stateWorld_finds_workspace
      invariant.appendFrame.recognizer.grammarWorkspaceDistinct
      invariant.appendFrame.recognizer.tokensWorkspaceDistinct)
    invariant.appendFrame.recognizer.workspaceLength
    invariant.appendFrame.recognizer.workspaceEncoded
    invariant.appendFrame.positionBound
  cases chartShape : workspace.chart position with
  | nil =>
      have conditionFalse : Lanius.FunctionalView.Term.evaluate
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          world environment positionActivityCondition =
          .ok (.boolean false, world) := by
        simpa [world, environment, chartHeadValue, chartShape, encodeStateId]
          using condition
      exact {
        nextFurthest := furthest
        nextFurthestEq := by simp [chartShape]
        execution := by
          rw [positionActivityCommand]
          exact .ifFalse conditionFalse .skip
      }
  | cons current remaining =>
      have conditionTrue : Lanius.FunctionalView.Term.evaluate
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          world environment positionActivityCondition =
          .ok (.boolean true, world) := by
        simpa [world, environment, chartHeadValue, chartShape, encodeStateId]
          using condition
      have positionResult : Lanius.FunctionalView.Term.evaluate
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          world environment (stateSlot ⟨14, by omega⟩) =
          .ok (.signed .i32 (Int.ofNat position), world) :=
        Lanius.FunctionalView.Term.evaluate_slot (by rfl)
      have assigned : Lanius.FunctionalView.Stateful.Command.Evaluates
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          world environment
          (.sequence
            (.setLocal ⟨13, by omega⟩ (stateSlot ⟨14, by omega⟩)) .skip)
          .next world
          (Lanius.FunctionalView.Stateful.Env.set environment ⟨13, by omega⟩
            (.signed .i32 (Int.ofNat position))) :=
        .sequenceNext (.setLocal positionResult) .skip
      have environmentAfter :
          Lanius.FunctionalView.Stateful.Env.set environment ⟨13, by omega⟩
              (.signed .i32 (Int.ofNat position)) =
            positionEnvironment words tokens workspaceValues grammarCell
              tokensCell workspaceCell workspaceLayout grammar grammarLayout
              workspace.states.length position position := by
        apply Lanius.FunctionalView.Env.eq_ofFn
        rfl
      exact {
        nextFurthest := position
        nextFurthestEq := by simp [chartShape]
        execution := by
          rw [positionActivityCommand]
          apply Lanius.FunctionalView.Stateful.Command.Evaluates.ifTrue
            conditionTrue
          rw [← environmentAfter]
          exact assigned
      }

private theorem RecognizerPositionLoopInvariant.activity_nextFurthest_eq
    (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest) :
    invariant.functional_execute_activity.nextFurthest =
      invariant.execute_activity.nextFurthest := by
  rw [invariant.functional_execute_activity.nextFurthestEq,
    invariant.execute_activity.nextFurthestEq]

/-- Functional execution of the position increment, independent of the
    physical local-cell representation used by structural Core. -/
private theorem positionAdvanceCommand_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat) (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 16) (position : Nat)
    (positionEq : environment ⟨14, by omega⟩ =
      .signed .i32 (Int.ofNat position))
    (incrementBound : position + 1 ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment positionAdvanceCommand .next world
      (Lanius.FunctionalView.Stateful.Env.set environment ⟨14, by omega⟩
        (.signed .i32 (Int.ofNat (position + 1)))) := by
  have oneResult : Lanius.FunctionalView.Term.evaluate
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateLiteral 1) =
      .ok (.signed .i32 1, world) := by
    rfl
  have addition : Int.ofNat position + 1 = Int.ofNat (position + 1) := by
    simp
  have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target (position + 1)
    incrementBound
  have updated : evalAssignValue verifiedParserCore.target .add
      (some (.signed .i32 (Int.ofNat position))) (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (position + 1))) := by
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
      beq_self_eq_true, if_true, evalSignedBinary]
    rw [addition, wrapped]
  have updateResult :
      (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell).evalLocalUpdate .add (environment ⟨14, by omega⟩)
        (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (position + 1))) := by
    rw [positionEq]
    simpa [positionStatefulMachine, stateStatefulMachine,
      Lanius.FunctionalView.Core.Stateful.machineWith] using updated
  rw [positionAdvanceCommand]
  exact .sequenceNext (.updateLocal oneResult updateResult) .skip

/-- Updating the position slot beneath the scoped state cursor produces the
    canonical environment for the next position. -/
private theorem positionEnvironment_push_advance
    (words : List Int) (tokens : List Nat) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (grammarLayout : PackedGrammarLayout) (stateCount furthest position : Nat)
    (candidate : Int) :
    Lanius.FunctionalView.Stateful.Env.set
        ((positionEnvironment words tokens workspaceValues
          grammarCell tokensCell workspaceCell workspaceLayout grammar
          grammarLayout stateCount furthest position).push
          (.signed .i32 candidate))
        ⟨14, by omega⟩ (.signed .i32 (Int.ofNat (position + 1))) =
      ((positionEnvironment words tokens workspaceValues
        grammarCell tokensCell workspaceCell workspaceLayout grammar
        grammarLayout stateCount furthest (position + 1)).push
        (.signed .i32 candidate)) := by
  apply Lanius.FunctionalView.Env.eq_ofFn
  rfl

structure RecognizerPositionStateEntry
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (source : State) (position furthest : Nat)
    (sourceInvariant : RecognizerPositionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell source
      position furthest) where
  chartEntry : RecognizerChartLoopEntry grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell source 23 position 24 sourceInvariant.appendFrame.recognizer
    sourceInvariant.workspaceWithinGrammar sourceInvariant.appendFrame.stateBaseLocal
    sourceInvariant.positionLocal sourceInvariant.appendFrame.positionBound
  cursor :
    (Sigma fun current : Nat => Sigma fun remaining : List Nat =>
      RecognizerStateLoopInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell chartEntry.cursorCell chartEntry.bound
        position current remaining)
    ⊕ RecognizerStateFinishedInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell chartEntry.cursorCell chartEntry.bound
        position
  preservedSeparate : CellSet.Disjoint
    (localBindingFrameFootprint chartEntry.bound
      verifiedParserPositionLoopPreservedBindings)
    (stateLoopMutableCells workspaceCell stateCountCell chartEntry.cursorCell)

/-- Enter the state-chain scope through the common chart-head protocol and
    lift its cursor classification into the full state-loop resource frame. -/
noncomputable def RecognizerPositionLoopInvariant.enter_state_loop
    (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest) :
    RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest invariant := by
  let chartEntry := invariant.appendFrame.recognizer.enter_chart_loop
    invariant.workspaceWithinGrammar invariant.appendFrame.stateBaseLocal
    23 position 24 invariant.positionLocal invariant.appendFrame.positionBound
    (by decide)
  let afterReadAppend := invariant.appendFrame.after_empty_effect
    chartEntry.headRead.effect chartEntry.headRead.invariant.wellFormed
  let boundAppend := afterReadAppend.after_bind_local 24
    (.signed .i32 (chartHeadValue workspace position))
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide) (by decide) (by decide)
  have boundAppend' : RecognizerAppendFrame grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell chartEntry.bound position := by
    simpa [chartEntry.boundEq] using boundAppend
  have preserveBoundCellId (id : VarId) (different : 24 ≠ id) :
      chartEntry.bound.cellId? id = runtime.cellId? id := by
    rw [chartEntry.boundEq,
      bindLocal_preserves_other_cellId _ 24 id _ different]
    unfold State.cellId?
    rw [chartEntry.headRead.effect.locals]
  have preserveBoundLocal (id : VarId) (different : 24 ≠ id)
      (value : Value) (found : runtime.local? id = some value) :
      chartEntry.bound.local? id = some value := by
    have afterRead := chartEntry.headRead.effect.empty_preserves_local
      invariant.appendFrame.recognizer.wellFormed found
    rw [chartEntry.boundEq]
    exact (bindLocal_preserves_other_local
      chartEntry.headRead.invariant.wellFormed different).trans afterRead
  have cursorFrameSeparate : CellSet.Disjoint
      (localBindingFrameFootprint chartEntry.bound
        verifiedParserStateLoopPreservedBindings)
      (CellSet.singleton chartEntry.cursorCell) := by
    have notMember :
        ¬ verifiedParserStateLoopPreservedBindings.ContainsCoreId 24 := by
      intro member
      have preserved := (StateLoopPreservedLocal_source_frame 24).mpr member
      have persistent := (StateLoopPreservedLocal_iff 24).mp preserved |>.1
      exact (Nat.not_succ_le_self 23)
        (StateLoopPersistentLocal.le23 24 persistent)
    simpa [chartEntry.boundEq, chartEntry.cursorCellEq] using
      bindLocal_fresh_disjoint_from_frame chartEntry.headRead.after 24
        (.signed .i32 (chartHeadValue workspace position))
        verifiedParserStateLoopPreservedBindings
        chartEntry.headRead.invariant.wellFormed notMember
  have stateFrameSeparate : StateLoopFrameSeparated chartEntry.bound
      workspaceCell stateCountCell chartEntry.cursorCell := by
    unfold StateLoopFrameSeparated
    intro cell framed written
    obtain ⟨id, member, cellId⟩ := framed
    have preserved := (StateLoopPreservedLocal_source_frame id).mpr member
    change cell = workspaceCell ∨ cell = stateCountCell ∨
      cell = chartEntry.cursorCell at written
    rcases written with rfl | rfl | rfl
    · by_cases samePosition : id = 23
      · subst id
        have atSource := invariant.positionOwned.1
        have atBound := (preserveBoundCellId 23 (by decide)).trans atSource
        exact invariant.positionWorkspaceDistinct
          (Option.some.inj (atBound.symm.trans cellId))
      · have outer := preserved.to_position_loop samePosition
        have atSource : runtime.cellId? id = some cell := by
          rw [preserveBoundCellId id (by
            exact Nat.ne_of_gt (Nat.lt_of_le_of_lt
              (StateLoopPersistentLocal.le23 id
                ((StateLoopPreservedLocal_iff id).mp preserved |>.1))
              (by decide : 23 < 24)))] at cellId
          exact cellId
        exact invariant.preservedLocalsSeparate id outer |>.1 atSource
    · by_cases samePosition : id = 23
      · subst id
        have atSource := invariant.positionOwned.1
        have atBound := (preserveBoundCellId 23 (by decide)).trans atSource
        exact invariant.positionStateCountDistinct
          (Option.some.inj (atBound.symm.trans cellId))
      · have outer := preserved.to_position_loop samePosition
        have atSource : runtime.cellId? id = some cell := by
          rw [preserveBoundCellId id (by
            exact Nat.ne_of_gt (Nat.lt_of_le_of_lt
              (StateLoopPersistentLocal.le23 id
                ((StateLoopPreservedLocal_iff id).mp preserved |>.1))
              (by decide : 23 < 24)))] at cellId
          exact cellId
        exact invariant.preservedLocalsSeparate id outer |>.2.1 atSource
    · exact cursorFrameSeparate chartEntry.cursorCell ⟨id, member, cellId⟩
        (by simp [CellSet.singleton])
  have positionCursorSeparate : CellSet.Disjoint
      (localBindingFrameFootprint chartEntry.bound
        verifiedParserPositionLoopPreservedBindings)
      (CellSet.singleton chartEntry.cursorCell) := by
    have notMember :
        ¬ verifiedParserPositionLoopPreservedBindings.ContainsCoreId 24 := by
      intro member
      have preserved := (PositionLoopPreservedLocal_source_frame 24).mpr member
      have impossible : (24 : Nat) ≤ 15 :=
        PositionLoopPreservedLocal.le15 (id := 24) preserved
      omega
    simpa [chartEntry.boundEq, chartEntry.cursorCellEq] using
      bindLocal_fresh_disjoint_from_frame chartEntry.headRead.after 24
        (.signed .i32 (chartHeadValue workspace position))
        verifiedParserPositionLoopPreservedBindings
        chartEntry.headRead.invariant.wellFormed notMember
  have outerFrameSeparate : CellSet.Disjoint
      (localBindingFrameFootprint chartEntry.bound
        verifiedParserPositionLoopPreservedBindings)
      (stateLoopMutableCells workspaceCell stateCountCell
        chartEntry.cursorCell) := by
    intro cell framed written
    obtain ⟨id, member, cellId⟩ := framed
    have preserved := (PositionLoopPreservedLocal_source_frame id).mpr member
    change cell = workspaceCell ∨ cell = stateCountCell ∨
      cell = chartEntry.cursorCell at written
    rcases written with sameWorkspace | sameStateCount | sameCursor
    · have sourceCellId : runtime.cellId? id = some cell := by
        rw [← preserveBoundCellId id (Nat.ne_of_gt
          (Nat.lt_of_le_of_lt preserved.le15 (by decide : 15 < 24)))]
        exact cellId
      exact invariant.preservedSeparate cell
        ⟨id, member, sourceCellId⟩ (Or.inl sameWorkspace)
    · have sourceCellId : runtime.cellId? id = some cell := by
        rw [← preserveBoundCellId id (Nat.ne_of_gt
          (Nat.lt_of_le_of_lt preserved.le15 (by decide : 15 < 24)))]
        exact cellId
      exact invariant.preservedSeparate cell
        ⟨id, member, sourceCellId⟩ (Or.inr (Or.inl sameStateCount))
    · exact positionCursorSeparate cell ⟨id, member, cellId⟩
        (by simpa [CellSet.singleton] using sameCursor)
  have cursorStateCountDistinct : chartEntry.cursorCell ≠ stateCountCell := by
    rw [chartEntry.cursorCellEq]
    exact Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
      chartEntry.headRead.invariant.wellFormed
      (chartEntry.headRead.effect.empty_preserves_assertion
        invariant.appendFrame.recognizer.wellFormed _
        invariant.appendFrame.stateCountOwned).2
  have makeActive (current : Nat) (remaining : List Nat)
      (cursor : RecognizerChartCursorInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell chartEntry.cursorCell chartEntry.bound position 24 current
        remaining) :
      RecognizerStateLoopInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell chartEntry.cursorCell chartEntry.bound
        position current remaining := {
    chartCursor := cursor
    appendFrame := boundAppend'
    kindCountLocal := preserveBoundLocal 11 (by decide) _
      invariant.kindCountLocal
    lhsOffsetsOffsetLocal := preserveBoundLocal 13 (by decide) _
      invariant.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal := preserveBoundLocal 14 (by decide) _
      invariant.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal := preserveBoundLocal 15 (by decide) _
      invariant.lhsProductionsOffsetLocal
    positionLocal := preserveBoundLocal 23 (by decide) _ invariant.positionLocal
    positionAdvanceI32 := invariant.positionAdvanceI32
    persistentSeparate := stateFrameSeparate
    cursorStateCountDistinct := cursorStateCountDistinct
  }
  exact {
    chartEntry := chartEntry
    cursor := match chartEntry.cursor with
      | .inl active => .inl ⟨active.1, active.2.1,
          makeActive active.1 active.2.1 active.2.2⟩
      | .inr finished => .inr {
          chartCursor := finished
          appendFrame := boundAppend'
          kindCountLocal := preserveBoundLocal 11 (by decide) _
            invariant.kindCountLocal
          lhsOffsetsOffsetLocal := preserveBoundLocal 13 (by decide) _
            invariant.lhsOffsetsOffsetLocal
          lhsCountsOffsetLocal := preserveBoundLocal 14 (by decide) _
            invariant.lhsCountsOffsetLocal
          lhsProductionsOffsetLocal := preserveBoundLocal 15 (by decide) _
            invariant.lhsProductionsOffsetLocal
          positionLocal := preserveBoundLocal 23 (by decide) _
            invariant.positionLocal
          positionAdvanceI32 := invariant.positionAdvanceI32
          persistentSeparate := stateFrameSeparate
          cursorStateCountDistinct := cursorStateCountDistinct
        }
    preservedSeparate := outerFrameSeparate
  }

private def RecognizerPositionStateEntry.functionalConfig
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant) :
    RecognizerStateConfig grammarLayout grammar words tokens workspaceLayout
      grammarCell tokensCell workspaceCell stateCountCell
      entry.chartEntry.cursorCell position := {
  workspace := workspace
  workspaceValues := workspaceValues
  runtime := entry.chartEntry.bound
  cursor := entry.cursor
}

private theorem RecognizerPositionStateEntry.functionalConfig_candidate
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant) :
    entry.functionalConfig.candidate = chartHeadValue workspace position := by
  have chartLocal : entry.chartEntry.bound.local? 24 =
      some (.signed .i32 (chartHeadValue workspace position)) := by
    rw [entry.chartEntry.boundEq]
    exact bindLocal_finds_local entry.chartEntry.headRead.after 24
      (.signed .i32 (chartHeadValue workspace position))
      entry.chartEntry.headRead.invariant.wellFormed
  cases cursorEq : entry.cursor with
  | inl active =>
      obtain ⟨current, remaining, invariant⟩ := active
      have currentLocal : entry.chartEntry.bound.local? 24 =
          some (.signed .i32 (Int.ofNat current)) :=
        Assertion.localPointsTo_local 24 entry.chartEntry.cursorCell _
          entry.chartEntry.bound invariant.chartCursor.cursorOwned
      have valueEq : Int.ofNat current = chartHeadValue workspace position := by
        have equal := Option.some.inj (currentLocal.symm.trans chartLocal)
        injection equal
      simpa [RecognizerPositionStateEntry.functionalConfig,
        RecognizerStateConfig.candidate, cursorEq] using valueEq
  | inr finished =>
      have currentLocal : entry.chartEntry.bound.local? 24 =
          some (.signed .i32 (-1)) :=
        Assertion.localPointsTo_local 24 entry.chartEntry.cursorCell _
          entry.chartEntry.bound finished.chartCursor.cursorOwned
      have valueEq : (-1 : Int) = chartHeadValue workspace position := by
        have equal := Option.some.inj (currentLocal.symm.trans chartLocal)
        injection equal
      simpa [RecognizerPositionStateEntry.functionalConfig,
        RecognizerStateConfig.candidate, cursorEq] using valueEq

private theorem RecognizerPositionStateEntry.functional_environment_extends
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant)
    (outerFurthest : Nat) :
    Lanius.FunctionalView.Env.Extends stateIntoPositionEmbedding
      entry.functionalConfig.functionalRuntime.environment
      ((positionEnvironment words tokens workspaceValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar grammarLayout workspace.states.length
        outerFurthest position).push
        (.signed .i32 (chartHeadValue workspace position))) := by
  have candidateEq := entry.functionalConfig_candidate
  simp only [RecognizerPositionStateEntry.functionalConfig] at candidateEq
  simp only [RecognizerPositionStateEntry.functionalConfig,
    RecognizerStateConfig.functionalRuntime,
    Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
  rw [candidateEq]
  exact stateEnvironment_extends_positionEnvironment words tokens
    workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
    grammarLayout workspace.states.length outerFurthest position
    (chartHeadValue workspace position)

/-- Execute the already-verified compact state loop in the exact sixteen-slot
    environment created by the enclosing position scope. -/
private noncomputable def
    RecognizerPositionStateEntry.functional_execute_state_loop
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant)
    (outerFurthest : Nat) :
    Lanius.FunctionalView.Stateful.Command.RenameResult
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      Lanius.FunctionalView.Core.Stateful.actionRenamer
      stateIntoPositionEmbedding entry.functionalConfig.functionalRuntime.world
      ((positionEnvironment words tokens workspaceValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar grammarLayout workspace.states.length
        outerFurthest position).push
        (.signed .i32 (chartHeadValue workspace position)))
      stateLoopCommand entry.functionalConfig.functional_run.completion
      entry.functionalConfig.functional_run.after.world
      entry.functionalConfig.functional_run.after.environment :=
  entry.functionalConfig.evaluates_in_position_environment _
    (entry.functional_environment_extends outerFurthest)

/-- On ordinary state-loop completion, embedded values come from the compact
    loop result and the three nonembedded values come from its frame theorem;
    together they recover the unique canonical enclosing environment. -/
private theorem RecognizerPositionStateEntry.functional_state_after_large_eq
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant)
    (outerFurthest : Nat) (nextWorkspace : LogicalWorkspace)
    (nextValues : List Int)
    (environmentEq : entry.functionalConfig.functional_run.after.environment =
      stateEnvironment words tokens nextValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar.grammar.n_kinds
        grammarLayout.lhsOffsetsOffset grammarLayout.lhsCountsOffset
        grammarLayout.lhsProductionsOffset nextWorkspace.states.length position
        (-1)) :
    (entry.functional_execute_state_loop outerFurthest).afterLarge =
      ((positionEnvironment words tokens nextValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar grammarLayout
        nextWorkspace.states.length outerFurthest position).push
        (.signed .i32 (-1))) := by
  let execution := entry.functional_execute_state_loop outerFurthest
  have leftRelated : Lanius.FunctionalView.Env.Extends
      stateIntoPositionEmbedding
      (stateEnvironment words tokens nextValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar.grammar.n_kinds
        grammarLayout.lhsOffsetsOffset grammarLayout.lhsCountsOffset
        grammarLayout.lhsProductionsOffset nextWorkspace.states.length position
        (-1)) execution.afterLarge := by
    simpa only [environmentEq] using execution.related
  have rightRelated := stateEnvironment_extends_positionEnvironment words tokens
    nextValues grammarCell tokensCell workspaceCell workspaceLayout grammar
    grammarLayout nextWorkspace.states.length outerFurthest position (-1)
  have rightPreserved := positionStateFrame_preserved words tokens
    workspaceValues nextValues grammarCell tokensCell workspaceCell
    workspaceLayout grammar grammarLayout workspace.states.length
    nextWorkspace.states.length outerFurthest position
    (chartHeadValue workspace position) (-1)
  exact Lanius.FunctionalView.Env.eq_of_extends_and_preserves leftRelated
    rightRelated execution.preserved rightPreserved

def positionStateScopeMutableCells
    (workspaceCell stateCountCell positionCell cursorCell : CellId) : CellSet :=
  CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.union (CellSet.singleton positionCell)
        (CellSet.singleton cursorCell)))

def positionStateScopeRetainedCells
    (workspaceCell stateCountCell positionCell : CellId) : CellSet :=
  CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton positionCell))

/-- Closing local 24 hides its fresh cursor cell while retaining exactly the
    workspace, state-count, and position writes of a normal position body. -/
structure RecognizerPositionStateScopeClosure
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (source : State) (position furthest : Nat)
    (sourceInvariant : RecognizerPositionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell source
      position furthest)
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant)
    (innerAfter : State) (completion : Completion) where
  after : State
  execution : Executes verifiedParserCore source
    parserRecognizePositionStateScope completion after
  effect : ModifiesOnly
    (positionStateScopeRetainedCells workspaceCell stateCountCell positionCell)
    source after
  wellFormed : StateWellFormed after
  stateEq : after = restoreLocals entry.chartEntry.headRead.after innerAfter
  cells : after.cells = innerAfter.cells

def RecognizerPositionStateEntry.close_scope
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant)
    (innerAfter : State) (completion : Completion)
    (innerExecution : Executes verifiedParserCore entry.chartEntry.bound
      (.sequence parserRecognizeStateLoop parserRecognizePositionAdvance)
      completion innerAfter)
    (innerEffect : ModifiesOnly
      (positionStateScopeMutableCells workspaceCell stateCountCell positionCell
        entry.chartEntry.cursorCell) entry.chartEntry.bound innerAfter)
    (innerWellFormed : StateWellFormed innerAfter) :
    RecognizerPositionStateScopeClosure grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant entry innerAfter completion := by
  let writes := positionStateScopeMutableCells workspaceCell stateCountCell
    positionCell entry.chartEntry.cursorCell
  let retained := positionStateScopeRetainedCells workspaceCell stateCountCell
    positionCell
  let after := restoreLocals entry.chartEntry.headRead.after innerAfter
  have entered : StoreEffect CellSet.empty entry.chartEntry.headRead.after
      entry.chartEntry.bound := by
    rw [entry.chartEntry.boundEq]
    exact bindLocal_effect entry.chartEntry.headRead.after 24
      (.signed .i32 (chartHeadValue workspace position))
  have scopeEffect : StoreEffect writes entry.chartEntry.headRead.after
      innerAfter :=
    (entered.weaken CellSet.empty_subset).trans_same (by
      simpa [writes] using innerEffect.toStoreEffect)
  have closedEffect : ModifiesOnly writes entry.chartEntry.headRead.after
      after := by
    simpa [after] using scopeEffect.restoreLocals
  have totalEffect : ModifiesOnly writes source after := by
    simpa [writes] using
      (entry.chartEntry.headRead.effect.weaken CellSet.empty_subset).trans_same
        closedEffect
  have retainedEffect : ModifiesOnly retained source after := by
    apply totalEffect.hideFreshWritesExcept
    intro cell written
    change cell = workspaceCell ∨ cell = stateCountCell ∨
      cell = positionCell ∨ cell = entry.chartEntry.cursorCell at written
    rcases written with rfl | rfl | rfl | rfl
    · exact .inl (.inl rfl)
    · exact .inl (.inr (.inl rfl))
    · exact .inl (.inr (.inr rfl))
    · exact .inr (by
        rw [entry.chartEntry.cursorCellEq]
        exact entry.chartEntry.headRead.effect.nextCell)
  have bodyAtBound : Executes verifiedParserCore
      (entry.chartEntry.headRead.after.bindLocal 24
        (.signed .i32 (chartHeadValue workspace position)))
      (.sequence parserRecognizeStateLoop parserRecognizePositionAdvance)
      completion innerAfter := by
    simpa [entry.chartEntry.boundEq] using innerExecution
  have scopedExecution := executesLetLocal (id := 24) (type := parserI32Type)
    entry.chartEntry.headRead.evaluation bodyAtBound
  exact {
    after := after
    execution := by
      rw [extractedParserRecognize_position_state_scope_shape]
      simpa [after] using scopedExecution
    effect := by simpa [retained] using retainedEffect
    wellFormed := scopeEffect.restoreLocals_wellFormed
      entry.chartEntry.headRead.invariant.wellFormed innerWellFormed
    stateEq := rfl
    cells := rfl
  }

/-- Recover the recognizer representation after the temporary state cursor is
    closed on an early-return path. -/
theorem RecognizerPositionStateScopeClosure.restore_recognizer
    (closed : RecognizerPositionStateScopeClosure grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell source
      position furthest sourceInvariant entry innerAfter completion)
    (innerEffect : ModifiesOnly
      (positionStateScopeMutableCells workspaceCell stateCountCell positionCell
        entry.chartEntry.cursorCell) entry.chartEntry.bound innerAfter)
    (inner : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextValues grammarCell tokensCell
      workspaceCell innerAfter) :
    RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
      nextWorkspace nextValues grammarCell tokensCell workspaceCell
      closed.after := by
  have entered : StoreEffect CellSet.empty entry.chartEntry.headRead.after
      entry.chartEntry.bound := by
    rw [entry.chartEntry.boundEq]
    exact bindLocal_effect entry.chartEntry.headRead.after 24
      (.signed .i32 (chartHeadValue beforeWorkspace position))
  have parameterCellId : ∀ id,
      id ∈ verifiedParserRecognizerParameterIds →
      entry.chartEntry.bound.cellId? id =
        entry.chartEntry.headRead.after.cellId? id := by
    intro id member
    rw [entry.chartEntry.boundEq]
    apply bindLocal_preserves_other_cellId
    exact Nat.ne_of_gt (Nat.lt_of_le_of_lt
      ((mem_verifiedParserRecognizerParameterIds_iff id).mp member)
      (by decide : 5 < 24))
  rw [closed.stateEq]
  exact RecognizerInvariant.restore_temporary
    entry.chartEntry.headRead.after entry.chartEntry.bound innerAfter
    entry.chartEntry.headRead.invariant.wellFormed entered innerEffect
    parameterCellId inner

/-- Uniform execution of the state-chain loop after the chart-head entry has
    classified the chart.  An empty chart executes the exact false-condition
    loop path; a nonempty chart delegates to the verified well-founded loop. -/
structure RecognizerPositionStateExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (source : State) (position furthest : Nat)
    (sourceInvariant : RecognizerPositionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell source
      position furthest)
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore entry.chartEntry.bound
    parserRecognizeStateLoop completion after
  effect : ModifiesOnly
    (stateLoopMutableCells workspaceCell stateCountCell
      entry.chartEntry.cursorCell) entry.chartEntry.bound after
  outcome : RecognizerStateLoopOutcome grammarLayout grammar words tokens
    workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell entry.chartEntry.cursorCell position after completion

noncomputable def RecognizerPositionStateEntry.execute_state_loop
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant) :
    RecognizerPositionStateExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant entry := by
  let assembled := entry.functionalConfig.functional_run
  exact {
    after := assembled.result.physicalAfter
    completion := Lanius.FunctionalView.Core.Stateful.toCoreCompletion
      assembled.completion
    execution := assembled.result.execution
    effect := assembled.result.effect
    outcome := assembled.result.outcome.physical
  }

theorem RecognizerPositionStateEntry.bound_well_formed
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant) :
    StateWellFormed entry.chartEntry.bound := by
  rw [entry.chartEntry.boundEq]
  exact bindLocal_preserves_well_formed entry.chartEntry.headRead.after 24
    (.signed .i32 (chartHeadValue workspace position))
    entry.chartEntry.headRead.invariant.wellFormed

theorem RecognizerPositionStateEntry.preserved_local_at_bound
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant)
    (id : VarId) (preserved : PositionLoopPreservedLocal id)
    (value : Value) (found : source.local? id = some value) :
    entry.chartEntry.bound.local? id = some value := by
  have afterRead := entry.chartEntry.headRead.effect.empty_preserves_local
    sourceInvariant.appendFrame.recognizer.wellFormed found
  rw [entry.chartEntry.boundEq]
  exact (bindLocal_preserves_other_local
    entry.chartEntry.headRead.invariant.wellFormed
    (Nat.ne_of_gt (Nat.lt_of_le_of_lt preserved.le15
      (by decide : 15 < 24)))).trans afterRead

/-- Every local named by the outer position-loop frame survives the complete
    state-chain execution.  The entry constructor proves the physical
    separation once, so callers need only name the semantic local they retain. -/
theorem RecognizerPositionStateEntry.preserve_local_after_state_effect
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant)
    (effect : ModifiesOnly
      (stateLoopMutableCells workspaceCell stateCountCell
        entry.chartEntry.cursorCell) entry.chartEntry.bound after)
    (id : VarId) (preserved : PositionLoopPreservedLocal id)
    (value : Value) (found : entry.chartEntry.bound.local? id = some value) :
    after.local? id = some value :=
  effect.preserves_local_of_disjoint entry.bound_well_formed
    entry.preservedSeparate
    ((PositionLoopPreservedLocal_source_frame id).mp preserved) found

/-- The two outer-loop scalars framed around the state-chain loop.  Packaging
    this once avoids re-proving their preservation separately for active and
    initially-empty charts. -/
structure RecognizerPositionStateScalarFrame
    (workspaceCell stateCountCell cursorCell positionCell furthestCell : CellId)
    (runtime : State) (position furthest : Nat) : Prop where
  positionOwned : (Assertion.localPointsTo 23 positionCell
    (some (.signed .i32 (Int.ofNat position)))).holds runtime
  furthestOwned : (Assertion.localPointsTo 22 furthestCell
    (some (.signed .i32 (Int.ofNat furthest)))).holds runtime
  positionDistinct : positionCell ≠ workspaceCell ∧
    positionCell ≠ stateCountCell ∧ positionCell ≠ cursorCell
  furthestDistinct : furthestCell ≠ workspaceCell ∧
    furthestCell ≠ stateCountCell ∧ furthestCell ≠ cursorCell
  positionPreservedSeparate : CellSet.Disjoint
    (localBindingFrameFootprint runtime
      verifiedParserPositionLoopPreservedBindings)
    (CellSet.singleton positionCell)
  furthestPreservedSeparate : CellSet.Disjoint
    (localBindingFrameFootprint runtime
      verifiedParserPositionLoopPreservedBindings)
    (CellSet.singleton furthestCell)

theorem RecognizerPositionStateEntry.scalar_frame
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant) :
    RecognizerPositionStateScalarFrame workspaceCell stateCountCell
      entry.chartEntry.cursorCell positionCell furthestCell
      entry.chartEntry.bound position furthest := by
  have positionAfterRead := entry.chartEntry.headRead.effect
    |>.empty_preserves_assertion
      sourceInvariant.appendFrame.recognizer.wellFormed _
      sourceInvariant.positionOwned
  have furthestAfterRead := entry.chartEntry.headRead.effect
    |>.empty_preserves_assertion
      sourceInvariant.appendFrame.recognizer.wellFormed _
      sourceInvariant.furthestOwned
  have positionOwned : (Assertion.localPointsTo 23 positionCell
      (some (.signed .i32 (Int.ofNat position)))).holds
      entry.chartEntry.bound := by
    rw [entry.chartEntry.boundEq]
    exact bindLocal_preserves_localPointsTo_of_ne
      entry.chartEntry.headRead.after 24 23
      (.signed .i32 (chartHeadValue workspace position)) positionCell _
      entry.chartEntry.headRead.invariant.wellFormed (by decide)
      positionAfterRead
  have furthestOwned : (Assertion.localPointsTo 22 furthestCell
      (some (.signed .i32 (Int.ofNat furthest)))).holds
      entry.chartEntry.bound := by
    rw [entry.chartEntry.boundEq]
    exact bindLocal_preserves_localPointsTo_of_ne
      entry.chartEntry.headRead.after 24 22
      (.signed .i32 (chartHeadValue workspace position)) furthestCell _
      entry.chartEntry.headRead.invariant.wellFormed (by decide)
      furthestAfterRead
  have positionCursorDistinct : positionCell ≠ entry.chartEntry.cursorCell := by
    rw [entry.chartEntry.cursorCellEq]
    exact (Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
      entry.chartEntry.headRead.invariant.wellFormed positionAfterRead.2).symm
  have furthestCursorDistinct : furthestCell ≠ entry.chartEntry.cursorCell := by
    rw [entry.chartEntry.cursorCellEq]
    exact (Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
      entry.chartEntry.headRead.invariant.wellFormed furthestAfterRead.2).symm
  have boundCellId (id : VarId) (different : 24 ≠ id) :
      entry.chartEntry.bound.cellId? id = source.cellId? id := by
    rw [entry.chartEntry.boundEq,
      bindLocal_preserves_other_cellId _ 24 id _ different]
    unfold State.cellId?
    rw [entry.chartEntry.headRead.effect.locals]
  have preservedSeparate (scalarCell : CellId)
      (writtenBranch :
        positionLoopMutableCells workspaceCell stateCountCell positionCell
          furthestCell scalarCell) :
      CellSet.Disjoint
        (localBindingFrameFootprint entry.chartEntry.bound
          verifiedParserPositionLoopPreservedBindings)
        (CellSet.singleton scalarCell) := by
    intro cell framed written
    change cell = scalarCell at written
    subst cell
    obtain ⟨id, member, cellId⟩ := framed
    have preserved := (PositionLoopPreservedLocal_source_frame id).mpr member
    have different : 24 ≠ id := Nat.ne_of_gt
      (Nat.lt_of_le_of_lt preserved.le15 (by decide : 15 < 24))
    have sourceCellId : source.cellId? id = some scalarCell := by
      rw [← boundCellId id different]
      exact cellId
    exact sourceInvariant.preservedSeparate scalarCell
      ⟨id, member, sourceCellId⟩
      writtenBranch
  exact {
    positionOwned := positionOwned
    furthestOwned := furthestOwned
    positionDistinct := ⟨sourceInvariant.positionWorkspaceDistinct,
      sourceInvariant.positionStateCountDistinct, positionCursorDistinct⟩
    furthestDistinct := ⟨sourceInvariant.furthestWorkspaceDistinct,
      sourceInvariant.furthestStateCountDistinct, furthestCursorDistinct⟩
    positionPreservedSeparate := preservedSeparate positionCell
      (by exact Or.inr (Or.inr (Or.inl rfl)))
    furthestPreservedSeparate := preservedSeparate furthestCell
      (by exact Or.inr (Or.inr (Or.inr rfl)))
  }

theorem RecognizerPositionStateScalarFrame.after_state_effect
    (frame : RecognizerPositionStateScalarFrame workspaceCell stateCountCell
      cursorCell positionCell furthestCell before position furthest)
    (beforeWellFormed : StateWellFormed before)
    (effect : ModifiesOnly
      (stateLoopMutableCells workspaceCell stateCountCell cursorCell)
      before after) :
    RecognizerPositionStateScalarFrame workspaceCell stateCountCell cursorCell
      positionCell furthestCell after position furthest := {
  positionOwned := effect.preserves_localPointsTo beforeWellFormed
    frame.positionOwned (by
      simp only [stateLoopMutableCells, CellSet.union, CellSet.singleton,
        not_or]
      exact ⟨frame.positionDistinct.1, frame.positionDistinct.2.1,
        frame.positionDistinct.2.2⟩)
  furthestOwned := effect.preserves_localPointsTo beforeWellFormed
    frame.furthestOwned (by
      simp only [stateLoopMutableCells, CellSet.union, CellSet.singleton,
        not_or]
      exact ⟨frame.furthestDistinct.1, frame.furthestDistinct.2.1,
        frame.furthestDistinct.2.2⟩)
  positionDistinct := frame.positionDistinct
  furthestDistinct := frame.furthestDistinct
  positionPreservedSeparate := by
    rw [effect.localBindingFrameFootprint_eq
      verifiedParserPositionLoopPreservedBindings]
    exact frame.positionPreservedSeparate
  furthestPreservedSeparate := by
    rw [effect.localBindingFrameFootprint_eq
      verifiedParserPositionLoopPreservedBindings]
    exact frame.furthestPreservedSeparate
}

theorem RecognizerPositionStateScalarFrame.after_position_effect
    (frame : RecognizerPositionStateScalarFrame workspaceCell stateCountCell
      cursorCell positionCell furthestCell before position furthest)
    (beforeWellFormed : StateWellFormed before)
    (effect : ModifiesOnly (CellSet.singleton positionCell) before after)
    (afterPositionOwned : (Assertion.localPointsTo 23 positionCell
      (some (.signed .i32 (Int.ofNat nextPosition)))).holds after)
    (positionFurthestDistinct : positionCell ≠ furthestCell) :
    RecognizerPositionStateScalarFrame workspaceCell stateCountCell cursorCell
      positionCell furthestCell after nextPosition furthest := {
  positionOwned := afterPositionOwned
  furthestOwned := effect.preserves_localPointsTo beforeWellFormed
    frame.furthestOwned (by
      simpa [CellSet.singleton] using positionFurthestDistinct.symm)
  positionDistinct := frame.positionDistinct
  furthestDistinct := frame.furthestDistinct
  positionPreservedSeparate := by
    rw [effect.localBindingFrameFootprint_eq
      verifiedParserPositionLoopPreservedBindings]
    exact frame.positionPreservedSeparate
  furthestPreservedSeparate := by
    rw [effect.localBindingFrameFootprint_eq
      verifiedParserPositionLoopPreservedBindings]
    exact frame.furthestPreservedSeparate
}

/-- A position-loop framed local survives the position increment.  This is
    the scalar counterpart of `preserve_local_after_state_effect`; together
    they compose the two effects in a normal position iteration. -/
theorem RecognizerPositionStateScalarFrame.preserve_local_after_position_effect
    (frame : RecognizerPositionStateScalarFrame workspaceCell stateCountCell
      cursorCell positionCell furthestCell before position furthest)
    (beforeWellFormed : StateWellFormed before)
    (effect : ModifiesOnly (CellSet.singleton positionCell) before after)
    (id : VarId) (preserved : PositionLoopPreservedLocal id)
    (value : Value) (found : before.local? id = some value) :
    after.local? id = some value :=
  effect.preserves_local_of_disjoint beforeWellFormed
    frame.positionPreservedSeparate
    ((PositionLoopPreservedLocal_source_frame id).mp preserved) found

/-- Normal inner execution for one position: the state chain finishes, then
    local 23 advances exactly once.  The temporary cursor remains in scope;
    `close_scope` is the sole operation that removes it. -/
structure RecognizerPositionStateAdvance
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (beforeWorkspace nextWorkspace : LogicalWorkspace)
    (beforeValues nextValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (source : State) (position furthest : Nat)
    (sourceInvariant : RecognizerPositionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace beforeValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell source
      position furthest)
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant)
    (stateAfter : State)
    (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
      nextWorkspace)
    (finished : RecognizerStateFinishedInvariant grammarLayout grammar words
      tokens workspaceLayout nextWorkspace nextValues grammarCell tokensCell
      workspaceCell stateCountCell entry.chartEntry.cursorCell stateAfter
      position) where
  after : State
  execution : Executes verifiedParserCore entry.chartEntry.bound
    (.sequence parserRecognizeStateLoop parserRecognizePositionAdvance)
    .next after
  effect : ModifiesOnly
    (positionStateScopeMutableCells workspaceCell stateCountCell positionCell
      entry.chartEntry.cursorCell) entry.chartEntry.bound after
  wellFormed : StateWellFormed after
  appendFrame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout nextWorkspace nextValues grammarCell tokensCell
    workspaceCell stateCountCell after position
  scalars : RecognizerPositionStateScalarFrame workspaceCell stateCountCell
    entry.chartEntry.cursorCell positionCell furthestCell after (position + 1)
    furthest
  finalPositionLocal : after.local? 6 = some
    (.signed .i32 (Int.ofNat (finalPosition workspaceLayout.tokenCount)))
  kindCountLocal : after.local? 11 = some
    (.signed .i32 (Int.ofNat grammar.grammar.n_kinds))
  startNonterminalLocal : after.local? 12 = some
    (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal))
  lhsOffsetsOffsetLocal : after.local? 13 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset))
  lhsCountsOffsetLocal : after.local? 14 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset))
  lhsProductionsOffsetLocal : after.local? 15 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset))

noncomputable def RecognizerPositionStateEntry.advance_position
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant)
    (stateAfter : State)
    (stateExecution : Executes verifiedParserCore entry.chartEntry.bound
      parserRecognizeStateLoop .next stateAfter)
    (stateEffect : ModifiesOnly
      (stateLoopMutableCells workspaceCell stateCountCell
        entry.chartEntry.cursorCell) entry.chartEntry.bound stateAfter)
    (nextWorkspace : LogicalWorkspace) (nextValues : List Int)
    (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
      nextWorkspace)
    (finished : RecognizerStateFinishedInvariant grammarLayout grammar words
      tokens workspaceLayout nextWorkspace nextValues grammarCell tokensCell
      workspaceCell stateCountCell entry.chartEntry.cursorCell stateAfter
      position) :
    RecognizerPositionStateAdvance grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace nextWorkspace beforeValues nextValues
      grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell source position furthest sourceInvariant entry stateAfter
      growth finished := by
  let stateScalars := entry.scalar_frame.after_state_effect
    entry.bound_well_formed stateEffect
  let incrementExists := executesIncrementOwnedI32Local verifiedParserCore
    stateAfter 23 positionCell position finished.appendFrame.recognizer.wellFormed
    stateScalars.positionOwned (by
      have bounded := sourceInvariant.positionAdvanceI32
      omega)
  let after := Classical.choose incrementExists
  have incrementFacts := Classical.choose_spec incrementExists
  have parameterFrameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint stateAfter
        verifiedParserRecognizerParameterFrame)
      (CellSet.singleton positionCell) :=
    CellSet.Disjoint.mono_left
      (localBindingFrameFootprint_mono (fun id member =>
        (PositionLoopPreservedLocal_source_frame id).mp (Or.inl member)))
      stateScalars.positionPreservedSeparate
  let recognizer := finished.appendFrame.recognizer
    |>.after_disjoint_scalar_effect positionCell incrementFacts.2.2.2
      incrementFacts.2.1 sourceInvariant.positionGrammarDistinct.symm
      sourceInvariant.positionTokensDistinct.symm
      sourceInvariant.positionWorkspaceDistinct.symm parameterFrameDisjoint
  have stateBaseDistinct : stateAfter.cellId? 8 ≠ some positionCell :=
    stateScalars.positionPreservedSeparate.localCell_ne_of_singleton
      ((PositionLoopPreservedLocal_source_frame 8).mp (by
        simp [PositionLoopPreservedLocal]))
  have stateCapacityDistinct : stateAfter.cellId? 9 ≠ some positionCell :=
    stateScalars.positionPreservedSeparate.localCell_ne_of_singleton
      ((PositionLoopPreservedLocal_source_frame 9).mp (by
        simp [PositionLoopPreservedLocal]))
  let appendFrame := finished.appendFrame.after_scalar_effect positionCell
    incrementFacts.2.2.2 recognizer stateBaseDistinct stateCapacityDistinct
    stateScalars.positionDistinct.2.1.symm
  have finalAtBound := entry.preserved_local_at_bound 6 (by
    simp [PositionLoopPreservedLocal]) _ sourceInvariant.finalPositionLocal
  have kindAtBound := entry.preserved_local_at_bound 11 (by
    simp [PositionLoopPreservedLocal]) _ sourceInvariant.kindCountLocal
  have startAtBound := entry.preserved_local_at_bound 12 (by
    simp [PositionLoopPreservedLocal]) _ sourceInvariant.startNonterminalLocal
  have lhsOffsetsAtBound := entry.preserved_local_at_bound 13 (by
    simp [PositionLoopPreservedLocal]) _ sourceInvariant.lhsOffsetsOffsetLocal
  have lhsCountsAtBound := entry.preserved_local_at_bound 14 (by
    simp [PositionLoopPreservedLocal]) _ sourceInvariant.lhsCountsOffsetLocal
  have lhsProductionsAtBound := entry.preserved_local_at_bound 15 (by
    simp [PositionLoopPreservedLocal]) _
    sourceInvariant.lhsProductionsOffsetLocal
  have finalAtState := entry.preserve_local_after_state_effect stateEffect 6
    (by simp [PositionLoopPreservedLocal]) _ finalAtBound
  have kindAtState := entry.preserve_local_after_state_effect stateEffect 11
    (by simp [PositionLoopPreservedLocal]) _ kindAtBound
  have startAtState := entry.preserve_local_after_state_effect stateEffect 12
    (by simp [PositionLoopPreservedLocal]) _ startAtBound
  have lhsOffsetsAtState := entry.preserve_local_after_state_effect stateEffect
    13 (by simp [PositionLoopPreservedLocal]) _ lhsOffsetsAtBound
  have lhsCountsAtState := entry.preserve_local_after_state_effect stateEffect
    14 (by simp [PositionLoopPreservedLocal]) _ lhsCountsAtBound
  have lhsProductionsAtState := entry.preserve_local_after_state_effect
    stateEffect 15 (by simp [PositionLoopPreservedLocal]) _
    lhsProductionsAtBound
  have combinedEffect := stateEffect.trans incrementFacts.2.2.2
  have writesEqual : CellSet.union
      (stateLoopMutableCells workspaceCell stateCountCell
        entry.chartEntry.cursorCell)
      (CellSet.singleton positionCell) =
      positionStateScopeMutableCells workspaceCell stateCountCell positionCell
        entry.chartEntry.cursorCell := by
    funext cell
    simp [stateLoopMutableCells, positionStateScopeMutableCells,
      CellSet.union, CellSet.singleton]
    constructor
    · rintro ((rfl | rfl | rfl) | rfl)
      · exact Or.inl rfl
      · exact Or.inr (Or.inl rfl)
      · exact Or.inr (Or.inr (Or.inr rfl))
      · exact Or.inr (Or.inr (Or.inl rfl))
    · rintro (rfl | rfl | rfl | rfl)
      · exact Or.inl (Or.inl rfl)
      · exact Or.inl (Or.inr (Or.inl rfl))
      · exact Or.inr rfl
      · exact Or.inl (Or.inr (Or.inr rfl))
  rw [writesEqual] at combinedEffect
  exact {
    after := after
    execution := executesSequence stateExecution incrementFacts.1
    effect := combinedEffect
    wellFormed := incrementFacts.2.1
    appendFrame := appendFrame
    scalars := stateScalars.after_position_effect
      finished.appendFrame.recognizer.wellFormed incrementFacts.2.2.2
      incrementFacts.2.2.1 sourceInvariant.positionFurthestDistinct
    finalPositionLocal :=
      stateScalars.preserve_local_after_position_effect
        finished.appendFrame.recognizer.wellFormed incrementFacts.2.2.2 6
        (by simp [PositionLoopPreservedLocal]) _ finalAtState
    kindCountLocal := stateScalars.preserve_local_after_position_effect
      finished.appendFrame.recognizer.wellFormed incrementFacts.2.2.2 11
      (by simp [PositionLoopPreservedLocal]) _ kindAtState
    startNonterminalLocal := stateScalars.preserve_local_after_position_effect
      finished.appendFrame.recognizer.wellFormed incrementFacts.2.2.2 12
      (by simp [PositionLoopPreservedLocal]) _ startAtState
    lhsOffsetsOffsetLocal :=
      stateScalars.preserve_local_after_position_effect
        finished.appendFrame.recognizer.wellFormed incrementFacts.2.2.2 13
        (by simp [PositionLoopPreservedLocal]) _ lhsOffsetsAtState
    lhsCountsOffsetLocal :=
      stateScalars.preserve_local_after_position_effect
        finished.appendFrame.recognizer.wellFormed incrementFacts.2.2.2 14
        (by simp [PositionLoopPreservedLocal]) _ lhsCountsAtState
    lhsProductionsOffsetLocal :=
      stateScalars.preserve_local_after_position_effect
        finished.appendFrame.recognizer.wellFormed incrementFacts.2.2.2 15
        (by simp [PositionLoopPreservedLocal]) _ lhsProductionsAtState
  }

/-- Resource frame immediately after one normal position iteration.  The
    append frame remains indexed by the position just processed; callers may
    re-index it to `position + 1` only when that position is still in range. -/
structure RecognizerPositionPostFrame
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (runtime : State) (position furthest : Nat) : Prop where
  appendFrame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime position
  workspaceWithinGrammar : WorkspaceWithinGrammar grammar workspace
  finalPositionLocal : runtime.local? 6 = some
    (.signed .i32 (Int.ofNat (finalPosition workspaceLayout.tokenCount)))
  kindCountLocal : runtime.local? 11 = some
    (.signed .i32 (Int.ofNat grammar.grammar.n_kinds))
  startNonterminalLocal : runtime.local? 12 = some
    (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal))
  lhsOffsetsOffsetLocal : runtime.local? 13 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset))
  lhsCountsOffsetLocal : runtime.local? 14 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset))
  lhsProductionsOffsetLocal : runtime.local? 15 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset))
  positionOwned : (Assertion.localPointsTo 23 positionCell
    (some (.signed .i32 (Int.ofNat (position + 1))))).holds runtime
  furthestOwned : (Assertion.localPointsTo 22 furthestCell
    (some (.signed .i32 (Int.ofNat furthest)))).holds runtime
  furthestBound : furthest ≤ position
  positionFurthestDistinct : positionCell ≠ furthestCell
  positionStateCountDistinct : positionCell ≠ stateCountCell
  furthestStateCountDistinct : furthestCell ≠ stateCountCell
  positionGrammarDistinct : positionCell ≠ grammarCell
  positionTokensDistinct : positionCell ≠ tokensCell
  furthestGrammarDistinct : furthestCell ≠ grammarCell
  furthestTokensDistinct : furthestCell ≠ tokensCell
  positionWorkspaceDistinct : positionCell ≠ workspaceCell
  furthestWorkspaceDistinct : furthestCell ≠ workspaceCell
  preservedSeparate : PositionLoopFrameSeparated runtime workspaceCell
    stateCountCell positionCell furthestCell

theorem RecognizerPositionPostFrame.next_invariant
    (frame : RecognizerPositionPostFrame grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest)
    (nextBound : position + 1 ≤
      finalPosition workspaceLayout.tokenCount) :
    RecognizerPositionLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime
      (position + 1) furthest := {
  appendFrame := frame.appendFrame.at_position (position + 1) nextBound
  workspaceWithinGrammar := frame.workspaceWithinGrammar
  finalPositionLocal := frame.finalPositionLocal
  kindCountLocal := frame.kindCountLocal
  startNonterminalLocal := frame.startNonterminalLocal
  lhsOffsetsOffsetLocal := frame.lhsOffsetsOffsetLocal
  lhsCountsOffsetLocal := frame.lhsCountsOffsetLocal
  lhsProductionsOffsetLocal := frame.lhsProductionsOffsetLocal
  positionOwned := frame.positionOwned
  furthestOwned := frame.furthestOwned
  furthestBound := Nat.le_trans frame.furthestBound (Nat.le_succ position)
  positionFurthestDistinct := frame.positionFurthestDistinct
  positionStateCountDistinct := frame.positionStateCountDistinct
  furthestStateCountDistinct := frame.furthestStateCountDistinct
  positionGrammarDistinct := frame.positionGrammarDistinct
  positionTokensDistinct := frame.positionTokensDistinct
  furthestGrammarDistinct := frame.furthestGrammarDistinct
  furthestTokensDistinct := frame.furthestTokensDistinct
  positionWorkspaceDistinct := frame.positionWorkspaceDistinct
  furthestWorkspaceDistinct := frame.furthestWorkspaceDistinct
  preservedSeparate := frame.preservedSeparate
}

/-- Close the state cursor after a normal advance and recover the exact outer
    position-loop frame.  All locals are restored from the caller; all cell
    contents come from the verified inner execution. -/
structure RecognizerPositionClosedAdvance
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (beforeWorkspace nextWorkspace : LogicalWorkspace)
    (beforeValues nextValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (source : State) (position furthest : Nat)
    (sourceInvariant : RecognizerPositionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace beforeValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell source
      position furthest)
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant)
    (stateAfter : State)
    (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
      nextWorkspace)
    (finished : RecognizerStateFinishedInvariant grammarLayout grammar words
      tokens workspaceLayout nextWorkspace nextValues grammarCell tokensCell
      workspaceCell stateCountCell entry.chartEntry.cursorCell stateAfter
      position)
    (advance : RecognizerPositionStateAdvance grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace nextWorkspace beforeValues nextValues
      grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell source position furthest sourceInvariant entry stateAfter
      growth finished) where
  closed : RecognizerPositionStateScopeClosure grammarLayout grammar words
    tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
    workspaceCell stateCountCell positionCell furthestCell source position
    furthest sourceInvariant entry advance.after .next
  frame : RecognizerPositionPostFrame grammarLayout grammar words tokens
    workspaceLayout nextWorkspace nextValues grammarCell tokensCell
    workspaceCell stateCountCell positionCell furthestCell closed.after position
    furthest

noncomputable def RecognizerPositionStateAdvance.close
    (advance : RecognizerPositionStateAdvance grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace nextWorkspace beforeValues
      nextValues grammarCell tokensCell workspaceCell stateCountCell
      positionCell furthestCell source position furthest sourceInvariant entry
      stateAfter growth finished) :
    RecognizerPositionClosedAdvance grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace nextWorkspace beforeValues nextValues
      grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell source position furthest sourceInvariant entry stateAfter
      growth finished advance := by
  let closed := entry.close_scope advance.after .next advance.execution
    advance.effect advance.wellFormed
  have entered : StoreEffect CellSet.empty entry.chartEntry.headRead.after
      entry.chartEntry.bound := by
    rw [entry.chartEntry.boundEq]
    exact bindLocal_effect entry.chartEntry.headRead.after 24
      (.signed .i32 (chartHeadValue beforeWorkspace position))
  have boundCellId (id : VarId) (different : 24 ≠ id) :
      entry.chartEntry.bound.cellId? id =
        entry.chartEntry.headRead.after.cellId? id := by
    rw [entry.chartEntry.boundEq,
      bindLocal_preserves_other_cellId _ 24 id _ different]
  have parameterCellId : ∀ id,
      id ∈ verifiedParserRecognizerParameterIds →
      entry.chartEntry.bound.cellId? id =
        entry.chartEntry.headRead.after.cellId? id := by
    intro id member
    exact boundCellId id (Nat.ne_of_gt (Nat.lt_of_le_of_lt
      ((mem_verifiedParserRecognizerParameterIds_iff id).mp member)
      (by decide : 5 < 24)))
  have recognizerAtRestore : RecognizerInvariant grammarLayout grammar words
      tokens workspaceLayout nextWorkspace nextValues grammarCell tokensCell
      workspaceCell
      (restoreLocals entry.chartEntry.headRead.after advance.after) :=
    RecognizerInvariant.restore_temporary entry.chartEntry.headRead.after
      entry.chartEntry.bound advance.after
      entry.chartEntry.headRead.invariant.wellFormed entered advance.effect
      parameterCellId advance.appendFrame.recognizer
  have recognizer : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextValues grammarCell tokensCell
      workspaceCell closed.after := by
    rw [closed.stateEq]
    exact recognizerAtRestore
  have restoreOwned (id : VarId) (cell : CellId) (value : Option Value)
      (different : 24 ≠ id)
      (owned : (Assertion.localPointsTo id cell value).holds advance.after) :
      (Assertion.localPointsTo id cell value).holds closed.after := by
    rw [closed.stateEq]
    exact localPointsTo_restore_temporary
      entry.chartEntry.headRead.after entry.chartEntry.bound advance.after id
      cell value advance.effect (boundCellId id different) owned
  have stateCountOwned := restoreOwned 18 stateCountCell
    (some (.signed .i32 (Int.ofNat nextWorkspace.states.length))) (by decide)
    advance.appendFrame.stateCountOwned
  have positionOwned := restoreOwned 23 positionCell
    (some (.signed .i32 (Int.ofNat (position + 1)))) (by decide)
    advance.scalars.positionOwned
  have furthestOwned := restoreOwned 22 furthestCell
    (some (.signed .i32 (Int.ofNat furthest))) (by decide)
    advance.scalars.furthestOwned
  have restoredLocal (id : VarId) (different : 24 ≠ id) (value : Value)
      (found : advance.after.local? id = some value) :
      closed.after.local? id = some value := by
    rw [closed.stateEq]
    have completedCellId : advance.after.cellId? id =
        entry.chartEntry.bound.cellId? id := by
      unfold State.cellId?
      rw [advance.effect.locals]
    have restoredCellId :
        (restoreLocals entry.chartEntry.headRead.after advance.after).cellId? id =
          advance.after.cellId? id := by
      change entry.chartEntry.headRead.after.cellId? id =
        advance.after.cellId? id
      rw [completedCellId, boundCellId id different]
    unfold State.local?
    rw [restoredCellId]
    exact found
  have appendFrame : RecognizerAppendFrame grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextValues grammarCell tokensCell
      workspaceCell stateCountCell closed.after position := {
    recognizer := recognizer
    positionBound := sourceInvariant.appendFrame.positionBound
    stateBaseLocal := restoredLocal 8 (by decide) _
      advance.appendFrame.stateBaseLocal
    stateCapacityLocal := restoredLocal 9 (by decide) _
      advance.appendFrame.stateCapacityLocal
    stateCountLocal := Assertion.localPointsTo_local 18 stateCountCell _
      closed.after stateCountOwned
    stateCountOwned := stateCountOwned
    stateCountBackingDistinct := sourceInvariant.appendFrame
      |>.stateCountBackingDistinct
    stateCountParameterSeparate := by
      unfold RecognizerParameterFrameSeparated
      rw [closed.effect.localBindingFrameFootprint_eq
        verifiedParserRecognizerParameterFrame]
      exact sourceInvariant.appendFrame.stateCountParameterSeparate
  }
  exact ⟨closed, {
    appendFrame := appendFrame
    workspaceWithinGrammar := finished.chartCursor.workspaceWithinGrammar
    finalPositionLocal := restoredLocal 6 (by decide) _
      advance.finalPositionLocal
    kindCountLocal := restoredLocal 11 (by decide) _
      advance.kindCountLocal
    startNonterminalLocal := restoredLocal 12 (by decide) _
      advance.startNonterminalLocal
    lhsOffsetsOffsetLocal := restoredLocal 13 (by decide) _
      advance.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal := restoredLocal 14 (by decide) _
      advance.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal := restoredLocal 15 (by decide) _
      advance.lhsProductionsOffsetLocal
    positionOwned := positionOwned
    furthestOwned := furthestOwned
    furthestBound := sourceInvariant.furthestBound
    positionFurthestDistinct := sourceInvariant.positionFurthestDistinct
    positionStateCountDistinct := sourceInvariant.positionStateCountDistinct
    furthestStateCountDistinct := sourceInvariant.furthestStateCountDistinct
    positionGrammarDistinct := sourceInvariant.positionGrammarDistinct
    positionTokensDistinct := sourceInvariant.positionTokensDistinct
    furthestGrammarDistinct := sourceInvariant.furthestGrammarDistinct
    furthestTokensDistinct := sourceInvariant.furthestTokensDistinct
    positionWorkspaceDistinct := sourceInvariant.positionWorkspaceDistinct
    furthestWorkspaceDistinct := sourceInvariant.furthestWorkspaceDistinct
    preservedSeparate := by
      unfold PositionLoopFrameSeparated
      rw [closed.effect.localBindingFrameFootprint_eq
        verifiedParserPositionLoopPreservedBindings]
      exact sourceInvariant.preservedSeparate
  }⟩

abbrev RecognizerPositionStateScopeOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (position furthest : Nat) : State → Completion → Prop :=
  WorkspaceLoopOutcome workspaceLayout.capacity beforeWorkspace
    (parserCapacityCompletion position)
    (fun nextWorkspace nextValues after =>
      RecognizerPositionPostFrame grammarLayout grammar words tokens
        workspaceLayout nextWorkspace nextValues grammarCell tokensCell
        workspaceCell stateCountCell positionCell furthestCell after position
        furthest)
    (fun workspace workspaceValues after =>
      RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
        workspace workspaceValues grammarCell tokensCell workspaceCell after)

/-- Exact execution of the scoped state-chain portion of one position body.
    Capacity exhaustion skips the increment and returns through the same
    lexical-scope closer as normal completion. -/
structure RecognizerPositionStateScopeExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (source : State) (position furthest : Nat)
    (sourceInvariant : RecognizerPositionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell source
      position furthest)
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore source
    parserRecognizePositionStateScope completion after
  effect : ModifiesOnly
    (positionStateScopeRetainedCells workspaceCell stateCountCell positionCell)
    source after
  outcome : RecognizerPositionStateScopeOutcome grammarLayout grammar words
    tokens workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell positionCell furthestCell position furthest after completion

/-- One scoped position-state execution whose FunctionalView control flow and
    physical Core refinement are constructed from the same state-loop run. -/
private inductive RecognizerPositionStateScopeSynchronizedExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (source : State) (position furthest : Nat)
    (sourceInvariant : RecognizerPositionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell source
      position furthest)
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant) : Type where
  | completed (nextWorkspace : LogicalWorkspace) (nextValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
        nextWorkspace)
      (frame : RecognizerPositionPostFrame grammarLayout grammar words tokens
        workspaceLayout nextWorkspace nextValues grammarCell tokensCell
        workspaceCell stateCountCell positionCell furthestCell physicalAfter
        position furthest)
      (functionalExecution :
        Lanius.FunctionalView.Stateful.Command.Evaluates
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (positionStatefulMachine workspaceLayout grammar words tokens
            grammarCell tokensCell)
          (stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell)
          (positionEnvironment words tokens workspaceValues grammarCell
            tokensCell workspaceCell workspaceLayout grammar grammarLayout
            workspace.states.length furthest position)
          positionStateScopeCommand .next
          (stateWorld words tokens nextValues grammarCell tokensCell
            workspaceCell)
          (positionEnvironment words tokens nextValues grammarCell tokensCell
            workspaceCell workspaceLayout grammar grammarLayout
            nextWorkspace.states.length furthest (position + 1)))
      (physicalExecution : Executes verifiedParserCore source
        parserRecognizePositionStateScope .next physicalAfter)
      (effect : ModifiesOnly
        (positionStateScopeRetainedCells workspaceCell stateCountCell
          positionCell) source physicalAfter) :
      RecognizerPositionStateScopeSynchronizedExecution grammarLayout grammar
        words tokens workspaceLayout workspace workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell positionCell furthestCell source
        position furthest sourceInvariant entry
  | full (nextWorkspace : LogicalWorkspace) (nextValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
        nextWorkspace)
      (invariant : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout nextWorkspace nextValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter)
      (functionalAfterWorld :
        (positionTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell).World)
      (functionalAfterEnvironment : Lanius.FunctionalView.Env 15)
      (functionalExecution :
        Lanius.FunctionalView.Stateful.Command.Evaluates
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (positionStatefulMachine workspaceLayout grammar words tokens
            grammarCell tokensCell)
          (stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell)
          (positionEnvironment words tokens workspaceValues grammarCell
            tokensCell workspaceCell workspaceLayout grammar grammarLayout
            workspace.states.length furthest position)
          positionStateScopeCommand
          (.returned (some (parseResultValue 2 (Int.ofNat stateCount) (-1)
            (Int.ofNat position))))
          functionalAfterWorld functionalAfterEnvironment)
      (physicalExecution : Executes verifiedParserCore source
        parserRecognizePositionStateScope
        (parserCapacityCompletion position stateCount) physicalAfter)
      (effect : ModifiesOnly
        (positionStateScopeRetainedCells workspaceCell stateCountCell
          positionCell) source physicalAfter) :
      RecognizerPositionStateScopeSynchronizedExecution grammarLayout grammar
        words tokens workspaceLayout workspace workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell positionCell furthestCell source
        position furthest sourceInvariant entry

/-- Compose the source-derived chart-head binding, the renamed verified state
    loop, the position increment, and lexical-scope closure in FunctionalView
    while retaining the matching physical execution. -/
private noncomputable def RecognizerPositionStateEntry.execute_scope_synchronized
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant) :
    RecognizerPositionStateScopeSynchronizedExecution grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell source
      position furthest sourceInvariant entry := by
  let baseWorld := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let baseEnvironment := positionEnvironment words tokens workspaceValues
    grammarCell tokensCell workspaceCell workspaceLayout grammar grammarLayout
    workspace.states.length furthest position
  have initializerResult : Lanius.FunctionalView.Term.evaluate
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      baseWorld baseEnvironment
      (stateChartHeadTerm ⟨3, by omega⟩ ⟨14, by omega⟩) =
      .ok (.signed .i32 (chartHeadValue workspace position), baseWorld) :=
    stateChartHeadTerm_evaluates workspaceLayout grammar words tokens
      grammarCell tokensCell workspaceCell baseWorld baseEnvironment
      ⟨3, by omega⟩ ⟨14, by omega⟩ workspace workspaceValues position
      (by rfl) (by rfl)
      (stateWorld_finds_workspace
        sourceInvariant.appendFrame.recognizer.grammarWorkspaceDistinct
        sourceInvariant.appendFrame.recognizer.tokensWorkspaceDistinct)
      sourceInvariant.appendFrame.recognizer.workspaceLength
      sourceInvariant.appendFrame.recognizer.workspaceEncoded
      sourceInvariant.appendFrame.positionBound
  generalize runEq : entry.functionalConfig.functional_run = assembled
  obtain ⟨completion, functionalAfter, trace, result⟩ := assembled
  have sourceCompletionEq :
      entry.functionalConfig.functional_run.completion = completion := by
    simpa using congrArg (fun run => run.completion) runEq
  have sourceAfterEq :
      entry.functionalConfig.functional_run.after = functionalAfter := by
    simpa using congrArg (fun run => run.after) runEq
  let renamed := entry.functional_execute_state_loop furthest
  cases completion with
  | next =>
    cases result.outcome with
    | completed nextWorkspace nextValues stateAfter growth finished worldEq
        environmentEq =>
      have sourceEnvironmentEq :
          entry.functionalConfig.functional_run.after.environment =
            stateEnvironment words tokens nextValues grammarCell tokensCell
              workspaceCell workspaceLayout grammar.grammar.n_kinds
              grammarLayout.lhsOffsetsOffset grammarLayout.lhsCountsOffset
              grammarLayout.lhsProductionsOffset nextWorkspace.states.length
              position (-1) := by
        rw [sourceAfterEq]
        exact environmentEq
      have renamedAfterEq := entry.functional_state_after_large_eq furthest
        nextWorkspace nextValues sourceEnvironmentEq
      have initialWorldEq : entry.functionalConfig.functionalRuntime.world =
          baseWorld := by
        rfl
      have sourceWorldEq :
          entry.functionalConfig.functional_run.after.world =
            stateWorld words tokens nextValues grammarCell tokensCell
              workspaceCell := by
        rw [sourceAfterEq]
        exact worldEq
      have stateFunctional : Lanius.FunctionalView.Stateful.Command.Evaluates
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (positionStatefulMachine workspaceLayout grammar words tokens
            grammarCell tokensCell)
          baseWorld
          (baseEnvironment.push
            (.signed .i32 (chartHeadValue workspace position)))
          positionStateLoopCommand .next
          (stateWorld words tokens nextValues grammarCell tokensCell workspaceCell)
          ((positionEnvironment words tokens nextValues grammarCell tokensCell
            workspaceCell workspaceLayout grammar grammarLayout
            nextWorkspace.states.length furthest position).push
            (.signed .i32 (-1))) := by
        simpa only [renamed, baseEnvironment, initialWorldEq,
          sourceCompletionEq, sourceWorldEq, renamedAfterEq] using
            renamed.evaluated
      have advanceFunctional := positionAdvanceCommand_evaluates workspaceLayout
        grammar words tokens grammarCell tokensCell
        (stateWorld words tokens nextValues grammarCell tokensCell workspaceCell)
        ((positionEnvironment words tokens nextValues grammarCell tokensCell
          workspaceCell workspaceLayout grammar grammarLayout
          nextWorkspace.states.length furthest position).push
          (.signed .i32 (-1))) position (by rfl) (by
            have bounded := sourceInvariant.positionAdvanceI32
            omega)
      have scopedFunctionalRaw :=
        Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
          (type := parserI32Type) initializerResult
          (Lanius.FunctionalView.Stateful.Command.Evaluates.sequenceNext
            stateFunctional advanceFunctional)
      have scopedFunctional :
          Lanius.FunctionalView.Stateful.Command.Evaluates
            (positionTermMachine workspaceLayout grammar words tokens grammarCell
              tokensCell)
            (positionStatefulMachine workspaceLayout grammar words tokens
              grammarCell tokensCell)
            baseWorld baseEnvironment positionStateScopeCommand .next
            (stateWorld words tokens nextValues grammarCell tokensCell
              workspaceCell)
            (positionEnvironment words tokens nextValues grammarCell tokensCell
              workspaceCell workspaceLayout grammar grammarLayout
              nextWorkspace.states.length furthest (position + 1)) := by
        rw [positionStateScopeCommand]
        simpa only [positionEnvironment_push_advance,
          Lanius.FunctionalView.Stateful.Env.pop_push] using scopedFunctionalRaw
      let advance := entry.advance_position result.physicalAfter result.execution
        result.effect nextWorkspace nextValues growth finished
      let closed := advance.close
      exact .completed nextWorkspace nextValues closed.closed.after growth
        closed.frame (by simpa [baseWorld, baseEnvironment] using scopedFunctional)
        closed.closed.execution closed.closed.effect
  | returned value =>
    cases result.outcome with
    | full nextWorkspace nextValues stateAfter growth terminal stateCount
        wellFormed =>
      have initialWorldEq : entry.functionalConfig.functionalRuntime.world =
          baseWorld := by
        rfl
      have sourceWorldEq :
          entry.functionalConfig.functional_run.after.world =
            functionalAfter.world := by
        simpa using congrArg (fun runtime => runtime.world) sourceAfterEq
      have stateFunctional : Lanius.FunctionalView.Stateful.Command.Evaluates
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (positionStatefulMachine workspaceLayout grammar words tokens
            grammarCell tokensCell)
          baseWorld
          (baseEnvironment.push
            (.signed .i32 (chartHeadValue workspace position)))
          positionStateLoopCommand
          (.returned (some (parseResultValue 2 (Int.ofNat stateCount) (-1)
            (Int.ofNat position))))
          functionalAfter.world renamed.afterLarge := by
        simpa only [renamed, baseEnvironment, initialWorldEq,
          sourceCompletionEq, sourceWorldEq] using renamed.evaluated
      have bodyFunctional :=
        Lanius.FunctionalView.Stateful.Command.Evaluates.sequenceStop
          (secondCommand := positionAdvanceCommand) stateFunctional (by simp)
      have scopedFunctional :=
        Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
          (type := parserI32Type) initializerResult bodyFunctional
      have mutableSubset : CellSet.Subset
          (stateLoopMutableCells workspaceCell stateCountCell
            entry.chartEntry.cursorCell)
          (positionStateScopeMutableCells workspaceCell stateCountCell
            positionCell entry.chartEntry.cursorCell) := by
        intro cell written
        change cell = workspaceCell ∨ cell = stateCountCell ∨
          cell = entry.chartEntry.cursorCell at written
        rcases written with rfl | rfl | rfl
        · exact Or.inl rfl
        · exact Or.inr (Or.inl rfl)
        · exact Or.inr (Or.inr (Or.inr rfl))
      have innerEffect := result.effect.weaken mutableSubset
      let closed := entry.close_scope result.physicalAfter
        (parserCapacityCompletion position stateCount)
        (executesSequenceReturned result.execution)
        innerEffect wellFormed
      let restored := closed.restore_recognizer innerEffect terminal
      exact .full nextWorkspace nextValues closed.after growth restored stateCount
        closed.wellFormed functionalAfter.world
        (Lanius.FunctionalView.Stateful.Env.pop renamed.afterLarge)
        (by simpa [baseWorld, baseEnvironment, positionStateScopeCommand] using
          scopedFunctional)
        closed.execution closed.effect
  | breakLoop => cases result.outcome
  | continueLoop => cases result.outcome

private def RecognizerPositionStateScopeSynchronizedExecution.physical
    (execution : RecognizerPositionStateScopeSynchronizedExecution
      grammarLayout grammar words tokens workspaceLayout workspace
      workspaceValues grammarCell tokensCell workspaceCell stateCountCell
      positionCell furthestCell source position furthest sourceInvariant entry) :
    RecognizerPositionStateScopeExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant entry := by
  cases execution with
  | completed nextWorkspace nextValues physicalAfter growth frame _ trace
      effect =>
      exact {
        after := physicalAfter
        completion := .next
        execution := trace
        effect := effect
        outcome := .completed nextWorkspace nextValues physicalAfter growth frame
      }
  | full nextWorkspace nextValues physicalAfter growth invariant stateCount
      wellFormed _ _ _ trace effect =>
      exact {
        after := physicalAfter
        completion := parserCapacityCompletion position stateCount
        execution := trace
        effect := effect
        outcome := .full nextWorkspace nextValues physicalAfter growth invariant
          stateCount wellFormed
      }

noncomputable def RecognizerPositionStateEntry.execute_scope
    (entry : RecognizerPositionStateEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant) :
    RecognizerPositionStateScopeExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source position
      furthest sourceInvariant entry :=
  entry.execute_scope_synchronized.physical

/-! ### Total chart-position loop -/

/-- Typed result of one extracted position-loop body.  Normal completion
    carries the reusable post-position frame; capacity exhaustion carries the
    exact early-return state. -/
inductive RecognizerPositionStepOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (position : Nat) : State → Completion → Type
  | advanced (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (after : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (furthest : Nat)
      (frame : RecognizerPositionPostFrame grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell positionCell furthestCell after position
        furthest) :
      RecognizerPositionStepOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell positionCell furthestCell position after .next
  | full (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (after : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (invariant : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell after)
      (stateCount : Nat) (wellFormed : StateWellFormed after) :
      RecognizerPositionStepOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell positionCell furthestCell position after
        (parserCapacityCompletion position stateCount)

structure RecognizerPositionStepExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (before : State) (position furthest : Nat)
    (beforeInvariant : RecognizerPositionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell before
      position furthest) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before
    parserRecognizePositionLoopBody completion after
  effect : ModifiesOnly
    (positionLoopMutableCells workspaceCell stateCountCell positionCell
      furthestCell) before after
  outcome : RecognizerPositionStepOutcome grammarLayout grammar words tokens
    workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell positionCell furthestCell position after completion

/-- One complete position body with FunctionalView as the control-flow owner
    and structural Core retained as the refinement result. -/
private inductive RecognizerPositionStepSynchronizedExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (before : State) (position furthest : Nat)
    (beforeInvariant : RecognizerPositionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell before
      position furthest) : Type where
  | advanced (nextWorkspace : LogicalWorkspace) (nextValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
        nextWorkspace)
      (nextFurthest : Nat)
      (frame : RecognizerPositionPostFrame grammarLayout grammar words tokens
        workspaceLayout nextWorkspace nextValues grammarCell tokensCell
        workspaceCell stateCountCell positionCell furthestCell physicalAfter
        position nextFurthest)
      (functionalExecution :
        Lanius.FunctionalView.Stateful.Command.Evaluates
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (positionStatefulMachine workspaceLayout grammar words tokens
            grammarCell tokensCell)
          (stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell)
          (positionEnvironment words tokens workspaceValues grammarCell
            tokensCell workspaceCell workspaceLayout grammar grammarLayout
            workspace.states.length furthest position)
          positionBodyCommand .next
          (stateWorld words tokens nextValues grammarCell tokensCell
            workspaceCell)
          (positionEnvironment words tokens nextValues grammarCell tokensCell
            workspaceCell workspaceLayout grammar grammarLayout
            nextWorkspace.states.length nextFurthest (position + 1)))
      (physicalExecution : Executes verifiedParserCore before
        parserRecognizePositionLoopBody .next physicalAfter)
      (effect : ModifiesOnly
        (positionLoopMutableCells workspaceCell stateCountCell positionCell
          furthestCell) before physicalAfter) :
      RecognizerPositionStepSynchronizedExecution grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell positionCell furthestCell before position
        furthest beforeInvariant
  | full (nextWorkspace : LogicalWorkspace) (nextValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
        nextWorkspace)
      (invariant : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout nextWorkspace nextValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter)
      (functionalAfterWorld :
        (positionTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell).World)
      (functionalAfterEnvironment : Lanius.FunctionalView.Env 15)
      (functionalExecution :
        Lanius.FunctionalView.Stateful.Command.Evaluates
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (positionStatefulMachine workspaceLayout grammar words tokens
            grammarCell tokensCell)
          (stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell)
          (positionEnvironment words tokens workspaceValues grammarCell
            tokensCell workspaceCell workspaceLayout grammar grammarLayout
            workspace.states.length furthest position)
          positionBodyCommand
          (.returned (some (parseResultValue 2 (Int.ofNat stateCount) (-1)
            (Int.ofNat position))))
          functionalAfterWorld functionalAfterEnvironment)
      (physicalExecution : Executes verifiedParserCore before
        parserRecognizePositionLoopBody
        (parserCapacityCompletion position stateCount) physicalAfter)
      (effect : ModifiesOnly
        (positionLoopMutableCells workspaceCell stateCountCell positionCell
          furthestCell) before physicalAfter) :
      RecognizerPositionStepSynchronizedExecution grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell positionCell furthestCell before position
        furthest beforeInvariant

/-- The chart-activity write and the retained state-scope writes are exactly
    the mutable footprint of one position body. -/
private theorem positionActivityScopeWrites_eq
    (workspaceCell stateCountCell positionCell furthestCell : CellId) :
    CellSet.union (CellSet.singleton furthestCell)
        (positionStateScopeRetainedCells workspaceCell stateCountCell
          positionCell) =
      positionLoopMutableCells workspaceCell stateCountCell positionCell
        furthestCell := by
  funext cell
  simp [positionStateScopeRetainedCells, positionLoopMutableCells,
    CellSet.union, CellSet.singleton]
  constructor
  · rintro (rfl | rfl | rfl | rfl)
    · exact Or.inr (Or.inr (Or.inr rfl))
    · exact Or.inl rfl
    · exact Or.inr (Or.inl rfl)
    · exact Or.inr (Or.inr (Or.inl rfl))
  · rintro (rfl | rfl | rfl | rfl)
    · exact Or.inr (Or.inl rfl)
    · exact Or.inr (Or.inr (Or.inl rfl))
    · exact Or.inr (Or.inr (Or.inr rfl))
    · exact Or.inl rfl

/-- Execute the whole position body once. FunctionalView owns its sequencing;
    the structural Core trace is carried as refinement evidence for the
    enclosing extracted loop. -/
private noncomputable def
    RecognizerPositionLoopInvariant.execute_step_synchronized
    (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest) :
    RecognizerPositionStepSynchronizedExecution grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest invariant := by
  let activity := invariant.execute_activity
  let functionalActivity := invariant.functional_execute_activity
  have nextFurthestEq : functionalActivity.nextFurthest =
      activity.nextFurthest := invariant.activity_nextFurthest_eq
  have activityFunctional :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (positionTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell)
        (positionEnvironment words tokens workspaceValues grammarCell tokensCell
          workspaceCell workspaceLayout grammar grammarLayout
          workspace.states.length furthest position)
        positionActivityCommand .next
        (stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell)
        (positionEnvironment words tokens workspaceValues grammarCell tokensCell
          workspaceCell workspaceLayout grammar grammarLayout
          workspace.states.length activity.nextFurthest position) := by
    simpa only [nextFurthestEq] using functionalActivity.execution
  let entry := activity.invariant.enter_state_loop
  let scope := entry.execute_scope_synchronized
  cases scope with
  | completed nextWorkspace nextValues physicalAfter growth frame
      scopeFunctional scopePhysical scopeEffect =>
      have functionalExecution :
          Lanius.FunctionalView.Stateful.Command.Evaluates
            (positionTermMachine workspaceLayout grammar words tokens grammarCell
              tokensCell)
            (positionStatefulMachine workspaceLayout grammar words tokens
              grammarCell tokensCell)
            (stateWorld words tokens workspaceValues grammarCell tokensCell
              workspaceCell)
            (positionEnvironment words tokens workspaceValues grammarCell
              tokensCell workspaceCell workspaceLayout grammar grammarLayout
              workspace.states.length furthest position)
            positionBodyCommand .next
            (stateWorld words tokens nextValues grammarCell tokensCell
              workspaceCell)
            (positionEnvironment words tokens nextValues grammarCell tokensCell
              workspaceCell workspaceLayout grammar grammarLayout
              nextWorkspace.states.length activity.nextFurthest
              (position + 1)) := by
        rw [positionBodyCommand_shape, positionExpectedBodyCommand]
        exact .sequenceNext activityFunctional scopeFunctional
      have physicalExecution : Executes verifiedParserCore runtime
          parserRecognizePositionLoopBody .next physicalAfter := by
        rw [extractedParserRecognize_position_body_shape]
        exact executesSequence activity.execution scopePhysical
      have effect := activity.effect.trans scopeEffect
      rw [positionActivityScopeWrites_eq] at effect
      exact .advanced nextWorkspace nextValues physicalAfter growth
        activity.nextFurthest frame functionalExecution physicalExecution effect
  | full nextWorkspace nextValues physicalAfter growth terminal stateCount
      wellFormed functionalAfterWorld functionalAfterEnvironment
      scopeFunctional scopePhysical scopeEffect =>
      have functionalExecution :
          Lanius.FunctionalView.Stateful.Command.Evaluates
            (positionTermMachine workspaceLayout grammar words tokens grammarCell
              tokensCell)
            (positionStatefulMachine workspaceLayout grammar words tokens
              grammarCell tokensCell)
            (stateWorld words tokens workspaceValues grammarCell tokensCell
              workspaceCell)
            (positionEnvironment words tokens workspaceValues grammarCell
              tokensCell workspaceCell workspaceLayout grammar grammarLayout
              workspace.states.length furthest position)
            positionBodyCommand
            (.returned (some (parseResultValue 2 (Int.ofNat stateCount) (-1)
              (Int.ofNat position))))
            functionalAfterWorld functionalAfterEnvironment := by
        rw [positionBodyCommand_shape, positionExpectedBodyCommand]
        exact .sequenceNext activityFunctional scopeFunctional
      have physicalExecution : Executes verifiedParserCore runtime
          parserRecognizePositionLoopBody
          (parserCapacityCompletion position stateCount) physicalAfter := by
        rw [extractedParserRecognize_position_body_shape]
        exact executesSequence activity.execution scopePhysical
      have effect := activity.effect.trans scopeEffect
      rw [positionActivityScopeWrites_eq] at effect
      exact .full nextWorkspace nextValues physicalAfter growth terminal
        stateCount wellFormed functionalAfterWorld functionalAfterEnvironment
        functionalExecution physicalExecution effect

private def RecognizerPositionStepSynchronizedExecution.physical
    (execution : RecognizerPositionStepSynchronizedExecution grammarLayout
      grammar words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell before
      position furthest beforeInvariant) :
    RecognizerPositionStepExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell before position
      furthest beforeInvariant := by
  cases execution with
  | advanced nextWorkspace nextValues physicalAfter growth nextFurthest frame
      _ trace effect =>
      exact {
        after := physicalAfter
        completion := .next
        execution := trace
        effect := effect
        outcome := .advanced nextWorkspace nextValues physicalAfter growth
          nextFurthest frame
      }
  | full nextWorkspace nextValues physicalAfter growth invariant stateCount
      wellFormed _ _ _ trace effect =>
      exact {
        after := physicalAfter
        completion := parserCapacityCompletion position stateCount
        execution := trace
        effect := effect
        outcome := .full nextWorkspace nextValues physicalAfter growth invariant
          stateCount wellFormed
      }

/-- Execute one complete chart-position body: record chart activity, execute
    the state-chain scope, and expose either the next position frame or the
    exact capacity return. -/
noncomputable def RecognizerPositionLoopInvariant.execute_step
    (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest) :
    RecognizerPositionStepExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest invariant :=
  invariant.execute_step_synchronized.physical

/-- Final position-loop state after the last position has advanced.  Keeping
    this separate from the active invariant makes the final false loop test
    explicit in the extracted execution trace. -/
structure RecognizerPositionFinishedInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (runtime : State) (furthest : Nat) : Prop where
  frame : RecognizerPositionPostFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell positionCell furthestCell runtime
    (finalPosition workspaceLayout.tokenCount) furthest

theorem RecognizerPositionFinishedInvariant.condition_negative
    (invariant : RecognizerPositionFinishedInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell runtime
      furthest) :
    Evaluates verifiedParserCore runtime
      (.binary .lessEqual (.local 23) (.local 6)) (.boolean false) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 23)
      (.signed .i32
        (Int.ofNat (finalPosition workspaceLayout.tokenCount + 1))) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 23 _
      (Assertion.localPointsTo_local 23 positionCell _ runtime
        invariant.frame.positionOwned)⟩
  have right : Evaluates verifiedParserCore runtime (.local 6)
      (.signed .i32
        (Int.ofNat (finalPosition workspaceLayout.tokenCount))) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 6 _
      invariant.frame.finalPositionLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]
  omega

/-- Final result of the complete position loop.  Capacity returns retain the
    position at which exhaustion occurred; normal completion carries the
    final-position resource frame needed by root search. -/
inductive RecognizerPositionLoopOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId) : State → Completion → Prop
  | completed (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (after : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (furthest : Nat)
      (invariant : RecognizerPositionFinishedInvariant grammarLayout grammar
        words tokens workspaceLayout workspace workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell positionCell furthestCell after
        furthest) :
      RecognizerPositionLoopOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell positionCell furthestCell after .next
  | full (position stateCount : Nat) (after : State)
      (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (invariant : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell after)
      (wellFormed : StateWellFormed after) :
      RecognizerPositionLoopOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell positionCell furthestCell after
        (parserCapacityCompletion position stateCount)

theorem RecognizerPositionLoopOutcome.prepend_growth
    (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
      middleWorkspace)
    (outcome : RecognizerPositionLoopOutcome grammarLayout grammar words tokens
      workspaceLayout middleWorkspace grammarCell tokensCell workspaceCell
      stateCountCell positionCell furthestCell after completion) :
    RecognizerPositionLoopOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell positionCell furthestCell after completion := by
  cases outcome with
  | completed workspace workspaceValues after suffixGrowth furthest invariant =>
      exact .completed workspace workspaceValues after
        (growth.trans suffixGrowth) furthest invariant
  | full position stateCount after workspace workspaceValues suffixGrowth
      invariant wellFormed =>
      exact .full position stateCount after workspace workspaceValues
        (growth.trans suffixGrowth) invariant wellFormed

/-- Algorithmic state of the position loop.  The finished constructor is a
    real state because the extracted `while` must still execute its final
    false condition. -/
inductive RecognizerPositionCursor
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId) (runtime : State) : Type
  | active (position furthest : Nat)
      (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell positionCell furthestCell runtime position
        furthest)
  | finished (furthest : Nat)
      (invariant : RecognizerPositionFinishedInvariant grammarLayout grammar
        words tokens workspaceLayout workspace workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell positionCell furthestCell runtime
        furthest)

structure RecognizerPositionConfig
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId) where
  workspace : LogicalWorkspace
  workspaceValues : List Int
  runtime : State
  cursor : RecognizerPositionCursor grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell positionCell furthestCell runtime

def RecognizerPositionConfig.measure
    (config : RecognizerPositionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      positionCell furthestCell) : Nat :=
  match config.cursor with
  | .active position _ _ =>
      finalPosition workspaceLayout.tokenCount + 1 - position
  | .finished _ _ => 0

def RecognizerPositionConfig.currentPosition
    (config : RecognizerPositionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      positionCell furthestCell) : Nat :=
  match config.cursor with
  | .active position _ _ => position
  | .finished _ _ => finalPosition workspaceLayout.tokenCount + 1

def RecognizerPositionConfig.currentFurthest
    (config : RecognizerPositionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      positionCell furthestCell) : Nat :=
  match config.cursor with
  | .active _ furthest _ => furthest
  | .finished furthest _ => furthest

noncomputable def RecognizerPositionConfig.functionalRuntime
    (config : RecognizerPositionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      positionCell furthestCell) :
    Lanius.FunctionalView.Stateful.Loop.Runtime
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell) 15 :=
  (stateWorld words tokens config.workspaceValues grammarCell tokensCell
      workspaceCell,
    positionEnvironment words tokens config.workspaceValues grammarCell tokensCell
      workspaceCell workspaceLayout grammar grammarLayout
      config.workspace.states.length config.currentFurthest
      config.currentPosition)

theorem RecognizerPositionConfig.functional_condition
    (config : RecognizerPositionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      positionCell furthestCell) :
    Lanius.FunctionalView.Term.evaluate
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      config.functionalRuntime.world config.functionalRuntime.environment
      positionLoopCondition =
      .ok (.boolean (decide (config.currentPosition ≤
        finalPosition workspaceLayout.tokenCount)),
        config.functionalRuntime.world) := by
  apply positionLoopCondition_evaluates workspaceLayout grammar words tokens
    grammarCell tokensCell
  · rfl
  · rfl

/-! The position loop now carries one FunctionalView runtime and one matching
physical Core state through every edge. -/

inductive RecognizerPositionSynchronizedOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (functionalAfter : Lanius.FunctionalView.Stateful.Loop.Runtime
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell) 15) :
    State → Lanius.FunctionalView.Stateful.Completion → Type where
  | completed (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (furthest : Nat)
      (invariant : RecognizerPositionFinishedInvariant grammarLayout grammar
        words tokens workspaceLayout workspace workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell positionCell furthestCell
        physicalAfter furthest)
      (worldEq : functionalAfter.world =
        stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell)
      (environmentEq : functionalAfter.environment =
        positionEnvironment words tokens workspaceValues grammarCell tokensCell
          workspaceCell workspaceLayout grammar grammarLayout
          workspace.states.length furthest
          (finalPosition workspaceLayout.tokenCount + 1)) :
      RecognizerPositionSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell positionCell furthestCell functionalAfter physicalAfter
        .next
  | full (position stateCount : Nat) (physicalAfter : State)
      (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (invariant : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (wellFormed : StateWellFormed physicalAfter) :
      RecognizerPositionSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell positionCell furthestCell functionalAfter physicalAfter
        (.returned (some (parseResultValue 2 (Int.ofNat stateCount) (-1)
          (Int.ofNat position))))

def RecognizerPositionSynchronizedOutcome.prepend_growth
    (outcome : RecognizerPositionSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout middleWorkspace grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell functionalAfter
      physicalAfter completion)
    (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
      middleWorkspace) :
    RecognizerPositionSynchronizedOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell positionCell furthestCell functionalAfter physicalAfter
      completion := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter suffix furthest invariant
      worldEq environmentEq =>
      exact .completed workspace workspaceValues physicalAfter
        (growth.trans suffix) furthest invariant worldEq environmentEq
  | full position stateCount physicalAfter workspace workspaceValues suffix
      invariant wellFormed =>
      exact .full position stateCount physicalAfter workspace workspaceValues
        (growth.trans suffix) invariant wellFormed

def RecognizerPositionSynchronizedOutcome.physical
    (outcome : RecognizerPositionSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell functionalAfter
      physicalAfter completion) :
    RecognizerPositionLoopOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell positionCell furthestCell physicalAfter
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion) := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter growth furthest invariant
      _ _ =>
      exact .completed workspace workspaceValues physicalAfter growth furthest
        invariant
  | full position stateCount physicalAfter workspace workspaceValues growth
      invariant wellFormed =>
      exact .full position stateCount physicalAfter workspace workspaceValues
        growth invariant wellFormed

structure RecognizerPositionFunctionalResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (config : RecognizerPositionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      positionCell furthestCell)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (functionalAfter : Lanius.FunctionalView.Stateful.Loop.Runtime
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell) 15) where
  physicalAfter : State
  execution : Executes verifiedParserCore config.runtime
    parserRecognizePositionLoop
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
    physicalAfter
  effect : ModifiesOnly
    (positionLoopMutableCells workspaceCell stateCountCell positionCell
      furthestCell) config.runtime physicalAfter
  outcome : RecognizerPositionSynchronizedOutcome grammarLayout grammar words
    tokens workspaceLayout config.workspace grammarCell tokensCell workspaceCell
    stateCountCell positionCell furthestCell functionalAfter physicalAfter
    completion

/-- One position-loop decision shared by the reified FunctionalView command
    and the exact extracted Core loop. -/
private noncomputable def RecognizerPositionConfig.functional_decide
    (config : RecognizerPositionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      positionCell furthestCell) :
    Lanius.FunctionalView.Stateful.Loop.Decision
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      positionLoopCondition positionBodyCommand
      (RecognizerPositionConfig grammarLayout grammar words tokens
        workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
        positionCell furthestCell)
      RecognizerPositionConfig.functionalRuntime RecognizerPositionConfig.measure
      (RecognizerPositionFunctionalResult grammarLayout grammar words tokens
        workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
        positionCell furthestCell) config := by
  cases cursorShape : config.cursor with
  | finished furthest invariant =>
      have functionalFalse : Lanius.FunctionalView.Term.evaluate
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          config.functionalRuntime.world config.functionalRuntime.environment
          positionLoopCondition =
          .ok (.boolean false, config.functionalRuntime.world) := by
        have outside : ¬ (finalPosition workspaceLayout.tokenCount + 1 ≤
            finalPosition workspaceLayout.tokenCount) := by omega
        simpa [RecognizerPositionConfig.currentPosition, cursorShape, outside]
          using config.functional_condition
      apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
      exact {
        completion := .next
        after := config.functionalRuntime
        edge := .conditionFalse functionalFalse
        result := {
          physicalAfter := config.runtime
          execution := by
            rw [extractedParserRecognize_position_loop_shape]
            exact executesWhileFalse invariant.condition_negative
          effect := ModifiesOnly.reflAny
            (positionLoopMutableCells workspaceCell stateCountCell positionCell
              furthestCell) config.runtime
          outcome := by
            apply RecognizerPositionSynchronizedOutcome.completed
              config.workspace config.workspaceValues config.runtime
              (.refl config.workspace) furthest invariant
            · rfl
            · change positionEnvironment words tokens config.workspaceValues
                  grammarCell tokensCell workspaceCell workspaceLayout grammar
                  grammarLayout config.workspace.states.length
                  config.currentFurthest config.currentPosition = _
              rw [show config.currentFurthest = furthest by
                    simp [RecognizerPositionConfig.currentFurthest,
                      cursorShape],
                show config.currentPosition =
                    finalPosition workspaceLayout.tokenCount + 1 by
                    simp [RecognizerPositionConfig.currentPosition,
                      cursorShape]]
        }
      }
  | active position furthest invariant =>
      let step := invariant.execute_step_synchronized
      have positionBound : position ≤
          finalPosition workspaceLayout.tokenCount :=
        invariant.appendFrame.positionBound
      have configRuntimeEq : config.functionalRuntime =
          (stateWorld words tokens config.workspaceValues grammarCell tokensCell
              workspaceCell,
            positionEnvironment words tokens config.workspaceValues grammarCell
              tokensCell workspaceCell workspaceLayout grammar grammarLayout
              config.workspace.states.length furthest position) := by
        unfold RecognizerPositionConfig.functionalRuntime
        rw [show config.currentFurthest = furthest by
              simp [RecognizerPositionConfig.currentFurthest, cursorShape],
          show config.currentPosition = position by
              simp [RecognizerPositionConfig.currentPosition, cursorShape]]
        rfl
      have functionalTrue : Lanius.FunctionalView.Term.evaluate
          (positionTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          config.functionalRuntime.world config.functionalRuntime.environment
          positionLoopCondition =
          .ok (.boolean true, config.functionalRuntime.world) := by
        simpa [RecognizerPositionConfig.currentPosition, cursorShape,
          positionBound] using config.functional_condition
      have physicalTrue := invariant.condition_true
      cases step with
      | full nextWorkspace nextValues physicalAfter growth nextInvariant
          stateCount wellFormed functionalAfterWorld functionalAfterEnvironment
          functionalBody physicalBody stepEffect =>
          apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
          exact {
            completion := .returned (some (parseResultValue 2
              (Int.ofNat stateCount) (-1) (Int.ofNat position)))
            after := (functionalAfterWorld, functionalAfterEnvironment)
            edge := .returned functionalTrue (by
              simpa only [configRuntimeEq,
                Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                  functionalBody)
            result := {
              physicalAfter := physicalAfter
              execution := by
                rw [extractedParserRecognize_position_loop_shape]
                exact executesWhileReturned physicalTrue physicalBody
              effect := stepEffect
              outcome := .full position stateCount physicalAfter nextWorkspace
                nextValues growth nextInvariant wellFormed
            }
          }
      | advanced nextWorkspace nextValues physicalAfter growth nextFurthest
          frame functionalBody physicalBody stepEffect =>
          by_cases nextBound : position + 1 ≤
              finalPosition workspaceLayout.tokenCount
          · let nextConfig : RecognizerPositionConfig grammarLayout grammar
                words tokens workspaceLayout grammarCell tokensCell
                workspaceCell stateCountCell positionCell furthestCell := {
              workspace := nextWorkspace
              workspaceValues := nextValues
              runtime := physicalAfter
              cursor := .active (position + 1) nextFurthest
                (frame.next_invariant nextBound)
            }
            have nextRuntimeEq : nextConfig.functionalRuntime =
                (stateWorld words tokens nextValues grammarCell tokensCell
                    workspaceCell,
                  positionEnvironment words tokens nextValues grammarCell
                    tokensCell workspaceCell workspaceLayout grammar grammarLayout
                    nextWorkspace.states.length nextFurthest (position + 1)) := by
              rfl
            apply Lanius.FunctionalView.Stateful.Loop.Decision.next nextConfig
            · apply Lanius.FunctionalView.Stateful.Loop.Iteration.next
                functionalTrue
              simpa only [configRuntimeEq, nextRuntimeEq,
                Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                  functionalBody
            · simp only [WellFoundedRelation.rel,
                RecognizerPositionConfig.measure, nextConfig]
              simp [cursorShape]
              have decreases := Nat.sub_lt_sub_left
                (show position <
                  finalPosition workspaceLayout.tokenCount + 1 by omega)
                (Nat.lt_succ_self position)
              change sizeOf
                  (finalPosition workspaceLayout.tokenCount - position) <
                sizeOf
                  (finalPosition workspaceLayout.tokenCount + 1 - position)
              simpa using decreases
            · intro completion after result
              exact {
                physicalAfter := result.physicalAfter
                execution := by
                  rw [extractedParserRecognize_position_loop_shape]
                  exact executesWhileTrueThen physicalTrue physicalBody
                    result.execution
                effect := stepEffect.trans_same result.effect
                outcome := result.outcome.prepend_growth growth
              }
          · have atFinal : position =
                finalPosition workspaceLayout.tokenCount := by
              have positionBound := invariant.appendFrame.positionBound
              omega
            let finishedInvariant : RecognizerPositionFinishedInvariant
                grammarLayout grammar words tokens workspaceLayout nextWorkspace
                nextValues grammarCell tokensCell workspaceCell stateCountCell
                positionCell furthestCell physicalAfter nextFurthest := {
              frame := by simpa [atFinal] using frame
            }
            let nextConfig : RecognizerPositionConfig grammarLayout grammar
                words tokens workspaceLayout grammarCell tokensCell
                workspaceCell stateCountCell positionCell furthestCell := {
              workspace := nextWorkspace
              workspaceValues := nextValues
              runtime := physicalAfter
              cursor := .finished nextFurthest finishedInvariant
            }
            have nextRuntimeEq : nextConfig.functionalRuntime =
                (stateWorld words tokens nextValues grammarCell tokensCell
                    workspaceCell,
                  positionEnvironment words tokens nextValues grammarCell
                    tokensCell workspaceCell workspaceLayout grammar grammarLayout
                    nextWorkspace.states.length nextFurthest (position + 1)) := by
              unfold RecognizerPositionConfig.functionalRuntime
              change (stateWorld words tokens nextValues grammarCell tokensCell
                  workspaceCell,
                positionEnvironment words tokens nextValues grammarCell
                  tokensCell workspaceCell workspaceLayout grammar grammarLayout
                  nextWorkspace.states.length nextFurthest
                  (finalPosition workspaceLayout.tokenCount + 1)) = _
              rw [← atFinal]
            apply Lanius.FunctionalView.Stateful.Loop.Decision.next nextConfig
            · apply Lanius.FunctionalView.Stateful.Loop.Iteration.next
                functionalTrue
              simpa only [configRuntimeEq, nextRuntimeEq,
                Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                  functionalBody
            · simp only [WellFoundedRelation.rel,
                RecognizerPositionConfig.measure, nextConfig]
              simp [cursorShape]
              have positive : 0 <
                  finalPosition workspaceLayout.tokenCount + 1 - position :=
                Nat.sub_pos_of_lt (by omega)
              change sizeOf 0 < sizeOf
                (finalPosition workspaceLayout.tokenCount + 1 - position)
              simpa using positive
            · intro completion after result
              exact {
                physicalAfter := result.physicalAfter
                execution := by
                  rw [extractedParserRecognize_position_loop_shape]
                  exact executesWhileTrueThen physicalTrue physicalBody
                    result.execution
                effect := stepEffect.trans_same result.effect
                outcome := result.outcome.prepend_growth growth
              }

noncomputable def RecognizerPositionConfig.functional_run
    (config : RecognizerPositionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      positionCell furthestCell) :=
  Lanius.FunctionalView.Stateful.Loop.run
    (positionTermMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    positionLoopCondition positionBodyCommand
    (RecognizerPositionConfig grammarLayout grammar words tokens workspaceLayout
      grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell)
    RecognizerPositionConfig.functionalRuntime RecognizerPositionConfig.measure
    (RecognizerPositionFunctionalResult grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      positionCell furthestCell)
    RecognizerPositionConfig.functional_decide config

structure RecognizerPositionLoopExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (before : State) (position furthest : Nat)
    (beforeInvariant : RecognizerPositionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell before
      position furthest) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before parserRecognizePositionLoop
    completion after
  effect : ModifiesOnly
    (positionLoopMutableCells workspaceCell stateCountCell positionCell
      furthestCell) before after
  outcome : RecognizerPositionLoopOutcome grammarLayout grammar words tokens
    workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell positionCell furthestCell after completion

/-- Total execution of the exact extracted chart-position loop. FunctionalView
    owns the loop trace; the physical Core execution is its refinement result. -/
noncomputable def RecognizerPositionLoopInvariant.execute_loop
    (invariant : RecognizerPositionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest) :
    RecognizerPositionLoopExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell runtime position
      furthest invariant := by
  let initial : RecognizerPositionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      positionCell furthestCell := {
    workspace := workspace
    workspaceValues := workspaceValues
    runtime := runtime
    cursor := .active position furthest invariant
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

def verifiedParserRootLoopAccessFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedAccessFrameForCore
    parserRecognizeRootLoop (by native_decide)

def verifiedParserRootLoopLiveFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedLiveFrameBeforeCore
    parserRecognizeRootLoop (by native_decide)

theorem verifiedParser_root_loop_access_frame :
    verifiedParserRootLoopAccessFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("root_state", 41, .readWrite),
      ("workspace", 4, .read),
      ("state_base", 8, .read),
      ("grammar", 0, .read),
      ("start_nonterminal", 12, .read),
      ("state_count", 18, .read)] := by
  native_decide

theorem verifiedParser_root_loop_live_frame :
    verifiedParserRootLoopLiveFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("root_state", 41, .readWrite),
      ("workspace", 4, .read),
      ("state_base", 8, .read),
      ("grammar", 0, .read),
      ("start_nonterminal", 12, .read),
      ("state_count", 18, .read),
      ("furthest_position", 22, .read)] := by
  native_decide

/-- Locals live across root search whose cells are shared with the enclosing
    result frame.  The `root_state` cursor is excluded because `chartCursor`
    owns it. -/
def verifiedParserRootLoopSharedFrame :
    LocalAccessFrame :=
  verifiedParserRootLoopLiveFrame.excludingName "root_state"

def verifiedParserRootLoopSharedFrameIds : List VarId :=
  verifiedParserRootLoopSharedFrame.ids

theorem verifiedParser_root_loop_shared_frame_ids :
    verifiedParserRootLoopSharedFrameIds = [4, 8, 0, 12, 18, 22] := by
  native_decide

@[simp] theorem mem_verifiedParserRootLoopSharedFrameIds_iff
    (id : Nat) :
    id ∈ verifiedParserRootLoopSharedFrameIds ↔
      id = 4 ∨ id = 8 ∨ id = 0 ∨ id = 12 ∨ id = 18 ∨ id = 22 := by
  rw [verifiedParser_root_loop_shared_frame_ids]
  simp only [List.mem_cons, List.not_mem_nil, or_false]

def verifiedParserRootLoopBindings : LocalBindingFrame :=
  LocalBindingFrame.union verifiedParserRecognizerParameterFrame
    verifiedParserRootLoopSharedFrame.bindings

def RootLoopFramedLocal (id : VarId) : Prop :=
  id ∈ verifiedParserRecognizerParameterIds ∨
    id ∈ verifiedParserRootLoopSharedFrameIds

theorem verifiedParserRootLoopBindings_core_ids :
    verifiedParserRootLoopBindings.coreIds =
      verifiedParserRecognizerParameterIds ++
        verifiedParserRootLoopSharedFrameIds := by
  native_decide

theorem RootLoopFramedLocal_source_frame (id : VarId) :
    RootLoopFramedLocal id ↔
      verifiedParserRootLoopBindings.ContainsCoreId id := by
  rw [LocalBindingFrame.ContainsCoreId,
    verifiedParserRootLoopBindings_core_ids]
  simp [RootLoopFramedLocal]

theorem rootLoopFramedLocalFootprint_eq (runtime : State) :
    localCellFootprint runtime RootLoopFramedLocal =
      localBindingFrameFootprint runtime verifiedParserRootLoopBindings := by
  unfold localBindingFrameFootprint
  congr 1
  funext id
  exact propext (RootLoopFramedLocal_source_frame id)

theorem RootLoopFramedLocal.le22
    (id : Nat) (framed : RootLoopFramedLocal id) : id ≤ 22 := by
  unfold RootLoopFramedLocal at framed
  rcases framed with parameter | shared
  · exact Nat.le_trans
      ((mem_verifiedParserRecognizerParameterIds_iff id).mp parameter)
      (by decide)
  · rw [mem_verifiedParserRootLoopSharedFrameIds_iff] at shared
    rcases shared with rfl | rfl | rfl | rfl | rfl | rfl <;> decide

theorem extractedParserRecognize_root_loop_shape :
    parserRecognizeRootLoop =
      .whileLoop
        (.binary .greaterEqual (.local 41)
          (.value (.signed .i32 0)))
        parserRecognizeRootLoopBody := by
  rfl

theorem extractedParserRecognize_root_body_shape :
    parserRecognizeRootLoopBody =
      .letLocal 42 parserI32Type (parserRecognizeStateValueCall 41 28)
        (.sequence
          (.ifThenElse parserRecognizeRootPredicate
            parserRecognizeRootSuccessBranch .skip)
          (parserRecognizeCursorAdvanceStatement 41)) := by
  rfl

theorem extractedParserRecognize_root_predicate_shape :
    parserRecognizeRootPredicate =
      .binary .logicalAnd
        (.binary .logicalAnd
          (.binary .equal (parserRecognizeStateValueCall 41 30)
            (.value (.signed .i32 0)))
          (.binary .equal
            (.call extractedParserLhsFunction.id [.local 0, .local 42])
            (.local 12)))
        (.binary .equal (parserRecognizeStateValueCall 41 29)
          (.call extractedParserRhsLengthFunction.id [.local 0, .local 42])) := by
  rfl

theorem extractedParserRecognize_root_success_shape :
    parserRecognizeRootSuccessBranch =
      .sequence
        (.returnValue (some (.call extractedParserParseResultFunction.id
          [.constant 0, .local 18, .local 41,
            .value (.signed .i32 0)])))
        .skip := by
  rfl


end Lanius.Extraction.ParserRecognize
