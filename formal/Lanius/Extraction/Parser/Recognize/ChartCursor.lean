import Lanius.Extraction.Parser.Recognize.Common

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
/-! ## Shared chart-cursor execution frame -/

/-- Source declarations whose cells must remain distinct from a chart cursor:
    the recognizer parameters and the uniquely resolved `state_base` local. -/
def ChartCursorFramedLocal (id : VarId) : Prop :=
  id ∈ verifiedParserRecognizerParameterIds ∨
    id = verifiedParserRecognizerStateBase.coreId

def verifiedParserChartCursorBindings : LocalBindingFrame :=
  LocalBindingFrame.union verifiedParserRecognizerParameterFrame
    [verifiedParserRecognizerStateBase.binding]

theorem verifiedParserChartCursorBindings_core_ids :
    verifiedParserChartCursorBindings.coreIds =
      verifiedParserRecognizerParameterIds ++
        [verifiedParserRecognizerStateBase.coreId] := by
  native_decide

theorem ChartCursorFramedLocal_source_frame (id : VarId) :
    ChartCursorFramedLocal id ↔
      verifiedParserChartCursorBindings.ContainsCoreId id := by
  rw [LocalBindingFrame.ContainsCoreId,
    verifiedParserChartCursorBindings_core_ids]
  simp [ChartCursorFramedLocal]

theorem chartCursorFramedLocalFootprint_eq (runtime : State) :
    localCellFootprint runtime ChartCursorFramedLocal =
      localBindingFrameFootprint runtime verifiedParserChartCursorBindings := by
  unfold localBindingFrameFootprint
  congr 1
  funext id
  exact propext (ChartCursorFramedLocal_source_frame id)

@[simp] theorem ChartCursorFramedLocal_iff (id : Nat) :
    ChartCursorFramedLocal id ↔
      id ∈ verifiedParserRecognizerParameterIds ∨ id = 8 := by
  simp [ChartCursorFramedLocal]

theorem ChartCursorFramedLocal.le8
    (id : Nat) (framed : ChartCursorFramedLocal id) : id ≤ 8 := by
  rw [ChartCursorFramedLocal_iff] at framed
  rcases framed with parameter | rfl
  · exact Nat.le_trans
      ((mem_verifiedParserRecognizerParameterIds_iff id).mp parameter)
      (by decide)
  · decide

/-- The complete source-derived local frame that must remain physically
    separate from the owned chart-cursor cell. -/
def ChartCursorFrameSeparated (runtime : State) (cursorCell : CellId) : Prop :=
  CellSet.Disjoint
    (localBindingFrameFootprint runtime verifiedParserChartCursorBindings)
    (CellSet.singleton cursorCell)

/-- A `state_value` call as it appears inside the recognizer, parameterized by
    the local that owns the current chart cursor. -/
def parserRecognizeStateValueCall
    (cursorLocal : VarId) (fieldConstant : ConstantId) : Expr :=
  .call extractedParserStateValueFunction.id
    [.local 4, .local 8, .local cursorLocal, .constant fieldConstant]

/-- Read-only execution frame shared by every recognizer loop that follows
    `STATE_NEXT`.  It connects an owned concrete cursor local to a semantic
    suffix of one logical chart. -/
structure RecognizerChartCursorInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell cursorCell : CellId)
    (runtime : State) (chartPosition cursorLocal current : Nat)
    (remaining : List Nat) : Type where
  recognizer : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell runtime
  workspaceWithinGrammar : WorkspaceWithinGrammar grammar workspace
  stateBaseLocal : runtime.local? 8 = some
    (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
  cursorOwned : (Assertion.localPointsTo cursorLocal cursorCell
    (some (.signed .i32 (Int.ofNat current)))).holds runtime
  cursorFrameSeparate : ChartCursorFrameSeparated runtime cursorCell
  cursorBackingDistinct : cursorCell ≠ grammarCell ∧
    cursorCell ≠ tokensCell ∧ cursorCell ≠ workspaceCell
  chartPositionBound : chartPosition ≤ finalPosition workspaceLayout.tokenCount
  cursor : ChartCursor (workspace.chart chartPosition) current remaining

/-- Pointwise compatibility view derived from the stored separation
    footprint.  The footprint, rather than one inequality per use, is the
    invariant's source of truth. -/
theorem RecognizerChartCursorInvariant.cursorFramedDistinct
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining)
    (id : VarId) (framed : ChartCursorFramedLocal id) :
    runtime.cellId? id ≠ some cursorCell :=
  invariant.cursorFrameSeparate.localCell_ne_of_singleton
    ((ChartCursorFramedLocal_source_frame id).mp framed)

