import Lanius.Extraction.Parser.Recognize.State.Symbol
import Lanius.Extraction.Parser.Recognize.Prediction
import Lanius.Extraction.Parser.Recognize.Nullable

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
structure RecognizerStateNonterminalIndexBinding
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
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)
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
        grammar.grammar.n_kinds) where
  nonterminal : Nat
  nonterminalEq : nonterminal =
    (grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩ -
      grammar.grammar.n_kinds
  nonterminalBound : nonterminal < grammar.grammar.n_nonterminals
  evaluation : Evaluates verifiedParserCore
    (symbolBinding.afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
      ((grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))))
    (.binary .subtract (.local 29) (.local 11))
    (.signed .i32 (Int.ofNat nonterminal))
    (symbolBinding.afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
      ((grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩))))
  bound : State
  boundEq : bound =
    ((symbolBinding.afterRead.bindLocal 29 (.signed .i32 (Int.ofNat
      ((grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩)))).bindLocal
      30 (.signed .i32 (Int.ofNat nonterminal)))
  invariant : RecognizerStateLoopInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell bound position current remaining
  productionOwned : (Assertion.localPointsTo 25 bindings.productionCell
    (some (.signed .i32 (Int.ofNat candidate.production)))).holds bound
  dotOwned : (Assertion.localPointsTo 26 bindings.dotCell
    (some (.signed .i32 (Int.ofNat candidate.dot)))).holds bound
  originOwned : (Assertion.localPointsTo 27 bindings.originCell
    (some (.signed .i32 (Int.ofNat candidate.origin)))).holds bound
  expectedCell : CellId
  nonterminalLocal : bound.local? 30 =
    some (.signed .i32 (Int.ofNat nonterminal))
  expectedOwned : (Assertion.localPointsTo 30 expectedCell
    (some (.signed .i32 (Int.ofNat nonterminal)))).holds bound
  expectedCellDistinct : expectedCell ≠ workspaceCell ∧
    expectedCell ≠ stateCountCell ∧ expectedCell ≠ cursorCell

noncomputable def RecognizerStateSymbolBinding.bind_nonterminal_index
    (symbolBinding : RecognizerStateSymbolBinding grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isNonterminal : ¬
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩ <
        grammar.grammar.n_kinds) :
    RecognizerStateNonterminalIndexBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal := by
  let symbol := (grammar.productionAt ⟨candidate.production,
    productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
  let nonterminal := symbol - grammar.grammar.n_kinds
  let source := symbolBinding.afterRead.bindLocal 29
    (.signed .i32 (Int.ofNat symbol))
  have kindCountLe : grammar.grammar.n_kinds ≤ symbol := by
    exact Nat.le_of_not_gt (by simpa [symbol] using isNonterminal)
  have symbolMember : symbol ∈
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs := by
    simpa [symbol] using List.get_mem
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs ⟨candidate.dot, dotBeforeEnd⟩
  have symbolBound : symbol <
      grammar.grammar.n_kinds + grammar.grammar.n_nonterminals :=
    symbolBinding.invariant.chartCursor.recognizer.grammarWellFormed
      |>.production_validation.rhsSymbolsInBounds
        ⟨candidate.production, productionBound⟩ symbol symbolMember
  have nonterminalBound : nonterminal < grammar.grammar.n_nonterminals := by
    dsimp [nonterminal]
    omega
  have symbolResult : Evaluates verifiedParserCore source (.local 29)
      (.signed .i32 (Int.ofNat symbol)) source :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore source 29 _
      (by simpa [source, symbol] using symbolBinding.symbolLocal)⟩
  have kindCountResult : Evaluates verifiedParserCore source (.local 11)
      (.signed .i32 (Int.ofNat grammar.grammar.n_kinds)) source :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore source 11 _
      (by simpa [source, symbol] using
        symbolBinding.invariant.kindCountLocal)⟩
  have differenceEq : Int.ofNat symbol -
      Int.ofNat grammar.grammar.n_kinds = Int.ofNat nonterminal := by
    simp [nonterminal, Int.ofNat_sub kindCountLe]
  have nonterminalI32 : nonterminal ≤ 2147483647 := by
    have domainFits :=
      symbolBinding.invariant.chartCursor.recognizer.grammarWellFormed
        |>.symbolDomainFitsI32
    omega
  have evaluation : Evaluates verifiedParserCore source
      (.binary .subtract (.local 29) (.local 11))
      (.signed .i32 (Int.ofNat nonterminal)) source := by
    have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target nonterminal
      nonterminalI32
    apply evaluatesEagerBinary (by decide) (by decide) symbolResult
      kindCountResult
    simp only [evalBinaryValue, evalSignedBinary]
    rw [differenceEq, wrapped]
    simp
  let bound := source.bindLocal 30
    (.signed .i32 (Int.ofNat nonterminal))
  let expectedCell := source.nextCell
  exact {
    nonterminal := nonterminal
    nonterminalEq := rfl
    nonterminalBound := nonterminalBound
    evaluation := by simpa [source, symbol] using evaluation
    bound := bound
    boundEq := by simp [bound, source, symbol]
    invariant := by
      simpa [bound, source, symbol] using
        symbolBinding.invariant.after_bind_local 30
          (.signed .i32 (Int.ofNat nonterminal)) (by decide)
    productionOwned := by
      simpa [bound, source] using bindLocal_preserves_localPointsTo_of_ne
        source 30 25 (.signed .i32 (Int.ofNat nonterminal))
        bindings.productionCell
        (some (.signed .i32 (Int.ofNat candidate.production)))
        symbolBinding.invariant.chartCursor.recognizer.wellFormed (by decide)
        symbolBinding.productionOwned
    dotOwned := by
      simpa [bound, source] using bindLocal_preserves_localPointsTo_of_ne
        source 30 26 (.signed .i32 (Int.ofNat nonterminal)) bindings.dotCell
        (some (.signed .i32 (Int.ofNat candidate.dot)))
        symbolBinding.invariant.chartCursor.recognizer.wellFormed (by decide)
        symbolBinding.dotOwned
    originOwned := by
      simpa [bound, source] using bindLocal_preserves_localPointsTo_of_ne
        source 30 27 (.signed .i32 (Int.ofNat nonterminal))
        bindings.originCell
        (some (.signed .i32 (Int.ofNat candidate.origin)))
        symbolBinding.invariant.chartCursor.recognizer.wellFormed (by decide)
        symbolBinding.originOwned
    expectedCell := expectedCell
    nonterminalLocal := by
      simpa [bound] using bindLocal_finds_local source 30
        (.signed .i32 (Int.ofNat nonterminal))
        symbolBinding.invariant.chartCursor.recognizer.wellFormed
    expectedOwned := by
      simpa [bound, expectedCell] using bindLocal_owns_fresh source 30
        (.signed .i32 (Int.ofNat nonterminal))
        symbolBinding.invariant.chartCursor.recognizer.wellFormed
    expectedCellDistinct := by
      exact ⟨Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
          symbolBinding.invariant.chartCursor.recognizer.wellFormed
          symbolBinding.invariant.chartCursor.recognizer.workspaceBacking,
        Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
          symbolBinding.invariant.chartCursor.recognizer.wellFormed
          symbolBinding.invariant.appendFrame.stateCountOwned.2,
        Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
          symbolBinding.invariant.chartCursor.recognizer.wellFormed
          symbolBinding.invariant.chartCursor.cursorOwned.2⟩
  }

structure RecognizerStatePredictionEntry
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
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)
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
      bindings symbolBinding isNonterminal) where
  first : Nat
  count : Nat
  firstEvaluation : Evaluates verifiedParserCore nonterminalBinding.bound
    (.index (.local 0) (.binary .add (.local 13) (.local 30)))
    (.signed .i32 (Int.ofNat first)) nonterminalBinding.bound
  countEvaluation : Evaluates verifiedParserCore
    (nonterminalBinding.bound.bindLocal 31
      (.signed .i32 (Int.ofNat first)))
    (.index (.local 0) (.binary .add (.local 14) (.local 30)))
    (.signed .i32 (Int.ofNat count))
    (nonterminalBinding.bound.bindLocal 31
      (.signed .i32 (Int.ofNat first)))
  indexCell : CellId
  indexCellEq : indexCell =
    ((nonterminalBinding.bound.bindLocal 31
      (.signed .i32 (Int.ofNat first))).bindLocal 32
        (.signed .i32 (Int.ofNat count))).nextCell
  predictionState : State
  predictionStateEq : predictionState =
    (((nonterminalBinding.bound.bindLocal 31
      (.signed .i32 (Int.ofNat first))).bindLocal 32
        (.signed .i32 (Int.ofNat count))).bindLocal 33
          (.signed .i32 0))
  invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell indexCell predictionState position first count 0
  stateInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell predictionState position current
    remaining
  cursorOwned : (Assertion.localPointsTo 24 cursorCell
    (some (.signed .i32 (Int.ofNat current)))).holds predictionState
  productionOwned : (Assertion.localPointsTo 25 bindings.productionCell
    (some (.signed .i32 (Int.ofNat candidate.production)))).holds
      predictionState
  dotOwned : (Assertion.localPointsTo 26 bindings.dotCell
    (some (.signed .i32 (Int.ofNat candidate.dot)))).holds predictionState
  originOwned : (Assertion.localPointsTo 27 bindings.originCell
    (some (.signed .i32 (Int.ofNat candidate.origin)))).holds predictionState
  expectedOwned : (Assertion.localPointsTo 30
    nonterminalBinding.expectedCell
    (some (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal)))).holds
      predictionState
  persistentLocalIndexSeparate : CellSet.Disjoint
    (localBindingFrameFootprint predictionState
      verifiedParserStateLoopPersistentBindings)
    (CellSet.singleton indexCell)
  cursorIndexDistinct : cursorCell ≠ indexCell
  productionIndexDistinct : bindings.productionCell ≠ indexCell
  dotIndexDistinct : bindings.dotCell ≠ indexCell
  originIndexDistinct : bindings.originCell ≠ indexCell
  expectedIndexDistinct : nonterminalBinding.expectedCell ≠ indexCell

theorem RecognizerStatePredictionEntry.persistentLocalIndexDistinct
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding)
    (id : VarId) (persistent : StateLoopPersistentLocal id) :
    entry.predictionState.cellId? id ≠ some entry.indexCell :=
  entry.persistentLocalIndexSeparate.localCell_ne_of_singleton
    ((StateLoopPersistentLocal_source_frame id).mp persistent)

