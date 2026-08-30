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

def parserRecognizeChartClearLoop : Stmt :=
  (recognizerWhileLoops extractedParserRecognizeBody)[0]?.getD .skip

def parserRecognizeChartClearCondition : Expr :=
  .binary .less (.local 10) (.local 8)

def parserRecognizeChartClearLoopBody : Stmt :=
  match parserRecognizeChartClearLoop with
  | .whileLoop _ body => body
  | _ => .skip

def parserRecognizeChartClearWrite : Expr :=
  .assign .set (.index (.local 4) (.local 10))
    (.unary .negate (.value (.signed .i32 1)))

theorem extractedParserRecognize_chart_clear_loop_shape :
    parserRecognizeChartClearLoop =
      .whileLoop parserRecognizeChartClearCondition
        parserRecognizeChartClearLoopBody := by
  rfl

theorem extractedParserRecognize_chart_clear_body_shape :
    parserRecognizeChartClearLoopBody =
      .sequence (.expression parserRecognizeChartClearWrite)
        (parserRecognizeIncrementLocal 10) := by
  rfl

/-! ## Stateful FunctionalView for chart clearing

The layout contains exactly the two locals touched by one loop iteration.
The command below is recovered from the checked Core statement, rather than
being a second handwritten copy of the parser body. -/

private def chartClearBodyLayout : Layout 2 :=
  pairLayout 4 10

private def chartClearBodyContext : Context :=
  (Context.empty.bind 4 (.slice parserI32Type)).bind 10 parserI32Type

private def chartClearBodySource : Stmt :=
  .sequence (.expression parserRecognizeChartClearWrite)
    (parserRecognizeIncrementLocal 10)

private def chartClearBodyReification? :=
  reifyCommand? verifiedParserCore (.structure 0) chartClearBodyContext true
    chartClearBodyLayout 11 chartClearBodySource

private theorem chartClearBodyReification_exists :
    chartClearBodyReification?.isSome := by
  native_decide

/-- Mechanically recovered mutable proof view of one chart-clear iteration. -/
private def chartClearBodyView :=
  chartClearBodyReification?.get chartClearBodyReification_exists

private def chartClearIndexTerm :
    Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 2 :=
  .reference (.slot ⟨1, by omega⟩)

private def chartClearNegativeOneTerm :
    Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 2 :=
  .apply (.unary .negate parserI32Type parserI32Type)
    [.reference (.literal (.signed .i32 1))]

private def chartClearOneTerm :
    Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 2 :=
  .reference (.literal (.signed .i32 1))

private def chartClearBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 2 :=
  .sequence
    (.action (.setI32Index ⟨0, by omega⟩
      chartClearIndexTerm chartClearNegativeOneTerm))
    (.sequence
      (.updateLocal .add ⟨1, by omega⟩
        chartClearOneTerm)
      .skip)

private theorem chartClearBodyView_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      chartClearBodyLayout 11 chartClearBodyView.command =
      parserRecognizeChartClearLoopBody := by
  rw [chartClearBodyView.toCoreExactly]
  exact extractedParserRecognize_chart_clear_body_shape.symm

private theorem chartClearBodyCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      chartClearBodyLayout 11 chartClearBodyCommand =
      parserRecognizeChartClearLoopBody := by
  rw [extractedParserRecognize_chart_clear_body_shape]
  rfl

/-! The complete loop additionally reads `state_base`.  The two mutable body
    slots stay in their original order and the read-only bound is appended. -/

private def chartClearLoopLayout : Layout 3 :=
  Layout.push chartClearBodyLayout 8

private def chartClearLoopIndexTerm :
    Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 3 :=
  .reference (.slot ⟨1, by omega⟩)

private def chartClearLoopBoundTerm :
    Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 3 :=
  .reference (.slot ⟨2, by omega⟩)

private def chartClearLoopCondition :
    Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 3 :=
  .apply (.binary .less parserI32Type parserI32Type (.scalar .bool))
    [chartClearLoopIndexTerm, chartClearLoopBoundTerm]

private def chartClearLoopNegativeOneTerm :
    Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 3 :=
  .apply (.unary .negate parserI32Type parserI32Type)
    [.reference (.literal (.signed .i32 1))]

private def chartClearLoopBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 3 :=
  .sequence
    (.action (.setI32Index ⟨0, by omega⟩ chartClearLoopIndexTerm
      chartClearLoopNegativeOneTerm))
    (.sequence
      (.updateLocal .add ⟨1, by omega⟩
        (.reference (.literal (.signed .i32 1))))
      .skip)

