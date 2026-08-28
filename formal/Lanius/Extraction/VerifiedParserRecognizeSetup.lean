import Lanius.Extraction.VerifiedParserRecognizeLoops

namespace Lanius.Extraction.ParserRecognize

set_option maxRecDepth 100000

open Lanius.Core
open Lanius.Semantics
open Lanius.Separation
open Lanius.Properties
open Lanius.Compiler.Parser
open Lanius.CallContracts
open Lanius.Extraction
open Lanius.Extraction.ParserValidation
open Lanius.Extraction.ParserAccessors
open Lanius.Extraction.ParserResult
open Lanius.Extraction.ParserScan
open Lanius.Extraction.ParserFind
open Lanius.SymbolicCore

def parserRecognizeInputGuard : Stmt :=
  match parserRecognizeAfterGrammarGuard with
  | .sequence guard _ => guard
  | _ => .skip

def parserRecognizeBadInputBranch : Stmt :=
  match parserRecognizeInputGuard with
  | .ifThenElse _ badInput _ => badInput
  | _ => .skip

def parserRecognizeFinalPositionStatement : Stmt :=
  (findLetLocalStatement 6 parserRecognizeAfterGrammarGuard).getD .skip

def parserRecognizePositionCountStatement : Stmt :=
  (findLetLocalStatement 7 parserRecognizeAfterGrammarGuard).getD .skip

def parserRecognizeStateBaseStatement : Stmt :=
  (findLetLocalStatement 8 parserRecognizeAfterGrammarGuard).getD .skip

def parserRecognizeWorkspaceGuard : Stmt :=
  match parserRecognizeStateBaseStatement with
  | .letLocal 8 _ _ (.sequence guard _) => guard
  | _ => .skip

def parserRecognizeBadWorkspaceBranch : Stmt :=
  match parserRecognizeWorkspaceGuard with
  | .ifThenElse _ badWorkspace _ => badWorkspace
  | _ => .skip

def parserRecognizeStateCapacityStatement : Stmt :=
  (findLetLocalStatement 9 parserRecognizeAfterGrammarGuard).getD .skip

def parserRecognizeChartIndexStatement : Stmt :=
  (findLetLocalStatement 10 parserRecognizeAfterGrammarGuard).getD .skip

theorem extractedParserRecognize_after_grammar_guard_shape :
    parserRecognizeAfterGrammarGuard =
      .sequence parserRecognizeInputGuard
        parserRecognizeFinalPositionStatement := by
  rfl

theorem extractedParserRecognize_body_shape :
    extractedParserRecognizeBody =
      .sequence parserRecognizeGrammarGuard
        parserRecognizeAfterGrammarGuard := by
  rfl

theorem extractedParserRecognize_input_guard_shape :
    parserRecognizeInputGuard =
      .ifThenElse
        (.binary .logicalOr
          (.binary .logicalOr
            (.binary .less (.local 3) (.value (.signed .i32 0)))
            (.binary .greater (.local 3)
              (.value (.signed .i32 536870911))))
          (.binary .less (.local 5) (.value (.signed .i32 0))))
        parserRecognizeBadInputBranch .skip := by
  rfl

theorem extractedParserRecognize_final_position_statement_shape :
    parserRecognizeFinalPositionStatement =
      .letLocal 6 parserI32Type
        (.binary .multiply (.local 3) (.value (.signed .i32 2)))
        parserRecognizePositionCountStatement := by
  rfl

theorem extractedParserRecognize_position_count_statement_shape :
    parserRecognizePositionCountStatement =
      .letLocal 7 parserI32Type
        (.binary .add (.local 6) (.value (.signed .i32 1)))
        parserRecognizeStateBaseStatement := by
  rfl

theorem extractedParserRecognize_state_base_statement_shape :
    parserRecognizeStateBaseStatement =
      .letLocal 8 parserI32Type
        (.binary .multiply (.local 7) (.constant 24))
        (.sequence parserRecognizeWorkspaceGuard
          parserRecognizeStateCapacityStatement) := by
  rfl

theorem extractedParserRecognize_workspace_guard_shape :
    parserRecognizeWorkspaceGuard =
      .ifThenElse
        (.binary .less (.local 5) (.local 8))
        parserRecognizeBadWorkspaceBranch .skip := by
  rfl

theorem extractedParserRecognize_state_capacity_statement_shape :
    parserRecognizeStateCapacityStatement =
      .letLocal 9 parserI32Type
        (.binary .divide
          (.binary .subtract (.local 5) (.local 8)) (.constant 27))
        parserRecognizeChartIndexStatement := by
  rfl

theorem extractedParserRecognize_chart_index_statement_shape :
    parserRecognizeChartIndexStatement =
      .letLocal 10 parserI32Type (.value (.signed .i32 0))
        (.sequence parserRecognizeChartClearLoop
          parserRecognizeSeedSetupStatement) := by
  rfl

/-- The recognizer's signed-range guard is false for every caller state
    described by a checked workspace layout. -/
theorem RecognizerResources.input_guard_evaluates_false
    (resources : RecognizerResources grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      runtime) :
    Evaluates verifiedParserCore runtime
      (.binary .logicalOr
        (.binary .logicalOr
          (.binary .less (.local 3) (.value (.signed .i32 0)))
          (.binary .greater (.local 3)
            (.value (.signed .i32 536870911))))
        (.binary .less (.local 5) (.value (.signed .i32 0))))
      (.boolean false) runtime := by
  have tokenResult : Evaluates verifiedParserCore runtime (.local 3)
      (.signed .i32 (Int.ofNat tokens.length)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 3 _
      resources.tokenCountLocal⟩
  have workspaceResult : Evaluates verifiedParserCore runtime (.local 5)
      (.signed .i32 (Int.ofNat workspaceValues.length)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 5 _
      resources.workspaceLengthLocal⟩
  have zero : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 0)) (.signed .i32 0) runtime := ⟨1, rfl⟩
  have maximum : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 536870911)) (.signed .i32 536870911) runtime :=
    ⟨1, rfl⟩
  have tokenNonnegative : Evaluates verifiedParserCore runtime
      (.binary .less (.local 3) (.value (.signed .i32 0)))
      (.boolean false) runtime := by
    apply evaluatesEagerBinary (by decide) (by decide) tokenResult zero
    simp [evalBinaryValue, evalSignedBinary]
  have tokenBound : tokens.length ≤ maxTokenCount := by
    rw [← resources.workspaceTokenCount]
    exact workspaceLayout.tokenBound
  have intTokenBound : Int.ofNat tokens.length ≤ 536870911 := by
    rw [show (536870911 : Int) = Int.ofNat 536870911 by rfl]
    exact Int.ofNat_le.mpr (by simpa [maxTokenCount] using tokenBound)
  have tokenWithinMaximum : Evaluates verifiedParserCore runtime
      (.binary .greater (.local 3) (.value (.signed .i32 536870911)))
      (.boolean false) runtime := by
    apply evaluatesEagerBinary (by decide) (by decide) tokenResult maximum
    simp [evalBinaryValue, evalSignedBinary]
    exact intTokenBound
  have workspaceNonnegative : Evaluates verifiedParserCore runtime
      (.binary .less (.local 5) (.value (.signed .i32 0)))
      (.boolean false) runtime := by
    apply evaluatesEagerBinary (by decide) (by decide) workspaceResult zero
    simp [evalBinaryValue, evalSignedBinary]
  have first := evaluatesPureLogicalOr tokenNonnegative tokenWithinMaximum
  exact evaluatesPureLogicalOr first workspaceNonnegative

theorem RecognizerResources.input_guard_executes
    (resources : RecognizerResources grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      runtime) :
    Executes verifiedParserCore runtime parserRecognizeInputGuard .next
      runtime := by
  rw [extractedParserRecognize_input_guard_shape]
  exact executesIfFalse resources.input_guard_evaluates_false
    (executesSkip verifiedParserCore runtime)

/-- Function-entry resources add the one ownership fact that cannot be
    reconstructed from representation values alone: the caller's six local
    bindings do not alias the workspace array backing cell. -/
structure RecognizerEntryResources
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (runtime : State) : Prop where
  resources : RecognizerResources grammarLayout grammar words tokens
    workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
    runtime
  parameterWorkspaceSeparate : CellSet.Disjoint
    (localBindingFrameFootprint runtime
      verifiedParserRecognizerParameterFrame)
    (CellSet.singleton workspaceCell)

theorem RecognizerEntryResources.after_empty_effect
    (entry : RecognizerEntryResources grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    RecognizerEntryResources grammarLayout grammar words tokens workspaceLayout
      workspaceValues grammarCell tokensCell workspaceCell after := by
  have resources : RecognizerResources grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      after := {
    grammarEncoded := entry.resources.grammarEncoded
    grammarWellFormed := entry.resources.grammarWellFormed
    wordsI32 := entry.resources.wordsI32
    tokensI32 := entry.resources.tokensI32
    workspaceLength := entry.resources.workspaceLength
    workspaceTokenCount := entry.resources.workspaceTokenCount
    wellFormed := afterWellFormed
    grammarLocal := effect.empty_preserves_local entry.resources.wellFormed
      entry.resources.grammarLocal
    grammarLengthLocal := effect.empty_preserves_local
      entry.resources.wellFormed entry.resources.grammarLengthLocal
    tokensLocal := effect.empty_preserves_local entry.resources.wellFormed
      entry.resources.tokensLocal
    tokenCountLocal := effect.empty_preserves_local entry.resources.wellFormed
      entry.resources.tokenCountLocal
    workspaceLocal := effect.empty_preserves_local entry.resources.wellFormed
      entry.resources.workspaceLocal
    workspaceLengthLocal := effect.empty_preserves_local
      entry.resources.wellFormed entry.resources.workspaceLengthLocal
    grammarBacking := effect.empty_preserves_entry entry.resources.wellFormed
      entry.resources.grammarBacking
    tokensBacking := effect.empty_preserves_entry entry.resources.wellFormed
      entry.resources.tokensBacking
    workspaceBacking := effect.empty_preserves_entry entry.resources.wellFormed
      entry.resources.workspaceBacking
    grammarWorkspaceDistinct := entry.resources.grammarWorkspaceDistinct
    tokensWorkspaceDistinct := entry.resources.tokensWorkspaceDistinct
  }
  exact {
    resources := resources
    parameterWorkspaceSeparate := by
      rw [effect.localBindingFrameFootprint_eq]
      exact entry.parameterWorkspaceSeparate
  }

/-- The recognizer's entry resources construct the validator invariant for
    the exact internal call frame.  No second grammar representation is
    introduced: both proofs share the caller's packed grammar backing cell. -/
theorem RecognizerEntryResources.grammar_validation_invariant
    (entry : RecognizerEntryResources grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before) :
    GrammarValidationInvariant grammarLayout grammar words grammarCell
      (parserGrammarValidCallee before words grammarCell) := by
  let bindings := parserGrammarValidBindings words grammarCell
  let callee := parserGrammarValidCallee before words grammarCell
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, parserGrammarValidCallee, bindings] using
      (enterCall_preserves_wellFormed
        (bindings := bindings) entry.resources.wellFormed)
  have grammarLocal : callee.local? 0 =
      some (parserGrammarValue words grammarCell) := by
    simpa [callee, parserGrammarValidCallee, bindings,
      parserGrammarValidBindings] using
      enterCall_local_of_binding before []
        [(1, .signed .i32 (Int.ofNat words.length))] 0
        (parserGrammarValue words grammarCell) entry.resources.wellFormed
        (by simp)
  have grammarLengthLocal : callee.local? 1 =
      some (.signed .i32 (Int.ofNat words.length)) := by
    simpa [callee, parserGrammarValidCallee, bindings,
      parserGrammarValidBindings] using
      enterCall_local_of_binding before
        [(0, parserGrammarValue words grammarCell)] [] 1
        (.signed .i32 (Int.ofNat words.length)) entry.resources.wellFormed
        (by simp)
  have grammarBacking : callee.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values words)) } := by
    have effect := enterCall_effect before bindings
    have old := StateWellFormed.cell_lt_next_of_entry entry.resources.wellFormed
      entry.resources.grammarBacking
    exact (effect.oldCells grammarCell old (by simp [CellSet.empty])).trans
      entry.resources.grammarBacking
  exact {
    encoded := entry.resources.grammarEncoded
    grammarWellFormed := entry.resources.grammarWellFormed
    wordsI32 := entry.resources.wordsI32
    stateWellFormed := calleeWellFormed
    grammarLocal := grammarLocal
    grammarLengthLocal := grammarLengthLocal
    grammarBacking := grammarBacking
  }