theorem RecognizerChartCursorInvariant.state_at_cursor
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining) :
    ∃ state,
      workspace.state? current = some state ∧
      state.position = chartPosition :=
  invariant.recognizer.workspaceEncoded.state_at_chart_cursor invariant.cursor

theorem RecognizerChartCursorInvariant.state_within_grammar
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining)
    (state : EarleyState) (found : workspace.state? current = some state) :
    StateKeyWithinGrammar grammar state.key :=
  invariant.workspaceWithinGrammar current state found

def RecognizerChartCursorInvariant.after_empty_effect
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell before chartPosition cursorLocal current
      remaining)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    RecognizerChartCursorInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell after chartPosition cursorLocal current
      remaining := {
  recognizer := invariant.recognizer.after_empty_effect effect afterWellFormed
  workspaceWithinGrammar := invariant.workspaceWithinGrammar
  stateBaseLocal := effect.empty_preserves_local invariant.recognizer.wellFormed
    invariant.stateBaseLocal
  cursorOwned := effect.empty_preserves_assertion invariant.recognizer.wellFormed
    (Assertion.localPointsTo cursorLocal cursorCell
      (some (.signed .i32 (Int.ofNat current)))) invariant.cursorOwned
  cursorFrameSeparate := by
    unfold ChartCursorFrameSeparated
    rw [effect.localBindingFrameFootprint_eq verifiedParserChartCursorBindings]
    exact invariant.cursorFrameSeparate
  cursorBackingDistinct := invariant.cursorBackingDistinct
  chartPositionBound := invariant.chartPositionBound
  cursor := invariant.cursor
}

/-- Temporary bindings above the persistent recognizer locals preserve a
    chart cursor and its separation frame.  The remaining recognizer loops all
    bind decoded state fields before testing them, so this is deliberately a
    cursor-level operation rather than a nullable-loop special case. -/
def RecognizerChartCursorInvariant.after_bind_local
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining)
    (id : VarId) (value : Value)
    (persistentBefore : 8 < id) (cursorBefore : cursorLocal < id) :
    RecognizerChartCursorInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell (runtime.bindLocal id value) chartPosition
      cursorLocal current remaining := by
  have different (fixed : Nat) (bound : fixed ≤ 8) : id ≠ fixed :=
    Nat.ne_of_gt (Nat.lt_of_le_of_lt bound persistentBefore)
  have cursorDifferent : id ≠ cursorLocal := Nat.ne_of_gt cursorBefore
  exact {
    recognizer := invariant.recognizer.after_bind_local id value
      (different 0 (by decide)) (different 1 (by decide))
      (different 2 (by decide)) (different 3 (by decide))
      (different 4 (by decide)) (different 5 (by decide))
    workspaceWithinGrammar := invariant.workspaceWithinGrammar
    stateBaseLocal :=
      (bindLocal_preserves_other_local invariant.recognizer.wellFormed
        (different 8 (by decide))).trans invariant.stateBaseLocal
    cursorOwned := bindLocal_preserves_localPointsTo_of_ne runtime id
      cursorLocal value cursorCell
      (some (.signed .i32 (Int.ofNat current)))
      invariant.recognizer.wellFormed cursorDifferent invariant.cursorOwned
    cursorFrameSeparate := by
      unfold ChartCursorFrameSeparated
      intro cell framed written
      obtain ⟨queried, queriedFramed, cellId⟩ := framed
      have queriedFramedPredicate :=
        (ChartCursorFramedLocal_source_frame queried).mpr queriedFramed
      have notEqual : id ≠ queried :=
        different queried queriedFramedPredicate.le8
      apply invariant.cursorFrameSeparate cell
      · exact ⟨queried, queriedFramed, by
          simpa [State.bindLocal, State.bindCell, State.cellId?, notEqual]
            using cellId⟩
      · exact written
    cursorBackingDistinct := invariant.cursorBackingDistinct
    chartPositionBound := invariant.chartPositionBound
    cursor := invariant.cursor
  }