private def chartClearLoopCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 3 :=
  .whileLoop chartClearLoopCondition chartClearLoopBodyCommand

private theorem chartClearLoopCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      chartClearLoopLayout 11 chartClearLoopCommand =
      parserRecognizeChartClearLoop := by
  rw [extractedParserRecognize_chart_clear_loop_shape,
    extractedParserRecognize_chart_clear_body_shape]
  rfl

private def chartClearWorld (values : List Int) (workspaceCell : CellId) :
    Lanius.FunctionalView.Core.ReadOnly.World :=
  Lanius.FunctionalView.Core.ReadOnly.World.singleton workspaceCell values

private def chartClearEnvironment (values : List Int)
    (workspaceCell : CellId) (index : Nat) :
    Lanius.FunctionalView.Env 2 :=
  pairEnvironment (workspaceValue values workspaceCell)
    (.signed .i32 (Int.ofNat index))

private def chartClearLocalCells (workspaceLocalCell indexCell : CellId) :
    Fin 2 → CellId :=
  pairCells workspaceLocalCell indexCell

def recognizerChartClearWrites
    (workspaceCell indexCell : CellId) : CellSet :=
  CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton indexCell)

def verifiedParserChartClearAccessFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedAccessFrameForCore
    parserRecognizeChartClearLoop (by native_decide)

def verifiedParserChartClearLiveFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedLiveFrameBeforeCore
    parserRecognizeChartClearLoop (by native_decide)

theorem verifiedParser_chart_clear_access_frame :
    verifiedParserChartClearAccessFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("chart_word_index", 10, .readWrite),
      ("state_base", 8, .read),
      ("workspace", 4, .readWrite)] := by
  native_decide

theorem verifiedParser_chart_clear_live_frame :
    verifiedParserChartClearLiveFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("chart_word_index", 10, .readWrite),
      ("state_base", 8, .read),
      ("workspace", 4, .readWrite),
      ("grammar", 0, .read),
      ("state_capacity", 9, .read),
      ("final_position", 6, .read),
      ("tokens", 2, .read),
      ("token_count", 3, .read)] := by
  native_decide

/-- Declarations live across chart clearing whose cells are not owned by the
    loop index.  This must come from liveness rather than the clear body's
    direct accesses: `final_position` and `state_capacity` are consumed by
    the seeding and chart-processing continuation. -/
def verifiedParserChartClearSharedFrame :
    LocalAccessFrame :=
  verifiedParserChartClearLiveFrame.excludingName "chart_word_index"

def verifiedParserChartClearSharedFrameIds : List VarId :=
  verifiedParserChartClearSharedFrame.ids

def verifiedParserChartClearPersistentBindings : LocalBindingFrame :=
  LocalBindingFrame.union verifiedParserRecognizerParameterFrame
    verifiedParserChartClearSharedFrame.bindings

theorem verifiedParser_chart_clear_shared_frame_ids :
    verifiedParserChartClearSharedFrameIds = [8, 4, 0, 9, 6, 2, 3] := by
  native_decide

theorem verifiedParserChartClearPersistentBindings_core_ids :
    verifiedParserChartClearPersistentBindings.coreIds =
      verifiedParserRecognizerParameterIds ++
        verifiedParserChartClearSharedFrameIds := by
  native_decide

@[simp] theorem mem_verifiedParserChartClearSharedFrameIds_iff
    (id : Nat) :
    id ∈ verifiedParserChartClearSharedFrameIds ↔
      id = 8 ∨ id = 4 ∨ id = 0 ∨ id = 9 ∨ id = 6 ∨ id = 2 ∨ id = 3 := by
  rw [verifiedParser_chart_clear_shared_frame_ids]
  simp only [List.mem_cons, List.not_mem_nil, or_false]

/-- The chart-clear loop preserves every source parameter plus every shared
    declaration live in its continuation. -/
def ChartClearPersistentLocal (id : VarId) : Prop :=
  id ∈ verifiedParserRecognizerParameterIds ∨
    id ∈ verifiedParserChartClearSharedFrameIds

theorem ChartClearPersistentLocal_source_frame (id : VarId) :
    ChartClearPersistentLocal id ↔
      verifiedParserChartClearPersistentBindings.ContainsCoreId id := by
  rw [LocalBindingFrame.ContainsCoreId,
    verifiedParserChartClearPersistentBindings_core_ids]
  simp [ChartClearPersistentLocal]