noncomputable def RecognizerStateNonterminalIndexBinding.enter_prediction
    (nonterminalBinding : RecognizerStateNonterminalIndexBinding grammarLayout
      grammar words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell runtime position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal) :
    RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding := by
  let nonterminal := nonterminalBinding.nonterminal
  have lhsOffsetBound : nonterminal < grammar.lhsOffsets.length := by
    simpa [grammar.lhsOffsets_length,
      nonterminalBinding.invariant.chartCursor.recognizer.grammarWellFormed
        |>.lhsIndexCount] using nonterminalBinding.nonterminalBound
  have lhsCountBound : nonterminal < grammar.lhsCounts.length := by
    simpa [grammar.lhsCounts_length,
      nonterminalBinding.invariant.chartCursor.recognizer.grammarWellFormed
        |>.lhsIndexCount] using nonterminalBinding.nonterminalBound
  let first := grammar.lhsOffsets.get ⟨nonterminal, lhsOffsetBound⟩
  let count := grammar.lhsCounts.get ⟨nonterminal, lhsCountBound⟩
  have firstEvaluation : Evaluates verifiedParserCore nonterminalBinding.bound
      (.index (.local 0) (.binary .add (.local 13) (.local 30)))
      (.signed .i32 (Int.ofNat first)) nonterminalBinding.bound := by
    simpa [first, nonterminal] using
      nonterminalBinding.invariant.read_lhs_offset nonterminal
        nonterminalBinding.nonterminalBound nonterminalBinding.nonterminalLocal
  let firstState := nonterminalBinding.bound.bindLocal 31
    (.signed .i32 (Int.ofNat first))
  let firstInvariant := nonterminalBinding.invariant.after_bind_local 31
    (.signed .i32 (Int.ofNat first)) (by decide)
  have nonterminalAtFirst : firstState.local? 30 =
      some (.signed .i32 (Int.ofNat nonterminal)) :=
    (bindLocal_preserves_other_local
      nonterminalBinding.invariant.chartCursor.recognizer.wellFormed
      (by decide : 31 ≠ 30)).trans nonterminalBinding.nonterminalLocal
  have countEvaluation : Evaluates verifiedParserCore firstState
      (.index (.local 0) (.binary .add (.local 14) (.local 30)))
      (.signed .i32 (Int.ofNat count)) firstState := by
    simpa [firstState, firstInvariant, count, nonterminal] using
      firstInvariant.read_lhs_count nonterminal
        nonterminalBinding.nonterminalBound nonterminalAtFirst
  let countState := firstState.bindLocal 32
    (.signed .i32 (Int.ofNat count))
  let countInvariant := firstInvariant.after_bind_local 32
    (.signed .i32 (Int.ofNat count)) (by decide)
  let indexCell := countState.nextCell
  let predictionState := countState.bindLocal 33 (.signed .i32 0)
  let predictionStateInvariant := countInvariant.after_bind_local 33
    (.signed .i32 0) (by decide)
  have preserveOwned (id : VarId) (cell : CellId) (value : Value)
      (idNot31 : 31 ≠ id) (idNot32 : 32 ≠ id) (idNot33 : 33 ≠ id)
      (owned : (Assertion.localPointsTo id cell (some value)).holds
        nonterminalBinding.bound) :
      (Assertion.localPointsTo id cell (some value)).holds
        predictionState := by
    have atFirst := bindLocal_preserves_localPointsTo_of_ne
      nonterminalBinding.bound 31 id (.signed .i32 (Int.ofNat first)) cell
      (some value)
      nonterminalBinding.invariant.chartCursor.recognizer.wellFormed idNot31
      owned
    have atCount := bindLocal_preserves_localPointsTo_of_ne firstState 32 id
      (.signed .i32 (Int.ofNat count)) cell (some value)
      firstInvariant.chartCursor.recognizer.wellFormed idNot32 (by
        simpa [firstState] using atFirst)
    simpa [countState, predictionState] using
      bindLocal_preserves_localPointsTo_of_ne countState 33 id
        (.signed .i32 0) cell (some value)
        countInvariant.chartCursor.recognizer.wellFormed idNot33 (by
          simpa [countState] using atCount)
  have cursorOwned := preserveOwned 24 cursorCell
    (.signed .i32 (Int.ofNat current)) (by decide) (by decide) (by decide)
    nonterminalBinding.invariant.chartCursor.cursorOwned
  have productionOwned := preserveOwned 25 bindings.productionCell
    (.signed .i32 (Int.ofNat candidate.production))
    (by decide) (by decide) (by decide) nonterminalBinding.productionOwned
  have dotOwned := preserveOwned 26 bindings.dotCell
    (.signed .i32 (Int.ofNat candidate.dot))
    (by decide) (by decide) (by decide) nonterminalBinding.dotOwned
  have originOwned := preserveOwned 27 bindings.originCell
    (.signed .i32 (Int.ofNat candidate.origin))
    (by decide) (by decide) (by decide) nonterminalBinding.originOwned
  have expectedOwned := preserveOwned 30 nonterminalBinding.expectedCell
    (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal))
    (by decide) (by decide) (by decide) nonterminalBinding.expectedOwned
  have firstOwnedAtFirst := bindLocal_owns_fresh nonterminalBinding.bound 31
    (.signed .i32 (Int.ofNat first))
    nonterminalBinding.invariant.chartCursor.recognizer.wellFormed
  have firstOwnedAtCount : (Assertion.localPointsTo 31
      nonterminalBinding.bound.nextCell
      (some (.signed .i32 (Int.ofNat first)))).holds countState := by
    simpa [firstState, countState] using
      bindLocal_preserves_localPointsTo_of_ne firstState 32 31
        (.signed .i32 (Int.ofNat count)) nonterminalBinding.bound.nextCell
        (some (.signed .i32 (Int.ofNat first)))
        firstInvariant.chartCursor.recognizer.wellFormed (by decide)
        firstOwnedAtFirst
  have firstOwned : (Assertion.localPointsTo 31
      nonterminalBinding.bound.nextCell
      (some (.signed .i32 (Int.ofNat first)))).holds predictionState := by
    simpa [predictionState] using
      bindLocal_preserves_localPointsTo_of_ne countState 33 31
        (.signed .i32 0) nonterminalBinding.bound.nextCell
        (some (.signed .i32 (Int.ofNat first)))
        countInvariant.chartCursor.recognizer.wellFormed (by decide)
        firstOwnedAtCount
  have countOwnedAtCount := bindLocal_owns_fresh firstState 32
    (.signed .i32 (Int.ofNat count))
    firstInvariant.chartCursor.recognizer.wellFormed
  have countOwned : (Assertion.localPointsTo 32 firstState.nextCell
      (some (.signed .i32 (Int.ofNat count)))).holds predictionState := by
    simpa [countState, predictionState] using
      bindLocal_preserves_localPointsTo_of_ne countState 33 32
        (.signed .i32 0) firstState.nextCell
        (some (.signed .i32 (Int.ofNat count)))
        countInvariant.chartCursor.recognizer.wellFormed (by decide)
        countOwnedAtCount
  have firstWorkspaceDistinct :
      nonterminalBinding.bound.nextCell ≠ workspaceCell :=
    Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
      nonterminalBinding.invariant.chartCursor.recognizer.wellFormed
      nonterminalBinding.invariant.chartCursor.recognizer.workspaceBacking
  have firstStateCountDistinct :
      nonterminalBinding.bound.nextCell ≠ stateCountCell :=
    Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
      nonterminalBinding.invariant.chartCursor.recognizer.wellFormed
      nonterminalBinding.invariant.appendFrame.stateCountOwned.2
  have countWorkspaceDistinct : firstState.nextCell ≠ workspaceCell :=
    Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
      firstInvariant.chartCursor.recognizer.wellFormed
      firstInvariant.chartCursor.recognizer.workspaceBacking
  have countStateCountDistinct : firstState.nextCell ≠ stateCountCell :=
    Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
      firstInvariant.chartCursor.recognizer.wellFormed
      firstInvariant.appendFrame.stateCountOwned.2
  have indexFresh (id : VarId) (different : 33 ≠ id) :
      predictionState.cellId? id ≠ some indexCell := by
    simpa [predictionState, indexCell] using
      bindLocal_other_cellId_ne_fresh countState 33 id (.signed .i32 0)
        countInvariant.chartCursor.recognizer.wellFormed different
  have persistentExternal (id : VarId)
      (persistent : PredictionPersistentLocal id) :
      predictionState.cellId? id ≠ some workspaceCell ∧
        (id ≠ 18 → predictionState.cellId? id ≠ some stateCountCell) := by
    rw [PredictionPersistentLocal_iff] at persistent
    rcases persistent with parameter | rfl | rfl | rfl | rfl | rfl | rfl | rfl
    · have idLe :=
        (mem_verifiedParserRecognizerParameterIds_iff id).mp parameter
      have base := predictionStateInvariant.persistentLocalsSeparate id
        (Or.inl parameter)
      exact ⟨base.1, fun notCount => base.2.1 notCount⟩
    · exact ⟨predictionStateInvariant.persistentLocalsSeparate 8
        (by simp [StateLoopPersistentLocal]) |>.1, fun notCount =>
          predictionStateInvariant.persistentLocalsSeparate 8 (by
            simp [StateLoopPersistentLocal])
            |>.2.1 notCount⟩
    · exact ⟨predictionStateInvariant.persistentLocalsSeparate 9
        (by simp [StateLoopPersistentLocal]) |>.1, fun notCount =>
          predictionStateInvariant.persistentLocalsSeparate 9 (by
            simp [StateLoopPersistentLocal])
            |>.2.1 notCount⟩
    · exact ⟨predictionStateInvariant.persistentLocalsSeparate 15
        (by simp [StateLoopPersistentLocal]) |>.1, fun notCount =>
          predictionStateInvariant.persistentLocalsSeparate 15 (by
            simp [StateLoopPersistentLocal])
            |>.2.1 notCount⟩
    · exact ⟨predictionStateInvariant.persistentLocalsSeparate 18
        (by simp [StateLoopPersistentLocal]) |>.1,
          fun impossible => False.elim (impossible rfl)⟩
    · exact ⟨predictionStateInvariant.persistentLocalsSeparate 23
        (by simp [StateLoopPersistentLocal]) |>.1, fun notCount =>
          predictionStateInvariant.persistentLocalsSeparate 23 (by
            simp [StateLoopPersistentLocal])
            |>.2.1 notCount⟩
    · exact ⟨fun same => firstWorkspaceDistinct
          (Option.some.inj (firstOwned.1.symm.trans same)),
        fun _ same => firstStateCountDistinct
          (Option.some.inj (firstOwned.1.symm.trans same))⟩
    · exact ⟨fun same => countWorkspaceDistinct
          (Option.some.inj (countOwned.1.symm.trans same)),
        fun _ same => countStateCountDistinct
          (Option.some.inj (countOwned.1.symm.trans same))⟩
  have indexBackingDistinct :
      indexCell ≠ grammarCell ∧ indexCell ≠ tokensCell ∧
        indexCell ≠ workspaceCell ∧ indexCell ≠ stateCountCell := by
    exact ⟨Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        countInvariant.chartCursor.recognizer.wellFormed
        countInvariant.chartCursor.recognizer.grammarBacking,
      Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        countInvariant.chartCursor.recognizer.wellFormed
        countInvariant.chartCursor.recognizer.tokensBacking,
      Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        countInvariant.chartCursor.recognizer.wellFormed
        countInvariant.chartCursor.recognizer.workspaceBacking,
      Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        countInvariant.chartCursor.recognizer.wellFormed
        countInvariant.appendFrame.stateCountOwned.2⟩
  let rowId : Fin grammar.productionsByLhs.length :=
    ⟨nonterminal, by
      simpa [nonterminalBinding.invariant.chartCursor.recognizer
        |>.grammarWellFormed.lhsIndexCount] using
          nonterminalBinding.nonterminalBound⟩
  have rowRange : first + count ≤ grammar.lhsProductions.length := by
    have fits := offsetsFrom_row_fits 0 grammar.productionsByLhs rowId
    simpa [first, count, rowId, IndexedGrammar.lhsOffsets,
      IndexedGrammar.lhsCounts, IndexedGrammar.lhsProductions] using fits
  let row := grammar.productionsByLhs.get rowId
  have rowFound : grammar.productionsByLhs[nonterminal]? = some row := by
    rw [List.getElem?_eq_getElem rowId.isLt]
    simp [row, rowId, List.get_eq_getElem]
  have countEq : count = row.length := by
    simpa [count, row, rowId] using grammar.lhsCounts_get rowId
  have rowProductionBound : ∀ (rowIndex : Nat)
      (rowIndexBound : rowIndex < count),
      grammar.lhsProductions.get ⟨first + rowIndex, by
        have := rowRange
        omega⟩ < grammar.productionCount := by
    intro rowIndex indexBound
    have indexRowBound : rowIndex < row.length := by
      simpa [countEq] using indexBound
    let indexId : Fin row.length := ⟨rowIndex, indexRowBound⟩
    have packedEq := grammar.lhsProductions_get_at_row rowId indexId
    have selectedMember : row.get indexId ∈ row := List.get_mem row indexId
    obtain ⟨selectedBound, _⟩ :=
      nonterminalBinding.invariant.chartCursor.recognizer.grammarWellFormed
        |>.nonterminal_validation.listedProductionValid nonterminal row
          nonterminalBinding.nonterminalBound rowFound (row.get indexId)
          selectedMember
    have selectedEq : grammar.lhsProductions.get
        ⟨first + rowIndex, by
          have := rowRange
          omega⟩ = row.get indexId := by
      simpa [first, row, rowId, indexId] using packedEq
    rw [selectedEq]
    exact selectedBound
  exact {
    first := first
    count := count
    firstEvaluation := firstEvaluation
    countEvaluation := by simpa [firstState] using countEvaluation
    indexCell := indexCell
    indexCellEq := rfl
    predictionState := predictionState
    predictionStateEq := rfl
    invariant := by
      simpa [predictionState] using
        (show RecognizerPredictionLoopInvariant grammarLayout grammar words
          tokens workspaceLayout workspace workspaceValues grammarCell
          tokensCell workspaceCell stateCountCell indexCell predictionState
          position first count 0 from {
            frame := predictionStateInvariant.appendFrame
            workspaceWithinGrammar :=
              predictionStateInvariant.chartCursor.workspaceWithinGrammar
            positionLocal := predictionStateInvariant.positionLocal
            lhsProductionsOffsetLocal :=
              predictionStateInvariant.lhsProductionsOffsetLocal
            firstLocal := firstOwned.1 |> fun _ => by
              simpa [predictionState] using
                (Assertion.localPointsTo_local 31
                  nonterminalBinding.bound.nextCell _ predictionState firstOwned)
            countLocal := by
              exact Assertion.localPointsTo_local 32 firstState.nextCell _
                predictionState countOwned
            indexOwned := by
              simpa [predictionState, indexCell] using
                bindLocal_owns_fresh countState 33 (.signed .i32 0)
                  countInvariant.chartCursor.recognizer.wellFormed
            indexLe := Nat.zero_le count
            rowRange := rowRange
            rowProductionBound := rowProductionBound
            persistentSeparate := by
              intro cell framed written
              obtain ⟨id, preserved, cellId⟩ := framed
              have ⟨persistent, notStateCount⟩ :=
                (PredictionPreservedLocal_iff id).mp
                  ((PredictionPreservedLocal_source_frame id).mpr preserved)
              change cell = workspaceCell ∨ cell = stateCountCell ∨
                cell = indexCell at written
              rcases written with same | same | same
              · subst cell
                exact (persistentExternal id persistent).1 cellId
              · subst cell
                exact (persistentExternal id persistent).2 notStateCount cellId
              · subst cell
                exact indexFresh id (Nat.ne_of_gt persistent.lt33) cellId
            indexBackingDistinct := indexBackingDistinct
          })
    stateInvariant := by
      simpa [predictionState, countState, firstState] using
        predictionStateInvariant
    cursorOwned := cursorOwned
    productionOwned := productionOwned
    dotOwned := dotOwned
    originOwned := originOwned
    expectedOwned := expectedOwned
    persistentLocalIndexSeparate := localCellFootprint_disjoint_singleton (by
      intro id framed
      have persistent := (StateLoopPersistentLocal_source_frame id).mpr framed
      exact indexFresh id (Nat.ne_of_gt
        (Nat.lt_of_le_of_lt persistent.le23 (by decide))))
    cursorIndexDistinct := by
      intro same
      apply indexFresh 24 (by decide)
      simpa [same] using cursorOwned.1
    productionIndexDistinct := by
      intro same
      apply indexFresh 25 (by decide)
      simpa [same] using productionOwned.1
    dotIndexDistinct := by
      intro same
      apply indexFresh 26 (by decide)
      simpa [same] using dotOwned.1
    originIndexDistinct := by
      intro same
      apply indexFresh 27 (by decide)
      simpa [same] using originOwned.1
    expectedIndexDistinct := by
      intro same
      apply indexFresh 30 (by decide)
      simpa [same] using expectedOwned.1
  }

/-- Completed prediction replay, rebased into the enclosing state-chain
    frame.  The candidate being processed remains selected even when
    prediction appends extend its chart; the returned suffix is the exact
    suffix reconstructed in the enlarged logical workspace. -/
structure RecognizerStatePredictionCompletedFrame
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (beforeValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    (candidate : EarleyState)
    (found : beforeWorkspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound)
    (symbolBinding : RecognizerStateSymbolBinding grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isNonterminal : ¬
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩ <
        grammar.grammar.n_kinds)
    (nonterminalBinding : RecognizerStateNonterminalIndexBinding grammarLayout
      grammar words tokens workspaceLayout beforeWorkspace beforeValues
      grammarCell tokensCell workspaceCell stateCountCell cursorCell before
      position current remaining beforeInvariant candidate found
      productionBound dotBeforeEnd bindings symbolBinding isNonterminal)
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding) where
  workspace : LogicalWorkspace
  workspaceValues : List Int
  after : State
  nextRemaining : List Nat
  growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
    workspace
  predictionInvariant : RecognizerPredictionLoopInvariant grammarLayout grammar
    words tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell entry.indexCell after position entry.first
    entry.count entry.count
  stateInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell after position current nextRemaining
  progress :
    (workspace.states.length = beforeWorkspace.states.length ∧
      nextRemaining = remaining) ∨
    beforeWorkspace.states.length < workspace.states.length
  productionOwned : (Assertion.localPointsTo 25 bindings.productionCell
    (some (.signed .i32 (Int.ofNat candidate.production)))).holds after
  dotOwned : (Assertion.localPointsTo 26 bindings.dotCell
    (some (.signed .i32 (Int.ofNat candidate.dot)))).holds after
  originOwned : (Assertion.localPointsTo 27 bindings.originCell
    (some (.signed .i32 (Int.ofNat candidate.origin)))).holds after
  expectedOwned : (Assertion.localPointsTo 30
    nonterminalBinding.expectedCell
    (some (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal)))).holds after

noncomputable def RecognizerStatePredictionEntry.reframe_completed
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding)
    (workspace : LogicalWorkspace) (workspaceValues : List Int) (after : State)
    (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
      workspace)
    (predictionInvariant : RecognizerPredictionLoopInvariant grammarLayout
      grammar words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell entry.indexCell after position
      entry.first entry.count entry.count)
    (effect : ModifiesOnly
      (CellSet.union (CellSet.singleton workspaceCell)
        (CellSet.union (CellSet.singleton stateCountCell)
          (CellSet.singleton entry.indexCell))) entry.predictionState after) :
    RecognizerStatePredictionCompletedFrame grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding entry := by
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton entry.indexCell))
  have cursorNotWritten : ¬ writes cursorCell := by
    simpa [writes, CellSet.union, CellSet.singleton, not_or] using
      ⟨entry.stateInvariant.chartCursor.cursorBackingDistinct.2.2,
        entry.stateInvariant.cursorStateCountDistinct,
        entry.cursorIndexDistinct⟩
  have productionNotWritten : ¬ writes bindings.productionCell := by
    simpa [writes, CellSet.union, CellSet.singleton, not_or] using
      ⟨bindings.productionCellDistinct.1,
        bindings.productionCellDistinct.2.1,
        entry.productionIndexDistinct⟩
  have dotNotWritten : ¬ writes bindings.dotCell := by
    simpa [writes, CellSet.union, CellSet.singleton, not_or] using
      ⟨bindings.dotCellDistinct.1, bindings.dotCellDistinct.2.1,
        entry.dotIndexDistinct⟩
  have originNotWritten : ¬ writes bindings.originCell := by
    simpa [writes, CellSet.union, CellSet.singleton, not_or] using
      ⟨bindings.originCellDistinct.1, bindings.originCellDistinct.2.1,
        entry.originIndexDistinct⟩
  have expectedNotWritten : ¬ writes nonterminalBinding.expectedCell := by
    simpa [writes, CellSet.union, CellSet.singleton, not_or] using
      ⟨nonterminalBinding.expectedCellDistinct.1,
        nonterminalBinding.expectedCellDistinct.2.1,
        entry.expectedIndexDistinct⟩
  have productionOwned := effect.preserves_localPointsTo
    entry.invariant.frame.recognizer.wellFormed entry.productionOwned
    (by simpa [writes] using productionNotWritten)
  have dotOwned := effect.preserves_localPointsTo
    entry.invariant.frame.recognizer.wellFormed entry.dotOwned
    (by simpa [writes] using dotNotWritten)
  have originOwned := effect.preserves_localPointsTo
    entry.invariant.frame.recognizer.wellFormed entry.originOwned
    (by simpa [writes] using originNotWritten)
  have expectedOwned := effect.preserves_localPointsTo
    entry.invariant.frame.recognizer.wellFormed entry.expectedOwned
    (by simpa [writes] using expectedNotWritten)
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint entry.predictionState
        verifiedParserStateLoopPreservedBindings) writes := by
    intro cell framed written
    obtain ⟨id, preserved, cellId⟩ := framed
    have ⟨persistent, idNotCount⟩ :=
      (StateLoopPreservedLocal_iff id).mp
        ((StateLoopPreservedLocal_source_frame id).mpr preserved)
    have separated := entry.stateInvariant.persistentLocalsSeparate id persistent
    change cell = workspaceCell ∨ cell = stateCountCell ∨
      cell = entry.indexCell at written
    rcases written with same | same | same
    · subst cell; exact separated.1 cellId
    · subst cell; exact separated.2.1 idNotCount cellId
    · subst cell
      exact entry.persistentLocalIndexDistinct id persistent cellId
  let stateFrame := entry.stateInvariant.reframe_growth workspace workspaceValues
    after growth predictionInvariant.frame.recognizer
    predictionInvariant.workspaceWithinGrammar
    predictionInvariant.frame.stateCountOwned writes (by
      simpa [writes] using effect) frameDisjoint cursorNotWritten
  exact {
    workspace := workspace
    workspaceValues := workspaceValues
    after := after
    nextRemaining := stateFrame.nextRemaining
    growth := growth
    predictionInvariant := predictionInvariant
    stateInvariant := stateFrame.invariant
    progress := stateFrame.progress
    productionOwned := productionOwned
    dotOwned := dotOwned
    originOwned := originOwned
    expectedOwned := expectedOwned
  }