structure RecognizerChartCursorRead
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell cursorCell : CellId)
    (before : State) (chartPosition cursorLocal current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerChartCursorInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell cursorCell before chartPosition cursorLocal
      current remaining)
    (field constantId : Nat) (state : EarleyState) where
  after : State
  evaluation : Evaluates verifiedParserCore before
    (parserRecognizeStateValueCall cursorLocal constantId)
    (.signed .i32 (stateFieldValue workspace current state field)) after
  effect : ModifiesOnly CellSet.empty before after
  invariant : RecognizerChartCursorInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell cursorCell after chartPosition cursorLocal current remaining

/-- Store-pure grammar-row accessor result in the same persistent chart-cursor
    frame.  Both nullable replay and parent completion need these reads after
    decoding a state key. -/
structure RecognizerChartGrammarRead
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell cursorCell : CellId)
    (before : State) (chartPosition cursorLocal current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerChartCursorInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell cursorCell before chartPosition cursorLocal
      current remaining)
    (expression : Expr) (value : Nat) where
  after : State
  evaluation : Evaluates verifiedParserCore before expression
    (.signed .i32 (Int.ofNat value)) after
  effect : ModifiesOnly CellSet.empty before after
  invariant : RecognizerChartCursorInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell cursorCell after chartPosition cursorLocal current remaining

/-- Exact read of one field from the state selected by a recognizer chart
    cursor.  All generated `state_value` calls in the remaining loops reduce
    to this theorem. -/
noncomputable def RecognizerChartCursorInvariant.read_state_field
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining)
    (state : EarleyState) (found : workspace.state? current = some state)
    (field constantId : Nat) (fieldBound : field < stateWords)
    (constantFound : verifiedParserCore.constant? constantId = some {
      id := constantId
      type := parserI32Type
      value := .signed .i32 (Int.ofNat field)
    }) :
    RecognizerChartCursorRead grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining invariant field constantId state := by
  let value := workspaceValue workspaceValues workspaceCell
  let after := parserStateValueCallState runtime value
    (Int.ofNat (stateBase workspaceLayout.tokenCount)) (Int.ofNat current)
    (Int.ofNat field)
  have workspaceArgument : Evaluates verifiedParserCore runtime (.local 4)
      value runtime := by
    refine ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 4 value ?_⟩
    simpa [value] using invariant.recognizer.workspaceLocal
  have baseArgument : Evaluates verifiedParserCore runtime (.local 8)
      (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
      runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 8 _
      invariant.stateBaseLocal⟩
  have currentArgument : Evaluates verifiedParserCore runtime
      (.local cursorLocal) (.signed .i32 (Int.ofNat current)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime cursorLocal _
      (Assertion.localPointsTo_local cursorLocal cursorCell _ runtime
        invariant.cursorOwned)⟩
  have fieldArgument : Evaluates verifiedParserCore runtime
      (.constant constantId) (.signed .i32 (Int.ofNat field)) runtime := by
    refine ⟨2, ?_⟩
    simp [evalExpr, constantFound]
  have arguments : ArgumentsEvaluateTo verifiedParserCore runtime
      [.local 4, .local 8, .local cursorLocal, .constant constantId]
      [value,
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
        .signed .i32 (Int.ofNat current),
        .signed .i32 (Int.ofNat field)] runtime :=
    ArgumentsEvaluateTo.cons workspaceArgument
      (ArgumentsEvaluateTo.cons baseArgument
        (ArgumentsEvaluateTo.cons currentArgument
          (ArgumentsEvaluateTo.singleton fieldArgument)))
  have evaluation := extractedParserStateValueCall_reads_encoded
    workspaceLayout workspace workspaceValues workspaceCell
    invariant.recognizer.workspaceLength
    invariant.recognizer.workspaceEncoded state current field found fieldBound
    runtime runtime
    [.local 4, .local 8, .local cursorLocal, .constant constantId]
    invariant.recognizer.wellFormed arguments
    invariant.recognizer.workspaceBacking
  have exactEvaluation : Evaluates verifiedParserCore runtime
      (parserRecognizeStateValueCall cursorLocal constantId)
      (.signed .i32 (stateFieldValue workspace current state field)) after := by
    simpa [parserRecognizeStateValueCall, after, value, workspaceValue,
      parserStateValueCallState] using evaluation
  have effect : ModifiesOnly CellSet.empty runtime after :=
    parserStateValueCallState_effect
  have afterWellFormed : StateWellFormed after :=
    parserStateValueCallState_well_formed invariant.recognizer.wellFormed
  exact {
    after := after
    evaluation := exactEvaluation
    effect := effect
    invariant := invariant.after_empty_effect effect afterWellFormed
  }

/-- Read the logical RHS length for a grammar-valid production while
    preserving the chart-cursor frame. -/
noncomputable def RecognizerChartCursorInvariant.read_rhs_length
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining)
    (production : Nat) (productionBound : production < grammar.productionCount)
    (productionExpr : Expr)
    (productionEvaluation : Evaluates verifiedParserCore runtime productionExpr
      (.signed .i32 (Int.ofNat production)) runtime) :
    RecognizerChartGrammarRead grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining invariant
      (.call extractedParserRhsLengthFunction.id [.local 0, productionExpr])
      (grammar.rhsLengths.get ⟨production, by simpa using productionBound⟩) := by
  let arguments : List Expr := [.local 0, productionExpr]
  let callee := parserGrammarRowCallee runtime words grammarCell production
  let after := restoreLocals runtime callee
  have grammarEvaluation : Evaluates verifiedParserCore runtime (.local 0)
      (parserGrammarValue words grammarCell) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 0 _
      invariant.recognizer.grammarLocal⟩
  have argumentsEvaluation : ArgumentsEvaluateTo verifiedParserCore runtime
      arguments [parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production)] runtime := by
    simpa [arguments] using ArgumentsEvaluateTo.cons grammarEvaluation
      (ArgumentsEvaluateTo.singleton productionEvaluation)
  have entry : GrammarRowEntry words grammarCell production runtime := {
    valuesI32 := invariant.recognizer.wordsI32
    wellFormed := invariant.recognizer.wellFormed
    backing := invariant.recognizer.grammarBacking
  }
  have evaluation := extractedParserRhsLengthCall_reads_encoded grammarLayout
    grammar words invariant.recognizer.grammarEncoded grammarCell production
    productionBound runtime runtime arguments entry argumentsEvaluation
  have effect : ModifiesOnly CellSet.empty runtime after := by
    simpa [after, callee, parserGrammarRowCallee] using
      (enterCall_effect runtime
        (parserGrammarRowBindings words grammarCell production)).restoreLocals
  have afterWellFormed : StateWellFormed after :=
    (enterCall_effect runtime
      (parserGrammarRowBindings words grammarCell production))
      |>.restoreLocals_wellFormed invariant.recognizer.wellFormed
        entry.callee_wellFormed
  exact {
    after := after
    evaluation := by simpa [arguments, callee, after] using evaluation
    effect := effect
    invariant := invariant.after_empty_effect effect afterWellFormed
  }