/-- Adding source locals above the six parameters preserves all physical
    recognizer resources.  This is the common prelude rule used before chart
    clearing; it does not pretend the uncleared workspace encodes a logical
    Earley chart. -/
theorem RecognizerResources.after_bind_locals
    (resources : RecognizerResources grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      runtime)
    (bindings : List (VarId × Value))
    (afterParameters : ∀ binding, binding ∈ bindings → 5 < binding.1) :
    RecognizerResources grammarLayout grammar words tokens workspaceLayout
      workspaceValues grammarCell tokensCell workspaceCell
      (runtime.bindLocals bindings) := by
  have notRebound (id : VarId) (bound : id ≤ 5) :
      ∀ binding, binding ∈ bindings → binding.1 ≠ id := by
    intro binding member
    exact Nat.ne_of_gt (Nat.lt_of_le_of_lt bound
      (afterParameters binding member))
  have preserveLocal (id : VarId) (bound : id ≤ 5) (value : Value)
      (found : runtime.local? id = some value) :
      (runtime.bindLocals bindings).local? id = some value :=
    bindLocals_preserves_local runtime bindings id value resources.wellFormed
      found (notRebound id bound)
  have preserveEntry (cell : CellId) {value : Option Value}
      (found : runtime.cellEntry? cell = some { id := cell, value := value }) :
      (runtime.bindLocals bindings).cellEntry? cell =
        some { id := cell, value := value } := by
    exact (bindLocals_preserves_old_cell runtime bindings cell
      (StateWellFormed.cell_lt_next_of_entry resources.wellFormed found)).trans
      found
  exact {
    grammarEncoded := resources.grammarEncoded
    grammarWellFormed := resources.grammarWellFormed
    wordsI32 := resources.wordsI32
    tokensI32 := resources.tokensI32
    workspaceLength := resources.workspaceLength
    workspaceTokenCount := resources.workspaceTokenCount
    wellFormed := bindLocals_preserves_wellFormed runtime bindings
      resources.wellFormed
    grammarLocal := preserveLocal 0 (by decide) _ resources.grammarLocal
    grammarLengthLocal := preserveLocal 1 (by decide) _
      resources.grammarLengthLocal
    tokensLocal := preserveLocal 2 (by decide) _ resources.tokensLocal
    tokenCountLocal := preserveLocal 3 (by decide) _
      resources.tokenCountLocal
    workspaceLocal := preserveLocal 4 (by decide) _ resources.workspaceLocal
    workspaceLengthLocal := preserveLocal 5 (by decide) _
      resources.workspaceLengthLocal
    grammarBacking := preserveEntry grammarCell resources.grammarBacking
    tokensBacking := preserveEntry tokensCell resources.tokensBacking
    workspaceBacking := preserveEntry workspaceCell resources.workspaceBacking
    grammarWorkspaceDistinct := resources.grammarWorkspaceDistinct
    tokensWorkspaceDistinct := resources.tokensWorkspaceDistinct
  }

def recognizerPreludeBindings
    (layout : WorkspaceLayout) : List (VarId × Value) := [
  (6, .signed .i32 (Int.ofNat (finalPosition layout.tokenCount))),
  (7, .signed .i32 (Int.ofNat (chartCount layout.tokenCount))),
  (8, .signed .i32 (Int.ofNat (stateBase layout.tokenCount))),
  (9, .signed .i32 (Int.ofNat layout.capacity)),
  (10, .signed .i32 0)]

def recognizerPreludeState (before : State)
    (layout : WorkspaceLayout) : State :=
  before.bindLocals (recognizerPreludeBindings layout)

theorem recognizerPreludeBindings_after_parameters
    (binding : VarId × Value)
    (member : binding ∈ recognizerPreludeBindings layout) :
    5 < binding.1 := by
  have idMember : binding.1 ∈
      (recognizerPreludeBindings layout).map Prod.fst :=
    List.mem_map_of_mem member
  have cases : binding.1 = 6 ∨ binding.1 = 7 ∨ binding.1 = 8 ∨
      binding.1 = 9 ∨ binding.1 = 10 := by
    simpa [recognizerPreludeBindings] using idMember
  rcases cases with same | same | same | same | same <;> simp_all

theorem RecognizerEntryResources.prelude_resources
    (entry : RecognizerEntryResources grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before) :
    RecognizerResources grammarLayout grammar words tokens workspaceLayout
      workspaceValues grammarCell tokensCell workspaceCell
      (recognizerPreludeState before workspaceLayout) := by
  exact entry.resources.after_bind_locals
    (recognizerPreludeBindings workspaceLayout)
    recognizerPreludeBindings_after_parameters

structure RecognizerChartEntry
    (layout : WorkspaceLayout) (values : List Int)
    (workspaceCell : CellId) (before : State) where
  indexCell : CellId
  indexCellEq : indexCell = before.nextCell + 4
  invariant : RecognizerChartClearInvariant layout values workspaceCell
    indexCell (recognizerPreludeState before layout) 0

/-- Materialize the chart-clear loop boundary from the five scalar locals in
    the recognizer prelude.  Only the parameter/workspace separation belongs
    to the caller; every scalar cell and its non-aliasing facts are derived
    from ordinary fresh `let` allocation. -/