/-- Entry to nullable replay after prediction has finished.  Reading the
    chart head is read-only; the extracted `let nullable = ...` then owns one
    fresh cursor cell.  An empty chart enters the already-finished state,
    while a nonempty chart carries its exact unvisited suffix. -/
structure RecognizerStateNullableEntry
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (beforeValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    (candidate : EarleyState)
    (found : beforeWorkspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound)
    (symbolBinding : RecognizerStateSymbolBinding grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isNonterminal : ¬
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩ <
        grammar.grammar.n_kinds)
    (nonterminalBinding : RecognizerStateNonterminalIndexBinding grammarLayout
      grammar words tokens workspaceLayout beforeWorkspace beforeValues
      grammarCell tokensCell workspaceCell stateCountCell cursorCell before
      position current remaining beforeInvariant candidate found
      productionBound dotBeforeEnd bindings symbolBinding isNonterminal)
    (predictionEntry : RecognizerStatePredictionEntry grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace beforeValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal nonterminalBinding)
    (completed : RecognizerStatePredictionCompletedFrame grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace beforeValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal nonterminalBinding predictionEntry)
    where
  headRead : RecognizerChartHeadRead grammarLayout grammar words tokens
    workspaceLayout completed.workspace completed.workspaceValues grammarCell
    tokensCell workspaceCell completed.after 23 position
    completed.stateInvariant.chartCursor.recognizer
  nullableCursorCell : CellId
  nullableCursorCellEq : nullableCursorCell = headRead.after.nextCell
  bound : State
  boundEq : bound = headRead.after.bindLocal 36
    (.signed .i32 (chartHeadValue completed.workspace position))
  cursor :
    (Sigma fun nullableCurrent : Nat => Sigma fun nullableRemaining : List Nat =>
      RecognizerNullableLoopInvariant grammarLayout grammar words tokens
        workspaceLayout completed.workspace completed.workspaceValues
        grammarCell tokensCell workspaceCell stateCountCell nullableCursorCell
        bound position candidate.production candidate.dot candidate.origin
        current nonterminalBinding.nonterminal nullableCurrent nullableRemaining)
    ⊕ RecognizerNullableFinishedInvariant grammarLayout grammar words tokens
        workspaceLayout completed.workspace completed.workspaceValues
        grammarCell tokensCell workspaceCell stateCountCell nullableCursorCell
        bound position candidate.production candidate.dot candidate.origin
        current nonterminalBinding.nonterminal

noncomputable def RecognizerStatePredictionCompletedFrame.enter_nullable
    (completed : RecognizerStatePredictionCompletedFrame grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace beforeValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal nonterminalBinding predictionEntry) :
    RecognizerStateNullableEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry completed := by
  let headRead := completed.stateInvariant.chartCursor.recognizer.read_chart_head
    23 position completed.stateInvariant.positionLocal
    completed.stateInvariant.chartCursor.chartPositionBound
  let afterReadInvariant := completed.stateInvariant.after_empty_effect
    headRead.effect headRead.invariant.wellFormed
  let nullableCursorCell := headRead.after.nextCell
  let bound := headRead.after.bindLocal 36
    (.signed .i32 (chartHeadValue completed.workspace position))
  let boundStateInvariant := afterReadInvariant.after_bind_local 36
    (.signed .i32 (chartHeadValue completed.workspace position)) (by decide)
  have preserveOwned (id : VarId) (cell : CellId) (value : Value)
      (different : 36 ≠ id)
      (owned : (Assertion.localPointsTo id cell (some value)).holds
        completed.after) :
      (Assertion.localPointsTo id cell (some value)).holds bound := by
    have afterReadOwned := headRead.effect.empty_preserves_assertion
      completed.stateInvariant.chartCursor.recognizer.wellFormed _ owned
    simpa [bound] using bindLocal_preserves_localPointsTo_of_ne headRead.after
      36 id (.signed .i32 (chartHeadValue completed.workspace position)) cell
      (some value) headRead.invariant.wellFormed different afterReadOwned
  have productionOwned := preserveOwned 25 bindings.productionCell
    (.signed .i32 (Int.ofNat candidate.production)) (by decide)
    completed.productionOwned
  have dotOwned := preserveOwned 26 bindings.dotCell
    (.signed .i32 (Int.ofNat candidate.dot)) (by decide) completed.dotOwned
  have originOwned := preserveOwned 27 bindings.originCell
    (.signed .i32 (Int.ofNat candidate.origin)) (by decide)
    completed.originOwned
  have expectedOwned := preserveOwned 30 nonterminalBinding.expectedCell
    (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal)) (by decide)
    completed.expectedOwned
  have outerCursorOwned := preserveOwned 24 cursorCell
    (.signed .i32 (Int.ofNat current)) (by decide)
    completed.stateInvariant.chartCursor.cursorOwned
  have nullableCursorOwned : (Assertion.localPointsTo 36 nullableCursorCell
      (some (.signed .i32 (chartHeadValue completed.workspace position)))).holds
      bound := by
    simpa [bound, nullableCursorCell] using bindLocal_owns_fresh headRead.after
      36 (.signed .i32 (chartHeadValue completed.workspace position))
      headRead.invariant.wellFormed
  have nullableCursorFrameSeparate : ChartCursorFrameSeparated bound
      nullableCursorCell := by
    simpa [bound, nullableCursorCell, ChartCursorFrameSeparated] using
      bindLocal_fresh_disjoint_from_frame headRead.after 36
        (.signed .i32 (chartHeadValue completed.workspace position))
        verifiedParserChartCursorBindings headRead.invariant.wellFormed
        (by
          rw [LocalBindingFrame.ContainsCoreId,
            verifiedParserChartCursorBindings_core_ids]
          native_decide)
  have nullableCursorBackingDistinct : nullableCursorCell ≠ grammarCell ∧
      nullableCursorCell ≠ tokensCell ∧
      nullableCursorCell ≠ workspaceCell := by
    simpa [nullableCursorCell] using
      (⟨Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
          headRead.invariant.wellFormed headRead.invariant.grammarBacking,
        Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
          headRead.invariant.wellFormed headRead.invariant.tokensBacking,
        Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
          headRead.invariant.wellFormed headRead.invariant.workspaceBacking⟩)
  have nullableCursorStateCountDistinct : nullableCursorCell ≠ stateCountCell := by
    simpa [nullableCursorCell] using
      Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        headRead.invariant.wellFormed
        afterReadInvariant.appendFrame.stateCountOwned.2
  have nullableExternal (id : VarId) (preserved : NullablePreservedLocal id) :
      bound.cellId? id ≠ some workspaceCell ∧
        bound.cellId? id ≠ some stateCountCell := by
    rcases preserved with parameter | framed
    · have separated := boundStateInvariant.persistentLocalsSeparate id
        (Or.inl parameter)
      exact ⟨separated.1, separated.2.1 (by
        have boundId := (mem_verifiedParserRecognizerParameterIds_iff id).mp
          parameter
        exact Nat.ne_of_lt (Nat.lt_of_le_of_lt boundId (by decide)))⟩
    · rw [mem_verifiedParserNullableLoopPreservedFrameIds_iff] at framed
      rcases framed with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
          rfl | rfl
      · exact ⟨boundStateInvariant.persistentLocalsSeparate 4 (by
          simp [StateLoopPersistentLocal]) |>.1,
          boundStateInvariant.persistentLocalsSeparate 4 (by
            simp [StateLoopPersistentLocal]) |>.2.1 (by decide)⟩
      · exact ⟨boundStateInvariant.persistentLocalsSeparate 8 (by
          simp [StateLoopPersistentLocal]) |>.1,
          boundStateInvariant.persistentLocalsSeparate 8 (by
            simp [StateLoopPersistentLocal]) |>.2.1 (by decide)⟩
      · exact ⟨boundStateInvariant.persistentLocalsSeparate 23 (by
          simp [StateLoopPersistentLocal]) |>.1,
          boundStateInvariant.persistentLocalsSeparate 23 (by
            simp [StateLoopPersistentLocal]) |>.2.1 (by decide)⟩
      · exact ⟨boundStateInvariant.persistentLocalsSeparate 0 (by
          simp [StateLoopPersistentLocal]) |>.1,
          boundStateInvariant.persistentLocalsSeparate 0 (by
            simp [StateLoopPersistentLocal]) |>.2.1 (by decide)⟩
      · exact ⟨fun same => nonterminalBinding.expectedCellDistinct.1
            (Option.some.inj (expectedOwned.1.symm.trans same)),
          fun same => nonterminalBinding.expectedCellDistinct.2.1
            (Option.some.inj (expectedOwned.1.symm.trans same))⟩
      · exact ⟨boundStateInvariant.persistentLocalsSeparate 9 (by
          simp [StateLoopPersistentLocal]) |>.1,
          boundStateInvariant.persistentLocalsSeparate 9 (by
            simp [StateLoopPersistentLocal]) |>.2.1 (by decide)⟩
      · exact ⟨fun same => bindings.productionCellDistinct.1
            (Option.some.inj (productionOwned.1.symm.trans same)),
          fun same => bindings.productionCellDistinct.2.1
            (Option.some.inj (productionOwned.1.symm.trans same))⟩
      · exact ⟨fun same => bindings.dotCellDistinct.1
            (Option.some.inj (dotOwned.1.symm.trans same)),
          fun same => bindings.dotCellDistinct.2.1
            (Option.some.inj (dotOwned.1.symm.trans same))⟩
      · exact ⟨fun same => bindings.originCellDistinct.1
            (Option.some.inj (originOwned.1.symm.trans same)),
          fun same => bindings.originCellDistinct.2.1
            (Option.some.inj (originOwned.1.symm.trans same))⟩
      · exact ⟨fun same =>
            completed.stateInvariant.chartCursor.cursorBackingDistinct.2.2
              (Option.some.inj (outerCursorOwned.1.symm.trans same)),
          fun same => completed.stateInvariant.cursorStateCountDistinct
            (Option.some.inj (outerCursorOwned.1.symm.trans same))⟩
  have nullableFrameFresh : CellSet.Disjoint
      (localBindingFrameFootprint bound
        verifiedParserNullableLoopPreservedBindings)
      (CellSet.singleton nullableCursorCell) := by
    simpa [bound, nullableCursorCell] using
      bindLocal_fresh_disjoint_from_frame headRead.after 36
        (.signed .i32 (chartHeadValue completed.workspace position))
        verifiedParserNullableLoopPreservedBindings headRead.invariant.wellFormed
        (by
          rw [LocalBindingFrame.ContainsCoreId,
            verifiedParserNullableLoopPreservedBindings_core_ids]
          native_decide)
  have nullableSeparated : NullableFrameSeparated bound workspaceCell
      stateCountCell nullableCursorCell := by
    intro cell framed written
    obtain ⟨id, sourceMember, cellId⟩ := framed
    have external := nullableExternal id
      ((NullablePreservedLocal_source_frame id).mpr sourceMember)
    change cell = workspaceCell ∨ cell = stateCountCell ∨
      cell = nullableCursorCell at written
    rcases written with rfl | rfl | rfl
    · exact external.1 cellId
    · exact external.2 cellId
    · exact nullableFrameFresh nullableCursorCell
        ⟨id, sourceMember, cellId⟩ rfl
  have dotSuccI32 : candidate.dot + 1 ≤ 2147483647 := by
    have rowRange := headRead.invariant.grammarWellFormed.production_validation
      |>.rhsRange ⟨candidate.production, productionBound⟩
    have tableFits := headRead.invariant.grammarEncoded.rhsSymbols.2.1
    have wordsFit := headRead.invariant.wordsI32
    omega
  have parentOriginBound : candidate.origin ≤
      finalPosition workspaceLayout.tokenCount :=
    headRead.invariant.workspaceEncoded.originsBound current candidate
      (completed.growth.preserves_existing_state found)
  have candidatePosition : candidate.position = position := by
    obtain ⟨cursorState, cursorFound, cursorPosition⟩ :=
      beforeInvariant.chartCursor.state_at_cursor
    rw [found] at cursorFound
    injection cursorFound with stateEqual
    subst cursorState
    exact cursorPosition
  have parentStored : StoredPredecessor completed.workspace current
      candidate.production candidate.dot candidate.origin position := {
    state := candidate
    found := completed.growth.preserves_existing_state found
    productionEq := rfl
    dotEq := rfl
    originEq := rfl
    positionEq := candidatePosition
  }
  have parentSymbolFound :
      ((grammar.productionAt
        ⟨candidate.production, productionBound⟩).rhs)[candidate.dot]? =
        some (grammar.grammar.n_kinds + nonterminalBinding.nonterminal) := by
    rw [List.getElem?_eq_some_iff]
    refine ⟨dotBeforeEnd, ?_⟩
    change
      (grammar.productionAt
        ⟨candidate.production, productionBound⟩).rhs.get
          ⟨candidate.dot, dotBeforeEnd⟩ =
        grammar.grammar.n_kinds + nonterminalBinding.nonterminal
    have notBelow : grammar.grammar.n_kinds ≤
        (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.get
          ⟨candidate.dot, dotBeforeEnd⟩ := Nat.le_of_not_gt isNonterminal
    have := nonterminalBinding.nonterminalEq
    omega
  have parentAdvanceSound : ∀ child symbol finish,
      ((grammar.productionAt
        ⟨candidate.production, productionBound⟩).rhs)[candidate.dot]? =
        some symbol →
      RecognizesSymbol grammar tokens symbol position finish →
      EarleyStateSound grammar tokens
        ((recognizerNullableSeed candidate.production candidate.dot
          candidate.origin current child).atPosition finish) := by
    intro child symbol finish symbolFound recognized
    have candidateSound :=
      headRead.invariant.languageSound current candidate
        (completed.growth.preserves_existing_state found)
    have recognizedAtCandidate : RecognizesSymbol grammar tokens symbol
        candidate.position finish := by
      simpa [candidatePosition] using recognized
    have advanced := candidateSound.advance symbolFound recognizedAtCandidate
      current (.state child)
    simpa [recognizerNullableSeed, EarleyState.advanceSeed] using advanced
  have commonAppendFrame : RecognizerAppendFrame grammarLayout grammar words
      tokens workspaceLayout completed.workspace completed.workspaceValues
      grammarCell tokensCell workspaceCell stateCountCell bound position :=
    boundStateInvariant.appendFrame
  cases chartEq : completed.workspace.chart position with
  | nil =>
      have cursorValue : chartHeadValue completed.workspace position = -1 := by
        simp [chartHeadValue, chartEq, encodeStateId]
      exact {
        headRead := headRead
        nullableCursorCell := nullableCursorCell
        nullableCursorCellEq := rfl
        bound := bound
        boundEq := rfl
        cursor := .inr {
          chartCursor := {
            recognizer := boundStateInvariant.chartCursor.recognizer
            workspaceWithinGrammar :=
              boundStateInvariant.chartCursor.workspaceWithinGrammar
            stateBaseLocal := boundStateInvariant.chartCursor.stateBaseLocal
            cursorOwned := by simpa [cursorValue] using nullableCursorOwned
            cursorFrameSeparate := nullableCursorFrameSeparate
            cursorBackingDistinct := nullableCursorBackingDistinct
            chartPositionBound :=
              boundStateInvariant.chartCursor.chartPositionBound
          }
          appendFrame := commonAppendFrame
          positionLocal := boundStateInvariant.positionLocal
          parentStateLocal := Assertion.localPointsTo_local 24 cursorCell _ bound
            outerCursorOwned
          parentProductionLocal := Assertion.localPointsTo_local 25
            bindings.productionCell _ bound productionOwned
          parentDotLocal := Assertion.localPointsTo_local 26 bindings.dotCell _
            bound dotOwned
          parentOriginLocal := Assertion.localPointsTo_local 27
            bindings.originCell _ bound originOwned
          expectedLocal := Assertion.localPointsTo_local 30
            nonterminalBinding.expectedCell _ bound expectedOwned
          parentProductionBound := productionBound
          parentDotBeforeEnd := dotBeforeEnd
          dotSuccI32 := dotSuccI32
          parentOriginBound := parentOriginBound
          parentStored := parentStored
          parentSymbolFound := parentSymbolFound
          parentAdvanceSound := parentAdvanceSound
          persistentSeparate := nullableSeparated
          cursorStateCountDistinct := nullableCursorStateCountDistinct
        }
      }
  | cons nullableCurrent nullableRemaining =>
      have cursorValue : chartHeadValue completed.workspace position =
          Int.ofNat nullableCurrent := by
        simp [chartHeadValue, chartEq, encodeStateId]
      exact {
        headRead := headRead
        nullableCursorCell := nullableCursorCell
        nullableCursorCellEq := rfl
        bound := bound
        boundEq := rfl
        cursor := .inl ⟨nullableCurrent, nullableRemaining, {
          chartCursor := {
            recognizer := boundStateInvariant.chartCursor.recognizer
            workspaceWithinGrammar :=
              boundStateInvariant.chartCursor.workspaceWithinGrammar
            stateBaseLocal := boundStateInvariant.chartCursor.stateBaseLocal
            cursorOwned := by simpa [cursorValue] using nullableCursorOwned
            cursorFrameSeparate := nullableCursorFrameSeparate
            cursorBackingDistinct := nullableCursorBackingDistinct
            chartPositionBound :=
              boundStateInvariant.chartCursor.chartPositionBound
            cursor := by simpa [chartEq] using
              ChartCursor.atHead nullableCurrent nullableRemaining
          }
          appendFrame := commonAppendFrame
          positionLocal := boundStateInvariant.positionLocal
          parentStateLocal := Assertion.localPointsTo_local 24 cursorCell _ bound
            outerCursorOwned
          parentProductionLocal := Assertion.localPointsTo_local 25
            bindings.productionCell _ bound productionOwned
          parentDotLocal := Assertion.localPointsTo_local 26 bindings.dotCell _
            bound dotOwned
          parentOriginLocal := Assertion.localPointsTo_local 27
            bindings.originCell _ bound originOwned
          expectedLocal := Assertion.localPointsTo_local 30
            nonterminalBinding.expectedCell _ bound expectedOwned
          parentProductionBound := productionBound
          parentDotBeforeEnd := dotBeforeEnd
          dotSuccI32 := dotSuccI32
          parentOriginBound := parentOriginBound
          parentStored := parentStored
          parentSymbolFound := parentSymbolFound
          parentAdvanceSound := parentAdvanceSound
          persistentSeparate := nullableSeparated
          cursorStateCountDistinct := nullableCursorStateCountDistinct
        }⟩
      }

def parserRecognizeStateNullableScope : Stmt :=
  .letLocal 36 parserI32Type (parserRecognizeChartHeadExpr 23)
    (.sequence parserRecognizeNullableLoop .skip)

/-- The source-derived nullable entry is already one of the two compact
    FunctionalView configurations: an active chart suffix or its sentinel. -/
def RecognizerStateNullableEntry.functionalConfig
    (entry : RecognizerStateNullableEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry completed) :
    RecognizerNullableConfig grammarLayout grammar words tokens workspaceLayout
      grammarCell tokensCell workspaceCell stateCountCell
      entry.nullableCursorCell position candidate.production candidate.dot
      candidate.origin current nonterminalBinding.nonterminal :=
  match entry.cursor with
  | .inl ⟨nullableCurrent, nullableRemaining, invariant⟩ => .active {
      workspace := completed.workspace
      workspaceValues := completed.workspaceValues
      runtime := entry.bound
      current := nullableCurrent
      remaining := nullableRemaining
      invariant := invariant
    }
  | .inr invariant => .sentinel {
      workspace := completed.workspace
      workspaceValues := completed.workspaceValues
      runtime := entry.bound
      invariant := invariant
    }

/-- Execution inside the nullable-cursor lexical scope.  Both the empty-chart
    fast path and the active loop expose the same workspace-growing result
    contract to the scope-closing code. -/
structure RecognizerStateNullableInnerExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (beforeValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    (candidate : EarleyState)
    (found : beforeWorkspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound)
    (symbolBinding : RecognizerStateSymbolBinding grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isNonterminal : ¬
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩ <
        grammar.grammar.n_kinds)
    (nonterminalBinding : RecognizerStateNonterminalIndexBinding grammarLayout
      grammar words tokens workspaceLayout beforeWorkspace beforeValues
      grammarCell tokensCell workspaceCell stateCountCell cursorCell before
      position current remaining beforeInvariant candidate found
      productionBound dotBeforeEnd bindings symbolBinding isNonterminal)
    (predictionEntry : RecognizerStatePredictionEntry grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace beforeValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal nonterminalBinding)
    (completed : RecognizerStatePredictionCompletedFrame grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace beforeValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal nonterminalBinding predictionEntry)
    (entry : RecognizerStateNullableEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry completed)
    where
  after : State
  execution : Executes verifiedParserCore entry.bound
    (.sequence parserRecognizeNullableLoop .skip)
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
      entry.functionalConfig.functional_run.completion) after
  effect : ModifiesOnly
    (nullableFrameMutableCells workspaceCell stateCountCell
      entry.nullableCursorCell) entry.bound after
  outcome : RecognizerNullableSynchronizedOutcome grammarLayout grammar words
    tokens workspaceLayout completed.workspace grammarCell tokensCell
    workspaceCell stateCountCell entry.nullableCursorCell position
    candidate.production candidate.dot candidate.origin current
    nonterminalBinding.nonterminal entry.functionalConfig.functional_run.after
    after (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
      entry.functionalConfig.functional_run.completion)

noncomputable def RecognizerStateNullableEntry.execute_inner
    (entry : RecognizerStateNullableEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry completed) :
    RecognizerStateNullableInnerExecution grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry completed
      entry := by
  generalize runEq : entry.functionalConfig.functional_run = loop
  obtain ⟨completion, functionalAfter, trace, result⟩ := loop
  have sourceCompletionEq :
      entry.functionalConfig.functional_run.completion = completion := by
    simpa using congrArg (fun run => run.completion) runEq
  have sourceAfterEq : entry.functionalConfig.functional_run.after =
      functionalAfter := by
    simpa using congrArg (fun run => run.after) runEq
  have runtimeEq : entry.functionalConfig.runtime = entry.bound := by
    cases cursorEq : entry.cursor <;>
      simp [RecognizerStateNullableEntry.functionalConfig, cursorEq]
  have workspaceEq : entry.functionalConfig.workspace = completed.workspace := by
    cases cursorEq : entry.cursor <;>
      simp [RecognizerStateNullableEntry.functionalConfig, cursorEq]
  have loopExecution : Executes verifiedParserCore entry.bound
      parserRecognizeNullableLoop
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
      result.physicalAfter := by
    rw [← runtimeEq]
    exact result.execution
  have loopEffect : ModifiesOnly
      (nullableFrameMutableCells workspaceCell stateCountCell
        entry.nullableCursorCell) entry.bound result.physicalAfter := by
    rw [← runtimeEq]
    simpa [nullableFrameMutableCells] using result.effect
  have existsResult : ∃ result :
      RecognizerStateNullableInnerExecution grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position current remaining
        beforeInvariant candidate found productionBound dotBeforeEnd bindings
        symbolBinding isNonterminal nonterminalBinding predictionEntry completed
        entry, True := by
    cases completion with
    | next =>
        cases result.outcome with
        | completed workspace workspaceValues physicalAfter growth finished _ _ =>
            have growth' := growth
            rw [workspaceEq] at growth'
            exact ⟨{
              after := result.physicalAfter
              execution := by
                have sequenced := executesSequence
                  (by simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion]
                    using loopExecution)
                  (executesSkip verifiedParserCore result.physicalAfter)
                rw [sourceCompletionEq]
                simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion]
                  using sequenced
              effect := loopEffect
              outcome := by
                have synchronized := result.outcome
                rw [workspaceEq] at synchronized
                simpa [sourceCompletionEq, sourceAfterEq,
                  Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
                  synchronized
            }, trivial⟩
    | returned value =>
        cases result.outcome with
        | full finalWorkspace finalValues physicalAfter growth terminal
            stateCount wellFormed =>
            have growth' := growth
            rw [workspaceEq] at growth'
            exact ⟨{
              after := result.physicalAfter
              execution := by
                have returnedLoop : Executes verifiedParserCore entry.bound
                    parserRecognizeNullableLoop
                    (parserCapacityCompletion position stateCount)
                    result.physicalAfter := by
                  simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion,
                    parserCapacityCompletion] using loopExecution
                have sequenced : Executes verifiedParserCore entry.bound
                    (.sequence parserRecognizeNullableLoop .skip)
                    (parserCapacityCompletion position stateCount)
                    result.physicalAfter :=
                  executesSequenceReturned returnedLoop
                rw [sourceCompletionEq]
                simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion,
                  parserCapacityCompletion] using sequenced
              effect := loopEffect
              outcome := by
                have synchronized := result.outcome
                rw [workspaceEq] at synchronized
                simpa [sourceCompletionEq, sourceAfterEq,
                  Lanius.FunctionalView.Core.Stateful.toCoreCompletion,
                  parserCapacityCompletion] using synchronized
            }, trivial⟩
    | breakLoop => cases result.outcome
    | continueLoop => cases result.outcome
  exact Classical.choose existsResult