/-- Read one semantic RHS symbol through the extracted packed-grammar
    accessor.  The returned value is stated against the source production,
    rather than merely against the flattened storage row. -/
noncomputable def RecognizerChartCursorInvariant.read_rhs_symbol
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining)
    (production : Nat) (productionBound : production < grammar.productionCount)
    (dot : Nat)
    (dotBound : dot <
      (grammar.productionAt ⟨production, productionBound⟩).rhs.length)
    (productionExpr dotExpr : Expr)
    (productionEvaluation : Evaluates verifiedParserCore runtime productionExpr
      (.signed .i32 (Int.ofNat production)) runtime)
    (dotEvaluation : Evaluates verifiedParserCore runtime dotExpr
      (.signed .i32 (Int.ofNat dot)) runtime) :
    RecognizerChartGrammarRead grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining invariant
      (.call extractedParserRhsSymbolFunction.id
        [.local 0, productionExpr, dotExpr])
      ((grammar.productionAt ⟨production, productionBound⟩).rhs.get
        ⟨dot, dotBound⟩) := by
  let relative := grammar.rhsOffsets.get
    ⟨production, by simpa using productionBound⟩
  have symbolRowBound : relative + dot < grammar.rhsSymbols.length := by
    have range :=
      invariant.recognizer.grammarWellFormed.production_validation.rhsRange
        ⟨production, productionBound⟩
    have range' : relative +
        (grammar.productionAt ⟨production, productionBound⟩).rhs.length ≤
        grammar.rhsSymbols.length := by
      simpa [relative] using range
    omega
  let arguments : List Expr := [.local 0, productionExpr, dotExpr]
  let callee := parserGrammarDotCallee runtime words grammarCell production dot
  let relativeState := callee.bindLocal 3
    (.signed .i32 (Int.ofNat relative))
  let completed := restoreLocals callee relativeState
  let after := restoreLocals runtime completed
  have grammarEvaluation : Evaluates verifiedParserCore runtime (.local 0)
      (parserGrammarValue words grammarCell) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 0 _
      invariant.recognizer.grammarLocal⟩
  have argumentsEvaluation : ArgumentsEvaluateTo verifiedParserCore runtime
      arguments [parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production),
        .signed .i32 (Int.ofNat dot)] runtime := by
    simpa [arguments] using ArgumentsEvaluateTo.cons grammarEvaluation
      (ArgumentsEvaluateTo.cons productionEvaluation
        (ArgumentsEvaluateTo.singleton dotEvaluation))
  have entry : GrammarDotEntry words grammarCell production dot runtime := {
    valuesI32 := invariant.recognizer.wordsI32
    wellFormed := invariant.recognizer.wellFormed
    backing := invariant.recognizer.grammarBacking
  }
  have result := extractedParserRhsSymbolCall_reads_encoded grammarLayout
    grammar words invariant.recognizer.grammarEncoded grammarCell production dot
    relative productionBound rfl symbolRowBound runtime runtime arguments entry
    argumentsEvaluation
  have semanticValue : grammar.rhsSymbols.get
      ⟨relative + dot, symbolRowBound⟩ =
      (grammar.productionAt ⟨production, productionBound⟩).rhs.get
        ⟨dot, dotBound⟩ := by
    exact grammar.rhsSymbolAt production dot productionBound dotBound
      symbolRowBound
  have evaluation : Evaluates verifiedParserCore runtime
      (.call extractedParserRhsSymbolFunction.id arguments)
      (.signed .i32 (Int.ofNat
        ((grammar.productionAt ⟨production, productionBound⟩).rhs.get
          ⟨dot, dotBound⟩))) after := by
    have resultEvaluation := result.1
    rw [semanticValue] at resultEvaluation
    simpa [callee, relativeState, completed, after] using resultEvaluation
  have effect : ModifiesOnly CellSet.empty runtime after := by
    simpa [callee, relativeState, completed, after] using result.2.1
  have afterWellFormed : StateWellFormed after := by
    simpa [callee, relativeState, completed, after] using result.2.2.1
  exact {
    after := after
    evaluation := by simpa [arguments] using evaluation
    effect := effect
    invariant := invariant.after_empty_effect effect afterWellFormed
  }