noncomputable def makeRecognizerChartEntry
    (entry : RecognizerEntryResources grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before) :
    RecognizerChartEntry workspaceLayout workspaceValues workspaceCell
      before := by
  let bindings := recognizerPreludeBindings workspaceLayout
  let after := recognizerPreludeState before workspaceLayout
  let indexCell := before.nextCell + 4
  have afterResources := entry.prelude_resources
  have indexOwned : (Assertion.localPointsTo 10 indexCell
      (some (.signed .i32 0))).holds after := by
    simpa [after, bindings, recognizerPreludeState,
      recognizerPreludeBindings, indexCell] using
      bindLocals_owns_binding before (bindings.take 4) [] 10
        (.signed .i32 0) entry.resources.wellFormed (by simp)
  have indexDistinct : indexCell ≠ workspaceCell := by
    intro same
    have old := StateWellFormed.cell_lt_next_of_entry
      entry.resources.wellFormed entry.resources.workspaceBacking
    rw [← same] at old
    change before.nextCell + 4 < before.nextCell at old
    exact (Nat.not_lt_of_ge (Nat.le_add_right before.nextCell 4)) old
  have workspaceSeparate : CellSet.Disjoint
      (localBindingFrameFootprint after
        verifiedParserChartClearPersistentBindings)
      (CellSet.singleton workspaceCell) := by
    apply localBindingFrameFootprint_disjoint_singleton
    intro id member
    have persistent := (ChartClearPersistentLocal_source_frame id).mpr member
    by_cases oldId : id ≤ 5
    · have notRebound : ∀ binding, binding ∈ bindings →
          binding.1 ≠ id := by
        intro binding bindingMember
        have idMember : binding.1 ∈ bindings.map Prod.fst :=
          List.mem_map_of_mem bindingMember
        have cases : binding.1 = 6 ∨ binding.1 = 7 ∨ binding.1 = 8 ∨
            binding.1 = 9 ∨ binding.1 = 10 := by
          simpa [bindings, recognizerPreludeBindings] using idMember
        rcases cases with same | same | same | same | same
        · rw [same]
          exact Nat.ne_of_gt (Nat.lt_of_le_of_lt oldId (by decide : 5 < 6))
        · rw [same]
          exact Nat.ne_of_gt (Nat.lt_of_le_of_lt oldId (by decide : 5 < 7))
        · rw [same]
          exact Nat.ne_of_gt (Nat.lt_of_le_of_lt oldId (by decide : 5 < 8))
        · rw [same]
          exact Nat.ne_of_gt (Nat.lt_of_le_of_lt oldId (by decide : 5 < 9))
        · rw [same]
          exact Nat.ne_of_gt (Nat.lt_of_le_of_lt oldId (by decide : 5 < 10))
      change (before.bindLocals bindings).cellId? id ≠ some workspaceCell
      rw [bindLocals_preserves_cellId before bindings id notRebound]
      apply entry.parameterWorkspaceSeparate.localCell_ne_of_singleton
      apply (show id ∈ verifiedParserRecognizerParameterIds from ?_)
      exact (mem_verifiedParserRecognizerParameterIds_iff id).mpr oldId
    · have choices : id = 6 ∨ id = 8 ∨ id = 9 := by
        unfold ChartClearPersistentLocal at persistent
        rcases persistent with parameter | shared
        · have parameterBound :=
            (mem_verifiedParserRecognizerParameterIds_iff id).mp parameter
          exact False.elim (oldId parameterBound)
        · rw [mem_verifiedParserChartClearSharedFrameIds_iff] at shared
          rcases shared with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
            simp_all
      have old := StateWellFormed.cell_lt_next_of_entry
        entry.resources.wellFormed entry.resources.workspaceBacking
      rcases choices with rfl | rfl | rfl
      · simp [after, recognizerPreludeState,
          recognizerPreludeBindings, State.bindLocals, State.bindLocal,
          State.bindCell, State.cellId?]
        intro same
        rw [← same] at old
        exact (Nat.not_lt_of_ge (Nat.le_add_right before.nextCell 0)) old
      · simp [after, recognizerPreludeState,
          recognizerPreludeBindings, State.bindLocals, State.bindLocal,
          State.bindCell, State.cellId?]
        intro same
        rw [← same] at old
        exact (Nat.not_lt_of_ge (Nat.le_add_right before.nextCell 2)) old
      · simp [after, recognizerPreludeState,
          recognizerPreludeBindings, State.bindLocals, State.bindLocal,
          State.bindCell, State.cellId?]
        intro same
        rw [← same] at old
        exact (Nat.not_lt_of_ge (Nat.le_add_right before.nextCell 3)) old
  have indexSeparate : CellSet.Disjoint
      (localBindingFrameFootprint after
        verifiedParserChartClearPersistentBindings)
      (CellSet.singleton indexCell) := by
    let beforeIndex := before.bindLocals (bindings.take 4)
    have beforeIndexWellFormed := bindLocals_preserves_wellFormed before
      (bindings.take 4) entry.resources.wellFormed
    have fresh := bindLocal_fresh_disjoint_from_frame beforeIndex 10
      (.signed .i32 0) verifiedParserChartClearPersistentBindings
      beforeIndexWellFormed (by
        simp [LocalBindingFrame.ContainsCoreId,
          verifiedParserChartClearPersistentBindings_core_ids])
    have beforeIndexNext : beforeIndex.nextCell = indexCell := by
      simp [beforeIndex, indexCell, bindings, recognizerPreludeBindings,
        bindLocals_nextCell]
    change CellSet.Disjoint
      (localBindingFrameFootprint
        (beforeIndex.bindLocal 10 (.signed .i32 0))
        verifiedParserChartClearPersistentBindings)
      (CellSet.singleton indexCell)
    rw [← beforeIndexNext]
    exact fresh
  exact {
    indexCell := indexCell
    indexCellEq := rfl
    invariant := {
      valuesLength := entry.resources.workspaceLength
      wellFormed := afterResources.wellFormed
      workspaceLocal := afterResources.workspaceLocal
      workspaceLengthLocal := afterResources.workspaceLengthLocal
      stateBaseLocal := by
        simpa [after, bindings, recognizerPreludeState,
          recognizerPreludeBindings] using
          bindLocals_local_of_binding before (bindings.take 2)
            (bindings.drop 3) 8
            (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
            entry.resources.wellFormed
            (by simp [bindings, recognizerPreludeBindings])
      stateCapacityLocal := by
        simpa [after, bindings, recognizerPreludeState,
          recognizerPreludeBindings] using
          bindLocals_local_of_binding before (bindings.take 3)
            (bindings.drop 4) 9
            (.signed .i32 (Int.ofNat workspaceLayout.capacity))
            entry.resources.wellFormed
            (by simp [bindings, recognizerPreludeBindings])
      finalPositionLocal := by
        simpa [after, bindings, recognizerPreludeState,
          recognizerPreludeBindings] using
          bindLocals_local_of_binding before [] (bindings.drop 1) 6
            (.signed .i32
              (Int.ofNat (finalPosition workspaceLayout.tokenCount)))
            entry.resources.wellFormed
            (by simp [bindings, recognizerPreludeBindings])
      workspaceBacking := afterResources.workspaceBacking
      indexOwned := indexOwned
      indexLe := by simp
      indexDistinct := indexDistinct
      persistentSeparate := by
        intro cell framed written
        rcases written with workspaceWritten | indexWritten
        · exact workspaceSeparate cell framed workspaceWritten
        · exact indexSeparate cell framed indexWritten
      cleared := by simp
    }
  }

def recognizerSetupBindings (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (first count : Nat) : List (VarId × Value) := [
  (11, .signed .i32 (Int.ofNat grammar.grammar.n_kinds)),
  (12, .signed .i32 (Int.ofNat grammar.grammar.start_nonterminal)),
  (13, .signed .i32 (Int.ofNat layout.lhsOffsetsOffset)),
  (14, .signed .i32 (Int.ofNat layout.lhsCountsOffset)),
  (15, .signed .i32 (Int.ofNat layout.lhsProductionsOffset)),
  (16, .signed .i32 (Int.ofNat first)),
  (17, .signed .i32 (Int.ofNat count)),
  (18, .signed .i32 0),
  (19, .signed .i32 0)]

def recognizerSetupState (before : State) (layout : PackedGrammarLayout)
    (grammar : IndexedGrammar) (first count : Nat) : State :=
  before.bindLocals (recognizerSetupBindings layout grammar first count)

theorem recognizerSetupBindings_id_range
    (binding : VarId × Value)
    (member : binding ∈ recognizerSetupBindings layout grammar first count) :
    11 ≤ binding.1 ∧ binding.1 ≤ 19 := by
  have idMember : binding.1 ∈
      (recognizerSetupBindings layout grammar first count).map Prod.fst :=
    List.mem_map_of_mem member
  have cases : binding.1 = 11 ∨ binding.1 = 12 ∨ binding.1 = 13 ∨
      binding.1 = 14 ∨ binding.1 = 15 ∨ binding.1 = 16 ∨
      binding.1 = 17 ∨ binding.1 = 18 ∨ binding.1 = 19 := by
    simpa [recognizerSetupBindings] using idMember
  rcases cases with h | h | h | h | h | h | h | h | h <;> simp_all

structure RecognizerSetupEntry
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId) (before : State) where
  first : Nat
  count : Nat
  startBound : grammar.grammar.start_nonterminal <
    grammar.productionsByLhs.length
  firstEq : first = grammar.lhsOffsets.get
    ⟨grammar.grammar.start_nonterminal, by
      simpa [IndexedGrammar.lhsOffsets_length] using startBound⟩
  countEq : count = grammar.lhsCounts.get
    ⟨grammar.grammar.start_nonterminal, by
      simpa [IndexedGrammar.lhsCounts_length] using startBound⟩
  stateCountCell : CellId
  indexCell : CellId
  stateCountCellEq : stateCountCell = before.nextCell + 7
  indexCellEq : indexCell = before.nextCell + 8
  invariant : RecognizerInitialLoopInvariant grammarLayout grammar words tokens
    workspaceLayout emptyWorkspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell indexCell
    (recognizerSetupState before grammarLayout grammar first count) first count 0

noncomputable def makeRecognizerSetupEntry
    (recognizer : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout emptyWorkspace workspaceValues grammarCell tokensCell
      workspaceCell before)
    (clear : RecognizerChartClearInvariant workspaceLayout workspaceValues
      workspaceCell clearIndexCell before (stateBase workspaceLayout.tokenCount)) :
    RecognizerSetupEntry grammarLayout grammar words tokens workspaceLayout
      workspaceValues grammarCell tokensCell workspaceCell before := by
  let start := grammar.grammar.start_nonterminal
  have startBound : start < grammar.productionsByLhs.length := by
    simpa [start, recognizer.grammarWellFormed.lhsIndexCount] using
      recognizer.grammarWellFormed.startInBounds
  let rowId : Fin grammar.productionsByLhs.length := ⟨start, startBound⟩
  let first := grammar.lhsOffsets.get
    ⟨start, by simpa [IndexedGrammar.lhsOffsets_length] using startBound⟩
  let count := grammar.lhsCounts.get
    ⟨start, by simpa [IndexedGrammar.lhsCounts_length] using startBound⟩
  let bindings := recognizerSetupBindings grammarLayout grammar first count
  let after := recognizerSetupState before grammarLayout grammar first count
  have afterWellFormed : StateWellFormed after := by
    exact bindLocals_preserves_wellFormed before bindings recognizer.wellFormed
  have afterRecognizer : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout emptyWorkspace workspaceValues grammarCell tokensCell
      workspaceCell after := by
    exact recognizer.after_bind_locals bindings (by
      intro binding member
      have range := recognizerSetupBindings_id_range binding (by
        simpa [bindings] using member)
      obtain ⟨lower, upper⟩ := range
      exact Nat.lt_of_lt_of_le (by decide : 5 < 11) lower)
  let stateCountCell := before.nextCell + 7
  let indexCell := before.nextCell + 8
  have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 0))).holds after := by
    simpa [after, bindings, recognizerSetupState, recognizerSetupBindings, stateCountCell] using
      bindLocals_owns_binding before (bindings.take 7)
        [(19, .signed .i32 0)] 18 (.signed .i32 0) recognizer.wellFormed
        (by simp)
  have indexOwned : (Assertion.localPointsTo 19 indexCell
      (some (.signed .i32 0))).holds after := by
    simpa [after, bindings, recognizerSetupState, recognizerSetupBindings, indexCell] using
      bindLocals_owns_binding before (bindings.take 8) [] 19
        (.signed .i32 0) recognizer.wellFormed (by simp)
  have stateCountParameterSeparate :
      RecognizerParameterFrameSeparated after stateCountCell := by
    apply localBindingFrameFootprint_disjoint_singleton
    intro id member
    have idLe := (mem_verifiedParserRecognizerParameterIds_iff id).mp member
    have notRebound : ∀ binding, binding ∈ bindings → binding.1 ≠ id := by
      intro binding bindingMember
      have range := recognizerSetupBindings_id_range binding (by
        simpa [bindings] using bindingMember)
      obtain ⟨lower, upper⟩ := range
      exact Nat.ne_of_gt (Nat.lt_of_le_of_lt idLe
        (Nat.lt_of_lt_of_le (by decide : 5 < 11) lower))
    change (before.bindLocals bindings).cellId? id ≠ some stateCountCell
    rw [bindLocals_preserves_cellId before bindings id notRebound]
    intro found
    have old := StateWellFormed.cell_lt_next_of_local_binding id
      stateCountCell recognizer.wellFormed found
    exact (Nat.not_lt_of_ge (by simp [stateCountCell])) old
  have stateCountDistinct : stateCountCell ≠ grammarCell ∧
      stateCountCell ≠ tokensCell ∧ stateCountCell ≠ workspaceCell := by
    have grammarOld := StateWellFormed.cell_lt_next_of_entry
      recognizer.wellFormed recognizer.grammarBacking
    have tokensOld := StateWellFormed.cell_lt_next_of_entry
      recognizer.wellFormed recognizer.tokensBacking
    have workspaceOld := StateWellFormed.cell_lt_next_of_entry
      recognizer.wellFormed recognizer.workspaceBacking
    refine ⟨?_, ?_, ?_⟩
    · intro same
      have impossible := grammarOld
      rw [← same] at impossible
      change before.nextCell + 7 < before.nextCell at impossible
      exact (Nat.not_lt_of_ge (Nat.le_add_right before.nextCell 7)) impossible
    · intro same
      have impossible := tokensOld
      rw [← same] at impossible
      change before.nextCell + 7 < before.nextCell at impossible
      exact (Nat.not_lt_of_ge (Nat.le_add_right before.nextCell 7)) impossible
    · intro same
      have impossible := workspaceOld
      rw [← same] at impossible
      change before.nextCell + 7 < before.nextCell at impossible
      exact (Nat.not_lt_of_ge (Nat.le_add_right before.nextCell 7)) impossible
  have rowRange : first + count ≤ grammar.lhsProductions.length := by
    have fits := offsetsFrom_row_fits 0 grammar.productionsByLhs rowId
    simpa [first, count, rowId, IndexedGrammar.lhsOffsets,
      IndexedGrammar.lhsCounts, IndexedGrammar.lhsProductions] using fits
  let row := grammar.productionsByLhs.get rowId
  have rowFound : grammar.productionsByLhs[start]? = some row := by
    rw [List.getElem?_eq_getElem rowId.isLt]
    simp [row, rowId, List.get_eq_getElem]
  have countEq : count = row.length := by
    simpa [count, row, rowId] using grammar.lhsCounts_get rowId
  have rowProductionBound : ∀ (rowIndex : Nat) (rowIndexBound : rowIndex < count),
      grammar.lhsProductions.get ⟨first + rowIndex, by
        have := rowRange
        omega⟩ < grammar.productionCount := by
    intro rowIndex indexBound
    have indexRowBound : rowIndex < row.length := by
      simpa [countEq] using indexBound
    let indexId : Fin row.length := ⟨rowIndex, indexRowBound⟩
    have packedEq := grammar.lhsProductions_get_at_row rowId indexId
    have selectedMember : row.get indexId ∈ row := List.get_mem row indexId
    obtain ⟨selectedBound, _⟩ := recognizer.grammarWellFormed
      |>.nonterminal_validation.listedProductionValid start row
        recognizer.grammarWellFormed.startInBounds rowFound
        (row.get indexId) selectedMember
    have selectedEq : grammar.lhsProductions.get
        ⟨first + rowIndex, by have := rowRange; omega⟩ = row.get indexId := by
      simpa [first, row, rowId, indexId] using packedEq
    rw [selectedEq]
    exact selectedBound
  have persistentSeparate : InitialLoopFrameSeparated after workspaceCell
      stateCountCell indexCell := by
    unfold InitialLoopFrameSeparated
    intro cell framed written
    obtain ⟨id, member, found⟩ := framed
    have persistent := (InitialLoopPersistentLocal_source_frame id).mpr member
    have idLt := persistent.lt18
    rcases written with workspaceWritten | countOrIndex
    · have workspaceOld := StateWellFormed.cell_lt_next_of_entry
        recognizer.wellFormed recognizer.workspaceBacking
      change cell = workspaceCell at workspaceWritten
      subst cell
      by_cases oldId : id ≤ 9
      · have notRebound : ∀ binding, binding ∈ bindings →
            binding.1 ≠ id := by
          intro binding bindingMember
          have range := recognizerSetupBindings_id_range binding (by
            simpa [bindings] using bindingMember)
          obtain ⟨lower, upper⟩ := range
          exact Nat.ne_of_gt (Nat.lt_of_le_of_lt oldId
            (Nat.lt_of_lt_of_le (by decide : 9 < 11) lower))
        have beforeFound : before.cellId? id = some workspaceCell := by
          rw [← bindLocals_preserves_cellId before bindings id notRebound]
          simpa [after, recognizerSetupState] using found
        apply clear.persistentSeparate workspaceCell
        · refine ⟨id, ?_, beforeFound⟩
          apply (ChartClearPersistentLocal_source_frame id).mp
          unfold InitialLoopPersistentLocal at persistent
          unfold ChartClearPersistentLocal
          rcases persistent with parameter | shared
          · exact Or.inl parameter
          · rw [mem_verifiedParserInitialLoopSharedFrameIds_iff] at shared
            rw [mem_verifiedParserChartClearSharedFrameIds_iff]
            rcases shared with rfl | rfl | rfl | rfl | rfl | rfl | rfl |
              rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> simp_all
        · exact Or.inl rfl
      · have choices : id = 11 ∨ id = 12 ∨ id = 13 ∨ id = 14 ∨
            id = 15 ∨ id = 16 ∨ id = 17 := by
          unfold InitialLoopPersistentLocal at persistent
          rcases persistent with parameter | shared
          · have := (mem_verifiedParserRecognizerParameterIds_iff id).mp parameter
            exact False.elim (oldId (Nat.le_trans this (by decide : 5 ≤ 9)))
          · rw [mem_verifiedParserInitialLoopSharedFrameIds_iff] at shared
            rcases shared with rfl | rfl | rfl | rfl | rfl | rfl | rfl |
              rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> simp_all
        have freshNotWorkspace : ∀ offset,
            before.nextCell + offset ≠ workspaceCell := by
          intro offset same
          have impossible := workspaceOld
          rw [← same] at impossible
          exact (Nat.not_lt_of_ge (Nat.le_add_right before.nextCell offset))
            impossible
        rcases choices with rfl | rfl | rfl | rfl | rfl | rfl | rfl
        · apply freshNotWorkspace 0
          simpa [after, bindings, recognizerSetupState, recognizerSetupBindings, State.bindLocals,
            State.bindLocal, State.bindCell, State.cellId?] using found
        · apply freshNotWorkspace 1
          simpa [after, bindings, recognizerSetupState, recognizerSetupBindings, State.bindLocals,
            State.bindLocal, State.bindCell, State.cellId?] using found
        · apply freshNotWorkspace 2
          simpa [after, bindings, recognizerSetupState, recognizerSetupBindings, State.bindLocals,
            State.bindLocal, State.bindCell, State.cellId?, Nat.add_assoc] using found
        · apply freshNotWorkspace 3
          simpa [after, bindings, recognizerSetupState, recognizerSetupBindings, State.bindLocals,
            State.bindLocal, State.bindCell, State.cellId?, Nat.add_assoc] using found
        · apply freshNotWorkspace 4
          simpa [after, bindings, recognizerSetupState, recognizerSetupBindings, State.bindLocals,
            State.bindLocal, State.bindCell, State.cellId?, Nat.add_assoc] using found
        · apply freshNotWorkspace 5
          simpa [after, bindings, recognizerSetupState, recognizerSetupBindings, State.bindLocals,
            State.bindLocal, State.bindCell, State.cellId?, Nat.add_assoc] using found
        · apply freshNotWorkspace 6
          simpa [after, bindings, recognizerSetupState, recognizerSetupBindings, State.bindLocals,
            State.bindLocal, State.bindCell, State.cellId?, Nat.add_assoc] using found
    · rcases countOrIndex with countWritten | indexWritten
      · have state17WellFormed := bindLocals_preserves_wellFormed before
          (bindings.take 7) recognizer.wellFormed
        have countDisjoint := bindLocal_fresh_disjoint_from_frame
          (before.bindLocals (bindings.take 7)) 18 (.signed .i32 0)
          verifiedParserInitialLoopPersistentBindings state17WellFormed
          (by
            simp [LocalBindingFrame.ContainsCoreId,
              verifiedParserInitialLoopPersistentBindings_core_ids])
        change cell = stateCountCell at countWritten
        subst cell
        apply countDisjoint stateCountCell
        · refine ⟨id, member, ?_⟩
          have afterSplit : after =
              (before.bindLocals (bindings.take 8)).bindLocals
                (bindings.drop 8) := by
            rw [← bindLocals_append]
            simp [after, recognizerSetupState, bindings]
          rw [afterSplit] at found
          rw [bindLocals_preserves_cellId
            (before.bindLocals (bindings.take 8)) (bindings.drop 8) id] at found
          · simpa [bindings, recognizerSetupBindings, State.bindLocals] using found
          · intro binding bindingMember
            have idMember : binding.1 ∈
                (bindings.drop 8).map Prod.fst :=
              List.mem_map_of_mem bindingMember
            have same : binding.1 = 19 := by
              simpa [bindings, recognizerSetupBindings] using idMember
            rw [same]
            exact Nat.ne_of_gt (Nat.lt_trans idLt (by decide : 18 < 19))
        · simp [CellSet.singleton, stateCountCell, bindings, recognizerSetupBindings,
            bindLocals_nextCell]
      · have state18WellFormed := bindLocals_preserves_wellFormed before
          (bindings.take 8) recognizer.wellFormed
        have indexDisjoint := bindLocal_fresh_disjoint_from_frame
          (before.bindLocals (bindings.take 8)) 19 (.signed .i32 0)
          verifiedParserInitialLoopPersistentBindings state18WellFormed
          (by
            simp [LocalBindingFrame.ContainsCoreId,
              verifiedParserInitialLoopPersistentBindings_core_ids])
        change cell = indexCell at indexWritten
        subst cell
        apply indexDisjoint indexCell ⟨id, member, found⟩
        simp [CellSet.singleton, indexCell, bindings, recognizerSetupBindings,
          bindLocals_nextCell]
  exact {
    first := first
    count := count
    startBound := startBound
    firstEq := by simp [first, start]
    countEq := by simp [count, start]
    stateCountCell := stateCountCell
    indexCell := indexCell
    stateCountCellEq := rfl
    indexCellEq := rfl
    invariant := {
      frame := {
        recognizer := afterRecognizer
        positionBound := by simp
        stateBaseLocal := bindLocals_preserves_local before bindings 8 _
          recognizer.wellFormed clear.stateBaseLocal (by
            intro binding member
            have range := recognizerSetupBindings_id_range binding (by
              simpa [bindings] using member)
            obtain ⟨lower, upper⟩ := range
            exact Nat.ne_of_gt (Nat.lt_of_lt_of_le (by decide : 8 < 11)
              lower))
        stateCapacityLocal :=
          bindLocals_preserves_local before bindings 9 _
            recognizer.wellFormed clear.stateCapacityLocal (by
              intro binding member
              have range := recognizerSetupBindings_id_range binding (by
                simpa [bindings] using member)
              obtain ⟨lower, upper⟩ := range
              exact Nat.ne_of_gt (Nat.lt_of_lt_of_le (by decide : 9 < 11)
                lower))
        stateCountLocal := Assertion.localPointsTo_local 18 stateCountCell _
          after stateCountOwned
        stateCountOwned := stateCountOwned
        stateCountBackingDistinct := stateCountDistinct
        stateCountParameterSeparate := stateCountParameterSeparate
      }
      workspaceWithinGrammar := emptyWorkspace_withinGrammar grammar
      finalPositionLocal :=
        bindLocals_preserves_local before bindings 6 _ recognizer.wellFormed
          clear.finalPositionLocal (by
            intro binding member
            have range := recognizerSetupBindings_id_range binding (by
              simpa [bindings] using member)
            obtain ⟨lower, upper⟩ := range
            exact Nat.ne_of_gt (Nat.lt_of_lt_of_le (by decide : 6 < 11)
              lower))
      kindCountLocal := by
        simpa [after, bindings, recognizerSetupState, recognizerSetupBindings] using
          bindLocals_local_of_binding before [] (bindings.drop 1) 11
            (.signed .i32 (Int.ofNat grammar.grammar.n_kinds))
            recognizer.wellFormed (by simp [bindings, recognizerSetupBindings])
      startNonterminalLocal := by
        simpa [after, bindings, recognizerSetupState, recognizerSetupBindings] using
          bindLocals_local_of_binding before (bindings.take 1)
            (bindings.drop 2) 12
            (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal))
            recognizer.wellFormed (by simp [bindings, recognizerSetupBindings])
      lhsOffsetsOffsetLocal := by
        simpa [after, bindings, recognizerSetupState, recognizerSetupBindings] using
          bindLocals_local_of_binding before (bindings.take 2)
            (bindings.drop 3) 13
            (.signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset))
            recognizer.wellFormed (by simp [bindings, recognizerSetupBindings])
      lhsCountsOffsetLocal := by
        simpa [after, bindings, recognizerSetupState, recognizerSetupBindings] using
          bindLocals_local_of_binding before (bindings.take 3)
            (bindings.drop 4) 14
            (.signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset))
            recognizer.wellFormed (by simp [bindings, recognizerSetupBindings])
      lhsProductionsOffsetLocal := by
        simpa [after, bindings, recognizerSetupState, recognizerSetupBindings] using
          bindLocals_local_of_binding before (bindings.take 4)
            (bindings.drop 5) 15
            (.signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset))
            recognizer.wellFormed (by simp [bindings, recognizerSetupBindings])
      firstLocal := by
        simpa [after, bindings, recognizerSetupState, recognizerSetupBindings] using
          bindLocals_local_of_binding before (bindings.take 5)
            (bindings.drop 6) 16 (.signed .i32 (Int.ofNat first))
            recognizer.wellFormed (by simp [bindings, recognizerSetupBindings])
      countLocal := by
        simpa [after, bindings, recognizerSetupState, recognizerSetupBindings] using
          bindLocals_local_of_binding before (bindings.take 6)
            (bindings.drop 7) 17 (.signed .i32 (Int.ofNat count))
            recognizer.wellFormed (by simp [bindings, recognizerSetupBindings])
      indexOwned := by simpa [indexCell] using indexOwned
      indexLe := by simp
      rowRange := rowRange
      rowProductionBound := rowProductionBound
      persistentSeparate := persistentSeparate
      indexBackingDistinct := by
        have grammarOld := StateWellFormed.cell_lt_next_of_entry
          recognizer.wellFormed recognizer.grammarBacking
        have tokensOld := StateWellFormed.cell_lt_next_of_entry
          recognizer.wellFormed recognizer.tokensBacking
        have workspaceOld := StateWellFormed.cell_lt_next_of_entry
          recognizer.wellFormed recognizer.workspaceBacking
        refine ⟨?_, ?_, ?_, ?_⟩
        · intro same
          have impossible := grammarOld
          rw [← same] at impossible
          change before.nextCell + 8 < before.nextCell at impossible
          exact (Nat.not_lt_of_ge (Nat.le_add_right before.nextCell 8)) impossible
        · intro same
          have impossible := tokensOld
          rw [← same] at impossible
          change before.nextCell + 8 < before.nextCell at impossible
          exact (Nat.not_lt_of_ge (Nat.le_add_right before.nextCell 8)) impossible
        · intro same
          have impossible := workspaceOld
          rw [← same] at impossible
          change before.nextCell + 8 < before.nextCell at impossible
          exact (Nat.not_lt_of_ge (Nat.le_add_right before.nextCell 8)) impossible
        · simp [indexCell, stateCountCell]
    }
  }