theorem chartClearPersistentLocalFootprint_eq (runtime : State) :
    localCellFootprint runtime ChartClearPersistentLocal =
      localBindingFrameFootprint runtime
        verifiedParserChartClearPersistentBindings := by
  unfold localBindingFrameFootprint
  congr 1
  funext id
  exact propext (ChartClearPersistentLocal_source_frame id)

/-- Partial concrete initialization of the chart prefix. Addresses strictly
    below `index` contain `-1`; the remaining words retain arbitrary caller
    contents until their iterations execute. -/
structure RecognizerChartClearInvariant
    (layout : WorkspaceLayout) (values : List Int)
    (workspaceCell indexCell : CellId) (runtime : State) (index : Nat) :
    Prop where
  valuesLength : values.length = layout.workspaceLength
  wellFormed : StateWellFormed runtime
  workspaceLocal : runtime.local? 4 =
    some (workspaceValue values workspaceCell)
  workspaceLengthLocal : runtime.local? 5 =
    some (.signed .i32 (Int.ofNat values.length))
  stateBaseLocal : runtime.local? 8 =
    some (.signed .i32 (Int.ofNat (stateBase layout.tokenCount)))
  stateCapacityLocal : runtime.local? 9 =
    some (.signed .i32 (Int.ofNat layout.capacity))
  finalPositionLocal : runtime.local? 6 =
    some (.signed .i32 (Int.ofNat (finalPosition layout.tokenCount)))
  workspaceBacking : runtime.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values values))
  }
  indexOwned : (Assertion.localPointsTo 10 indexCell
    (some (.signed .i32 (Int.ofNat index)))).holds runtime
  indexLe : index ≤ stateBase layout.tokenCount
  indexDistinct : indexCell ≠ workspaceCell
  persistentSeparate : CellSet.Disjoint
    (localBindingFrameFootprint runtime
      verifiedParserChartClearPersistentBindings)
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton indexCell))
  cleared : ∀ address, address < index → listWords values address = -1

theorem RecognizerChartClearInvariant.condition_true
    (invariant : RecognizerChartClearInvariant layout values workspaceCell
      indexCell runtime index)
    (bound : index < stateBase layout.tokenCount) :
    Evaluates verifiedParserCore runtime
      (.binary .less (.local 10) (.local 8)) (.boolean true) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 10)
      (.signed .i32 (Int.ofNat index)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 10 _
      (Assertion.localPointsTo_local 10 indexCell _ runtime
        invariant.indexOwned)⟩
  have right : Evaluates verifiedParserCore runtime (.local 8)
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 8 _
      invariant.stateBaseLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt, bound]

theorem RecognizerChartClearInvariant.condition_false
    (invariant : RecognizerChartClearInvariant layout values workspaceCell
      indexCell runtime index)
    (done : stateBase layout.tokenCount ≤ index) :
    Evaluates verifiedParserCore runtime
      (.binary .less (.local 10) (.local 8)) (.boolean false) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 10)
      (.signed .i32 (Int.ofNat index)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 10 _
      (Assertion.localPointsTo_local 10 indexCell _ runtime
        invariant.indexOwned)⟩
  have right : Evaluates verifiedParserCore runtime (.local 8)
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 8 _
      invariant.stateBaseLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt]
  omega

structure RecognizerChartClearExecution
    (layout : WorkspaceLayout) (beforeValues : List Int)
    (workspaceCell indexCell : CellId) (before : State) (index : Nat)
    (beforeInvariant : RecognizerChartClearInvariant layout beforeValues
      workspaceCell indexCell before index) where
  after : State
  values : List Int
  execution : Executes verifiedParserCore before parserRecognizeChartClearLoop
    .next after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton indexCell)) before after
  invariant : RecognizerChartClearInvariant layout values workspaceCell
    indexCell after (stateBase layout.tokenCount)
  encoded : EncodesWorkspace layout emptyWorkspace (listWords values)

/-! ## Total FunctionalView chart-clear loop -/

private structure ChartClearFunctionalConfig
    (layout : WorkspaceLayout) (workspaceCell : CellId) where
  values : List Int
  index : Nat
  valuesLength : values.length = layout.workspaceLength
  indexLe : index ≤ stateBase layout.tokenCount
  cleared : ∀ address, address < index → listWords values address = -1