/-- Nullable replay after its source chart-head local has closed.  The normal
    result retains both the restored outer state-loop frame and the exact
    compact nullable runtime reached by FunctionalView. -/
inductive RecognizerStateNullableSynchronizedOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position current : Nat) (remaining : List Nat)
    (parentProduction parentDot parentOrigin expected : Nat)
    (sourceCompletion : Lanius.FunctionalView.Stateful.Completion)
    (after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (nullableTermMachine workspaceLayout grammar words grammarCell) 12) :
    State → Completion → Type where
  | completed (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (frame : RecognizerStateGrowthFrame grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace workspace workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell cursorCell physicalAfter
        position current remaining)
      (sourceCompletionEq : sourceCompletion = .next)
      (worldEq : after.world = nullableWorld words tokens workspaceValues
        grammarCell tokensCell workspaceCell)
      (environmentEq : after.environment = nullableEnvironment words
        workspaceValues grammarCell workspaceCell workspaceLayout
        workspace.states.length position current parentProduction parentDot
        parentOrigin expected (-1)) :
      RecognizerStateNullableSynchronizedOutcome grammarLayout grammar words
        tokens workspaceLayout beforeWorkspace grammarCell tokensCell
        workspaceCell stateCountCell cursorCell position current remaining
        parentProduction parentDot parentOrigin expected sourceCompletion after
        physicalAfter .next
  | full (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (terminal : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter)
      (sourceCompletionEq :
        Lanius.FunctionalView.Core.Stateful.toCoreCompletion sourceCompletion =
          parserCapacityCompletion position stateCount)
      (sourceStops : sourceCompletion ≠ .next) :
      RecognizerStateNullableSynchronizedOutcome grammarLayout grammar words
        tokens workspaceLayout beforeWorkspace grammarCell tokensCell
        workspaceCell stateCountCell cursorCell position current remaining
        parentProduction parentDot parentOrigin expected sourceCompletion after
        physicalAfter (parserCapacityCompletion position stateCount)

def RecognizerStateNullableSynchronizedOutcome.physical
    (outcome : RecognizerStateNullableSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position current remaining
      parentProduction parentDot parentOrigin expected sourceCompletion after
      physicalAfter completion) :
    RecognizerStateOperationOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position current remaining physicalAfter
      completion := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter growth frame _ _ _ =>
      exact .completed workspace workspaceValues physicalAfter growth frame
  | full workspace workspaceValues physicalAfter growth terminal stateCount
      wellFormed _ _ =>
      exact .full workspace workspaceValues physicalAfter growth terminal
        stateCount wellFormed

/-- The complete nullable-replay scope, with its fresh cursor hidden again
    and its semantic growth rebased through the prediction phase. -/
structure RecognizerStateNullableExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (beforeValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (position current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    (candidate : EarleyState)
    (found : beforeWorkspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound)
    (symbolBinding : RecognizerStateSymbolBinding grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isNonterminal : ¬
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩ <
        grammar.grammar.n_kinds)
    (nonterminalBinding : RecognizerStateNonterminalIndexBinding grammarLayout
      grammar words tokens workspaceLayout beforeWorkspace beforeValues
      grammarCell tokensCell workspaceCell stateCountCell cursorCell before
      position current remaining beforeInvariant candidate found
      productionBound dotBeforeEnd bindings symbolBinding isNonterminal)
    (predictionEntry : RecognizerStatePredictionEntry grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace beforeValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal nonterminalBinding)
    (completed : RecognizerStatePredictionCompletedFrame grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace beforeValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal nonterminalBinding predictionEntry)
    (entry : RecognizerStateNullableEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry completed)
    where
  after : State
  execution : Executes verifiedParserCore completed.after
    parserRecognizeStateNullableScope
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
      entry.functionalConfig.functional_run.completion) after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell)) completed.after after
  outcome : RecognizerStateNullableSynchronizedOutcome grammarLayout grammar
    words tokens workspaceLayout beforeWorkspace grammarCell tokensCell
    workspaceCell stateCountCell cursorCell position current remaining
    candidate.production candidate.dot candidate.origin
    nonterminalBinding.nonterminal
    entry.functionalConfig.functional_run.completion
    entry.functionalConfig.functional_run.after after
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
      entry.functionalConfig.functional_run.completion)