/-- Execution of the artifact-derived recognizer setup and its complete
    seeding/position/root continuation.  The result deliberately hides the
    fresh lexical cells: they are scoped implementation details restored by
    the extracted `let` semantics. -/
structure RecognizerSetupExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId) (before : State) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before
    parserRecognizeSeedSetupStatement completion after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  finalWorkspace : LogicalWorkspace
  finalWorkspaceValues : List Int
  growth : WorkspaceAppendClosure workspaceLayout.capacity emptyWorkspace
    finalWorkspace
  workspaceArtifact : RecognizerWorkspaceArtifact workspaceLayout
    finalWorkspace finalWorkspaceValues workspaceCell after
  outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
    tokens workspaceLayout completion

/-- Evaluate the exact nested setup statements selected from the extracted
    recognizer, then enter the verified start-production loop. -/
noncomputable def executeRecognizerSetup
    (recognizer : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout emptyWorkspace workspaceValues grammarCell tokensCell
      workspaceCell before)
    (clear : RecognizerChartClearInvariant workspaceLayout workspaceValues
      workspaceCell clearIndexCell before (stateBase workspaceLayout.tokenCount)) :
    RecognizerSetupExecution grammarLayout grammar words tokens workspaceLayout
      workspaceValues grammarCell tokensCell workspaceCell before := by
  let entry := makeRecognizerSetupEntry recognizer clear
  obtain ⟨constant8, _, _, constant11, _, _⟩ :=
    verifiedParser_count_header_constants
  obtain ⟨_, _, _, _, _, constant20, constant21, constant22⟩ :=
    verifiedParser_range_header_constants
  let r1 := before.bindLocal 11
    (.signed .i32 (Int.ofNat grammar.grammar.n_kinds))
  let recognizer1 := recognizer.after_bind_local 11
    (.signed .i32 (Int.ofNat grammar.grammar.n_kinds))
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
  let r2 := r1.bindLocal 12
    (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal))
  let recognizer2 := recognizer1.after_bind_local 12
    (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal))
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
  let r3 := r2.bindLocal 13
    (.signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset))
  let recognizer3 := recognizer2.after_bind_local 13
    (.signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset))
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
  let r4 := r3.bindLocal 14
    (.signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset))
  let recognizer4 := recognizer3.after_bind_local 14
    (.signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset))
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
  let r5 := r4.bindLocal 15
    (.signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset))
  let recognizer5 := recognizer4.after_bind_local 15
    (.signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset))
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
  have startAtR5 : r5.local? 12 = some
      (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal)) := by
    have atR2 := bindLocal_finds_local r1 12
      (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal))
      recognizer1.wellFormed
    have atR3 := (bindLocal_preserves_other_local recognizer2.wellFormed
      (boundId := 13) (queriedId := 12) (value :=
        .signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset))
      (by decide)).trans atR2
    have atR4 := (bindLocal_preserves_other_local recognizer3.wellFormed
      (boundId := 14) (queriedId := 12) (value :=
        .signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset))
      (by decide)).trans atR3
    exact (bindLocal_preserves_other_local recognizer4.wellFormed
      (boundId := 15) (queriedId := 12) (value :=
        .signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset))
      (by decide)).trans atR4
  have offsetsAtR5 : r5.local? 13 = some
      (.signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset)) := by
    have atR3 := bindLocal_finds_local r2 13
      (.signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset))
      recognizer2.wellFormed
    have atR4 := (bindLocal_preserves_other_local recognizer3.wellFormed
      (boundId := 14) (queriedId := 13) (value :=
        .signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset))
      (by decide)).trans atR3
    exact (bindLocal_preserves_other_local recognizer4.wellFormed
      (boundId := 15) (queriedId := 13) (value :=
        .signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset))
      (by decide)).trans atR4
  have countsAtR5 : r5.local? 14 = some
      (.signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset)) := by
    have atR4 := bindLocal_finds_local r3 14
      (.signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset))
      recognizer3.wellFormed
    exact (bindLocal_preserves_other_local recognizer4.wellFormed
      (boundId := 15) (queriedId := 14) (value :=
        .signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset))
      (by decide)).trans atR4
  have kindEvaluation := recognizer.read_packed_header 8 1
    grammar.grammar.n_kinds recognizer.grammarEncoded.kindCount constant8
  have startEvaluation := recognizer1.read_packed_header 11 4
    grammar.grammar.start_nonterminal
    recognizer.grammarEncoded.startNonterminal constant11
  have offsetsEvaluation := recognizer2.read_packed_header 20 13
    grammarLayout.lhsOffsetsOffset recognizer.grammarEncoded.lhsOffsetsOffset
    constant20
  have countsEvaluation := recognizer3.read_packed_header 21 14
    grammarLayout.lhsCountsOffset recognizer.grammarEncoded.lhsCountsOffset
    constant21
  have productionsEvaluation := recognizer4.read_packed_header 22 15
    grammarLayout.lhsProductionsOffset
    recognizer.grammarEncoded.lhsProductionsOffset constant22
  have firstEvaluation : Evaluates verifiedParserCore r5
      (.index (.local 0) (.binary .add (.local 13) (.local 12)))
      (.signed .i32 (Int.ofNat entry.first)) r5 := by
    have read := recognizer5.read_packed_nat_table 13 12
      grammarLayout.lhsOffsetsOffset grammar.grammar.start_nonterminal
      grammar.lhsOffsets recognizer.grammarEncoded.lhsOffsets offsetsAtR5
      startAtR5 (by
        simpa [IndexedGrammar.lhsOffsets_length] using entry.startBound)
    simpa [r5, r4, r3, r2, r1, entry.firstEq] using read
  let r6 := r5.bindLocal 16 (.signed .i32 (Int.ofNat entry.first))
  let recognizer6 := recognizer5.after_bind_local 16
    (.signed .i32 (Int.ofNat entry.first))
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
  have startAtR6 : r6.local? 12 = some
      (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal)) :=
    (bindLocal_preserves_other_local recognizer5.wellFormed
      (boundId := 16) (queriedId := 12) (value :=
        .signed .i32 (Int.ofNat entry.first)) (by decide)).trans startAtR5
  have countsAtR6 : r6.local? 14 = some
      (.signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset)) :=
    (bindLocal_preserves_other_local recognizer5.wellFormed
      (boundId := 16) (queriedId := 14) (value :=
        .signed .i32 (Int.ofNat entry.first)) (by decide)).trans countsAtR5
  have countEvaluation : Evaluates verifiedParserCore r6
      (.index (.local 0) (.binary .add (.local 14) (.local 12)))
      (.signed .i32 (Int.ofNat entry.count)) r6 := by
    have read := recognizer6.read_packed_nat_table 14 12
      grammarLayout.lhsCountsOffset grammar.grammar.start_nonterminal
      grammar.lhsCounts recognizer.grammarEncoded.lhsCounts countsAtR6 startAtR6
      (by simpa [IndexedGrammar.lhsCounts_length] using entry.startBound)
    simpa [r6, r5, r4, r3, r2, r1, entry.countEq] using read
  let r7 := r6.bindLocal 17 (.signed .i32 (Int.ofNat entry.count))
  let r8 := r7.bindLocal 18 (.signed .i32 0)
  let r9 := r8.bindLocal 19 (.signed .i32 0)
  let continuation := entry.invariant.execute_continuation
  have continuationExecution : Executes verifiedParserCore r9
      parserRecognizeAfterInitialIndexBinding continuation.completion
      continuation.after := by
    simpa [r9, r8, r7, r6, r5, r4, r3, r2, r1,
      recognizerSetupState, recognizerSetupBindings, State.bindLocals] using
      continuation.execution
  let setupWrites : CellSet := CellSet.union
    (CellSet.singleton workspaceCell) (fun cell => before.nextCell ≤ cell)
  have continuationSubset : CellSet.Subset
      (recognizerInitialWrites workspaceCell entry.stateCountCell
        entry.indexCell) setupWrites := by
    intro cell written
    change cell = workspaceCell ∨
      cell = entry.stateCountCell ∨ cell = entry.indexCell at written
    change cell = workspaceCell ∨ before.nextCell ≤ cell
    rcases written with rfl | rfl | rfl
    · exact .inl rfl
    · exact .inr (by
        rw [entry.stateCountCellEq]
        exact Nat.le_add_right before.nextCell 7)
    · exact .inr (by
        rw [entry.indexCellEq]
        exact Nat.le_add_right before.nextCell 8)
  have continuationEffect : ModifiesOnly setupWrites r9
      continuation.after := by
    simpa [r9, r8, r7, r6, r5, r4, r3, r2, r1,
      recognizerSetupState, recognizerSetupBindings, State.bindLocals] using
      continuation.effect.weaken continuationSubset
  have wellFormed7 : StateWellFormed r7 :=
    bindLocal_preserves_well_formed r6 17 _ recognizer6.wellFormed
  have wellFormed8 : StateWellFormed r8 :=
    bindLocal_preserves_well_formed r7 18 _ wellFormed7
  have zeroAtR8 : Evaluates verifiedParserCore r8
      (.value (.signed .i32 0)) (.signed .i32 0) r8 := ⟨1, rfl⟩
  let closed19 := closesFreshLocalExcept (id := 19)
    (type := parserI32Type) setupWrites wellFormed8 zeroAtR8
    continuationExecution
    (continuationEffect.weaken CellSet.subset_union_left)
    continuation.wellFormed
  let after19 := closed19.after
  have execution19 : Executes verifiedParserCore r8
      parserRecognizeInitialIndexStatement continuation.completion after19 := by
    rw [extractedParserRecognize_initial_index_statement_shape]
    simpa [closed19, after19] using closed19.execution
  have effect19 : ModifiesOnly setupWrites r8 after19 := by
    simpa [after19] using closed19.effect
  have wellFormed19 : StateWellFormed after19 := by
    simpa [after19] using closed19.wellFormed
  have zeroAtR7 : Evaluates verifiedParserCore r7
      (.value (.signed .i32 0)) (.signed .i32 0) r7 := ⟨1, rfl⟩
  let closed18 := closesFreshLocalExcept (id := 18)
    (type := parserI32Type) setupWrites wellFormed7 zeroAtR7 execution19
    (effect19.weaken CellSet.subset_union_left) wellFormed19
  let after18 := closed18.after
  have execution18 : Executes verifiedParserCore r7
      parserRecognizeStateCountStatement continuation.completion after18 := by
    rw [extractedParserRecognize_state_count_statement_shape]
    simpa [closed18, after18] using closed18.execution
  have effect18 : ModifiesOnly setupWrites r7 after18 := by
    simpa [after18] using closed18.effect
  have wellFormed18 : StateWellFormed after18 := by
    simpa [after18] using closed18.wellFormed
  let closed17 := closesFreshLocalExcept (id := 17)
    (type := parserI32Type) setupWrites recognizer6.wellFormed countEvaluation
    execution18 (effect18.weaken CellSet.subset_union_left) wellFormed18
  let after17 := closed17.after
  have execution17 : Executes verifiedParserCore r6
      parserRecognizeStartCountStatement continuation.completion after17 := by
    rw [extractedParserRecognize_start_count_statement_shape]
    simpa [closed17, after17, r6, r5, r4, r3, r2, r1] using
      closed17.execution
  have effect17 : ModifiesOnly setupWrites r6 after17 := by
    simpa [after17, r6, r5, r4, r3, r2, r1] using closed17.effect
  have wellFormed17 : StateWellFormed after17 := by
    simpa [after17] using closed17.wellFormed
  let closed16 := closesFreshLocalExcept (id := 16)
    (type := parserI32Type) setupWrites recognizer5.wellFormed firstEvaluation
    execution17 (effect17.weaken CellSet.subset_union_left) wellFormed17
  let after16 := closed16.after
  have execution16 : Executes verifiedParserCore r5
      parserRecognizeStartFirstStatement continuation.completion after16 := by
    rw [extractedParserRecognize_start_first_statement_shape]
    simpa [closed16, after16, r5, r4, r3, r2, r1] using
      closed16.execution
  have effect16 : ModifiesOnly setupWrites r5 after16 := by
    simpa [after16, r5, r4, r3, r2, r1] using closed16.effect
  have wellFormed16 : StateWellFormed after16 := by
    simpa [after16] using closed16.wellFormed
  let closed15 := closesFreshLocalExcept (id := 15)
    (type := parserI32Type) setupWrites recognizer4.wellFormed
    productionsEvaluation execution16
    (effect16.weaken CellSet.subset_union_left) wellFormed16
  let after15 := closed15.after
  have execution15 : Executes verifiedParserCore r4
      parserRecognizeLhsProductionsStatement continuation.completion after15 := by
    rw [extractedParserRecognize_lhs_productions_statement_shape]
    simpa [closed15, after15, r4, r3, r2, r1] using closed15.execution
  have effect15 : ModifiesOnly setupWrites r4 after15 := by
    simpa [after15, r4, r3, r2, r1] using closed15.effect
  have wellFormed15 : StateWellFormed after15 := by
    simpa [after15] using closed15.wellFormed
  let closed14 := closesFreshLocalExcept (id := 14)
    (type := parserI32Type) setupWrites recognizer3.wellFormed
    countsEvaluation execution15
    (effect15.weaken CellSet.subset_union_left) wellFormed15
  let after14 := closed14.after
  have execution14 : Executes verifiedParserCore r3
      parserRecognizeLhsCountsStatement continuation.completion after14 := by
    rw [extractedParserRecognize_lhs_counts_statement_shape]
    simpa [closed14, after14, r3, r2, r1] using closed14.execution
  have effect14 : ModifiesOnly setupWrites r3 after14 := by
    simpa [after14, r3, r2, r1] using closed14.effect
  have wellFormed14 : StateWellFormed after14 := by
    simpa [after14] using closed14.wellFormed
  let closed13 := closesFreshLocalExcept (id := 13)
    (type := parserI32Type) setupWrites recognizer2.wellFormed
    offsetsEvaluation execution14
    (effect14.weaken CellSet.subset_union_left) wellFormed14
  let after13 := closed13.after
  have execution13 : Executes verifiedParserCore r2
      parserRecognizeLhsOffsetsStatement continuation.completion after13 := by
    rw [extractedParserRecognize_lhs_offsets_statement_shape]
    simpa [closed13, after13, r2, r1] using closed13.execution
  have effect13 : ModifiesOnly setupWrites r2 after13 := by
    simpa [after13, r2, r1] using closed13.effect
  have wellFormed13 : StateWellFormed after13 := by
    simpa [after13] using closed13.wellFormed
  let closed12 := closesFreshLocalExcept (id := 12)
    (type := parserI32Type) setupWrites recognizer1.wellFormed startEvaluation
    execution13 (effect13.weaken CellSet.subset_union_left) wellFormed13
  let after12 := closed12.after
  have execution12 : Executes verifiedParserCore r1
      parserRecognizeStartNonterminalStatement continuation.completion
      after12 := by
    rw [extractedParserRecognize_start_nonterminal_statement_shape]
    simpa [closed12, after12, r1] using closed12.execution
  have effect12 : ModifiesOnly setupWrites r1 after12 := by
    simpa [after12, r1] using closed12.effect
  have wellFormed12 : StateWellFormed after12 := by
    simpa [after12] using closed12.wellFormed
  let closed11 := closesFreshLocalExcept (id := 11)
    (type := parserI32Type) setupWrites recognizer.wellFormed kindEvaluation
    execution12 (effect12.weaken CellSet.subset_union_left) wellFormed12
  let after11 := closed11.after
  have execution11 : Executes verifiedParserCore before
      parserRecognizeSeedSetupStatement continuation.completion after11 := by
    rw [extractedParserRecognize_seed_setup_shape]
    simpa [closed11, after11] using closed11.execution
  have visibleEffect : ModifiesOnly (CellSet.singleton workspaceCell)
      before after11 := by
    apply closed11.effect.hideFreshWritesExcept
    intro cell written
    change cell = workspaceCell ∨ before.nextCell ≤ cell at written
    exact written
  have cells : after11.cells = continuation.after.cells := by
    simp [after11, closed11, after12, closed12, after13, closed13, after14,
      closed14, after15, closed15, after16, closed16, after17, closed17,
      after18, closed18, after19, closed19]
  exact {
    after := after11
    completion := continuation.completion
    execution := execution11
    effect := visibleEffect
    wellFormed := closed11.wellFormed
    finalWorkspace := continuation.finalWorkspace
    finalWorkspaceValues := continuation.finalWorkspaceValues
    growth := continuation.growth
    workspaceArtifact := continuation.workspaceArtifact.transfer_cells cells
    outcome := continuation.outcome
  }