private def ChartClearFunctionalConfig.runtime
    (config : ChartClearFunctionalConfig layout workspaceCell) :
    Lanius.FunctionalView.Stateful.Loop.Runtime
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore) 3 :=
  (chartClearWorld config.values workspaceCell,
    (chartClearEnvironment config.values workspaceCell config.index).push
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))))

private def ChartClearFunctionalConfig.measure
    (config : ChartClearFunctionalConfig layout workspaceCell) : Nat :=
  stateBase layout.tokenCount - config.index

private def ChartClearFunctionalConfig.advance
    (config : ChartClearFunctionalConfig layout workspaceCell)
    (bound : config.index < stateBase layout.tokenCount) :
    ChartClearFunctionalConfig layout workspaceCell := {
  values := setI32Value config.values config.index (-1)
  index := config.index + 1
  valuesLength := by simpa using config.valuesLength
  indexLe := Nat.succ_le_of_lt bound
  cleared := by
    intro address addressBound
    by_cases current : address = config.index
    · subst address
      apply listWords_set_same
      rw [config.valuesLength]
      exact Nat.lt_of_lt_of_le bound layout.baseFits
    · rw [listWords_set_other config.values (-1) current]
      exact config.cleared address (by omega)
}

private theorem ChartClearFunctionalConfig.advance_world
    (config : ChartClearFunctionalConfig layout workspaceCell)
    (bound : config.index < stateBase layout.tokenCount) :
    Lanius.FunctionalView.Core.ReadOnly.World.setI32Slice
      config.runtime.world workspaceCell
      (setI32Value config.values config.index (-1)) =
      (config.advance bound).runtime.world := by
  simp [ChartClearFunctionalConfig.runtime,
    ChartClearFunctionalConfig.advance, chartClearWorld,
    Lanius.FunctionalView.Stateful.Loop.Runtime.world]