noncomputable def RecognizerStateNullableEntry.execute
    (entry : RecognizerStateNullableEntry grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry completed) :
    RecognizerStateNullableExecution grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry completed
      entry := by
  let inner := entry.execute_inner
  obtain ⟨innerAfter, innerExecution, innerEffect, innerSynchronized⟩ := inner
  let innerCompletion :=
    Lanius.FunctionalView.Core.Stateful.toCoreCompletion
      entry.functionalConfig.functional_run.completion
  have innerOutcome : RecognizerNullableLoopOutcome grammarLayout grammar words
      tokens workspaceLayout completed.workspace grammarCell tokensCell
      workspaceCell stateCountCell entry.nullableCursorCell position
      candidate.production candidate.dot candidate.origin current
      nonterminalBinding.nonterminal innerAfter innerCompletion := by
    exact innerSynchronized.physical
  let writes := nullableFrameMutableCells workspaceCell stateCountCell
    entry.nullableCursorCell
  let retainedWrites := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton stateCountCell)
  let after := restoreLocals entry.headRead.after innerAfter
  have entered : StoreEffect CellSet.empty entry.headRead.after entry.bound := by
    rw [entry.boundEq]
    exact bindLocal_effect entry.headRead.after 36
      (.signed .i32 (chartHeadValue completed.workspace position))
  have scopeEffect : StoreEffect writes entry.headRead.after innerAfter :=
    (entered.weaken CellSet.empty_subset).trans_same (by
      simpa [writes] using innerEffect.toStoreEffect)
  have closedEffect : ModifiesOnly writes entry.headRead.after after := by
    simpa [after] using scopeEffect.restoreLocals
  have totalEffect : ModifiesOnly writes completed.after after := by
    simpa [writes] using
      (entry.headRead.effect.weaken CellSet.empty_subset).trans_same closedEffect
  have effect : ModifiesOnly retainedWrites completed.after after := by
    apply totalEffect.hideFreshWritesExcept
    intro cell written
    change cell = workspaceCell ∨ cell = stateCountCell ∨
      cell = entry.nullableCursorCell at written
    rcases written with rfl | rfl | rfl
    · exact .inl (.inl rfl)
    · exact .inl (.inr rfl)
    · exact .inr (by
        rw [entry.nullableCursorCellEq]
        exact entry.headRead.effect.nextCell)
  have execution : Executes verifiedParserCore completed.after
      parserRecognizeStateNullableScope innerCompletion after := by
    have bodyExecution : Executes verifiedParserCore
        (entry.headRead.after.bindLocal 36
          (.signed .i32 (chartHeadValue completed.workspace position)))
        (.sequence parserRecognizeNullableLoop .skip) innerCompletion
        innerAfter := by
      simpa [entry.boundEq] using innerExecution
    have scopedExecution := executesLetLocal (id := 36)
      (type := parserI32Type)
      entry.headRead.evaluation bodyExecution
    simpa [parserRecognizeStateNullableScope, after] using scopedExecution
  have afterWellFormed : StateWellFormed after :=
    scopeEffect.restoreLocals_wellFormed entry.headRead.invariant.wellFormed
      (by
        rcases innerSynchronized.view with completedResult | fullResult
        · rcases completedResult with ⟨_, _, _, _, finished, _, _⟩
          exact finished.chartCursor.recognizer.wellFormed
        · rcases fullResult with ⟨_, _, _, _, _, wellFormed, _⟩
          exact wellFormed)
  have existsResult : ∃ result :
      RecognizerStateNullableExecution grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position current remaining
        beforeInvariant candidate found productionBound dotBeforeEnd bindings
        symbolBinding isNonterminal nonterminalBinding predictionEntry completed
        entry, True := by
    rcases Or.comm.mp innerSynchronized.view with fullResult | completedResult
    · rcases fullResult with ⟨finalWorkspace, finalValues, growth, terminal,
        stateCount, _, completionEq⟩
      have sourceCoreCompletionEq :
          Lanius.FunctionalView.Core.Stateful.toCoreCompletion
              entry.functionalConfig.functional_run.completion =
            parserCapacityCompletion position stateCount := by
        simpa [innerCompletion] using completionEq
      have sourceStops :
          entry.functionalConfig.functional_run.completion ≠ .next := by
        intro sourceNext
        rw [sourceNext] at sourceCoreCompletionEq
        simp [Lanius.FunctionalView.Core.Stateful.toCoreCompletion,
          parserCapacityCompletion] at sourceCoreCompletionEq
      have parameterCellId : ∀ id,
          id ∈ verifiedParserRecognizerParameterIds →
          entry.bound.cellId? id = entry.headRead.after.cellId? id := by
        intro id member
        rw [entry.boundEq]
        apply bindLocal_preserves_other_cellId
        exact Nat.ne_of_gt (Nat.lt_of_le_of_lt
          ((mem_verifiedParserRecognizerParameterIds_iff id).mp member)
          (by decide))
      have restoredRecognizer : RecognizerInvariant grammarLayout grammar
          words tokens workspaceLayout finalWorkspace finalValues grammarCell
          tokensCell workspaceCell after := by
        simpa [after] using RecognizerInvariant.restore_temporary
          entry.headRead.after entry.bound innerAfter
          entry.headRead.invariant.wellFormed entered innerEffect
          parameterCellId terminal
      exact ⟨{
        after := after
        execution := execution
        effect := effect
        outcome := by
          simpa [completionEq] using
            (RecognizerStateNullableSynchronizedOutcome.full finalWorkspace
              finalValues after (completed.growth.trans growth)
              restoredRecognizer stateCount afterWellFormed
              sourceCoreCompletionEq sourceStops)
      }, trivial⟩
    · rcases completedResult with ⟨completionEq, nextWorkspace, nextValues,
        growth, finished, worldEq, environmentEq⟩
      have sourceCompletionEq :
          entry.functionalConfig.functional_run.completion = .next := by
        generalize sourceShape :
          entry.functionalConfig.functional_run.completion = sourceCompletion
          at completionEq ⊢
        cases sourceCompletion with
        | next => rfl
        | returned value =>
            simp [innerCompletion,
              Lanius.FunctionalView.Core.Stateful.toCoreCompletion] at completionEq
        | breakLoop =>
            simp [innerCompletion,
              Lanius.FunctionalView.Core.Stateful.toCoreCompletion] at completionEq
        | continueLoop =>
            simp [innerCompletion,
              Lanius.FunctionalView.Core.Stateful.toCoreCompletion] at completionEq
      have parameterCellId : ∀ id,
          id ∈ verifiedParserRecognizerParameterIds →
          entry.bound.cellId? id = entry.headRead.after.cellId? id := by
        intro id member
        rw [entry.boundEq]
        apply bindLocal_preserves_other_cellId
        exact Nat.ne_of_gt (Nat.lt_of_le_of_lt
          ((mem_verifiedParserRecognizerParameterIds_iff id).mp member)
          (by decide))
      have restoredRecognizer : RecognizerInvariant grammarLayout grammar
          words tokens workspaceLayout nextWorkspace nextValues grammarCell
          tokensCell workspaceCell after := by
        simpa [after] using RecognizerInvariant.restore_temporary
          entry.headRead.after entry.bound innerAfter
          entry.headRead.invariant.wellFormed entered innerEffect
          parameterCellId finished.chartCursor.recognizer
      have countCellId : entry.bound.cellId? 18 =
          entry.headRead.after.cellId? 18 := by
        rw [entry.boundEq]
        exact bindLocal_preserves_other_cellId _ 36 18 _ (by decide)
      have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
          (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))).holds
          after := by
        simpa [after] using localPointsTo_restore_temporary
          entry.headRead.after entry.bound innerAfter 18 stateCountCell
          (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))
          innerEffect countCellId finished.appendFrame.stateCountOwned
      have frameDisjoint : CellSet.Disjoint
          (localBindingFrameFootprint completed.after
            verifiedParserStateLoopPreservedBindings) retainedWrites := by
        intro cell framed written
        obtain ⟨id, sourceMember, cellId⟩ := framed
        have ⟨persistent, notCount⟩ :=
          (StateLoopPreservedLocal_iff id).mp
            ((StateLoopPreservedLocal_source_frame id).mpr sourceMember)
        have separated :=
          completed.stateInvariant.persistentLocalsSeparate id persistent
        change cell = workspaceCell ∨ cell = stateCountCell at written
        rcases written with rfl | rfl
        · exact separated.1 cellId
        · exact separated.2.1 notCount cellId
      have cursorNotWritten : ¬ retainedWrites cursorCell := by
        simpa [retainedWrites, CellSet.union, CellSet.singleton, not_or] using
          ⟨completed.stateInvariant.chartCursor.cursorBackingDistinct.2.2,
            completed.stateInvariant.cursorStateCountDistinct⟩
      let nestedFrame := completed.stateInvariant.reframe_growth nextWorkspace
        nextValues after growth restoredRecognizer
        finished.chartCursor.workspaceWithinGrammar stateCountOwned
        retainedWrites effect frameDisjoint cursorNotWritten
      let outerFrame := nestedFrame.prepend completed.growth completed.progress
      exact ⟨{
        after := after
        execution := execution
        effect := effect
        outcome := by
          simpa [completionEq] using
            (RecognizerStateNullableSynchronizedOutcome.completed nextWorkspace
              nextValues after (completed.growth.trans growth) outerFrame
              sourceCompletionEq worldEq environmentEq)
      }, trivial⟩
  exact Classical.choose existsResult

/-- The source prediction scope and the compact FunctionalView loop share this
    one configuration.  It is defined at the scope boundary so both the
    physical compatibility API and the enclosing functional proof consume the
    same run. -/
def RecognizerStatePredictionEntry.functionalConfig
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding) :
    RecognizerPredictionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      entry.indexCell position entry.first entry.count := {
  workspace := workspace
  workspaceValues := workspaceValues
  runtime := entry.predictionState
  index := 0
  invariant := entry.invariant
}

/-- Prediction followed by nullable replay as one synchronized source
    operation.  Normal completion retains the exact completed prediction frame
    that created the nullable entry; a prediction capacity return never creates
    such an entry. -/
inductive RecognizerStatePredictionSynchronizedOutcome
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
    (predictionAfter : Lanius.FunctionalView.Stateful.Loop.Runtime
      (predictionTermMachine workspaceLayout words grammarCell) 10) :
    State → Completion → Type where
  | nullable
      (completed : RecognizerStatePredictionCompletedFrame grammarLayout grammar
        words tokens workspaceLayout workspace workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell cursorCell before position current
        remaining beforeInvariant candidate found productionBound dotBeforeEnd
        bindings symbolBinding isNonterminal nonterminalBinding entry)
      (predictionCompletionEq :
        entry.functionalConfig.functional_run.completion = .next)
      (predictionWorldEq : predictionAfter.world = predictionWorld words tokens
        completed.workspaceValues grammarCell tokensCell workspaceCell)
      (predictionEnvironmentEq : predictionAfter.environment =
        predictionEnvironment words completed.workspaceValues grammarCell
          workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset
          position entry.first entry.count entry.count
          completed.workspace.states.length)
      (nullableEntry : RecognizerStateNullableEntry grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position current remaining
        beforeInvariant candidate found productionBound dotBeforeEnd bindings
        symbolBinding isNonterminal nonterminalBinding entry completed)
      (physicalAfter : State) (completion : Completion)
      (nullableOutcome : RecognizerStateNullableSynchronizedOutcome
        grammarLayout grammar words tokens workspaceLayout workspace grammarCell
        tokensCell workspaceCell stateCountCell cursorCell position current
        remaining candidate.production candidate.dot candidate.origin
        nonterminalBinding.nonterminal
        nullableEntry.functionalConfig.functional_run.completion
        nullableEntry.functionalConfig.functional_run.after physicalAfter
        completion) :
      RecognizerStatePredictionSynchronizedOutcome grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position current remaining
        beforeInvariant candidate found productionBound dotBeforeEnd bindings
        symbolBinding isNonterminal nonterminalBinding entry predictionAfter
        physicalAfter completion
  | predictionFull (finalWorkspace : LogicalWorkspace)
      (finalValues : List Int) (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
        finalWorkspace)
      (terminal : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout finalWorkspace finalValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter)
      (predictionCompletionEq :
        Lanius.FunctionalView.Core.Stateful.toCoreCompletion
          entry.functionalConfig.functional_run.completion =
            parserCapacityCompletion position stateCount)
      (predictionStops : entry.functionalConfig.functional_run.completion ≠
        .next) :
      RecognizerStatePredictionSynchronizedOutcome grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position current remaining
        beforeInvariant candidate found productionBound dotBeforeEnd bindings
        symbolBinding isNonterminal nonterminalBinding entry predictionAfter
        physicalAfter (parserCapacityCompletion position stateCount)

def RecognizerStatePredictionSynchronizedOutcome.physical
    (outcome : RecognizerStatePredictionSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal nonterminalBinding entry
      predictionAfter physicalAfter completion) :
    RecognizerStateOperationOutcome grammarLayout grammar words tokens
      workspaceLayout workspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position current remaining physicalAfter
      completion := by
  cases outcome with
  | nullable completed _ _ _ nullableEntry physicalAfter completion
      nullableOutcome =>
      exact nullableOutcome.physical
  | predictionFull finalWorkspace finalValues physicalAfter growth terminal
      stateCount wellFormed _ _ =>
      exact .full finalWorkspace finalValues physicalAfter growth terminal
        stateCount wellFormed

/-- The three semantic exits of prediction followed by nullable replay.  This
    removes the nested sum from `RecognizerStatePredictionSynchronizedOutcome`
    without discarding either FunctionalView post-state: successful prediction
    is retained even when nullable replay subsequently exhausts capacity. -/
inductive RecognizerStatePredictionNullableSynchronizedOutcome
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
    (predictionAfter : Lanius.FunctionalView.Stateful.Loop.Runtime
      (predictionTermMachine workspaceLayout words grammarCell) 10) :
    State → Completion → Type where
  | completed
      (predictionFrame : RecognizerStatePredictionCompletedFrame grammarLayout
        grammar words tokens workspaceLayout workspace workspaceValues
        grammarCell tokensCell workspaceCell stateCountCell cursorCell before
        position current remaining beforeInvariant candidate found
        productionBound dotBeforeEnd bindings symbolBinding isNonterminal
        nonterminalBinding entry)
      (predictionCompletionEq :
        entry.functionalConfig.functional_run.completion = .next)
      (predictionWorldEq : predictionAfter.world = predictionWorld words tokens
        predictionFrame.workspaceValues grammarCell tokensCell workspaceCell)
      (predictionEnvironmentEq : predictionAfter.environment =
        predictionEnvironment words predictionFrame.workspaceValues grammarCell
          workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset
          position entry.first entry.count entry.count
          predictionFrame.workspace.states.length)
      (nullableEntry : RecognizerStateNullableEntry grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position current remaining
        beforeInvariant candidate found productionBound dotBeforeEnd bindings
        symbolBinding isNonterminal nonterminalBinding entry predictionFrame)
      (nullableCompletionEq :
        nullableEntry.functionalConfig.functional_run.completion = .next)
      (finalWorkspace : LogicalWorkspace) (finalValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
        finalWorkspace)
      (frame : RecognizerStateGrowthFrame grammarLayout grammar words tokens
        workspaceLayout workspace finalWorkspace finalValues grammarCell
        tokensCell workspaceCell stateCountCell cursorCell physicalAfter
        position current remaining)
      (nullableWorldEq : nullableEntry.functionalConfig.functional_run.after.world =
        nullableWorld words tokens finalValues grammarCell tokensCell workspaceCell)
      (nullableEnvironmentEq :
        nullableEntry.functionalConfig.functional_run.after.environment =
          nullableEnvironment words finalValues grammarCell workspaceCell
            workspaceLayout finalWorkspace.states.length position current
            candidate.production candidate.dot candidate.origin
            nonterminalBinding.nonterminal (-1)) :
      RecognizerStatePredictionNullableSynchronizedOutcome grammarLayout grammar
        words tokens workspaceLayout workspace workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell cursorCell before position current
        remaining beforeInvariant candidate found productionBound dotBeforeEnd
        bindings symbolBinding isNonterminal nonterminalBinding entry
        predictionAfter physicalAfter .next
  | nullableFull
      (predictionFrame : RecognizerStatePredictionCompletedFrame grammarLayout
        grammar words tokens workspaceLayout workspace workspaceValues
        grammarCell tokensCell workspaceCell stateCountCell cursorCell before
        position current remaining beforeInvariant candidate found
        productionBound dotBeforeEnd bindings symbolBinding isNonterminal
        nonterminalBinding entry)
      (predictionCompletionEq :
        entry.functionalConfig.functional_run.completion = .next)
      (predictionWorldEq : predictionAfter.world = predictionWorld words tokens
        predictionFrame.workspaceValues grammarCell tokensCell workspaceCell)
      (predictionEnvironmentEq : predictionAfter.environment =
        predictionEnvironment words predictionFrame.workspaceValues grammarCell
          workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset
          position entry.first entry.count entry.count
          predictionFrame.workspace.states.length)
      (nullableEntry : RecognizerStateNullableEntry grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position current remaining
        beforeInvariant candidate found productionBound dotBeforeEnd bindings
        symbolBinding isNonterminal nonterminalBinding entry predictionFrame)
      (finalWorkspace : LogicalWorkspace) (finalValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
        finalWorkspace)
      (terminal : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout finalWorkspace finalValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter)
      (nullableCompletionEq :
        Lanius.FunctionalView.Core.Stateful.toCoreCompletion
            nullableEntry.functionalConfig.functional_run.completion =
          parserCapacityCompletion position stateCount)
      (nullableStops :
        nullableEntry.functionalConfig.functional_run.completion ≠ .next) :
      RecognizerStatePredictionNullableSynchronizedOutcome grammarLayout grammar
        words tokens workspaceLayout workspace workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell cursorCell before position current
        remaining beforeInvariant candidate found productionBound dotBeforeEnd
        bindings symbolBinding isNonterminal nonterminalBinding entry
        predictionAfter physicalAfter (parserCapacityCompletion position stateCount)
  | predictionFull (finalWorkspace : LogicalWorkspace)
      (finalValues : List Int) (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
        finalWorkspace)
      (terminal : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout finalWorkspace finalValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter)
      (predictionCompletionEq :
        Lanius.FunctionalView.Core.Stateful.toCoreCompletion
          entry.functionalConfig.functional_run.completion =
            parserCapacityCompletion position stateCount)
      (predictionStops : entry.functionalConfig.functional_run.completion ≠
        .next) :
      RecognizerStatePredictionNullableSynchronizedOutcome grammarLayout grammar
        words tokens workspaceLayout workspace workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell cursorCell before position current
        remaining beforeInvariant candidate found productionBound dotBeforeEnd
        bindings symbolBinding isNonterminal nonterminalBinding entry
        predictionAfter physicalAfter (parserCapacityCompletion position stateCount)