/-- The chart-clear loop and semantic recognizer continuation, starting at
    the state after the five prelude scalars have been bound. -/
structure RecognizerChartContinuationExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId) (before : State) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore
    (recognizerPreludeState before workspaceLayout)
    (.sequence parserRecognizeChartClearLoop
      parserRecognizeSeedSetupStatement) completion after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton (before.nextCell + 4)))
    (recognizerPreludeState before workspaceLayout) after
  wellFormed : StateWellFormed after
  finalWorkspace : LogicalWorkspace
  finalWorkspaceValues : List Int
  growth : WorkspaceAppendClosure workspaceLayout.capacity emptyWorkspace
    finalWorkspace
  workspaceArtifact : RecognizerWorkspaceArtifact workspaceLayout
    finalWorkspace finalWorkspaceValues workspaceCell after
  outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
    tokens workspaceLayout completion

/-- Clear the caller's workspace prefix, reframe it as the empty logical
    Earley workspace, and immediately execute the already verified recognizer
    continuation. -/
noncomputable def executeRecognizerChartContinuation
    (entry : RecognizerEntryResources grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before) :
    RecognizerChartContinuationExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before := by
  let chartEntry := makeRecognizerChartEntry entry
  let clearExecution := chartEntry.invariant.execute_loop
  have indexGrammarDistinct : chartEntry.indexCell ≠ grammarCell := by
    intro same
    have old := StateWellFormed.cell_lt_next_of_entry
      entry.resources.wellFormed entry.resources.grammarBacking
    rw [← same, chartEntry.indexCellEq] at old
    exact (Nat.not_lt_of_ge (Nat.le_add_right before.nextCell 4)) old
  have indexTokensDistinct : chartEntry.indexCell ≠ tokensCell := by
    intro same
    have old := StateWellFormed.cell_lt_next_of_entry
      entry.resources.wellFormed entry.resources.tokensBacking
    rw [← same, chartEntry.indexCellEq] at old
    exact (Nat.not_lt_of_ge (Nat.le_add_right before.nextCell 4)) old
  have afterRecognizer := clearExecution.recognizer_invariant
    entry.prelude_resources indexGrammarDistinct indexTokensDistinct
  let setup := executeRecognizerSetup afterRecognizer clearExecution.invariant
  have setupWrites : CellSet.Subset (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton workspaceCell)
        (CellSet.singleton chartEntry.indexCell)) :=
    CellSet.subset_union_left
  exact {
    after := setup.after
    completion := setup.completion
    execution := executesSequence clearExecution.execution setup.execution
    effect := by
      rw [← chartEntry.indexCellEq]
      exact clearExecution.effect.trans_same
        (setup.effect.weaken setupWrites)
    wellFormed := setup.wellFormed
    finalWorkspace := setup.finalWorkspace
    finalWorkspaceValues := setup.finalWorkspaceValues
    growth := setup.growth
    workspaceArtifact := setup.workspaceArtifact
    outcome := setup.outcome
  }