private theorem ChartClearFunctionalConfig.advance_environment
    (config : ChartClearFunctionalConfig layout workspaceCell)
    (bound : config.index < stateBase layout.tokenCount) :
    Lanius.FunctionalView.Stateful.Env.set config.runtime.environment
      ⟨1, by omega⟩ (.signed .i32 (Int.ofNat (config.index + 1))) =
      (config.advance bound).runtime.environment := by
  funext slot
  have cases : slot.val = 0 ∨ slot.val = 1 ∨ slot.val = 2 := by omega
  rcases cases with zero | one | two
  · have same : slot = ⟨0, by omega⟩ := Fin.ext zero
    rw [same]
    simp [ChartClearFunctionalConfig.runtime,
      ChartClearFunctionalConfig.advance, chartClearEnvironment,
      workspaceValue, Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push, pairEnvironment,
      Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
  · have same : slot = ⟨1, by omega⟩ := Fin.ext one
    rw [same]
    simp [ChartClearFunctionalConfig.runtime,
      ChartClearFunctionalConfig.advance, chartClearEnvironment,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push, pairEnvironment,
      Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
  · have same : slot = ⟨2, by omega⟩ := Fin.ext two
    rw [same]
    simp [ChartClearFunctionalConfig.runtime,
      ChartClearFunctionalConfig.advance, chartClearEnvironment,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push, pairEnvironment,
      Lanius.FunctionalView.Stateful.Loop.Runtime.environment]

private theorem ChartClearFunctionalConfig.condition
    (config : ChartClearFunctionalConfig layout workspaceCell) :
    Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      config.runtime.world config.runtime.environment
      chartClearLoopCondition =
      .ok (.boolean (decide (config.index < stateBase layout.tokenCount)),
        config.runtime.world) := by
  have left : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      config.runtime.world config.runtime.environment chartClearLoopIndexTerm =
      .ok (.signed .i32 (Int.ofNat config.index), config.runtime.world) := by
    rfl
  have right : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      config.runtime.world config.runtime.environment chartClearLoopBoundTerm =
      .ok (.signed .i32 (Int.ofNat (stateBase layout.tokenCount)),
        config.runtime.world) := by
    rfl
  exact Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_less left right

private theorem ChartClearFunctionalConfig.body
    (config : ChartClearFunctionalConfig layout workspaceCell)
    (bound : config.index < stateBase layout.tokenCount) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      (Lanius.FunctionalView.Core.Stateful.machine verifiedParserCore)
      config.runtime.world config.runtime.environment
      chartClearLoopBodyCommand .next
      (config.advance bound).runtime.world
      (config.advance bound).runtime.environment := by
  have indexInValues : config.index < config.values.length := by
    rw [config.valuesLength]
    exact Nat.lt_of_lt_of_le bound layout.baseFits
  have negativeOne : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      config.runtime.world config.runtime.environment
      chartClearLoopNegativeOneTerm =
      .ok (.signed .i32 (-1), config.runtime.world) :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_negate_one
  have incrementBound : config.index + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt bound)
      (stateBase_le_i32Max layout.tokenBound)
  have evaluated :=
    Lanius.FunctionalView.Core.Stateful.evaluatesSetI32AtCursorThenIncrementAndSkip
        (program := verifiedParserCore) (base := ⟨0, by omega⟩)
        (cursor := ⟨1, by omega⟩)
        (replacement := chartClearLoopNegativeOneTerm)
        (cell := workspaceCell) (values := config.values)
        (position := config.index) (replacementValue := -1)
        (by rfl) (by rfl) negativeOne
        Lanius.FunctionalView.Core.ReadOnly.World.singleton_finds
        indexInValues incrementBound
  rw [config.advance_world bound, config.advance_environment bound] at evaluated
  simpa [chartClearLoopBodyCommand, chartClearLoopIndexTerm] using evaluated

/-- One separation-logic proof covers every chart-clear iteration.  The
    algorithmic configuration supplies bounds and logical contents; physical
    cell ownership remains in `Representation`. -/
private theorem chartClearLoopBodySoundWithin
    (workspaceLocalCell indexCell boundLocalCell : CellId) :
    ConfigBodySoundWithin verifiedParserCore chartClearLoopLayout
      (pushCells (pairCells workspaceLocalCell indexCell) boundLocalCell)
      chartClearLoopCondition chartClearLoopBodyCommand actionAdapter 11
      (recognizerChartClearWrites workspaceCell indexCell)
      (ChartClearFunctionalConfig layout workspaceCell)
      ChartClearFunctionalConfig.runtime := by
  intro config afterWorld afterEnvironment before completion conditionTrue
    evaluated represented wellFormed
  have bound : config.index < stateBase layout.tokenCount := by
    by_cases bound : config.index < stateBase layout.tokenCount
    · exact bound
    · have conditionFalse : Lanius.FunctionalView.Term.evaluate
          (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
          config.runtime.world config.runtime.environment
          chartClearLoopCondition =
          .ok (.boolean false, config.runtime.world) := by
        rw [config.condition]
        simp [bound]
      have impossible := conditionFalse.symm.trans conditionTrue
      simp at impossible
  have canonical := config.body bound
  obtain ⟨completionEq, worldEq, environmentEq⟩ :=
    canonical.deterministic evaluated
  cases completionEq
  cases worldEq
  cases environmentEq
  have indexInValues : config.index < config.values.length := by
    rw [config.valuesLength]
    exact Nat.lt_of_lt_of_le bound layout.baseFits
  have negativeOne : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      config.runtime.world config.runtime.environment
      chartClearLoopNegativeOneTerm =
      .ok (.signed .i32 (-1), config.runtime.world) :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_negate_one
  have incrementBound : config.index + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt bound)
      (stateBase_le_i32Max layout.tokenBound)
  obtain ⟨after, execution, afterWellFormed, afterRepresented, effect⟩ :=
    represented.setI32AtCursorThenIncrementAndSkip
      (base := ⟨0, by omega⟩) (cursor := ⟨1, by omega⟩)
      (replacement := chartClearLoopNegativeOneTerm)
      (nextLocal := 11) wellFormed (by rfl) (by rfl) negativeOne
      Lanius.FunctionalView.Core.ReadOnly.World.singleton_finds
      indexInValues incrementBound
  rw [config.advance_world bound, config.advance_environment bound]
    at afterRepresented
  exact ⟨after, by
      simpa [chartClearLoopBodyCommand, chartClearLoopIndexTerm,
        Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using execution,
    afterWellFormed, afterRepresented, by
      simpa [recognizerChartClearWrites, pushCells, pairCells] using effect⟩

private structure ChartClearFunctionalPost
    (layout : WorkspaceLayout) (workspaceCell : CellId)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore) 3) where
  completionEq : completion = .next
  final : ChartClearFunctionalConfig layout workspaceCell
  finalIndex : final.index = stateBase layout.tokenCount
  afterEq : after = final.runtime

private abbrev ChartClearFunctionalResult
    (layout : WorkspaceLayout) (workspaceCell : CellId) :=
  fun (_ : ChartClearFunctionalConfig layout workspaceCell)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore) 3) =>
    ChartClearFunctionalPost layout workspaceCell completion after