/-- Read the logical left-hand-side nonterminal for a grammar-valid
    production while preserving the chart-cursor frame. -/
noncomputable def RecognizerChartCursorInvariant.read_lhs
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining)
    (production : Nat) (productionBound : production < grammar.productionCount)
    (productionExpr : Expr)
    (productionEvaluation : Evaluates verifiedParserCore runtime productionExpr
      (.signed .i32 (Int.ofNat production)) runtime) :
    RecognizerChartGrammarRead grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining invariant
      (.call extractedParserLhsFunction.id [.local 0, productionExpr])
      (grammar.productionLhs.get ⟨production, by simpa using productionBound⟩) := by
  let arguments : List Expr := [.local 0, productionExpr]
  let callee := parserGrammarRowCallee runtime words grammarCell production
  let after := restoreLocals runtime callee
  have grammarEvaluation : Evaluates verifiedParserCore runtime (.local 0)
      (parserGrammarValue words grammarCell) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 0 _
      invariant.recognizer.grammarLocal⟩
  have argumentsEvaluation : ArgumentsEvaluateTo verifiedParserCore runtime
      arguments [parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production)] runtime := by
    simpa [arguments] using ArgumentsEvaluateTo.cons grammarEvaluation
      (ArgumentsEvaluateTo.singleton productionEvaluation)
  have entry : GrammarRowEntry words grammarCell production runtime := {
    valuesI32 := invariant.recognizer.wordsI32
    wellFormed := invariant.recognizer.wellFormed
    backing := invariant.recognizer.grammarBacking
  }
  have evaluation := extractedParserLhsCall_reads_encoded grammarLayout grammar
    words invariant.recognizer.grammarEncoded grammarCell production
    productionBound runtime runtime arguments entry argumentsEvaluation
  have effect : ModifiesOnly CellSet.empty runtime after := by
    simpa [after, callee, parserGrammarRowCallee] using
      (enterCall_effect runtime
        (parserGrammarRowBindings words grammarCell production)).restoreLocals
  have afterWellFormed : StateWellFormed after :=
    (enterCall_effect runtime
      (parserGrammarRowBindings words grammarCell production))
      |>.restoreLocals_wellFormed invariant.recognizer.wellFormed
        entry.callee_wellFormed
  exact {
    after := after
    evaluation := by simpa [arguments, callee, after] using evaluation
    effect := effect
    invariant := invariant.after_empty_effect effect afterWellFormed
  }