/-- Flatten the synchronized prediction result without rerunning either source
    loop or selecting fresh logical workspace witnesses. -/
def RecognizerStatePredictionSynchronizedOutcome.flatten
    (outcome : RecognizerStatePredictionSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal nonterminalBinding entry
      predictionAfter physicalAfter completion) :
    RecognizerStatePredictionNullableSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal nonterminalBinding entry
      predictionAfter physicalAfter completion := by
  cases outcome with
  | nullable predictionFrame predictionCompletionEq predictionWorldEq
      predictionEnvironmentEq nullableEntry physicalAfter completion
      nullableOutcome =>
      cases nullableOutcome with
      | completed finalWorkspace finalValues physicalAfter growth frame
          nullableCompletionEq nullableWorldEq nullableEnvironmentEq =>
          exact .completed predictionFrame predictionCompletionEq
            predictionWorldEq predictionEnvironmentEq nullableEntry
            nullableCompletionEq finalWorkspace finalValues physicalAfter growth
            frame nullableWorldEq nullableEnvironmentEq
      | full finalWorkspace finalValues physicalAfter growth terminal stateCount
          wellFormed nullableCompletionEq nullableStops =>
          exact .nullableFull predictionFrame predictionCompletionEq
            predictionWorldEq predictionEnvironmentEq nullableEntry
            finalWorkspace finalValues physicalAfter growth terminal stateCount
            wellFormed nullableCompletionEq nullableStops
  | predictionFull finalWorkspace finalValues physicalAfter growth terminal
      stateCount wellFormed predictionCompletionEq predictionStops =>
      exact .predictionFull finalWorkspace finalValues physicalAfter growth
        terminal stateCount wellFormed predictionCompletionEq predictionStops

/-- What remains to be proved after the generated nonterminal locals are
    restored.  The logical workspace, growth proof, completion, and source
    post-states are selected by `outcome`; this predicate asks only for the
    corresponding physical invariant in the restored store. -/
structure RecognizerStateRestoredTerminal
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (physicalAfter : State) : Type where
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell physicalAfter
  wellFormed : StateWellFormed physicalAfter

def RecognizerStatePredictionNullableSynchronizedOutcome.Restored
    (outcome : RecognizerStatePredictionNullableSynchronizedOutcome
      grammarLayout grammar words tokens workspaceLayout workspace
      workspaceValues grammarCell tokensCell workspaceCell stateCountCell
      cursorCell before position current remaining beforeInvariant candidate
      found productionBound dotBeforeEnd bindings symbolBinding isNonterminal
      nonterminalBinding entry predictionAfter innerAfter completion)
    (physicalAfter : State) : Type :=
  match outcome with
  | .completed _ _ _ _ _ _ finalWorkspace finalValues _ _ _ _ _ =>
      RecognizerStateGrowthFrame grammarLayout grammar words tokens
        workspaceLayout workspace finalWorkspace finalValues grammarCell
        tokensCell workspaceCell stateCountCell cursorCell physicalAfter
        position current remaining
  | .nullableFull _ _ _ _ _ finalWorkspace finalValues _ _ _ stateCount _ _ _ =>
      RecognizerStateRestoredTerminal grammarLayout grammar words tokens
        workspaceLayout finalWorkspace finalValues grammarCell tokensCell
        workspaceCell physicalAfter
  | .predictionFull finalWorkspace finalValues _ _ _ stateCount _ _ _ =>
      RecognizerStateRestoredTerminal grammarLayout grammar words tokens
        workspaceLayout finalWorkspace finalValues grammarCell tokensCell
        workspaceCell physicalAfter

/-- A restored physical invariant projects to the compatibility outcome using
    the same workspace witness already fixed by the synchronized source run. -/
private def
    RecognizerStatePredictionNullableSynchronizedOutcome.physical_of_restored
    (outcome : RecognizerStatePredictionNullableSynchronizedOutcome
      grammarLayout grammar words tokens workspaceLayout workspace
      workspaceValues grammarCell tokensCell workspaceCell stateCountCell
      cursorCell before position current remaining beforeInvariant candidate
      found productionBound dotBeforeEnd bindings symbolBinding isNonterminal
      nonterminalBinding entry predictionAfter innerAfter completion)
    (restored : outcome.Restored physicalAfter) :
    RecognizerStateOperationOutcome grammarLayout grammar words tokens
      workspaceLayout workspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position current remaining physicalAfter
      completion := by
  cases outcome with
  | completed predictionFrame predictionCompletionEq predictionWorldEq
      predictionEnvironmentEq nullableEntry nullableCompletionEq finalWorkspace
      finalValues innerAfter growth frame nullableWorldEq nullableEnvironmentEq =>
      exact .completed finalWorkspace finalValues physicalAfter growth restored
  | nullableFull predictionFrame predictionCompletionEq predictionWorldEq
      predictionEnvironmentEq nullableEntry finalWorkspace finalValues
      innerAfter growth terminal stateCount wellFormed nullableCompletionEq
      nullableStops =>
      exact .full finalWorkspace finalValues physicalAfter growth
        restored.invariant stateCount restored.wellFormed
  | predictionFull finalWorkspace finalValues innerAfter growth terminal
      stateCount wellFormed predictionCompletionEq predictionStops =>
      exact .full finalWorkspace finalValues physicalAfter growth
        restored.invariant stateCount restored.wellFormed

/-- Source-side obligation after all generated nonterminal locals have closed.
    A normal result re-establishes the decoded-state environment; a returned
    capacity result has no continuation and therefore no environment contract. -/
def
    RecognizerStatePredictionNullableSynchronizedOutcome.FunctionalRestored
    (outcome : RecognizerStatePredictionNullableSynchronizedOutcome
      grammarLayout grammar words tokens workspaceLayout workspace
      workspaceValues grammarCell tokensCell workspaceCell stateCountCell
      cursorCell before position current remaining beforeInvariant candidate
      found productionBound dotBeforeEnd bindings symbolBinding isNonterminal
      nonterminalBinding entry predictionAfter innerAfter completion)
    (afterWorld : Lanius.FunctionalView.Core.ReadOnly.World)
    (afterEnvironment : Lanius.FunctionalView.Env 17) : Prop :=
  match outcome with
  | .completed _ _ _ _ _ _ finalWorkspace finalValues _ _ _ _ _ =>
      afterWorld = stateWorld words tokens finalValues grammarCell tokensCell
          workspaceCell ∧
        StateAfterBindingsEnvironment grammarLayout grammar words tokens
          workspaceLayout finalWorkspace finalValues grammarCell tokensCell
          workspaceCell position current candidate.production candidate.dot
          candidate.origin
          (grammar.productionAt
            ⟨candidate.production, productionBound⟩).rhs.length
          afterEnvironment
  | .nullableFull .. => True
  | .predictionFull .. => True

/-- Join the restored physical and source obligations.  Both are indexed by
    one synchronized outcome, so the resulting branch cannot mix workspace
    witnesses from separate executions. -/
def
    RecognizerStatePredictionNullableSynchronizedOutcome.branchSynchronized
    (outcome : RecognizerStatePredictionNullableSynchronizedOutcome
      grammarLayout grammar words tokens workspaceLayout workspace
      workspaceValues grammarCell tokensCell workspaceCell stateCountCell
      cursorCell before position current remaining beforeInvariant candidate
      found productionBound dotBeforeEnd bindings symbolBinding isNonterminal
      nonterminalBinding entry predictionAfter innerAfter completion)
    (physical : outcome.Restored physicalAfter)
    (functional : outcome.FunctionalRestored afterWorld afterEnvironment) :
    RecognizerStateBranchSynchronizedOutcome grammarLayout grammar words tokens
      workspaceLayout workspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position current remaining candidate.production
      candidate.dot candidate.origin
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
      afterWorld afterEnvironment physicalAfter completion := by
  cases outcome with
  | completed predictionFrame predictionCompletionEq predictionWorldEq
      predictionEnvironmentEq nullableEntry nullableCompletionEq finalWorkspace
      finalValues innerAfter growth frame nullableWorldEq nullableEnvironmentEq =>
      exact .completed finalWorkspace finalValues physicalAfter growth physical
        functional.1 functional.2
  | nullableFull predictionFrame predictionCompletionEq predictionWorldEq
      predictionEnvironmentEq nullableEntry finalWorkspace finalValues
      innerAfter growth terminal stateCount wellFormed nullableCompletionEq
      nullableStops =>
      exact .full finalWorkspace finalValues physicalAfter growth
        physical.invariant stateCount physical.wellFormed
  | predictionFull finalWorkspace finalValues innerAfter growth terminal
      stateCount wellFormed predictionCompletionEq predictionStops =>
      exact .full finalWorkspace finalValues physicalAfter growth
        physical.invariant stateCount physical.wellFormed

/-- Prediction followed by nullable replay, before the generated nonterminal
    locals are closed.  Capacity exhaustion in prediction returns immediately;
    otherwise the completed prediction frame is passed directly to the
    nullable operation. -/
structure RecognizerStatePredictionExecution
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
      symbolBinding isNonterminal nonterminalBinding) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore entry.predictionState
    (.sequence parserRecognizePredictionLoop parserRecognizeStateNullableScope)
    completion after
  effect : ModifiesOnly
    (recognizerPredictionWrites workspaceCell stateCountCell entry.indexCell)
    entry.predictionState after
  outcome : RecognizerStatePredictionSynchronizedOutcome grammarLayout grammar
    words tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell before position current remaining
    beforeInvariant candidate found productionBound dotBeforeEnd bindings
    symbolBinding isNonterminal nonterminalBinding entry
    entry.functionalConfig.functional_run.after after completion

/-- Execute the complete nonterminal operation inside locals 31--33. -/
noncomputable def RecognizerStatePredictionEntry.execute_nonterminal_inner
    (entry : RecognizerStatePredictionEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding) :
    RecognizerStatePredictionExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding entry := by
  generalize runEq : entry.functionalConfig.functional_run = prediction
  obtain ⟨completion, functionalAfter, trace, result⟩ := prediction
  have sourceCompletionEq :
      entry.functionalConfig.functional_run.completion = completion := by
    simpa using congrArg (fun run => run.completion) runEq
  have sourceAfterEq : entry.functionalConfig.functional_run.after =
      functionalAfter := by
    simpa using congrArg (fun run => run.after) runEq
  have loopExecution : Executes verifiedParserCore entry.predictionState
      parserRecognizePredictionLoop
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
      result.physicalAfter := result.execution
  have loopEffect : ModifiesOnly
      (recognizerPredictionWrites workspaceCell stateCountCell entry.indexCell)
      entry.predictionState result.physicalAfter := result.effect
  have existsResult : ∃ result :
      RecognizerStatePredictionExecution grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position current remaining
        beforeInvariant candidate found productionBound dotBeforeEnd bindings
        symbolBinding isNonterminal nonterminalBinding entry, True := by
    cases completion with
    | next =>
        cases result.outcome with
        | completed nextWorkspace nextValues physicalAfter growth finished
            worldEq environmentEq =>
            let completed := entry.reframe_completed nextWorkspace nextValues
              result.physicalAfter growth finished loopEffect
            let nullableEntry := completed.enter_nullable
            let nullable := nullableEntry.execute
            have completedAfterEq : completed.after = result.physicalAfter := by
              rfl
            have nullableExecution := nullable.execution
            rw [completedAfterEq] at nullableExecution
            have nullableEffect : ModifiesOnly
                (recognizerPredictionWrites workspaceCell stateCountCell
                  entry.indexCell) result.physicalAfter nullable.after :=
              nullable.effect.weaken (by
                intro cell written
                change cell = workspaceCell ∨ cell = stateCountCell at written
                change cell = workspaceCell ∨
                  cell = stateCountCell ∨ cell = entry.indexCell
                exact written.elim (fun same => Or.inl same)
                  (fun same => Or.inr (Or.inl same)))
            exact ⟨{
              after := nullable.after
              completion :=
                Lanius.FunctionalView.Core.Stateful.toCoreCompletion
                  nullableEntry.functionalConfig.functional_run.completion
              execution := executesSequence
                (by simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion]
                  using loopExecution)
                nullableExecution
              effect := by
                simpa [recognizerPredictionWrites] using
                  loopEffect.trans_same nullableEffect
              outcome := by
                simpa [sourceAfterEq] using
                  (RecognizerStatePredictionSynchronizedOutcome.nullable
                    completed (by simpa using sourceCompletionEq) worldEq
                    environmentEq nullableEntry nullable.after
                    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
                      nullableEntry.functionalConfig.functional_run.completion)
                    nullable.outcome)
            }, trivial⟩
    | returned value =>
        cases result.outcome with
        | full nextWorkspace nextValues physicalAfter growth terminal stateCount
            wellFormed =>
            exact ⟨{
              after := result.physicalAfter
              completion := parserCapacityCompletion position stateCount
              execution := executesSequenceReturned
                (by simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion]
                  using loopExecution)
              effect := by
                simpa [recognizerPredictionWrites] using loopEffect
              outcome := .predictionFull nextWorkspace nextValues
                result.physicalAfter growth terminal stateCount wellFormed
                (by
                  let sourceCompletion :
                      Lanius.FunctionalView.Stateful.Completion :=
                    entry.functionalConfig.functional_run.completion
                  change Lanius.FunctionalView.Core.Stateful.toCoreCompletion
                    sourceCompletion = parserCapacityCompletion position stateCount
                  rw [show sourceCompletion = .returned (some
                    (parseResultValue 2 (Int.ofNat stateCount) (-1)
                      (Int.ofNat position))) from sourceCompletionEq]
                  rfl)
                (by
                  intro sourceNext
                  have impossible := sourceNext.symm.trans sourceCompletionEq
                  cases impossible)
            }, trivial⟩
    | breakLoop => cases result.outcome
    | continueLoop => cases result.outcome
  exact Classical.choose existsResult

/-- The whole nonterminal branch, with the symbol, nonterminal, row bounds,
    and prediction index locals restored to the enclosing state operation. -/