private noncomputable def ChartClearFunctionalConfig.decide
    (config : ChartClearFunctionalConfig layout workspaceCell) :
    Lanius.FunctionalView.Stateful.Loop.Decision
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      (Lanius.FunctionalView.Core.Stateful.machine verifiedParserCore)
      chartClearLoopCondition chartClearLoopBodyCommand
      (ChartClearFunctionalConfig layout workspaceCell)
      ChartClearFunctionalConfig.runtime ChartClearFunctionalConfig.measure
      (ChartClearFunctionalResult layout workspaceCell) config := by
  by_cases done : config.index = stateBase layout.tokenCount
  · apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
    exact {
      completion := .next
      after := config.runtime
      edge := .conditionFalse (by
        rw [config.condition, done]
        simp)
      result := {
        completionEq := rfl
        final := config
        finalIndex := done
        afterEq := rfl
      }
    }
  · have bound : config.index < stateBase layout.tokenCount := by
      have := config.indexLe
      omega
    let next := config.advance bound
    apply Lanius.FunctionalView.Stateful.Loop.Decision.next next
    · refine Lanius.FunctionalView.Stateful.Loop.Iteration.next
        (conditionWorld := config.runtime.world) (by
        rw [config.condition]
        simp [bound]) (by
        simpa [next] using config.body bound)
    · dsimp [ChartClearFunctionalConfig.measure, next]
      change stateBase layout.tokenCount - (config.index + 1) <
        stateBase layout.tokenCount - config.index
      omega
    · intro completion after result
      exact result

/-- Execute the complete chart-clear loop by first running the pure
    FunctionalView algorithm and then crossing the separation boundary once.
    Neither recursion nor per-iteration frame reconstruction appears in the
    parser proof. -/