theorem RecognizerChartCursorInvariant.condition_nonnegative
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining) :
    Evaluates verifiedParserCore runtime
      (.binary .greaterEqual (.local cursorLocal)
        (.value (.signed .i32 0))) (.boolean true) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local cursorLocal)
      (.signed .i32 (Int.ofNat current)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime cursorLocal _
      (Assertion.localPointsTo_local cursorLocal cursorCell _ runtime
        invariant.cursorOwned)⟩
  have right : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 0)) (.signed .i32 0) runtime := ⟨1, rfl⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

def parserRecognizeCursorAdvance (cursorLocal : VarId) : Expr :=
  .assign .set (.local cursorLocal)
    (parserRecognizeStateValueCall cursorLocal 32)

def parserRecognizeCursorAdvanceStatement (cursorLocal : VarId) : Stmt :=
  .sequence (.expression (parserRecognizeCursorAdvance cursorLocal)) .skip

def RecognizerChartCursorInvariant.after_cursor_assignment
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell before chartPosition cursorLocal current
      remaining)
    (after : State) (newCurrent : Nat) (newRemaining : List Nat)
    (effect : ModifiesOnly (CellSet.singleton cursorCell) before after)
    (afterWellFormed : StateWellFormed after)
    (afterOwned : (Assertion.localPointsTo cursorLocal cursorCell
      (some (.signed .i32 (Int.ofNat newCurrent)))).holds after)
    (cursor : ChartCursor (workspace.chart chartPosition) newCurrent
      newRemaining) :
    RecognizerChartCursorInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell after chartPosition cursorLocal newCurrent
      newRemaining := by
  have nextRecognizer :=
    invariant.recognizer.after_disjoint_scalar_effect cursorCell effect
      afterWellFormed invariant.cursorBackingDistinct.1.symm
      invariant.cursorBackingDistinct.2.1.symm
      invariant.cursorBackingDistinct.2.2.symm
      (CellSet.Disjoint.mono_left
        (localBindingFrameFootprint_mono (fun id bound =>
          (ChartCursorFramedLocal_source_frame id).mp (Or.inl bound)))
        invariant.cursorFrameSeparate)
  have preserveStateBase : after.local? 8 = some
      (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))) :=
    effect.preserves_local_of_disjoint invariant.recognizer.wellFormed
      (localCellFootprint_disjoint_singleton invariant.cursorFramedDistinct)
      (by simp [ChartCursorFramedLocal]) invariant.stateBaseLocal
  exact {
    recognizer := nextRecognizer
    workspaceWithinGrammar := invariant.workspaceWithinGrammar
    stateBaseLocal := preserveStateBase
    cursorOwned := afterOwned
    cursorFrameSeparate := by
      unfold ChartCursorFrameSeparated
      rw [effect.localBindingFrameFootprint_eq
        verifiedParserChartCursorBindings]
      exact invariant.cursorFrameSeparate
    cursorBackingDistinct := invariant.cursorBackingDistinct
    chartPositionBound := invariant.chartPositionBound
    cursor := cursor
  }

structure RecognizerChartCursorAdvance
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell cursorCell : CellId)
    (before : State) (chartPosition cursorLocal current next : Nat)
    (tail : List Nat)
    (beforeInvariant : RecognizerChartCursorInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell cursorCell before chartPosition cursorLocal
      current (next :: tail)) where
  after : State
  execution : Executes verifiedParserCore before
    (parserRecognizeCursorAdvanceStatement cursorLocal) .next after
  effect : ModifiesOnly (CellSet.singleton cursorCell) before after
  invariant : RecognizerChartCursorInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell cursorCell after chartPosition cursorLocal next tail

/-- Read the post-processing `STATE_NEXT` link and advance an owned chart
    cursor to a nonempty suffix. -/