structure RecognizerStateNonterminalExecution
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
      beforeInvariant candidate found productionBound) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length)))
    parserRecognizeStateIncompleteBranch completion after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell))
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.length))) after
  outcome : RecognizerStateOperationOutcome grammarLayout grammar words tokens
    workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell cursorCell position current remaining after completion

/-- A closed physical branch indexed by the exact prediction/nullable execution
    it encloses.  These equations are established where the source outcome is
    eliminated, rather than reconstructed later from an opaque result. -/
private structure RecognizerStateClosedNonterminalExecution
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
    (nonterminalBinding : RecognizerStateNonterminalIndexBinding grammarLayout
      grammar words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell runtime position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal)
    (predictionEntry : RecognizerStatePredictionEntry grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding)
    (inner : RecognizerStatePredictionExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry) where
  physical : RecognizerStateNonterminalExecution grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell workspaceCell
    stateCountCell cursorCell runtime position current remaining beforeInvariant
    candidate found productionBound dotBeforeEnd bindings
  afterEq : physical.after = restoreLocals symbolBinding.afterRead inner.after
  completionEq : physical.completion = inner.completion

/-- Close locals 29--33 around one already-selected prediction/nullable run.
    Both the physical projection and the FunctionalView synchronization consume
    this same execution value; neither side is allowed to choose a second run. -/
private noncomputable def RecognizerStatePredictionExecution.close_nonterminal
    (inner : RecognizerStatePredictionExecution grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry) :
    RecognizerStateClosedNonterminalExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell workspaceCell
      stateCountCell cursorCell runtime position current remaining beforeInvariant
      candidate found productionBound dotBeforeEnd bindings symbolBinding
      isNonterminal nonterminalBinding predictionEntry inner := by
  let symbol := (grammar.productionAt ⟨candidate.production,
    productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
  let rhsScope := bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32
    (Int.ofNat (grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.length))
  let symbolBound := symbolBinding.afterRead.bindLocal 29
    (.signed .i32 (Int.ofNat symbol))
  obtain ⟨innerAfter, innerCompletion, innerExecution, innerEffect,
    innerSynchronized⟩ := inner
  let synchronizedInner : RecognizerStatePredictionExecution grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry := {
    after := innerAfter
    completion := innerCompletion
    execution := innerExecution
    effect := innerEffect
    outcome := innerSynchronized
  }
  have innerOutcome : RecognizerStateOperationOutcome grammarLayout grammar
      words tokens workspaceLayout workspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position current remaining
      innerAfter innerCompletion := innerSynchronized.physical
  let firstState := nonterminalBinding.bound.bindLocal 31
    (.signed .i32 (Int.ofNat predictionEntry.first))
  let countState := firstState.bindLocal 32
    (.signed .i32 (Int.ofNat predictionEntry.count))
  let nestedAfter := restoreLocals symbolBound innerAfter
  let after := restoreLocals symbolBinding.afterRead innerAfter
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton stateCountCell)
  have enteredSymbol : StoreEffect CellSet.empty symbolBinding.afterRead
      symbolBound := by
    exact bindLocal_effect symbolBinding.afterRead 29
      (.signed .i32 (Int.ofNat symbol))
  have enteredNonterminal : StoreEffect CellSet.empty symbolBound
      nonterminalBinding.bound := by
    rw [nonterminalBinding.boundEq]
    simpa [symbolBound, symbol] using bindLocal_effect symbolBound 30
      (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal))
  have enteredFirst : StoreEffect CellSet.empty nonterminalBinding.bound
      firstState := by
    exact bindLocal_effect nonterminalBinding.bound 31
      (.signed .i32 (Int.ofNat predictionEntry.first))
  have enteredCount : StoreEffect CellSet.empty firstState countState := by
    exact bindLocal_effect firstState 32
      (.signed .i32 (Int.ofNat predictionEntry.count))
  have enteredIndex : StoreEffect CellSet.empty countState
      predictionEntry.predictionState := by
    rw [predictionEntry.predictionStateEq]
    simpa [firstState, countState] using bindLocal_effect countState 33
      (.signed .i32 0)
  have enteredBeforeIndex : StoreEffect CellSet.empty symbolBinding.afterRead
      countState :=
    enteredSymbol.trans_same <| enteredNonterminal.trans_same <|
      enteredFirst.trans_same enteredCount
  have entered : StoreEffect CellSet.empty symbolBinding.afterRead
      predictionEntry.predictionState := enteredBeforeIndex.trans_same enteredIndex
  let innerWrites := recognizerPredictionWrites workspaceCell stateCountCell
    predictionEntry.indexCell
  have scopedStoreAll : StoreEffect innerWrites symbolBinding.afterRead
      innerAfter := (entered.weaken CellSet.empty_subset).trans_same
        (by simpa [innerWrites] using innerEffect.toStoreEffect)
  have closedAll : ModifiesOnly innerWrites symbolBinding.afterRead after := by
    simpa [after] using scopedStoreAll.restoreLocals
  have closed : ModifiesOnly writes symbolBinding.afterRead after := by
    apply closedAll.hideFreshWritesExcept
    intro cell written
    change cell = workspaceCell ∨ cell = stateCountCell ∨
      cell = predictionEntry.indexCell at written
    rcases written with rfl | rfl | rfl
    · exact .inl (.inl rfl)
    · exact .inl (.inr rfl)
    · exact .inr (by
        rw [predictionEntry.indexCellEq]
        exact enteredBeforeIndex.nextCell)
  have effect : ModifiesOnly writes rhsScope after :=
    (symbolBinding.effect.weaken CellSet.empty_subset).trans_same closed
  have indexEvaluation : Evaluates verifiedParserCore countState
      (.value (.signed .i32 0)) (.signed .i32 0) countState := ⟨1, rfl⟩
  have nestedExecution : Executes verifiedParserCore symbolBound
      parserRecognizeStateNonterminalBranch innerCompletion nestedAfter := by
    rw [extractedParserRecognize_state_nonterminal_shape]
    have innerExecution' : Executes verifiedParserCore
        (countState.bindLocal 33 (.signed .i32 0))
        (parserRecognizePredictionLoop.sequence parserRecognizeStateNullableScope)
        innerCompletion innerAfter := by
      rw [← predictionEntry.predictionStateEq]
      exact innerExecution
    have atIndex := executesLetLocal (id := 33) (type := parserI32Type)
      indexEvaluation innerExecution'
    have atCount := executesLetLocal (id := 32) (type := parserI32Type)
      predictionEntry.countEvaluation atIndex
    have atFirst := executesLetLocal (id := 31) (type := parserI32Type)
      predictionEntry.firstEvaluation atCount
    have atFirst' : Executes verifiedParserCore
        (symbolBound.bindLocal 30
          (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal)))
        (.letLocal 31 parserI32Type
          (.index (.local 0) (.binary .add (.local 13) (.local 30)))
          (.letLocal 32 parserI32Type
            (.index (.local 0) (.binary .add (.local 14) (.local 30)))
            (.letLocal 33 parserI32Type (.value (.signed .i32 0))
              (parserRecognizePredictionLoop.sequence
                parserRecognizeStateNullableScope))))
        innerCompletion
        (restoreLocals nonterminalBinding.bound
          (restoreLocals firstState (restoreLocals countState innerAfter))) := by
      rw [← nonterminalBinding.boundEq]
      exact atFirst
    have atNonterminal := executesLetLocal (id := 30) (type := parserI32Type)
      nonterminalBinding.evaluation atFirst'
    simpa [symbol, symbolBound, predictionEntry.predictionStateEq, firstState,
      countState, nestedAfter, restoreLocals, parserRecognizeStateNullableScope,
      parserRecognizeChartHeadExpr] using atNonterminal
  have symbolResult : Evaluates verifiedParserCore symbolBound (.local 29)
      (.signed .i32 (Int.ofNat symbol)) symbolBound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore symbolBound 29 _
      (by simpa [symbolBound, symbol] using symbolBinding.symbolLocal)⟩
  have kindCountResult : Evaluates verifiedParserCore symbolBound (.local 11)
      (.signed .i32 (Int.ofNat grammar.grammar.n_kinds)) symbolBound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore symbolBound 11 _
      (by simpa [symbolBound, symbol] using symbolBinding.invariant.kindCountLocal)⟩
  have terminalTest : Evaluates verifiedParserCore symbolBound
      (.binary .less (.local 29) (.local 11)) (.boolean false) symbolBound := by
    have compared := evaluatesNatLessThreaded symbolBound symbolBound symbolBound
      (.local 29) (.local 11) symbol grammar.grammar.n_kinds symbolResult
      kindCountResult
    have notLess : ¬ symbol < grammar.grammar.n_kinds := by
      simpa [symbol] using isNonterminal
    simpa [notLess] using compared
  have selected : Executes verifiedParserCore symbolBound
      (.ifThenElse (.binary .less (.local 29) (.local 11))
        parserRecognizeTerminalStatement parserRecognizeStateNonterminalBranch)
      innerCompletion nestedAfter := executesIfFalse terminalTest nestedExecution
  have temporaryCellId (id : VarId) (idLt : id < 29) :
      predictionEntry.predictionState.cellId? id =
        symbolBinding.afterRead.cellId? id := by
    have ne29 : 29 ≠ id := Nat.ne_of_gt idLt
    have ne30 : 30 ≠ id := Nat.ne_of_gt
      (Nat.lt_trans idLt (by decide : 29 < 30))
    have ne31 : 31 ≠ id := Nat.ne_of_gt
      (Nat.lt_trans idLt (by decide : 29 < 31))
    have ne32 : 32 ≠ id := Nat.ne_of_gt
      (Nat.lt_trans idLt (by decide : 29 < 32))
    have ne33 : 33 ≠ id := Nat.ne_of_gt
      (Nat.lt_trans idLt (by decide : 29 < 33))
    rw [predictionEntry.predictionStateEq]
    rw [bindLocal_preserves_other_cellId countState 33 id _ ne33]
    rw [bindLocal_preserves_other_cellId firstState 32 id _ ne32]
    rw [bindLocal_preserves_other_cellId nonterminalBinding.bound 31 id _ ne31]
    rw [nonterminalBinding.boundEq]
    rw [bindLocal_preserves_other_cellId symbolBound 30 id _ ne30]
    rw [show symbolBound = symbolBinding.afterRead.bindLocal 29
      (.signed .i32 (Int.ofNat symbol)) by rfl]
    exact bindLocal_preserves_other_cellId symbolBinding.afterRead 29 id _
      ne29
  have parameterCellId : ∀ id,
      id ∈ verifiedParserRecognizerParameterIds →
      predictionEntry.predictionState.cellId? id =
        symbolBinding.afterRead.cellId? id := by
    intro id member
    have idBound := (mem_verifiedParserRecognizerParameterIds_iff id).mp member
    exact temporaryCellId id
      (Nat.lt_of_le_of_lt idBound (by decide : 5 < 29))
  have finishFull (finalWorkspace : LogicalWorkspace) (finalValues : List Int)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
        finalWorkspace)
      (terminal : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout finalWorkspace finalValues grammarCell tokensCell
        workspaceCell innerAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed innerAfter)
      (completionEq : innerCompletion =
        parserCapacityCompletion position stateCount)
      (selectedFull : Executes verifiedParserCore symbolBound
        (.ifThenElse (.binary .less (.local 29) (.local 11))
          parserRecognizeTerminalStatement parserRecognizeStateNonterminalBranch)
        (parserCapacityCompletion position stateCount) nestedAfter) :
      RecognizerStateClosedNonterminalExecution grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell workspaceCell
        stateCountCell cursorCell runtime position current remaining beforeInvariant
        candidate found productionBound dotBeforeEnd bindings symbolBinding
        isNonterminal nonterminalBinding predictionEntry synchronizedInner := by
        have sequenced : Executes verifiedParserCore symbolBound
            (.sequence
              (.ifThenElse (.binary .less (.local 29) (.local 11))
                parserRecognizeTerminalStatement
                parserRecognizeStateNonterminalBranch)
              .skip)
            (parserCapacityCompletion position stateCount) nestedAfter :=
          executesSequenceReturned selectedFull
        have execution : Executes verifiedParserCore rhsScope
            parserRecognizeStateIncompleteBranch
            (parserCapacityCompletion position stateCount) after := by
          rw [extractedParserRecognize_state_incomplete_shape]
          simpa [rhsScope, symbolBound, symbol, after, nestedAfter,
            restoreLocals] using
            executesLetLocal (id := 29) (type := parserI32Type)
              symbolBinding.evaluation sequenced
        have recognizer : RecognizerInvariant grammarLayout grammar words tokens
            workspaceLayout finalWorkspace finalValues grammarCell tokensCell
            workspaceCell after := by
          simpa [after] using RecognizerInvariant.restore_temporary
            symbolBinding.afterRead predictionEntry.predictionState innerAfter
            symbolBinding.afterReadWellFormed entered innerEffect
            parameterCellId terminal
        have afterWellFormed : StateWellFormed after :=
          scopedStoreAll.restoreLocals_wellFormed
            symbolBinding.afterReadWellFormed wellFormed
        exact {
          physical := {
            after := after
            completion := parserCapacityCompletion position stateCount
            execution := execution
            effect := by simpa [rhsScope, writes] using effect
            outcome := .full finalWorkspace finalValues after growth recognizer
              stateCount afterWellFormed
          }
          afterEq := rfl
          completionEq := completionEq.symm
        }
  have finishCompleted (nextWorkspace : LogicalWorkspace)
      (nextValues : List Int)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity workspace
        nextWorkspace)
      (frame : RecognizerStateGrowthFrame grammarLayout grammar words tokens
        workspaceLayout workspace nextWorkspace nextValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell innerAfter position current remaining)
      (completionEq : innerCompletion = .next)
      (selectedNext : Executes verifiedParserCore symbolBound
        (.ifThenElse (.binary .less (.local 29) (.local 11))
          parserRecognizeTerminalStatement parserRecognizeStateNonterminalBranch)
        .next nestedAfter) :
      RecognizerStateClosedNonterminalExecution grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell workspaceCell
        stateCountCell cursorCell runtime position current remaining beforeInvariant
        candidate found productionBound dotBeforeEnd bindings symbolBinding
        isNonterminal nonterminalBinding predictionEntry synchronizedInner := by
        have sequenced : Executes verifiedParserCore symbolBound
            (.sequence
              (.ifThenElse (.binary .less (.local 29) (.local 11))
                parserRecognizeTerminalStatement
              parserRecognizeStateNonterminalBranch)
              .skip) .next nestedAfter :=
          executesSequence selectedNext
            (executesSkip verifiedParserCore nestedAfter)
        have execution : Executes verifiedParserCore rhsScope
            parserRecognizeStateIncompleteBranch .next after := by
          rw [extractedParserRecognize_state_incomplete_shape]
          simpa [rhsScope, symbolBound, symbol, after, nestedAfter,
            restoreLocals] using
            executesLetLocal (id := 29) (type := parserI32Type)
              symbolBinding.evaluation sequenced
        have recognizer : RecognizerInvariant grammarLayout grammar words tokens
            workspaceLayout nextWorkspace nextValues grammarCell tokensCell
            workspaceCell after := by
          simpa [after] using RecognizerInvariant.restore_temporary
            symbolBinding.afterRead predictionEntry.predictionState innerAfter
            symbolBinding.afterReadWellFormed entered innerEffect
            parameterCellId frame.invariant.chartCursor.recognizer
        have countCellId : predictionEntry.predictionState.cellId? 18 =
            symbolBinding.afterRead.cellId? 18 :=
          temporaryCellId 18 (by decide)
        have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
            (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))).holds
            after := by
          simpa [after] using localPointsTo_restore_temporary
            symbolBinding.afterRead predictionEntry.predictionState innerAfter
            18 stateCountCell
            (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))
            innerEffect countCellId frame.invariant.appendFrame.stateCountOwned
        have frameDisjoint : CellSet.Disjoint
            (localBindingFrameFootprint rhsScope
              verifiedParserStateLoopPreservedBindings) writes := by
          intro cell framed written
          exact bindings.invariant.persistentSeparate cell framed <| by
            rcases written with workspaceWritten | countWritten
            · exact .inl workspaceWritten
            · exact .inr (.inl countWritten)
        have cursorNotWritten : ¬ writes cursorCell := by
          simpa [writes, CellSet.union, CellSet.singleton, not_or] using
            ⟨bindings.invariant.chartCursor.cursorBackingDistinct.2.2,
              bindings.invariant.cursorStateCountDistinct⟩
        let nextFrame := bindings.invariant.reframe_growth nextWorkspace
          nextValues after growth recognizer
          frame.invariant.chartCursor.workspaceWithinGrammar stateCountOwned
          writes (by simpa [rhsScope] using effect) frameDisjoint
          cursorNotWritten
        exact {
          physical := {
            after := after
            completion := .next
            execution := execution
            effect := by simpa [rhsScope, writes] using effect
            outcome := .completed nextWorkspace nextValues after growth nextFrame
          }
          afterEq := rfl
          completionEq := completionEq.symm
        }
  let sourceOutcome := innerSynchronized.flatten
  cases sourceOutcome with
  | completed predictionFrame predictionCompletionEq predictionWorldEq
      predictionEnvironmentEq nullableEntry nullableCompletionEq finalWorkspace
      finalValues sourceAfter growth frame nullableWorldEq nullableEnvironmentEq =>
      exact finishCompleted finalWorkspace finalValues growth frame rfl (by
        simpa using selected)
  | nullableFull predictionFrame predictionCompletionEq predictionWorldEq
      predictionEnvironmentEq nullableEntry finalWorkspace finalValues sourceAfter
      growth terminal stateCount wellFormed nullableCompletionEq nullableStops =>
      exact finishFull finalWorkspace finalValues growth terminal stateCount
        wellFormed rfl (by simpa using selected)
  | predictionFull finalWorkspace finalValues sourceAfter growth terminal
      stateCount wellFormed predictionCompletionEq predictionStops =>
      exact finishFull finalWorkspace finalValues growth terminal stateCount
        wellFormed rfl (by simpa using selected)