/-- Execution of the complete recognizer body that follows successful grammar
    validation.  This theorem follows the extracted scalar prelude exactly:
    it checks the input bounds, computes the chart layout and state capacity,
    clears the chart prefix, and enters the verified semantic continuation. -/
structure RecognizerAfterGrammarExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId) (before : State) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before
    parserRecognizeAfterGrammarGuard completion after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  finalWorkspace : LogicalWorkspace
  finalWorkspaceValues : List Int
  growth : WorkspaceAppendClosure workspaceLayout.capacity emptyWorkspace
    finalWorkspace
  workspaceArtifact : RecognizerWorkspaceArtifact workspaceLayout
    finalWorkspace finalWorkspaceValues workspaceCell after
  outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
    tokens workspaceLayout completion

noncomputable def executeRecognizerAfterGrammarGuard
    (entry : RecognizerEntryResources grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before) :
    RecognizerAfterGrammarExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before := by
  have stateBaseBound : stateBase workspaceLayout.tokenCount ≤ 2147483647 :=
    stateBase_le_i32Max workspaceLayout.tokenBound
  have finalPositionBound :
      finalPosition workspaceLayout.tokenCount ≤ 2147483647 := by
    exact Nat.le_trans
      (Nat.le_of_lt (finalPosition_lt_stateBase workspaceLayout.tokenCount))
      stateBaseBound
  have chartCountBound :
      chartCount workspaceLayout.tokenCount ≤ 2147483647 := by
    have countLeBase : chartCount workspaceLayout.tokenCount ≤
        stateBase workspaceLayout.tokenCount := by
      simp only [stateBase, chartWords]
      omega
    exact Nat.le_trans countLeBase stateBaseBound
  have tokenEvaluation : Evaluates verifiedParserCore before (.local 3)
      (.signed .i32 (Int.ofNat workspaceLayout.tokenCount)) before := by
    rw [entry.resources.workspaceTokenCount]
    exact ⟨1, evalLocal_of_local 1 verifiedParserCore before 3 _
      entry.resources.tokenCountLocal⟩
  have twoEvaluation : Evaluates verifiedParserCore before
      (.value (.signed .i32 2)) (.signed .i32 2) before := ⟨1, rfl⟩
  have finalPositionEvaluation : Evaluates verifiedParserCore before
      (.binary .multiply (.local 3) (.value (.signed .i32 2)))
      (.signed .i32
        (Int.ofNat (finalPosition workspaceLayout.tokenCount))) before := by
    simpa [finalPosition] using evaluatesNatI32Multiply tokenEvaluation
      twoEvaluation finalPositionBound
  let r6 := before.bindLocal 6
    (.signed .i32 (Int.ofNat (finalPosition workspaceLayout.tokenCount)))
  have wellFormed6 : StateWellFormed r6 := by
    exact bindLocal_preserves_well_formed before 6 _ entry.resources.wellFormed
  have finalPositionLocal : r6.local? 6 = some
      (.signed .i32 (Int.ofNat (finalPosition workspaceLayout.tokenCount))) :=
    bindLocal_finds_local before 6 _ entry.resources.wellFormed
  have finalPositionLocalEvaluation : Evaluates verifiedParserCore r6 (.local 6)
      (.signed .i32
        (Int.ofNat (finalPosition workspaceLayout.tokenCount))) r6 :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore r6 6 _ finalPositionLocal⟩
  have oneEvaluation : Evaluates verifiedParserCore r6
      (.value (.signed .i32 1)) (.signed .i32 1) r6 := ⟨1, rfl⟩
  have chartCountEvaluation : Evaluates verifiedParserCore r6
      (.binary .add (.local 6) (.value (.signed .i32 1)))
      (.signed .i32 (Int.ofNat (chartCount workspaceLayout.tokenCount))) r6 := by
    simpa [chartCount] using evaluatesNatI32Add finalPositionLocalEvaluation
      oneEvaluation chartCountBound
  let r7 := r6.bindLocal 7
    (.signed .i32 (Int.ofNat (chartCount workspaceLayout.tokenCount)))
  have wellFormed7 : StateWellFormed r7 :=
    bindLocal_preserves_well_formed r6 7 _ wellFormed6
  have chartCountLocal : r7.local? 7 = some
      (.signed .i32 (Int.ofNat (chartCount workspaceLayout.tokenCount))) :=
    bindLocal_finds_local r6 7 _ wellFormed6
  have chartCountLocalEvaluation : Evaluates verifiedParserCore r7 (.local 7)
      (.signed .i32 (Int.ofNat (chartCount workspaceLayout.tokenCount))) r7 :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore r7 7 _ chartCountLocal⟩
  have chartWordsEvaluation : Evaluates verifiedParserCore r7 (.constant 24)
      (.signed .i32 2) r7 :=
    evaluatesConstant verifiedParser_workspace_constants.1
  have stateBaseEvaluation : Evaluates verifiedParserCore r7
      (.binary .multiply (.local 7) (.constant 24))
      (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))) r7 := by
    simpa [stateBase, chartWords] using
      evaluatesNatI32Multiply chartCountLocalEvaluation chartWordsEvaluation
        stateBaseBound
  let r8 := r7.bindLocal 8
    (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
  have wellFormed8 : StateWellFormed r8 :=
    bindLocal_preserves_well_formed r7 8 _ wellFormed7
  have stateBaseLocal : r8.local? 8 = some
      (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))) :=
    bindLocal_finds_local r7 8 _ wellFormed7
  have stateBaseLocalEvaluation : Evaluates verifiedParserCore r8 (.local 8)
      (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))) r8 :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore r8 8 _ stateBaseLocal⟩
  have workspaceLengthAt6 : r6.local? 5 = some
      (.signed .i32 (Int.ofNat workspaceLayout.workspaceLength)) := by
    rw [bindLocal_preserves_other_local entry.resources.wellFormed
      (by decide : 6 ≠ 5)]
    rw [← entry.resources.workspaceLength]
    exact entry.resources.workspaceLengthLocal
  have workspaceLengthAt7 : r7.local? 5 = some
      (.signed .i32 (Int.ofNat workspaceLayout.workspaceLength)) := by
    rw [bindLocal_preserves_other_local wellFormed6 (by decide : 7 ≠ 5)]
    exact workspaceLengthAt6
  have workspaceLengthAt8 : r8.local? 5 = some
      (.signed .i32 (Int.ofNat workspaceLayout.workspaceLength)) := by
    rw [bindLocal_preserves_other_local wellFormed7 (by decide : 8 ≠ 5)]
    exact workspaceLengthAt7
  have workspaceLengthEvaluation : Evaluates verifiedParserCore r8 (.local 5)
      (.signed .i32 (Int.ofNat workspaceLayout.workspaceLength)) r8 :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore r8 5 _ workspaceLengthAt8⟩
  have workspaceGuardCondition : Evaluates verifiedParserCore r8
      (.binary .less (.local 5) (.local 8)) (.boolean false) r8 := by
    apply evaluatesEagerBinary (by decide) (by decide)
      workspaceLengthEvaluation stateBaseLocalEvaluation
    simp [evalBinaryValue, evalSignedBinary, workspaceLayout.baseFits]
  have workspaceGuardExecution : Executes verifiedParserCore r8
      parserRecognizeWorkspaceGuard .next r8 := by
    rw [extractedParserRecognize_workspace_guard_shape]
    exact executesIfFalse workspaceGuardCondition
      (executesSkip verifiedParserCore r8)
  have suffixBound : workspaceLayout.workspaceLength -
      stateBase workspaceLayout.tokenCount ≤ 2147483647 := by
    exact Nat.le_trans (Nat.sub_le _ _) workspaceLayout.workspaceI32
  have suffixEvaluation : Evaluates verifiedParserCore r8
      (.binary .subtract (.local 5) (.local 8))
      (.signed .i32 (Int.ofNat (workspaceLayout.workspaceLength -
        stateBase workspaceLayout.tokenCount))) r8 :=
    evaluatesNatI32Subtract workspaceLengthEvaluation stateBaseLocalEvaluation
      workspaceLayout.baseFits suffixBound
  have stateWordsEvaluation : Evaluates verifiedParserCore r8 (.constant 27)
      (.signed .i32 9) r8 :=
    evaluatesConstant verifiedParser_workspace_constants.2
  have capacityBound : workspaceLayout.capacity ≤ 2147483647 := by
    exact Nat.le_trans
      (Nat.div_le_self
        (workspaceLayout.workspaceLength - stateBase workspaceLayout.tokenCount)
        9)
      suffixBound
  have capacityEvaluation : Evaluates verifiedParserCore r8
      (.binary .divide
        (.binary .subtract (.local 5) (.local 8)) (.constant 27))
      (.signed .i32 (Int.ofNat workspaceLayout.capacity)) r8 := by
    simpa [WorkspaceLayout.capacity, stateCapacity, stateWords] using
      evaluatesNatI32Divide suffixEvaluation stateWordsEvaluation
        (by decide : 0 < 9) capacityBound
  let r9 := r8.bindLocal 9
    (.signed .i32 (Int.ofNat workspaceLayout.capacity))
  let r10 := r9.bindLocal 10 (.signed .i32 0)
  have continuation := executeRecognizerChartContinuation entry
  have r10Eq : r10 = recognizerPreludeState before workspaceLayout := by
    simp [r10, r9, r8, r7, r6, recognizerPreludeState,
      recognizerPreludeBindings, State.bindLocals]
  have continuationExecution : Executes verifiedParserCore r10
      (.sequence parserRecognizeChartClearLoop
        parserRecognizeSeedSetupStatement)
      continuation.completion continuation.after := by
    simpa [r10Eq] using continuation.execution
  let preludeWrites : CellSet := CellSet.union
    (CellSet.singleton workspaceCell) (fun cell => before.nextCell ≤ cell)
  have continuationSubset : CellSet.Subset
      (CellSet.union (CellSet.singleton workspaceCell)
        (CellSet.singleton (before.nextCell + 4))) preludeWrites := by
    intro cell written
    change cell = workspaceCell ∨ cell = before.nextCell + 4 at written
    change cell = workspaceCell ∨ before.nextCell ≤ cell
    exact written.elim Or.inl (fun same => Or.inr (by
      rw [same]
      exact Nat.le_add_right before.nextCell 4))
  have continuationEffect : ModifiesOnly preludeWrites r10
      continuation.after := by
    simpa [r10Eq] using continuation.effect.weaken continuationSubset
  have wellFormed9 : StateWellFormed r9 :=
    bindLocal_preserves_well_formed r8 9 _ wellFormed8
  have wellFormed10 : StateWellFormed r10 :=
    bindLocal_preserves_well_formed r9 10 _ wellFormed9
  have zeroAtR9 : Evaluates verifiedParserCore r9
      (.value (.signed .i32 0)) (.signed .i32 0) r9 := ⟨1, rfl⟩
  let closed10 := closesFreshLocalExcept (id := 10)
    (type := parserI32Type) preludeWrites wellFormed9 zeroAtR9
    continuationExecution
    (continuationEffect.weaken CellSet.subset_union_left)
    continuation.wellFormed
  let after10 := closed10.after
  have execution10 : Executes verifiedParserCore r9
      parserRecognizeChartIndexStatement continuation.completion after10 := by
    rw [extractedParserRecognize_chart_index_statement_shape]
    simpa [closed10, after10] using closed10.execution
  have effect10 : ModifiesOnly preludeWrites r9 after10 := by
    simpa [after10] using closed10.effect
  have wellFormedAfter10 : StateWellFormed after10 := by
    simpa [after10] using closed10.wellFormed
  let closed9 := closesFreshLocalExcept (id := 9)
    (type := parserI32Type) preludeWrites wellFormed8 capacityEvaluation
    execution10 (effect10.weaken CellSet.subset_union_left)
    wellFormedAfter10
  let after9 := closed9.after
  have execution9 : Executes verifiedParserCore r8
      parserRecognizeStateCapacityStatement continuation.completion after9 := by
    rw [extractedParserRecognize_state_capacity_statement_shape]
    simpa [closed9, after9] using closed9.execution
  have effect9 : ModifiesOnly preludeWrites r8 after9 := by
    simpa [after9] using closed9.effect
  have wellFormedAfter9 : StateWellFormed after9 := by
    simpa [after9] using closed9.wellFormed
  have executionGuardAndCapacity : Executes verifiedParserCore r8
      (.sequence parserRecognizeWorkspaceGuard
        parserRecognizeStateCapacityStatement)
      continuation.completion after9 :=
    executesSequence workspaceGuardExecution execution9
  have effectGuardAndCapacity : ModifiesOnly preludeWrites r8 after9 :=
    (ModifiesOnly.reflAny preludeWrites r8).trans_same effect9
  let closed8 := closesFreshLocalExcept (id := 8)
    (type := parserI32Type) preludeWrites wellFormed7 stateBaseEvaluation
    executionGuardAndCapacity
    (effectGuardAndCapacity.weaken CellSet.subset_union_left)
    wellFormedAfter9
  let after8 := closed8.after
  have execution8 : Executes verifiedParserCore r7
      parserRecognizeStateBaseStatement continuation.completion after8 := by
    rw [extractedParserRecognize_state_base_statement_shape]
    simpa [closed8, after8] using closed8.execution
  have effect8 : ModifiesOnly preludeWrites r7 after8 := by
    simpa [after8] using closed8.effect
  have wellFormedAfter8 : StateWellFormed after8 := by
    simpa [after8] using closed8.wellFormed
  let closed7 := closesFreshLocalExcept (id := 7)
    (type := parserI32Type) preludeWrites wellFormed6 chartCountEvaluation
    execution8 (effect8.weaken CellSet.subset_union_left) wellFormedAfter8
  let after7 := closed7.after
  have execution7 : Executes verifiedParserCore r6
      parserRecognizePositionCountStatement continuation.completion after7 := by
    rw [extractedParserRecognize_position_count_statement_shape]
    simpa [closed7, after7] using closed7.execution
  have effect7 : ModifiesOnly preludeWrites r6 after7 := by
    simpa [after7] using closed7.effect
  have wellFormedAfter7 : StateWellFormed after7 := by
    simpa [after7] using closed7.wellFormed
  let closed6 := closesFreshLocalExcept (id := 6)
    (type := parserI32Type) preludeWrites entry.resources.wellFormed
    finalPositionEvaluation execution7
    (effect7.weaken CellSet.subset_union_left) wellFormedAfter7
  let after6 := closed6.after
  have execution6 : Executes verifiedParserCore before
      parserRecognizeFinalPositionStatement continuation.completion after6 := by
    rw [extractedParserRecognize_final_position_statement_shape]
    simpa [closed6, after6] using closed6.execution
  have wholeExecution : Executes verifiedParserCore before
      parserRecognizeAfterGrammarGuard continuation.completion after6 := by
    rw [extractedParserRecognize_after_grammar_guard_shape]
    exact executesSequence entry.resources.input_guard_executes execution6
  have visibleEffect : ModifiesOnly (CellSet.singleton workspaceCell)
      before after6 := by
    apply closed6.effect.hideFreshWritesExcept
    intro cell written
    change cell = workspaceCell ∨ before.nextCell ≤ cell at written
    exact written
  have cells : after6.cells = continuation.after.cells := by
    simp [after6, closed6, after7, closed7, after8, closed8, after9, closed9,
      after10, closed10]
  exact {
    after := after6
    completion := continuation.completion
    execution := wholeExecution
    effect := visibleEffect
    wellFormed := closed6.wellFormed
    finalWorkspace := continuation.finalWorkspace
    finalWorkspaceValues := continuation.finalWorkspaceValues
    growth := continuation.growth
    workspaceArtifact := continuation.workspaceArtifact.transfer_cells cells
    outcome := continuation.outcome
  }