noncomputable def RecognizerChartCursorInvariant.advance
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      (next :: tail)) :
    RecognizerChartCursorAdvance grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current next
      tail invariant := by
  let state := Classical.choose invariant.state_at_cursor
  have stateFacts := Classical.choose_spec invariant.state_at_cursor
  have found : workspace.state? current = some state := stateFacts.1
  have statePosition : state.position = chartPosition := stateFacts.2
  let read := invariant.read_state_field state found 4 32 (by decide)
    verifiedParser_find_constants.2.2.2.2
  have nextValue : stateFieldValue workspace current state 4 = Int.ofNat next := by
    simp only [stateFieldValue, stateNextValue]
    rw [statePosition, invariant.cursor.nextAfter]
    rfl
  have rightEvaluation : Evaluates verifiedParserCore runtime
      (parserRecognizeStateValueCall cursorLocal 32)
      (.signed .i32 (Int.ofNat next)) read.after := by
    simpa only [nextValue] using read.evaluation
  let assigned := evaluatesSetOwnedLocalFromEmpty
    (program := verifiedParserCore) cursorLocal cursorCell
    invariant.recognizer.wellFormed invariant.cursorOwned rightEvaluation
    read.invariant.recognizer.wellFormed read.effect
  let after := Classical.choose assigned
  have facts := Classical.choose_spec assigned
  have execution : Executes verifiedParserCore runtime
      (parserRecognizeCursorAdvanceStatement cursorLocal) .next after := by
    exact executesSequence (executesExpression facts.1)
      (executesSkip verifiedParserCore after)
  let nextCursor := invariant.cursor.next
    (invariant.recognizer.workspaceEncoded.wellFormed.chartIdsUnique
      chartPosition)
  have nextInvariant := invariant.after_cursor_assignment after next tail
    facts.2.2.2 facts.2.1 facts.2.2.1 nextCursor
  exact {
    after := after
    execution := execution
    effect := facts.2.2.2
    invariant := nextInvariant
  }

/-- State after the last chart element writes the `-1` sentinel into its
    owned cursor local. -/
structure RecognizerChartCursorFinished
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell cursorCell : CellId)
    (runtime : State) (chartPosition cursorLocal : Nat) : Type where
  recognizer : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell runtime
  workspaceWithinGrammar : WorkspaceWithinGrammar grammar workspace
  stateBaseLocal : runtime.local? 8 = some
    (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
  cursorOwned : (Assertion.localPointsTo cursorLocal cursorCell
    (some (.signed .i32 (-1)))).holds runtime
  cursorFrameSeparate : ChartCursorFrameSeparated runtime cursorCell
  cursorBackingDistinct : cursorCell ≠ grammarCell ∧
    cursorCell ≠ tokensCell ∧ cursorCell ≠ workspaceCell
  chartPositionBound : chartPosition ≤ finalPosition workspaceLayout.tokenCount

theorem RecognizerChartCursorFinished.cursorFramedDistinct
    (finished : RecognizerChartCursorFinished grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal)
    (id : VarId) (framed : ChartCursorFramedLocal id) :
    runtime.cellId? id ≠ some cursorCell :=
  finished.cursorFrameSeparate.localCell_ne_of_singleton
    ((ChartCursorFramedLocal_source_frame id).mp framed)

theorem RecognizerChartCursorFinished.condition_negative
    (finished : RecognizerChartCursorFinished grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal) :
    Evaluates verifiedParserCore runtime
      (.binary .greaterEqual (.local cursorLocal)
        (.value (.signed .i32 0))) (.boolean false) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local cursorLocal)
      (.signed .i32 (-1)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime cursorLocal _
      (Assertion.localPointsTo_local cursorLocal cursorCell _ runtime
        finished.cursorOwned)⟩
  have right : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 0)) (.signed .i32 0) runtime := ⟨1, rfl⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

structure RecognizerChartCursorExhaustion
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell cursorCell : CellId)
    (before : State) (chartPosition cursorLocal current : Nat)
    (beforeInvariant : RecognizerChartCursorInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell cursorCell before chartPosition cursorLocal
      current []) where
  after : State
  execution : Executes verifiedParserCore before
    (parserRecognizeCursorAdvanceStatement cursorLocal) .next after
  effect : ModifiesOnly (CellSet.singleton cursorCell) before after
  finished : RecognizerChartCursorFinished grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell cursorCell after chartPosition cursorLocal

/-- Read a final state's empty `STATE_NEXT` link and install the concrete
    `-1` loop sentinel. -/