/-- Compatibility projection of the shared nonterminal execution. -/
noncomputable def RecognizerStateSymbolBinding.execute_nonterminal
    (symbolBinding : RecognizerStateSymbolBinding grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isNonterminal : ¬
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩ <
        grammar.grammar.n_kinds) :
    RecognizerStateNonterminalExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings := by
  let nonterminalBinding := symbolBinding.bind_nonterminal_index isNonterminal
  let predictionEntry := nonterminalBinding.enter_prediction
  exact predictionEntry.execute_nonterminal_inner.close_nonterminal |>.physical

/-- The physical nonterminal executor together with the exact compact source
    run it encloses.  The equalities state the generated-local boundary
    explicitly, so later FunctionalView composition cannot pair the physical
    result with a separately chosen prediction or nullable execution. -/
structure RecognizerStateNonterminalSynchronizedExecution
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
        grammar.grammar.n_kinds) where
  nonterminalBinding : RecognizerStateNonterminalIndexBinding grammarLayout
    grammar words tokens workspaceLayout workspace workspaceValues grammarCell
    tokensCell workspaceCell stateCountCell cursorCell runtime position current
    remaining beforeInvariant candidate found productionBound dotBeforeEnd
    bindings symbolBinding isNonterminal
  predictionEntry : RecognizerStatePredictionEntry grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell runtime position current remaining
    beforeInvariant candidate found productionBound dotBeforeEnd bindings
    symbolBinding isNonterminal nonterminalBinding
  innerAfter : State
  completion : Completion
  sourceOutcome : RecognizerStatePredictionNullableSynchronizedOutcome
    grammarLayout grammar words tokens workspaceLayout workspace workspaceValues
    grammarCell tokensCell workspaceCell stateCountCell cursorCell runtime
    position current remaining beforeInvariant candidate found productionBound
    dotBeforeEnd bindings symbolBinding isNonterminal nonterminalBinding
    predictionEntry predictionEntry.functionalConfig.functional_run.after
    innerAfter completion
  physical : RecognizerStateNonterminalExecution grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell runtime position current remaining
    beforeInvariant candidate found productionBound dotBeforeEnd bindings
  afterEq : physical.after = restoreLocals symbolBinding.afterRead innerAfter
  completionEq : physical.completion = completion
  sourceCompletionEq : completion =
    predictionEntry.execute_nonterminal_inner.completion
  restored : sourceOutcome.Restored physical.after

/-- Closing locals 29--33 preserves exactly the logical result selected by the
    synchronized prediction/nullable run.  This is the store-framing argument
    formerly implicit in the compatibility executor. -/
private noncomputable def RecognizerStatePredictionExecution.restored_nonterminal
    (inner : RecognizerStatePredictionExecution grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal nonterminalBinding predictionEntry) :
    let sourceOutcome := inner.outcome.flatten
    sourceOutcome.Restored
      (restoreLocals symbolBinding.afterRead inner.after) := by
  obtain ⟨innerAfter, innerCompletion, innerExecution, innerEffect,
    innerOutcome⟩ := inner
  let symbol := (grammar.productionAt ⟨candidate.production,
    productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩
  let symbolBound := symbolBinding.afterRead.bindLocal 29
    (.signed .i32 (Int.ofNat symbol))
  let firstState := nonterminalBinding.bound.bindLocal 31
    (.signed .i32 (Int.ofNat predictionEntry.first))
  let countState := firstState.bindLocal 32
    (.signed .i32 (Int.ofNat predictionEntry.count))
  let after := restoreLocals symbolBinding.afterRead innerAfter
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton stateCountCell)
  have enteredSymbol : StoreEffect CellSet.empty symbolBinding.afterRead
      symbolBound := by
    exact bindLocal_effect symbolBinding.afterRead 29
      (.signed .i32 (Int.ofNat symbol))
  have enteredNonterminal : StoreEffect CellSet.empty symbolBound
      nonterminalBinding.bound := by
    rw [nonterminalBinding.boundEq]
    simpa [symbolBound, symbol] using bindLocal_effect symbolBound 30
      (.signed .i32 (Int.ofNat nonterminalBinding.nonterminal))
  have enteredFirst : StoreEffect CellSet.empty nonterminalBinding.bound
      firstState := by
    exact bindLocal_effect nonterminalBinding.bound 31
      (.signed .i32 (Int.ofNat predictionEntry.first))
  have enteredCount : StoreEffect CellSet.empty firstState countState := by
    exact bindLocal_effect firstState 32
      (.signed .i32 (Int.ofNat predictionEntry.count))
  have enteredIndex : StoreEffect CellSet.empty countState
      predictionEntry.predictionState := by
    rw [predictionEntry.predictionStateEq]
    simpa [firstState, countState] using bindLocal_effect countState 33
      (.signed .i32 0)
  have enteredBeforeIndex : StoreEffect CellSet.empty symbolBinding.afterRead
      countState :=
    enteredSymbol.trans_same <| enteredNonterminal.trans_same <|
      enteredFirst.trans_same enteredCount
  have entered : StoreEffect CellSet.empty symbolBinding.afterRead
      predictionEntry.predictionState := enteredBeforeIndex.trans_same enteredIndex
  let innerWrites := recognizerPredictionWrites workspaceCell stateCountCell
    predictionEntry.indexCell
  have scopedStoreAll : StoreEffect innerWrites symbolBinding.afterRead
      innerAfter := (entered.weaken CellSet.empty_subset).trans_same
        (by simpa [innerWrites] using innerEffect.toStoreEffect)
  have closedAll : ModifiesOnly innerWrites symbolBinding.afterRead after := by
    simpa [after] using scopedStoreAll.restoreLocals
  have closed : ModifiesOnly writes symbolBinding.afterRead after := by
    apply closedAll.hideFreshWritesExcept
    intro cell written
    change cell = workspaceCell ∨ cell = stateCountCell ∨
      cell = predictionEntry.indexCell at written
    rcases written with rfl | rfl | rfl
    · exact .inl (.inl rfl)
    · exact .inl (.inr rfl)
    · exact .inr (by
        rw [predictionEntry.indexCellEq]
        exact enteredBeforeIndex.nextCell)
  have temporaryCellId (id : VarId) (idLt : id < 29) :
      predictionEntry.predictionState.cellId? id =
        symbolBinding.afterRead.cellId? id := by
    have ne29 : 29 ≠ id := Nat.ne_of_gt idLt
    have ne30 : 30 ≠ id := Nat.ne_of_gt
      (Nat.lt_trans idLt (by decide : 29 < 30))
    have ne31 : 31 ≠ id := Nat.ne_of_gt
      (Nat.lt_trans idLt (by decide : 29 < 31))
    have ne32 : 32 ≠ id := Nat.ne_of_gt
      (Nat.lt_trans idLt (by decide : 29 < 32))
    have ne33 : 33 ≠ id := Nat.ne_of_gt
      (Nat.lt_trans idLt (by decide : 29 < 33))
    rw [predictionEntry.predictionStateEq]
    rw [bindLocal_preserves_other_cellId countState 33 id _ ne33]
    rw [bindLocal_preserves_other_cellId firstState 32 id _ ne32]
    rw [bindLocal_preserves_other_cellId nonterminalBinding.bound 31 id _ ne31]
    rw [nonterminalBinding.boundEq]
    rw [bindLocal_preserves_other_cellId symbolBound 30 id _ ne30]
    rw [show symbolBound = symbolBinding.afterRead.bindLocal 29
      (.signed .i32 (Int.ofNat symbol)) by rfl]
    exact bindLocal_preserves_other_cellId symbolBinding.afterRead 29 id _ ne29
  have parameterCellId : ∀ id,
      id ∈ verifiedParserRecognizerParameterIds →
      predictionEntry.predictionState.cellId? id =
        symbolBinding.afterRead.cellId? id := by
    intro id member
    have idBound := (mem_verifiedParserRecognizerParameterIds_iff id).mp member
    exact temporaryCellId id
      (Nat.lt_of_le_of_lt idBound (by decide : 5 < 29))
  change innerOutcome.flatten.Restored after
  generalize outcomeEq : innerOutcome.flatten = sourceOutcome
  cases sourceOutcome with
  | completed predictionFrame predictionCompletionEq predictionWorldEq
      predictionEnvironmentEq nullableEntry nullableCompletionEq finalWorkspace
      finalValues innerAfter growth frame nullableWorldEq nullableEnvironmentEq =>
      have recognizer : RecognizerInvariant grammarLayout grammar words tokens
          workspaceLayout finalWorkspace finalValues grammarCell tokensCell
          workspaceCell after := by
        simpa [after] using RecognizerInvariant.restore_temporary
          symbolBinding.afterRead predictionEntry.predictionState innerAfter
          symbolBinding.afterReadWellFormed entered innerEffect parameterCellId
          frame.invariant.chartCursor.recognizer
      have countCellId : predictionEntry.predictionState.cellId? 18 =
          symbolBinding.afterRead.cellId? 18 := temporaryCellId 18 (by decide)
      have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
          (some (.signed .i32 (Int.ofNat finalWorkspace.states.length)))).holds
          after := by
        simpa [after] using localPointsTo_restore_temporary
          symbolBinding.afterRead predictionEntry.predictionState innerAfter
          18 stateCountCell
          (some (.signed .i32 (Int.ofNat finalWorkspace.states.length)))
          innerEffect countCellId frame.invariant.appendFrame.stateCountOwned
      have frameDisjoint : CellSet.Disjoint
          (localBindingFrameFootprint
            (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
              (grammar.productionAt ⟨candidate.production,
                productionBound⟩).rhs.length)))
            verifiedParserStateLoopPreservedBindings) writes := by
        intro cell framed written
        exact bindings.invariant.persistentSeparate cell framed <| by
          rcases written with workspaceWritten | countWritten
          · exact .inl workspaceWritten
          · exact .inr (.inl countWritten)
      have cursorNotWritten : ¬ writes cursorCell := by
        simpa [writes, CellSet.union, CellSet.singleton, not_or] using
          ⟨bindings.invariant.chartCursor.cursorBackingDistinct.2.2,
            bindings.invariant.cursorStateCountDistinct⟩
      exact bindings.invariant.reframe_growth finalWorkspace finalValues after
        growth recognizer frame.invariant.chartCursor.workspaceWithinGrammar
        stateCountOwned writes
        (by
          simpa [writes] using
            (symbolBinding.effect.weaken CellSet.empty_subset).trans_same closed)
        frameDisjoint cursorNotWritten
  | nullableFull predictionFrame predictionCompletionEq predictionWorldEq
      predictionEnvironmentEq nullableEntry finalWorkspace finalValues
      innerAfter growth terminal stateCount wellFormed nullableCompletionEq
      nullableStops =>
      have recognizer : RecognizerInvariant grammarLayout grammar words tokens
          workspaceLayout finalWorkspace finalValues grammarCell tokensCell
          workspaceCell after := by
        simpa [after] using RecognizerInvariant.restore_temporary
          symbolBinding.afterRead predictionEntry.predictionState innerAfter
          symbolBinding.afterReadWellFormed entered innerEffect parameterCellId
          terminal
      have afterWellFormed : StateWellFormed after :=
        scopedStoreAll.restoreLocals_wellFormed
          symbolBinding.afterReadWellFormed wellFormed
      exact {
        invariant := recognizer
        wellFormed := afterWellFormed
      }
  | predictionFull finalWorkspace finalValues innerAfter growth terminal
      stateCount wellFormed predictionCompletionEq predictionStops =>
      have recognizer : RecognizerInvariant grammarLayout grammar words tokens
          workspaceLayout finalWorkspace finalValues grammarCell tokensCell
          workspaceCell after := by
        simpa [after] using RecognizerInvariant.restore_temporary
          symbolBinding.afterRead predictionEntry.predictionState innerAfter
          symbolBinding.afterReadWellFormed entered innerEffect parameterCellId
          terminal
      have afterWellFormed : StateWellFormed after :=
        scopedStoreAll.restoreLocals_wellFormed
          symbolBinding.afterReadWellFormed wellFormed
      exact {
        invariant := recognizer
        wellFormed := afterWellFormed
      }

/-- Execute the nonterminal branch once and retain its synchronized source
    witness alongside the compatibility-oriented physical result. -/
noncomputable def
    RecognizerStateSymbolBinding.execute_nonterminal_synchronized
    (symbolBinding : RecognizerStateSymbolBinding grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings)
    (isNonterminal : ¬
      (grammar.productionAt ⟨candidate.production,
        productionBound⟩).rhs.get ⟨candidate.dot, dotBeforeEnd⟩ <
        grammar.grammar.n_kinds) :
    RecognizerStateNonterminalSynchronizedExecution grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound dotBeforeEnd bindings
      symbolBinding isNonterminal := by
  let nonterminalBinding := symbolBinding.bind_nonterminal_index isNonterminal
  let predictionEntry := nonterminalBinding.enter_prediction
  let inner := predictionEntry.execute_nonterminal_inner
  let closed := inner.close_nonterminal
  let physical := closed.physical
  exact {
    nonterminalBinding := nonterminalBinding
    predictionEntry := predictionEntry
    innerAfter := inner.after
    completion := inner.completion
    sourceOutcome := inner.outcome.flatten
    physical := physical
    afterEq := closed.afterEq
    completionEq := closed.completionEq
    sourceCompletionEq := rfl
    restored := by
      rw [closed.afterEq]
      exact inner.restored_nonterminal
  }

/-- Compatibility projection from the synchronized nonterminal execution. -/
theorem RecognizerStateNonterminalSynchronizedExecution.physicalOutcome
    (execution : RecognizerStateNonterminalSynchronizedExecution grammarLayout
      grammar words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell runtime position current
      remaining beforeInvariant candidate found productionBound dotBeforeEnd
      bindings symbolBinding isNonterminal) :
    RecognizerStateOperationOutcome grammarLayout grammar words tokens
      workspaceLayout workspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position current remaining execution.physical.after
      execution.physical.completion := by
  rw [execution.completionEq]
  exact execution.sourceOutcome.physical_of_restored execution.restored



end Lanius.Extraction.ParserRecognize