noncomputable def RecognizerChartClearInvariant.execute_loop
    (invariant : RecognizerChartClearInvariant layout values workspaceCell
      indexCell runtime index) :
    RecognizerChartClearExecution layout values workspaceCell indexCell runtime
      index invariant := by
  have sharedLocalSubset : CellSet.Subset
      (localCellFootprint runtime (fun id => id = 4 ∨ id = 8))
      (localBindingFrameFootprint runtime
        verifiedParserChartClearPersistentBindings) :=
    localCellFootprint_mono (by
      intro id member
      apply (ChartClearPersistentLocal_source_frame id).mp
      rcases member with rfl | rfl <;>
        simp [ChartClearPersistentLocal,
          verifiedParser_chart_clear_shared_frame_ids])
  have sharedSeparate : CellSet.Disjoint
      (localCellFootprint runtime (fun id => id = 4 ∨ id = 8))
      (recognizerChartClearWrites workspaceCell indexCell) := by
    exact CellSet.Disjoint.mono_left sharedLocalSubset
      invariant.persistentSeparate
  let boundedView := SliceCursorBoundRepresentation.ofState
    invariant.wellFormed invariant.workspaceLocal invariant.workspaceBacking
    invariant.indexOwned invariant.stateBaseLocal sharedSeparate
    invariant.indexDistinct (by simp)
  let initial : ChartClearFunctionalConfig layout workspaceCell := {
    values := values
    index := index
    valuesLength := invariant.valuesLength
    indexLe := invariant.indexLe
    cleared := invariant.cleared
  }
  let localCells := pushCells
    (pairCells boundedView.sliceLocalCell indexCell)
    boundedView.boundLocalCell
  have represented : Representation chartClearLoopLayout localCells
      initial.runtime.world initial.runtime.environment runtime := by
    simpa [chartClearLoopLayout, chartClearBodyLayout, initial,
      ChartClearFunctionalConfig.runtime, chartClearWorld,
      chartClearEnvironment, workspaceValue, parserI32Type, localCells,
      boundedView, Lanius.FunctionalView.Stateful.Loop.Runtime.world,
      Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
        boundedView.represented
  let assembled := Lanius.FunctionalView.Stateful.Loop.run
    (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
    (Lanius.FunctionalView.Core.Stateful.machine verifiedParserCore)
    chartClearLoopCondition chartClearLoopBodyCommand
    (ChartClearFunctionalConfig layout workspaceCell)
    ChartClearFunctionalConfig.runtime ChartClearFunctionalConfig.measure
    (ChartClearFunctionalResult layout workspaceCell)
    ChartClearFunctionalConfig.decide initial
  rcases assembled with ⟨completion, abstractAfter, trace, result⟩
  cases result.completionEq
  let abstractSimulation := trace.simulatesWithin
    (chartClearLoopBodySoundWithin boundedView.sliceLocalCell indexCell
      boundedView.boundLocalCell) represented invariant.wellFormed
  have simulation : SimulatesWithin verifiedParserCore chartClearLoopLayout
      localCells initial.runtime.world initial.runtime.environment runtime
      chartClearLoopCommand .next result.final.runtime.world
      result.final.runtime.environment actionAdapter 11
      (recognizerChartClearWrites workspaceCell indexCell) := by
    rw [← result.afterEq]
    simpa [chartClearLoopCommand, localCells] using abstractSimulation
  let after := Classical.choose simulation
  have simulationFacts := Classical.choose_spec simulation
  have loopExecution := simulationFacts.1
  have afterWellFormed := simulationFacts.2.1
  have afterRepresented := simulationFacts.2.2.1
  have effect := simulationFacts.2.2.2
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint runtime
        verifiedParserChartClearPersistentBindings)
      (recognizerChartClearWrites workspaceCell indexCell) :=
    invariant.persistentSeparate
  have preserveLocal (id : VarId) (persistent : ChartClearPersistentLocal id)
      (value : Value) (found : runtime.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint invariant.wellFormed frameDisjoint
      ((ChartClearPersistentLocal_source_frame id).mp persistent) found
  have afterWorkspaceLocal : after.local? 4 =
      some (workspaceValue result.final.values workspaceCell) := by
    have owned := afterRepresented.localOwned ⟨0, by omega⟩
    have localFound := Assertion.localPointsTo_local 4
      (localCells ⟨0, by omega⟩)
      (workspaceValue result.final.values workspaceCell) after owned
    simpa [chartClearLoopLayout, chartClearBodyLayout,
      ChartClearFunctionalConfig.runtime, chartClearEnvironment,
      workspaceValue, parserI32Type, localCells] using localFound
  have afterStateBaseLocal : after.local? 8 = some
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))) := by
    have owned := afterRepresented.localOwned ⟨2, by omega⟩
    have localFound := Assertion.localPointsTo_local 8
      (localCells ⟨2, by omega⟩)
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))) after owned
    simpa [chartClearLoopLayout, chartClearBodyLayout,
      ChartClearFunctionalConfig.runtime, chartClearEnvironment,
      localCells] using localFound
  have afterWorkspaceBacking : after.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values result.final.values))
    } :=
    afterRepresented.worldOwned workspaceCell result.final.values (by
      simp [ChartClearFunctionalConfig.runtime, chartClearWorld,
        Lanius.FunctionalView.Stateful.Loop.Runtime.world])
  have afterIndexOwned : (Assertion.localPointsTo 10 indexCell
      (some (.signed .i32
        (Int.ofNat (stateBase layout.tokenCount))))).holds after := by
    have owned := afterRepresented.localOwned ⟨1, by omega⟩
    simpa [after, chartClearLoopLayout, chartClearBodyLayout,
      ChartClearFunctionalConfig.runtime, chartClearEnvironment,
      localCells, result.finalIndex,
      Lanius.FunctionalView.Stateful.Loop.Runtime.environment,
      Lanius.FunctionalView.Env.push, Layout.push, pushCells, pairCells,
      pairLayout] using owned
  have afterInvariant : RecognizerChartClearInvariant layout
      result.final.values workspaceCell indexCell after
      (stateBase layout.tokenCount) := {
    valuesLength := result.final.valuesLength
    wellFormed := afterWellFormed
    workspaceLocal := afterWorkspaceLocal
    workspaceLengthLocal := by
      have preserved := preserveLocal 5 (by
        simp [ChartClearPersistentLocal]) _ invariant.workspaceLengthLocal
      simpa [invariant.valuesLength, result.final.valuesLength] using preserved
    stateBaseLocal := afterStateBaseLocal
    stateCapacityLocal := preserveLocal 9 (by
      simp [ChartClearPersistentLocal]) _ invariant.stateCapacityLocal
    finalPositionLocal := preserveLocal 6 (by
      simp [ChartClearPersistentLocal]) _ invariant.finalPositionLocal
    workspaceBacking := afterWorkspaceBacking
    indexOwned := afterIndexOwned
    indexLe := by omega
    indexDistinct := invariant.indexDistinct
    persistentSeparate := by
      rw [effect.localBindingFrameFootprint_eq
        verifiedParserChartClearPersistentBindings]
      exact invariant.persistentSeparate
    cleared := by simpa [result.finalIndex] using result.final.cleared
  }
  exact {
    after := after
    values := result.final.values
    execution := by
      rw [← chartClearLoopCommand_toCore]
      simpa [after, chartClearLoopCommand,
        Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using loopExecution
    effect := by simpa [after, recognizerChartClearWrites] using effect
    invariant := afterInvariant
    encoded := encodesEmptyWorkspace_of_cleared_chart layout result.final.values
      (by simpa [result.finalIndex] using result.final.cleared)
  }

/-- Lift chart initialization back into the complete persistent recognizer
    frame. This is the semantic boundary between an arbitrary caller-owned
    workspace buffer and the empty logical workspace used by Earley seeding. -/
theorem RecognizerChartClearExecution.recognizer_invariant
    (execution : RecognizerChartClearExecution workspaceLayout beforeValues
      workspaceCell indexCell before index beforeInvariant)
    (resources : RecognizerResources grammarLayout grammar words tokens
      workspaceLayout beforeValues grammarCell tokensCell workspaceCell before)
    (indexGrammarDistinct : indexCell ≠ grammarCell)
    (indexTokensDistinct : indexCell ≠ tokensCell) :
    RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
      emptyWorkspace execution.values grammarCell tokensCell workspaceCell
      execution.after := by
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton indexCell)
  have parameterFootprintSubset : CellSet.Subset
      (localBindingFrameFootprint before
        verifiedParserRecognizerParameterFrame)
      (localBindingFrameFootprint before
        verifiedParserChartClearPersistentBindings) :=
    localBindingFrameFootprint_mono (fun id member =>
      (ChartClearPersistentLocal_source_frame id).mp (Or.inl member))
  have parameterFrameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        verifiedParserRecognizerParameterFrame) writes :=
    CellSet.Disjoint.mono_left parameterFootprintSubset
      beforeInvariant.persistentSeparate
  have preserveLocal (id : VarId)
      (idBound : id ∈ verifiedParserRecognizerParameterIds) (value : Value)
      (found : before.local? id = some value) :
      execution.after.local? id = some value :=
    execution.effect.preserves_local_of_disjoint resources.wellFormed
      parameterFrameDisjoint idBound found
  have grammarNotWritten : ¬ writes grammarCell := by
    simpa [writes, CellSet.union, CellSet.singleton, not_or] using
      ⟨resources.grammarWorkspaceDistinct, indexGrammarDistinct.symm⟩
  have tokensNotWritten : ¬ writes tokensCell := by
    simpa [writes, CellSet.union, CellSet.singleton, not_or] using
      ⟨resources.tokensWorkspaceDistinct, indexTokensDistinct.symm⟩
  have afterResources : RecognizerResources grammarLayout grammar words tokens
      workspaceLayout execution.values grammarCell tokensCell workspaceCell
      execution.after := {
    grammarEncoded := resources.grammarEncoded
    grammarWellFormed := resources.grammarWellFormed
    wordsI32 := resources.wordsI32
    tokensI32 := resources.tokensI32
    workspaceLength := execution.invariant.valuesLength
    workspaceTokenCount := resources.workspaceTokenCount
    wellFormed := execution.invariant.wellFormed
    grammarLocal := preserveLocal 0 (by simp) _ resources.grammarLocal
    grammarLengthLocal := preserveLocal 1 (by simp) _
      resources.grammarLengthLocal
    tokensLocal := preserveLocal 2 (by simp) _ resources.tokensLocal
    tokenCountLocal := preserveLocal 3 (by simp) _
      resources.tokenCountLocal
    workspaceLocal := execution.invariant.workspaceLocal
    workspaceLengthLocal := execution.invariant.workspaceLengthLocal
    grammarBacking := execution.effect.preserves_entry resources.wellFormed
      resources.grammarBacking grammarNotWritten
    tokensBacking := execution.effect.preserves_entry resources.wellFormed
      resources.tokensBacking tokensNotWritten
    workspaceBacking := execution.invariant.workspaceBacking
    grammarWorkspaceDistinct := resources.grammarWorkspaceDistinct
    tokensWorkspaceDistinct := resources.tokensWorkspaceDistinct
  }
  exact afterResources.with_workspace_encoding emptyWorkspace execution.encoded
    (emptyWorkspace_derivations grammar tokens)


end Lanius.Extraction.ParserRecognize