noncomputable def RecognizerChartCursorInvariant.exhaust
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current []) :
    RecognizerChartCursorExhaustion grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      invariant := by
  let state := Classical.choose invariant.state_at_cursor
  have stateFacts := Classical.choose_spec invariant.state_at_cursor
  have found : workspace.state? current = some state := stateFacts.1
  have statePosition : state.position = chartPosition := stateFacts.2
  let read := invariant.read_state_field state found 4 32 (by decide)
    verifiedParser_find_constants.2.2.2.2
  have nextValue : stateFieldValue workspace current state 4 = -1 := by
    simp only [stateFieldValue, stateNextValue]
    rw [statePosition, invariant.cursor.nextAfter]
    rfl
  have rightEvaluation : Evaluates verifiedParserCore runtime
      (parserRecognizeStateValueCall cursorLocal 32)
      (.signed .i32 (-1)) read.after := by
    simpa only [nextValue] using read.evaluation
  let assigned := evaluatesSetOwnedLocalFromEmpty
    (program := verifiedParserCore) cursorLocal cursorCell
    invariant.recognizer.wellFormed invariant.cursorOwned rightEvaluation
    read.invariant.recognizer.wellFormed read.effect
  let after := Classical.choose assigned
  have facts := Classical.choose_spec assigned
  have execution : Executes verifiedParserCore runtime
      (parserRecognizeCursorAdvanceStatement cursorLocal) .next after :=
    executesSequence (executesExpression facts.1)
      (executesSkip verifiedParserCore after)
  have nextRecognizer :=
    invariant.recognizer.after_disjoint_scalar_effect cursorCell facts.2.2.2
      facts.2.1 invariant.cursorBackingDistinct.1.symm
      invariant.cursorBackingDistinct.2.1.symm
      invariant.cursorBackingDistinct.2.2.symm
      (CellSet.Disjoint.mono_left
        (localBindingFrameFootprint_mono (fun id bound =>
          (ChartCursorFramedLocal_source_frame id).mp (Or.inl bound)))
        invariant.cursorFrameSeparate)
  have preserveStateBase : after.local? 8 = some
      (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))) :=
    facts.2.2.2.preserves_local_of_disjoint invariant.recognizer.wellFormed
      (localCellFootprint_disjoint_singleton (locals := fun id => id = 8)
        (by
          intro id same
          subst id
          exact invariant.cursorFramedDistinct 8
            (by simp [ChartCursorFramedLocal]))) rfl invariant.stateBaseLocal
  have finished : RecognizerChartCursorFinished grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell after chartPosition cursorLocal := {
    recognizer := nextRecognizer
    workspaceWithinGrammar := invariant.workspaceWithinGrammar
    stateBaseLocal := preserveStateBase
    cursorOwned := facts.2.2.1
    cursorFrameSeparate := by
      unfold ChartCursorFrameSeparated
      rw [facts.2.2.2.localBindingFrameFootprint_eq
        verifiedParserChartCursorBindings]
      exact invariant.cursorFrameSeparate
    cursorBackingDistinct := invariant.cursorBackingDistinct
    chartPositionBound := invariant.chartPositionBound
  }
  exact {
    after := after
    execution := execution
    effect := facts.2.2.2
    finished := finished
  }

noncomputable def RecognizerChartCursorInvariant.read_production
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining)
    (state : EarleyState) (found : workspace.state? current = some state) :
    RecognizerChartCursorRead grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining invariant 0 28 state :=
  invariant.read_state_field state found 0 28 (by decide)
    verifiedParser_find_constants.2.1

noncomputable def RecognizerChartCursorInvariant.read_dot
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining)
    (state : EarleyState) (found : workspace.state? current = some state) :
    RecognizerChartCursorRead grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining invariant 1 29 state :=
  invariant.read_state_field state found 1 29 (by decide)
    verifiedParser_find_constants.2.2.1

noncomputable def RecognizerChartCursorInvariant.read_origin
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining)
    (state : EarleyState) (found : workspace.state? current = some state) :
    RecognizerChartCursorRead grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining invariant 2 30 state :=
  invariant.read_state_field state found 2 30 (by decide)
    verifiedParser_find_constants.2.2.2.1

noncomputable def RecognizerChartCursorInvariant.read_next
    (invariant : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining)
    (state : EarleyState) (found : workspace.state? current = some state) :
    RecognizerChartCursorRead grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell runtime chartPosition cursorLocal current
      remaining invariant 4 32 state :=
  invariant.read_state_field state found 4 32 (by decide)
    verifiedParser_find_constants.2.2.2.2


end Lanius.Extraction.ParserRecognize