/-- End-to-end execution of the exact extracted `recognize` body for a packed,
    well-formed grammar and a checked caller workspace.  Grammar validation is
    executed first with an empty caller-visible effect; the resulting caller
    resources are then passed directly to the proved recognizer continuation. -/
structure RecognizerExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId) (before : State) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before extractedParserRecognizeBody
    completion after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  finalWorkspace : LogicalWorkspace
  finalWorkspaceValues : List Int
  growth : WorkspaceAppendClosure workspaceLayout.capacity emptyWorkspace
    finalWorkspace
  workspaceArtifact : RecognizerWorkspaceArtifact workspaceLayout
    finalWorkspace finalWorkspaceValues workspaceCell after
  outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
    tokens workspaceLayout completion

noncomputable def executeRecognizer
    (entry : RecognizerEntryResources grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before) :
    RecognizerExecution grammarLayout grammar words tokens workspaceLayout
      workspaceValues grammarCell tokensCell workspaceCell before := by
  let validation := entry.grammar_validation_invariant
  have guardResult :=
    parserRecognizeGrammarGuard_executes before entry.resources.grammarLocal
      entry.resources.grammarLengthLocal validation entry.resources.wellFormed
  let afterGuard := Classical.choose guardResult
  have guardFacts := Classical.choose_spec guardResult
  have guardExecution := guardFacts.1
  have guardEffect := guardFacts.2.1
  have afterGuardWellFormed := guardFacts.2.2
  let afterEntry := entry.after_empty_effect guardEffect afterGuardWellFormed
  let continuation := executeRecognizerAfterGrammarGuard afterEntry
  exact {
    after := continuation.after
    completion := continuation.completion
    execution := by
      rw [extractedParserRecognize_body_shape]
      exact executesSequence guardExecution continuation.execution
    effect := (guardEffect.weaken CellSet.empty_subset).trans_same
      continuation.effect
    wellFormed := continuation.wellFormed
    finalWorkspace := continuation.finalWorkspace
    finalWorkspaceValues := continuation.finalWorkspaceValues
    growth := continuation.growth
    workspaceArtifact := continuation.workspaceArtifact
    outcome := continuation.outcome
  }

/-- The concrete parse-result value selected by a completed semantic
    recognizer outcome.  This eliminates the dependent completion index at the
    public call boundary while retaining the richer proof object internally. -/
def RecognizerInitialContinuationOutcome.resultValue
    {completion : Completion}
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
      tokens workspaceLayout completion) : Value :=
  match outcome with
  | .full stateCount =>
      parseResultValue 2 (Int.ofNat stateCount) (-1) 0
  | .seeded _ _ _ continuation =>
      match continuation with
      | .full position stateCount =>
          parseResultValue 2 (Int.ofNat stateCount) (-1)
            (Int.ofNat position)
      | .completed workspace _ _ _ root =>
          match root with
          | .accepted rootState _ _ _ _ _ =>
              parseResultValue 0 (Int.ofNat workspace.states.length)
                (Int.ofNat rootState) 0
          | .rejected furthest =>
              parseResultValue 1 (Int.ofNat workspace.states.length) (-1)
                (Int.ofNat furthest)

theorem RecognizerInitialContinuationOutcome.completion_eq_returned
    {completion : Completion}
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
      tokens workspaceLayout completion) :
    completion = .returned (some outcome.resultValue) := by
  cases outcome with
  | full stateCount => rfl
  | seeded workspace workspaceValues completion continuation =>
      cases continuation with
      | full position stateCount =>
          simp [RecognizerInitialContinuationOutcome.resultValue,
            parserCapacityCompletion]
      | completed finalWorkspace finalValues growth completion root =>
          cases root <;>
            simp [RecognizerInitialContinuationOutcome.resultValue]

/-- Caller-facing language meaning of the recognizer result. Capacity
    exhaustion and rejection remain distinct, while acceptance carries the
    declarative grammar derivation proved by the Earley loop. -/
inductive RecognizerLanguageOutcome
    (grammar : IndexedGrammar) (tokens : List Nat) : Type where
  | capacityFull
  | rejected
  | accepted (materializedParse : MaterializedParse grammar tokens)

def RecognizerInitialContinuationOutcome.languageOutcome
    {completion : Completion}
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
      tokens workspaceLayout completion) :
    RecognizerLanguageOutcome grammar tokens :=
  match outcome with
  | .full _ => .capacityFull
  | .seeded _ _ _ continuation =>
      match continuation with
      | .full _ _ => .capacityFull
      | .completed _ _ _ _ root =>
          match root with
          | .accepted _ _ _ _ _ materializedParse =>
              .accepted materializedParse
          | .rejected _ => .rejected

theorem RecognizerExecution.returns_result
    (execution : RecognizerExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before) :
    Executes verifiedParserCore before extractedParserRecognizeBody
      (.returned (some execution.outcome.resultValue)) execution.after := by
  rw [← execution.outcome.completion_eq_returned]
  exact execution.execution

def parserRecognizeValues
    (words : List Int) (tokens : List Nat) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId) : List Value := [
  parserGrammarValue words grammarCell,
  .signed .i32 (Int.ofNat words.length),
  parserTokensValue tokens tokensCell,
  .signed .i32 (Int.ofNat tokens.length),
  workspaceValue workspaceValues workspaceCell,
  .signed .i32 (Int.ofNat workspaceValues.length)]

def parserRecognizeBindings
    (words : List Int) (tokens : List Nat) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId) : List (VarId × Value) := [
  (0, parserGrammarValue words grammarCell),
  (1, .signed .i32 (Int.ofNat words.length)),
  (2, parserTokensValue tokens tokensCell),
  (3, .signed .i32 (Int.ofNat tokens.length)),
  (4, workspaceValue workspaceValues workspaceCell),
  (5, .signed .i32 (Int.ofNat workspaceValues.length))]

def parserRecognizeCallee
    (caller : State) (words : List Int) (tokens : List Nat)
    (workspaceValues : List Int) (grammarCell tokensCell workspaceCell : CellId) :
    State :=
  enterCall caller (parserRecognizeBindings words tokens workspaceValues
    grammarCell tokensCell workspaceCell)

theorem extractedParserRecognize_function_contract_shape :
    extractedParserRecognizeFunction.parameters = [
        (0, .slice parserI32Type), (1, parserI32Type),
        (2, .slice parserI32Type), (3, parserI32Type),
        (4, .slice parserI32Type), (5, parserI32Type)] ∧
      extractedParserRecognizeFunction.returnType = .structure 0 ∧
      extractedParserRecognizeFunction.body =
        some extractedParserRecognizeBody := by
  exact ⟨rfl, rfl, rfl⟩

theorem extractedParserRecognize_parameters_bind :
    bindParameters extractedParserRecognizeFunction.parameters
        (parserRecognizeValues words tokens workspaceValues grammarCell
          tokensCell workspaceCell) =
      some (parserRecognizeBindings words tokens workspaceValues grammarCell
        tokensCell workspaceCell) := by
  rw [extractedParserRecognize_function_contract_shape.1]
  rfl

/-- Public internal-call contract for the extracted recognizer.  A caller
    proves ordinary argument evaluation and the callee's physical resource
    ownership once; this result supplies both the concrete Core evaluation and
    the semantic parse outcome chosen by the verified body. -/
structure RecognizerCallExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (before afterArguments : State) (arguments : List Expr) where
  after : State
  outcomeCompletion : Completion
  outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
    tokens workspaceLayout outcomeCompletion
  evaluation : Evaluates verifiedParserCore before
    (.call extractedParserRecognizeFunction.id arguments)
    outcome.resultValue after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) afterArguments after
  finalWorkspace : LogicalWorkspace
  finalWorkspaceValues : List Int
  growth : WorkspaceAppendClosure workspaceLayout.capacity emptyWorkspace
    finalWorkspace
  workspaceArtifact : RecognizerWorkspaceArtifact workspaceLayout
    finalWorkspace finalWorkspaceValues workspaceCell after

/-- Public semantic result paired with the concrete extracted-call proof. -/
def RecognizerCallExecution.languageOutcome
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before afterArguments arguments) :
    RecognizerLanguageOutcome grammar tokens :=
  execution.outcome.languageOutcome

noncomputable def executeRecognizerCall
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments
      (parserRecognizeValues words tokens workspaceValues grammarCell tokensCell
        workspaceCell) afterArguments)
    (entry : RecognizerEntryResources grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      (parserRecognizeCallee afterArguments words tokens workspaceValues
        grammarCell tokensCell workspaceCell)) :
    RecognizerCallExecution grammarLayout grammar words tokens workspaceLayout
      workspaceValues grammarCell tokensCell workspaceCell before afterArguments
      arguments := by
  let body := executeRecognizer entry
  let after := restoreLocals afterArguments body.after
  have bodyResult : Executes verifiedParserCore
      (parserRecognizeCallee afterArguments words tokens workspaceValues
        grammarCell tokensCell workspaceCell)
      extractedParserRecognizeBody
      (.returned (some body.outcome.resultValue)) body.after :=
    body.returns_result
  have evaluation : Evaluates verifiedParserCore before
      (.call extractedParserRecognizeFunction.id arguments)
      body.outcome.resultValue after := by
    apply evaluatesCallReturned argumentsResult verifiedParserCore_finds_recognize
      extractedParserRecognize_parameters_bind
      extractedParserRecognize_function_contract_shape.2.2 bodyResult
  have effect : ModifiesOnly (CellSet.singleton workspaceCell)
      afterArguments after := by
    simpa [after, parserRecognizeCallee] using
      call_effect body.effect.toStoreEffect
  exact {
    after := after
    outcomeCompletion := body.completion
    outcome := body.outcome
    evaluation := evaluation
    effect := effect
    finalWorkspace := body.finalWorkspace
    finalWorkspaceValues := body.finalWorkspaceValues
    growth := body.growth
    workspaceArtifact := body.workspaceArtifact.transfer_cells (by
      simp [after, restoreLocals])
  }

/-- The logical artifact returned by the verified public recognizer call is a
    well-formed Earley workspace.  Clients need only the public growth
    certificate; the recognizer's nested loop invariants remain hidden. -/
theorem RecognizerCallExecution.final_workspace_well_formed
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before afterArguments arguments) :
    WorkspaceWellFormed execution.finalWorkspace :=
  execution.growth.preserves_well_formed emptyWorkspace_wellFormed

end Lanius.Extraction.ParserRecognize
