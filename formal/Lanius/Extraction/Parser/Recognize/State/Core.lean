import Lanius.Extraction.Parser.Recognize.Prediction
import Lanius.Extraction.Parser.Recognize.Nullable
import Lanius.Extraction.Parser.Recognize.Parent

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
/-! ## Enclosing position, state-chain, and root loops -/

def parserRecognizePositionLoop : Stmt :=
  (recognizerWhileLoops extractedParserRecognizeBody)[2]?.getD .skip

def parserRecognizePositionLoopBody : Stmt :=
  match parserRecognizePositionLoop with
  | .whileLoop _ body => body
  | _ => .skip

/-- The chart-presence test at the start of one position iteration. -/
def parserRecognizePositionActivity : Stmt :=
  match parserRecognizePositionLoopBody with
  | .sequence activity _ => activity
  | _ => .skip

/-- The scoped state-chain traversal and position increment that follow the
    chart-presence test. -/
def parserRecognizePositionStateScope : Stmt :=
  match parserRecognizePositionLoopBody with
  | .sequence _ stateScope => stateScope
  | _ => .skip

/-- The increment that closes one normal position iteration. -/
def parserRecognizePositionAdvance : Stmt :=
  match parserRecognizePositionStateScope with
  | .letLocal 24 _ _ (.sequence _ advance) => advance
  | _ => .skip

def parserRecognizeStateLoop : Stmt :=
  (recognizerWhileLoops extractedParserRecognizeBody)[3]?.getD .skip

def parserRecognizeStateLoopBody : Stmt :=
  match parserRecognizeStateLoop with
  | .whileLoop _ body => body
  | _ => .skip

def parserRecognizeStateAfterBindings : Stmt :=
  match parserRecognizeStateLoopBody with
  | .letLocal 25 _ _ (.letLocal 26 _ _ (.letLocal 27 _ _
      (.letLocal 28 _ _ body))) => body
  | _ => .skip

def parserRecognizeStateIncompleteBranch : Stmt :=
  match parserRecognizeStateAfterBindings with
  | .sequence (.ifThenElse _ incomplete _) _ => incomplete
  | _ => .skip

def parserRecognizeStateCompleteBranch : Stmt :=
  match parserRecognizeStateAfterBindings with
  | .sequence (.ifThenElse _ _ complete) _ => complete
  | _ => .skip

def parserRecognizeStateNonterminalBranch : Stmt :=
  match parserRecognizeStateIncompleteBranch with
  | .letLocal 29 _ _ (.sequence (.ifThenElse _ _ nonterminal) _) =>
      nonterminal
  | _ => .skip

def parserRecognizeRootLoop : Stmt :=
  (recognizerWhileLoops extractedParserRecognizeBody)[7]?.getD .skip

def parserRecognizeRootLoopBody : Stmt :=
  match parserRecognizeRootLoop with
  | .whileLoop _ body => body
  | _ => .skip

def parserRecognizeRootPredicate : Expr :=
  match parserRecognizeRootLoopBody with
  | .letLocal 42 _ _ (.sequence (.ifThenElse predicate _ _) _) => predicate
  | _ => .value (.boolean false)

def parserRecognizeRootSuccessBranch : Stmt :=
  match parserRecognizeRootLoopBody with
  | .letLocal 42 _ _ (.sequence (.ifThenElse _ success _) _) => success
  | _ => .skip

/-- The final root-search scope, selected structurally from the checked
    recognizer artifact. -/
def parserRecognizeRootStatement : Stmt :=
  (findLetLocalStatement 41 extractedParserRecognizeBody).getD .skip

def parserRecognizePositionStatement : Stmt :=
  (findLetLocalStatement 22 extractedParserRecognizeBody).getD .skip

def parserRecognizeInitialIndexStatement : Stmt :=
  (findLetLocalStatement 19 extractedParserRecognizeBody).getD .skip

def parserRecognizeSeedSetupStatement : Stmt :=
  (findLetLocalStatement 11 extractedParserRecognizeBody).getD .skip

def parserRecognizeStartNonterminalStatement : Stmt :=
  (findLetLocalStatement 12 extractedParserRecognizeBody).getD .skip

def parserRecognizeLhsOffsetsStatement : Stmt :=
  (findLetLocalStatement 13 extractedParserRecognizeBody).getD .skip

def parserRecognizeLhsCountsStatement : Stmt :=
  (findLetLocalStatement 14 extractedParserRecognizeBody).getD .skip

def parserRecognizeLhsProductionsStatement : Stmt :=
  (findLetLocalStatement 15 extractedParserRecognizeBody).getD .skip

def parserRecognizeStartFirstStatement : Stmt :=
  (findLetLocalStatement 16 extractedParserRecognizeBody).getD .skip

def parserRecognizeStartCountStatement : Stmt :=
  (findLetLocalStatement 17 extractedParserRecognizeBody).getD .skip

def parserRecognizeStateCountStatement : Stmt :=
  (findLetLocalStatement 18 extractedParserRecognizeBody).getD .skip

def parserRecognizeAfterInitialIndexBinding : Stmt :=
  match parserRecognizeInitialIndexStatement with
  | .letLocal 19 _ _ body => body
  | _ => .skip

def parserRecognizeRootHeadExpr : Expr :=
  match parserRecognizeRootStatement with
  | .letLocal 41 _ initializer _ => initializer
  | _ => .value (.signed .i32 (-1))

def parserRecognizeRejectedReturn : Stmt :=
  match parserRecognizeRootStatement with
  | .letLocal 41 _ _ (.sequence _ rejected) => rejected
  | _ => .skip

theorem extractedParserRecognize_root_statement_shape :
    parserRecognizeRootStatement =
      .letLocal 41 parserI32Type parserRecognizeRootHeadExpr
        (.sequence parserRecognizeRootLoop parserRecognizeRejectedReturn) := by
  rfl

theorem extractedParserRecognize_position_statement_shape :
    parserRecognizePositionStatement =
      .letLocal 22 parserI32Type (.value (.signed .i32 0))
        (.letLocal 23 parserI32Type (.value (.signed .i32 0))
          (.sequence parserRecognizePositionLoop
            parserRecognizeRootStatement)) := by
  rfl

theorem extractedParserRecognize_initial_index_statement_shape :
    parserRecognizeInitialIndexStatement =
      .letLocal 19 parserI32Type (.value (.signed .i32 0))
        parserRecognizeAfterInitialIndexBinding := by
  rfl

theorem extractedParserRecognize_seed_setup_shape :
    parserRecognizeSeedSetupStatement =
      .letLocal 11 parserI32Type
        (.index (.local 0) (.constant 8))
        parserRecognizeStartNonterminalStatement := by
  rfl

theorem extractedParserRecognize_start_nonterminal_statement_shape :
    parserRecognizeStartNonterminalStatement =
      .letLocal 12 parserI32Type
        (.index (.local 0) (.constant 11))
        parserRecognizeLhsOffsetsStatement := by
  rfl

theorem extractedParserRecognize_lhs_offsets_statement_shape :
    parserRecognizeLhsOffsetsStatement =
      .letLocal 13 parserI32Type
        (.index (.local 0) (.constant 20))
        parserRecognizeLhsCountsStatement := by
  rfl

theorem extractedParserRecognize_lhs_counts_statement_shape :
    parserRecognizeLhsCountsStatement =
      .letLocal 14 parserI32Type
        (.index (.local 0) (.constant 21))
        parserRecognizeLhsProductionsStatement := by
  rfl

theorem extractedParserRecognize_lhs_productions_statement_shape :
    parserRecognizeLhsProductionsStatement =
      .letLocal 15 parserI32Type
        (.index (.local 0) (.constant 22))
        parserRecognizeStartFirstStatement := by
  rfl

theorem extractedParserRecognize_start_first_statement_shape :
    parserRecognizeStartFirstStatement =
      .letLocal 16 parserI32Type
        (.index (.local 0) (.binary .add (.local 13) (.local 12)))
        parserRecognizeStartCountStatement := by
  rfl

theorem extractedParserRecognize_start_count_statement_shape :
    parserRecognizeStartCountStatement =
      .letLocal 17 parserI32Type
        (.index (.local 0) (.binary .add (.local 14) (.local 12)))
        parserRecognizeStateCountStatement := by
  rfl

theorem extractedParserRecognize_state_count_statement_shape :
    parserRecognizeStateCountStatement =
      .letLocal 18 parserI32Type (.value (.signed .i32 0))
        parserRecognizeInitialIndexStatement := by
  rfl

theorem extractedParserRecognize_after_initial_index_shape :
    parserRecognizeAfterInitialIndexBinding =
      .sequence parserRecognizeInitialLoop parserRecognizePositionStatement := by
  rfl

theorem extractedParserRecognize_rejected_return_shape :
    parserRecognizeRejectedReturn =
      .sequence
        (.returnValue (some (.call extractedParserParseResultFunction.id [
          .constant 1,
          .local 18,
          .unary .negate (.value (.signed .i32 1)),
          .local 22])))
        .skip := by
  rfl

def verifiedParserPositionLoopAccessFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedAccessFrameForCore
    parserRecognizePositionLoop (by native_decide)

def verifiedParserPositionLoopLiveFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedLiveFrameBeforeCore
    parserRecognizePositionLoop (by native_decide)

theorem verifiedParser_position_loop_access_frame :
    verifiedParserPositionLoopAccessFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("position", 23, .readWrite),
      ("final_position", 6, .read),
      ("workspace", 4, .read),
      ("furthest_position", 22, .write),
      ("state_base", 8, .read),
      ("grammar", 0, .read),
      ("kind_count", 11, .read),
      ("tokens", 2, .read),
      ("token_count", 3, .read),
      ("state_capacity", 9, .read),
      ("state_count", 18, .readWrite),
      ("lhs_offsets_offset", 13, .read),
      ("lhs_counts_offset", 14, .read),
      ("lhs_productions_offset", 15, .read)] := by
  native_decide

theorem verifiedParser_position_loop_live_frame :
    verifiedParserPositionLoopLiveFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("position", 23, .readWrite),
      ("final_position", 6, .read),
      ("workspace", 4, .read),
      ("furthest_position", 22, .readWrite),
      ("state_base", 8, .read),
      ("grammar", 0, .read),
      ("kind_count", 11, .read),
      ("tokens", 2, .read),
      ("token_count", 3, .read),
      ("state_capacity", 9, .read),
      ("state_count", 18, .readWrite),
      ("lhs_offsets_offset", 13, .read),
      ("lhs_counts_offset", 14, .read),
      ("lhs_productions_offset", 15, .read),
      ("start_nonterminal", 12, .read)] := by
  native_decide

/-- Locals whose mappings survive every position iteration.  The three
    loop-owned scalars have dedicated ownership fields. -/
def verifiedParserPositionLoopPreservedFrame : LocalAccessFrame :=
  ((verifiedParserPositionLoopLiveFrame.excludingName "position")
    |>.excludingName "furthest_position")
    |>.excludingName "state_count"

def verifiedParserPositionLoopPreservedFrameIds : List VarId :=
  verifiedParserPositionLoopPreservedFrame.ids

theorem verifiedParser_position_loop_preserved_frame_ids :
    verifiedParserPositionLoopPreservedFrameIds =
      [6, 4, 8, 0, 11, 2, 3, 9, 13, 14, 15, 12] := by
  native_decide

@[simp] theorem mem_verifiedParserPositionLoopPreservedFrameIds_iff
    (id : VarId) :
    id ∈ verifiedParserPositionLoopPreservedFrameIds ↔
      id = 6 ∨ id = 4 ∨ id = 8 ∨ id = 0 ∨ id = 11 ∨ id = 2 ∨
      id = 3 ∨ id = 9 ∨ id = 13 ∨ id = 14 ∨ id = 15 ∨ id = 12 := by
  rw [verifiedParser_position_loop_preserved_frame_ids]
  simp only [List.mem_cons, List.not_mem_nil, or_false]

def verifiedParserPositionLoopPreservedBindings : LocalBindingFrame :=
  LocalBindingFrame.union verifiedParserRecognizerParameterFrame
    verifiedParserPositionLoopPreservedFrame.bindings

theorem verifiedParserPositionLoopPreservedBindings_core_ids :
    verifiedParserPositionLoopPreservedBindings.coreIds =
      verifiedParserRecognizerParameterIds ++
        verifiedParserPositionLoopPreservedFrameIds := by
  native_decide

def PositionLoopPreservedLocal (id : VarId) : Prop :=
  id ∈ verifiedParserRecognizerParameterIds ∨
    id ∈ verifiedParserPositionLoopPreservedFrameIds

theorem PositionLoopPreservedLocal_source_frame (id : VarId) :
    PositionLoopPreservedLocal id ↔
      verifiedParserPositionLoopPreservedBindings.ContainsCoreId id := by
  rw [LocalBindingFrame.ContainsCoreId,
    verifiedParserPositionLoopPreservedBindings_core_ids]
  simp [PositionLoopPreservedLocal]

theorem PositionLoopPreservedLocal.le15
    {id : VarId} (preserved : PositionLoopPreservedLocal id) : id ≤ 15 := by
  rcases preserved with parameter | framed
  · exact Nat.le_trans
      ((mem_verifiedParserRecognizerParameterIds_iff id).mp parameter)
      (by decide)
  · rw [mem_verifiedParserPositionLoopPreservedFrameIds_iff] at framed
    rcases framed with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
        rfl | rfl | rfl | rfl <;> decide

def positionLoopMutableCells
    (workspaceCell stateCountCell positionCell furthestCell : CellId) :
    CellSet :=
  CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.union (CellSet.singleton positionCell)
        (CellSet.singleton furthestCell)))

def PositionLoopFrameSeparated (runtime : State)
    (workspaceCell stateCountCell positionCell furthestCell : CellId) : Prop :=
  CellSet.Disjoint
    (localBindingFrameFootprint runtime
      verifiedParserPositionLoopPreservedBindings)
    (positionLoopMutableCells workspaceCell stateCountCell positionCell
      furthestCell)

def verifiedParserStateLoopAccessFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedAccessFrameForCore
    parserRecognizeStateLoop (by native_decide)

def verifiedParserStateLoopLiveFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedLiveFrameBeforeCore
    parserRecognizeStateLoop (by native_decide)

theorem verifiedParser_state_loop_access_frame :
    verifiedParserStateLoopAccessFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("state_id", 24, .readWrite),
      ("workspace", 4, .read),
      ("state_base", 8, .read),
      ("grammar", 0, .read),
      ("kind_count", 11, .read),
      ("tokens", 2, .read),
      ("token_count", 3, .read),
      ("position", 23, .read),
      ("state_capacity", 9, .read),
      ("state_count", 18, .readWrite),
      ("lhs_offsets_offset", 13, .read),
      ("lhs_counts_offset", 14, .read),
      ("lhs_productions_offset", 15, .read)] := by
  native_decide

theorem verifiedParser_state_loop_live_frame :
    verifiedParserStateLoopLiveFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("state_id", 24, .readWrite),
      ("workspace", 4, .read),
      ("state_base", 8, .read),
      ("grammar", 0, .read),
      ("kind_count", 11, .read),
      ("tokens", 2, .read),
      ("token_count", 3, .read),
      ("position", 23, .readWrite),
      ("state_capacity", 9, .read),
      ("state_count", 18, .readWrite),
      ("lhs_offsets_offset", 13, .read),
      ("lhs_counts_offset", 14, .read),
      ("lhs_productions_offset", 15, .read)] := by
  native_decide

/-- State-loop accesses shared with its surrounding position frame.  The
    mutable `state_id` cursor is omitted because `chartCursor` owns it. -/
def verifiedParserStateLoopSharedFrame :
    LocalAccessFrame :=
  verifiedParserStateLoopAccessFrame.excludingName "state_id"

def verifiedParserStateLoopSharedFrameIds : List VarId :=
  verifiedParserStateLoopSharedFrame.ids

theorem verifiedParser_state_loop_shared_frame_ids :
    verifiedParserStateLoopSharedFrameIds =
      [4, 8, 0, 11, 2, 3, 23, 9, 18, 13, 14, 15] := by
  native_decide

@[simp] theorem mem_verifiedParserStateLoopSharedFrameIds_iff
    (id : Nat) :
    id ∈ verifiedParserStateLoopSharedFrameIds ↔
      id = 4 ∨ id = 8 ∨ id = 0 ∨ id = 11 ∨ id = 2 ∨ id = 3 ∨
        id = 23 ∨ id = 9 ∨ id = 18 ∨ id = 13 ∨ id = 14 ∨ id = 15 := by
  rw [verifiedParser_state_loop_shared_frame_ids]
  simp only [List.mem_cons, List.not_mem_nil, or_false]

/-- Source-derived state-loop frame whose cells survive a prediction append. -/
def verifiedParserStateLoopPreservedFrame :
    LocalAccessFrame :=
  verifiedParserStateLoopSharedFrame.excludingName "state_count"

def verifiedParserStateLoopPreservedFrameIds : List VarId :=
  verifiedParserStateLoopPreservedFrame.ids

theorem verifiedParser_state_loop_preserved_frame_ids :
    verifiedParserStateLoopPreservedFrameIds =
      [4, 8, 0, 11, 2, 3, 23, 9, 13, 14, 15] := by
  native_decide

@[simp] theorem mem_verifiedParserStateLoopPreservedFrameIds_iff
    (id : Nat) :
    id ∈ verifiedParserStateLoopPreservedFrameIds ↔
      id = 4 ∨ id = 8 ∨ id = 0 ∨ id = 11 ∨ id = 2 ∨ id = 3 ∨
        id = 23 ∨ id = 9 ∨ id = 13 ∨ id = 14 ∨ id = 15 := by
  rw [verifiedParser_state_loop_preserved_frame_ids]
  simp only [List.mem_cons, List.not_mem_nil, or_false]

def verifiedParserStateLoopPersistentBindings : LocalBindingFrame :=
  LocalBindingFrame.union verifiedParserRecognizerParameterFrame
    verifiedParserStateLoopSharedFrame.bindings

def verifiedParserStateLoopPreservedBindings : LocalBindingFrame :=
  LocalBindingFrame.union verifiedParserRecognizerParameterFrame
    verifiedParserStateLoopPreservedFrame.bindings

def StateLoopPersistentLocal (id : VarId) : Prop :=
  id ∈ verifiedParserRecognizerParameterIds ∨
    id ∈ verifiedParserStateLoopSharedFrameIds

def StateLoopPreservedLocal (id : VarId) : Prop :=
  id ∈ verifiedParserRecognizerParameterIds ∨
    id ∈ verifiedParserStateLoopPreservedFrameIds

theorem verifiedParserStateLoopPersistentBindings_core_ids :
    verifiedParserStateLoopPersistentBindings.coreIds =
      verifiedParserRecognizerParameterIds ++
        verifiedParserStateLoopSharedFrameIds := by
  native_decide

theorem verifiedParserStateLoopPreservedBindings_core_ids :
    verifiedParserStateLoopPreservedBindings.coreIds =
      verifiedParserRecognizerParameterIds ++
        verifiedParserStateLoopPreservedFrameIds := by
  native_decide

theorem StateLoopPersistentLocal_source_frame (id : VarId) :
    StateLoopPersistentLocal id ↔
      verifiedParserStateLoopPersistentBindings.ContainsCoreId id := by
  rw [LocalBindingFrame.ContainsCoreId,
    verifiedParserStateLoopPersistentBindings_core_ids]
  simp [StateLoopPersistentLocal]

theorem StateLoopPreservedLocal_source_frame (id : VarId) :
    StateLoopPreservedLocal id ↔
      verifiedParserStateLoopPreservedBindings.ContainsCoreId id := by
  rw [LocalBindingFrame.ContainsCoreId,
    verifiedParserStateLoopPreservedBindings_core_ids]
  simp [StateLoopPreservedLocal]

theorem stateLoopPreservedLocalFootprint_eq (runtime : State) :
    localCellFootprint runtime StateLoopPreservedLocal =
      localBindingFrameFootprint runtime
        verifiedParserStateLoopPreservedBindings := by
  unfold localBindingFrameFootprint
  congr 1
  funext id
  exact propext (StateLoopPreservedLocal_source_frame id)

theorem StateLoopPreservedLocal_iff (id : VarId) :
    StateLoopPreservedLocal id ↔
      StateLoopPersistentLocal id ∧ id ≠ 18 := by
  unfold StateLoopPreservedLocal StateLoopPersistentLocal
  constructor
  · intro preserved
    rcases preserved with parameter | frame
    · refine ⟨Or.inl parameter, ?_⟩
      have bound :=
        (mem_verifiedParserRecognizerParameterIds_iff id).mp parameter
      exact Nat.ne_of_lt (Nat.lt_of_le_of_lt bound (by decide))
    · refine ⟨Or.inr ?_, ?_⟩
      · rw [mem_verifiedParserStateLoopPreservedFrameIds_iff] at frame
        rw [mem_verifiedParserStateLoopSharedFrameIds_iff]
        rcases frame with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
            rfl | rfl | rfl <;> simp
      · rw [mem_verifiedParserStateLoopPreservedFrameIds_iff] at frame
        rcases frame with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
            rfl | rfl | rfl <;> decide
  · rintro ⟨persistent, notCount⟩
    rcases persistent with parameter | frame
    · exact Or.inl parameter
    · right
      rw [mem_verifiedParserStateLoopSharedFrameIds_iff] at frame
      rw [mem_verifiedParserStateLoopPreservedFrameIds_iff]
      rcases frame with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
          rfl | rfl | rfl | rfl <;> simp_all

theorem StateLoopPreservedLocal.to_position_loop
    {id : VarId} (preserved : StateLoopPreservedLocal id)
    (notPosition : id ≠ 23) :
    PositionLoopPreservedLocal id := by
  rcases preserved with parameter | framed
  · exact Or.inl parameter
  · right
    rw [mem_verifiedParserStateLoopPreservedFrameIds_iff] at framed
    rw [mem_verifiedParserPositionLoopPreservedFrameIds_iff]
    rcases framed with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
        rfl | rfl | rfl <;> simp_all

def stateLoopMutableCells
    (workspaceCell stateCountCell cursorCell : CellId) : CellSet :=
  CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton cursorCell))

def StateLoopFrameSeparated (runtime : State)
    (workspaceCell stateCountCell cursorCell : CellId) : Prop :=
  CellSet.Disjoint
    (localBindingFrameFootprint runtime
      verifiedParserStateLoopPreservedBindings)
    (stateLoopMutableCells workspaceCell stateCountCell cursorCell)

theorem StateLoopPersistentLocal.le23
    (id : Nat) (persistent : StateLoopPersistentLocal id) : id ≤ 23 := by
  unfold StateLoopPersistentLocal at persistent
  rcases persistent with parameter | shared
  · exact Nat.le_trans
      ((mem_verifiedParserRecognizerParameterIds_iff id).mp parameter)
      (by decide)
  · rw [mem_verifiedParserStateLoopSharedFrameIds_iff] at shared
    rcases shared with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
        rfl | rfl | rfl | rfl <;> decide

/-- The chart-head expression used by the enclosing recognizer loops.  The
    workspace remains in parameter local 4; callers select the local that
    carries the chart position. -/
def parserRecognizeChartHeadExpr (positionLocal : VarId) : Expr :=
  .index (.local 4)
    (.call extractedParserChartWordFunction.id
      [.local positionLocal, .constant 25])

theorem extractedParserRecognize_root_head_expr_shape :
    parserRecognizeRootHeadExpr = parserRecognizeChartHeadExpr 6 := by
  rfl

theorem extractedParserRecognize_position_loop_shape :
    parserRecognizePositionLoop =
      .whileLoop
        (.binary .lessEqual (.local 23) (.local 6))
        parserRecognizePositionLoopBody := by
  rfl

theorem extractedParserRecognize_position_body_shape :
    parserRecognizePositionLoopBody =
      .sequence parserRecognizePositionActivity
        (.letLocal 24 parserI32Type (parserRecognizeChartHeadExpr 23)
          (.sequence parserRecognizeStateLoop
            parserRecognizePositionAdvance)) := by
  rfl

theorem extractedParserRecognize_position_activity_shape :
    parserRecognizePositionActivity =
      .ifThenElse
        (.binary .greaterEqual (parserRecognizeChartHeadExpr 23)
          (.value (.signed .i32 0)))
        (.sequence
          (.expression (.assign .set (.local 22) (.local 23))) .skip)
        .skip := by
  rfl

theorem extractedParserRecognize_position_state_scope_shape :
    parserRecognizePositionStateScope =
      .letLocal 24 parserI32Type (parserRecognizeChartHeadExpr 23)
        (.sequence parserRecognizeStateLoop
          parserRecognizePositionAdvance) := by
  rfl

theorem extractedParserRecognize_position_advance_shape :
    parserRecognizePositionAdvance =
      .sequence
        (.expression (.assign .add (.local 23)
          (.value (.signed .i32 1)))) .skip := by
  rfl

theorem extractedParserRecognize_state_loop_shape :
    parserRecognizeStateLoop =
      .whileLoop
        (.binary .greaterEqual (.local 24)
          (.value (.signed .i32 0)))
        parserRecognizeStateLoopBody := by
  rfl

/-! ## Artifact-derived FunctionalView for the state-chain loop

The layout contains exactly the live source declarations reported by the
checked state-loop access frame. Candidate fields and all branch-local values
remain lexical bindings inside the reified command.
-/

private def stateLoopLayout : Layout 13 := fun index =>
  [0, 2, 3, 4, 8, 9, 11, 13, 14, 15, 18, 23, 24].get index

private def stateLoopContext : Context :=
  let c0 := Context.empty.bind 0 (.slice parserI32Type)
  let c1 := c0.bind 2 (.slice parserI32Type)
  let c2 := c1.bind 3 parserI32Type
  let c3 := c2.bind 4 (.slice parserI32Type)
  let c4 := c3.bind 8 parserI32Type
  let c5 := c4.bind 9 parserI32Type
  let c6 := c5.bind 11 parserI32Type
  let c7 := c6.bind 13 parserI32Type
  let c8 := c7.bind 14 parserI32Type
  let c9 := c8.bind 15 parserI32Type
  let c10 := c9.bind 18 parserI32Type
  let c11 := c10.bind 23 parserI32Type
  c11.bind 24 parserI32Type

private def stateLoopReification? :=
  reifyCommand? verifiedParserCore (.structure 0) stateLoopContext true
    stateLoopLayout 25 parserRecognizeStateLoop

private theorem stateLoopReification_exists :
    stateLoopReification?.isSome := by
  native_decide

/-- Complete state-chain command recovered from the checked recognizer. -/
def parserRecognizeStateLoopView :=
  stateLoopReification?.get stateLoopReification_exists

theorem parserRecognizeStateLoopView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      stateLoopLayout 25 parserRecognizeStateLoopView.command =
      parserRecognizeStateLoop :=
  parserRecognizeStateLoopView.toCoreExactly

private def stateBodyReification? :=
  reifyCommand? verifiedParserCore (.structure 0) stateLoopContext true
    stateLoopLayout 25 parserRecognizeStateLoopBody

private theorem stateBodyReification_exists :
    stateBodyReification?.isSome := by
  native_decide

private def parserRecognizeStateBodyView :=
  stateBodyReification?.get stateBodyReification_exists

private theorem parserRecognizeStateBodyView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      stateLoopLayout 25 parserRecognizeStateBodyView.command =
      parserRecognizeStateLoopBody :=
  parserRecognizeStateBodyView.toCoreExactly

/-! ## Artifact-derived FunctionalView for the chart-position loop

The position view retains exactly the source locals reported live by the
checked access analysis.  In particular, its state-chain traversal is the
same nested `parserRecognizeStateLoop` command proved below; no second
handwritten position program is introduced.
-/

def positionLoopLayout : Layout 15 := fun index =>
  [0, 2, 3, 4, 6, 8, 9, 11, 12, 13, 14, 15, 18, 22, 23].get index

private def positionLoopContext : Context :=
  let c0 := Context.empty.bind 0 (.slice parserI32Type)
  let c1 := c0.bind 2 (.slice parserI32Type)
  let c2 := c1.bind 3 parserI32Type
  let c3 := c2.bind 4 (.slice parserI32Type)
  let c4 := c3.bind 6 parserI32Type
  let c5 := c4.bind 8 parserI32Type
  let c6 := c5.bind 9 parserI32Type
  let c7 := c6.bind 11 parserI32Type
  let c8 := c7.bind 12 parserI32Type
  let c9 := c8.bind 13 parserI32Type
  let c10 := c9.bind 14 parserI32Type
  let c11 := c10.bind 15 parserI32Type
  let c12 := c11.bind 18 parserI32Type
  let c13 := c12.bind 22 parserI32Type
  c13.bind 23 parserI32Type

private def positionLoopReification? :=
  reifyCommand? verifiedParserCore (.structure 0) positionLoopContext true
    positionLoopLayout 24 parserRecognizePositionLoop

private theorem positionLoopReification_exists :
    positionLoopReification?.isSome := by
  native_decide

/-- Complete chart-position command recovered from the checked recognizer. -/
def parserRecognizePositionLoopView :=
  positionLoopReification?.get positionLoopReification_exists

theorem parserRecognizePositionLoopView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      positionLoopLayout 24 parserRecognizePositionLoopView.command =
      parserRecognizePositionLoop :=
  parserRecognizePositionLoopView.toCoreExactly

private def positionBodyReification? :=
  reifyCommand? verifiedParserCore (.structure 0) positionLoopContext true
    positionLoopLayout 24 parserRecognizePositionLoopBody

private theorem positionBodyReification_exists :
    positionBodyReification?.isSome := by
  native_decide

private def parserRecognizePositionBodyView :=
  positionBodyReification?.get positionBodyReification_exists

private theorem parserRecognizePositionBodyView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      positionLoopLayout 24 parserRecognizePositionBodyView.command =
      parserRecognizePositionLoopBody :=
  parserRecognizePositionBodyView.toCoreExactly

/-! The position statement owns the two lexical counters surrounding the
    position loop.  Its compact boundary is the thirteen persistent locals
    that remain live after those counters close.  Reifying the whole statement
    makes the scope structure part of the checked artifact instead of leaving
    it implicit in the physical-state driver. -/

def positionStatementLayout : Layout 13 := fun index =>
  [0, 2, 3, 4, 6, 8, 9, 11, 12, 13, 14, 15, 18].get index

private def positionStatementContext : Context :=
  let c0 := Context.empty.bind 0 (.slice parserI32Type)
  let c1 := c0.bind 2 (.slice parserI32Type)
  let c2 := c1.bind 3 parserI32Type
  let c3 := c2.bind 4 (.slice parserI32Type)
  let c4 := c3.bind 6 parserI32Type
  let c5 := c4.bind 8 parserI32Type
  let c6 := c5.bind 9 parserI32Type
  let c7 := c6.bind 11 parserI32Type
  let c8 := c7.bind 12 parserI32Type
  let c9 := c8.bind 13 parserI32Type
  let c10 := c9.bind 14 parserI32Type
  let c11 := c10.bind 15 parserI32Type
  c11.bind 18 parserI32Type

private def positionStatementReification? :=
  reifyCommand? verifiedParserCore (.structure 0) positionStatementContext false
    positionStatementLayout 22 parserRecognizePositionStatement

private theorem positionStatementReification_exists :
    positionStatementReification?.isSome := by
  native_decide

/-- Complete position/root continuation recovered from the checked recognizer
    body before either scoped counter has been introduced. -/
def parserRecognizePositionStatementView :=
  positionStatementReification?.get positionStatementReification_exists

theorem parserRecognizePositionStatementView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      positionStatementLayout 22 parserRecognizePositionStatementView.command =
      parserRecognizePositionStatement :=
  parserRecognizePositionStatementView.toCoreExactly

def positionLoopCondition :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 15 :=
  .apply (.binary .lessEqual parserI32Type parserI32Type (.scalar .bool)) [
    .reference (.slot ⟨14, by omega⟩),
    .reference (.slot ⟨4, by omega⟩)]

/-- The body remains the command recovered from the checked Core artifact. -/
def positionBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 15 :=
  parserRecognizePositionBodyView.command

def positionLoopCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 15 :=
  .whileLoop positionLoopCondition positionBodyCommand

theorem positionLoopCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      positionLoopLayout 24 positionLoopCommand =
      parserRecognizePositionLoop := by
  rw [positionLoopCommand, Lanius.FunctionalView.Core.Stateful.toCoreStmt,
    positionLoopCondition, positionBodyCommand,
    parserRecognizePositionBodyView_toCore_exactly]
  exact extractedParserRecognize_position_loop_shape.symm

def stateSlot {arity : Nat} (index : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .reference (.slot index)

def stateLiteral {arity : Nat} (value : Int) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .reference (.literal (.signed .i32 value))

def stateLoopCondition :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 13 :=
  .apply (.binary .greaterEqual parserI32Type parserI32Type (.scalar .bool))
    [stateSlot ⟨12, by omega⟩, stateLiteral 0]

/-- The body is used directly from the checked reification. It is deliberately
    not copied into a second handwritten FunctionalView tree. -/
def stateBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 13 :=
  parserRecognizeStateBodyView.command

/-- Layout after the state body has decoded production, dot, origin, and RHS
    length. -/
private def stateAfterBindingsLayout : Layout 17 :=
  Layout.push
    (Layout.push
      (Layout.push
        (Layout.push stateLoopLayout 25) 26) 27) 28

/-- The remaining branch is projected from the one mechanically reified body.
    It is not independently reified or handwritten, so semantic proofs cannot
    accidentally select a different command than the enclosing body contains. -/
def stateAfterBindingsCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 17 :=
  match stateBodyCommand with
  | .letValue _ _ afterProduction =>
      match afterProduction with
      | .letValue _ _ afterDot =>
          match afterDot with
          | .letValue _ _ afterOrigin =>
              match afterOrigin with
              | .letValue _ _ afterBindings => afterBindings
              | _ => .skip
          | _ => .skip
      | _ => .skip
  | _ => .skip

def stateLessTerm {arity : Nat} (left right : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.binary .less parserI32Type parserI32Type (.scalar .bool))
    [.reference (.slot left), .reference (.slot right)]

/-- The two semantic branches and cursor advance are projections of the one
    artifact-derived command, never independently reified copies. -/
def stateIncompleteCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 17 :=
  match stateAfterBindingsCommand with
  | .sequence (.ifThenElse _ incomplete _) _ => incomplete
  | _ => .skip

def stateCompleteCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 17 :=
  match stateAfterBindingsCommand with
  | .sequence (.ifThenElse _ _ complete) _ => complete
  | _ => .skip

def stateAdvanceCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 17 :=
  match stateAfterBindingsCommand with
  | .sequence (.ifThenElse _ _ _) advance => advance
  | _ => .skip

private def stateLessTermMatches {arity : Nat}
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (left right : Fin arity) : Bool :=
  match term with
  | .apply (.binary .less leftType rightType resultType)
      [.reference (.slot left'), .reference (.slot right')] =>
      leftType == parserI32Type && rightType == parserI32Type &&
      resultType == .scalar .bool && left' == left && right' == right
  | _ => false

private theorem stateLessTermMatches_sound {arity : Nat}
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (left right : Fin arity)
    (matched : stateLessTermMatches term left right = true) :
    term = stateLessTerm left right := by
  simp only [stateLessTermMatches] at matched
  split at matched <;> simp_all [stateLessTerm]

private def stateAfterBindingsCommandMatches :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 17 → Bool
  | .sequence (.ifThenElse condition _ _) _ =>
      stateLessTermMatches condition ⟨14, by omega⟩ ⟨16, by omega⟩
  | _ => false

private theorem stateAfterBindingsCommand_matches :
    stateAfterBindingsCommandMatches stateAfterBindingsCommand = true := by
  native_decide

/-- Exact branch decomposition recovered from the executable constructor
    check, while retaining each branch by projection from the source command. -/
theorem stateAfterBindingsCommand_shape :
    stateAfterBindingsCommand =
      .sequence
        (.ifThenElse (stateLessTerm ⟨14, by omega⟩ ⟨16, by omega⟩)
          stateIncompleteCommand stateCompleteCommand)
        stateAdvanceCommand := by
  have matched := stateAfterBindingsCommand_matches
  generalize commandEq : stateAfterBindingsCommand = command at matched ⊢
  cases command <;> simp [stateAfterBindingsCommandMatches] at matched
  case sequence first advance =>
    cases first <;> simp [stateAfterBindingsCommandMatches] at matched
    case ifThenElse condition incomplete complete =>
      have conditionEq := stateLessTermMatches_sound condition
        ⟨14, by omega⟩ ⟨16, by omega⟩ matched
      simp_all [stateIncompleteCommand, stateCompleteCommand,
        stateAdvanceCommand]

def stateValueTerm {arity : Nat} (workspace base state : Fin arity)
    (field : ConstantId) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.call extractedParserStateValueFunction.id
      [.slice parserI32Type, parserI32Type, parserI32Type, parserI32Type]
      parserI32Type)
    [.reference (.slot workspace), .reference (.slot base),
      .reference (.slot state),
      .apply (.constant field parserI32Type) []]

def stateRhsLengthTerm {arity : Nat} (grammar production : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.call extractedParserRhsLengthFunction.id
      [.slice parserI32Type, parserI32Type] parserI32Type)
    [.reference (.slot grammar), .reference (.slot production)]

private def stateRhsSymbolTerm {arity : Nat}
    (grammar production dot : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.call extractedParserRhsSymbolFunction.id
      [.slice parserI32Type, parserI32Type, parserI32Type] parserI32Type)
    [.reference (.slot grammar), .reference (.slot production),
      .reference (.slot dot)]

private def stateScanTerminalTerm {arity : Nat}
    (grammar tokens tokenCount position symbol : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.call extractedParserScanTerminalFunction.id
      [.slice parserI32Type, .slice parserI32Type, parserI32Type,
        parserI32Type, parserI32Type] parserI32Type)
    [.reference (.slot grammar), .reference (.slot tokens),
      .reference (.slot tokenCount), .reference (.slot position),
      .reference (.slot symbol)]

def stateGreaterEqualZeroTerm {arity : Nat} (value : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.binary .greaterEqual parserI32Type parserI32Type (.scalar .bool))
    [.reference (.slot value), .reference (.literal (.signed .i32 0))]

def stateSubtractTerm {arity : Nat} (left right : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.binary .subtract parserI32Type parserI32Type parserI32Type)
    [.reference (.slot left), .reference (.slot right)]

/-- Read `slice[base + index]` in the exact form emitted by the extracted
    recognizer for the compact nonterminal lookup tables. -/
def stateIndexAddTerm {arity : Nat}
    (slice base index : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.index (.slice parserI32Type) parserI32Type parserI32Type) [
    .reference (.slot slice),
    .apply (.binary .add parserI32Type parserI32Type parserI32Type)
      [.reference (.slot base), .reference (.slot index)]]

def stateChartHeadTerm {arity : Nat}
    (workspace position : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.index (.slice parserI32Type) parserI32Type parserI32Type) [
    .reference (.slot workspace),
    .apply (.call extractedParserChartWordFunction.id
      [parserI32Type, parserI32Type] parserI32Type) [
        .reference (.slot position),
        .apply (.constant 25 parserI32Type) []]]

def stateLhsTerm {arity : Nat} (grammar production : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.call extractedParserLhsFunction.id
      [.slice parserI32Type, parserI32Type] parserI32Type)
    [.reference (.slot grammar), .reference (.slot production)]

/-! The generated FunctionalView syntax does not expose a lawful equality
    instance because arbitrary runtime `Value`s may occur as literals.  Parser
    commands use only scalar literals, so this checked relation deliberately
    recognizes that closed subset.  Its soundness theorem lets executable
    source-shape checks yield ordinary Lean equalities without trusting an
    unchecked boolean comparison. -/

private def stateLiteralMatches : Value → Value → Bool
  | .unit, .unit => true
  | .boolean left, .boolean right => decide (left = right)
  | .signed leftType left, .signed rightType right =>
      decide (leftType = rightType ∧ left = right)
  | .unsigned leftType left, .unsigned rightType right =>
      decide (leftType = rightType ∧ left = right)
  | .f32Bits left, .f32Bits right => decide (left = right)
  | .f64Bits left, .f64Bits right => decide (left = right)
  | .character left, .character right => decide (left = right)
  | .string left, .string right => decide (left = right)
  | .pointer left, .pointer right => decide (left = right)
  | _, _ => false

private theorem stateLiteralMatches_sound (left right : Value)
    (matched : stateLiteralMatches left right = true) : left = right := by
  cases left <;> cases right <;>
    simp_all [stateLiteralMatches, of_decide_eq_true]

private def stateOperationMatches :
    Lanius.FunctionalView.Core.Operation →
    Lanius.FunctionalView.Core.Operation → Bool :=
  fun left right => decide (left = right)

private theorem stateOperationMatches_sound
    (left right : Lanius.FunctionalView.Core.Operation)
    (matched : stateOperationMatches left right = true) : left = right := by
  exact of_decide_eq_true matched

mutual
  private def stateTermMatches {arity : Nat} :
      Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity →
      Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity →
      Bool
    | .reference (.slot left), .reference (.slot right) =>
        decide (left = right)
    | .reference (.literal left), .reference (.literal right) =>
        stateLiteralMatches left right
    | .apply leftOperation leftArguments,
        .apply rightOperation rightArguments =>
        stateOperationMatches leftOperation rightOperation &&
          stateTermsMatch leftArguments rightArguments
    | .logicalAnd leftFirst leftSecond,
        .logicalAnd rightFirst rightSecond
    | .logicalOr leftFirst leftSecond,
        .logicalOr rightFirst rightSecond =>
        stateTermMatches leftFirst rightFirst &&
          stateTermMatches leftSecond rightSecond
    | _, _ => false

  private def stateTermsMatch {arity : Nat} :
      List (Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature arity) →
      List (Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature arity) → Bool
    | [], [] => true
    | left :: leftRest, right :: rightRest =>
        stateTermMatches left right && stateTermsMatch leftRest rightRest
    | _, _ => false
end

mutual
  private theorem stateTermMatches_sound {arity : Nat}
      (left right : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature arity)
      (matched : stateTermMatches left right = true) : left = right := by
    cases left with
    | reference leftReference =>
        cases right <;> try
          simp only [stateTermMatches, Bool.false_eq_true] at matched
        case reference rightReference =>
          cases leftReference with
          | slot leftIndex =>
              cases rightReference with
              | slot rightIndex =>
                  simp only [stateTermMatches, decide_eq_true_eq] at matched
                  rw [matched]
              | literal _ =>
                  simp only [stateTermMatches, Bool.false_eq_true] at matched
          | literal leftValue =>
              cases rightReference with
              | slot _ =>
                  simp only [stateTermMatches, Bool.false_eq_true] at matched
              | literal rightValue =>
                  rw [stateLiteralMatches_sound leftValue rightValue matched]
    | apply leftOperation leftArguments =>
        cases right <;>
          simp only [stateTermMatches, Bool.false_eq_true] at matched
        case apply rightOperation rightArguments =>
          simp only [Bool.and_eq_true] at matched
          rw [stateOperationMatches_sound leftOperation rightOperation matched.1,
            stateTermsMatch_sound leftArguments rightArguments matched.2]
    | logicalAnd leftFirst leftSecond =>
        cases right <;>
          simp only [stateTermMatches, Bool.false_eq_true] at matched
        case logicalAnd rightFirst rightSecond =>
          simp only [Bool.and_eq_true] at matched
          rw [stateTermMatches_sound leftFirst rightFirst matched.1,
            stateTermMatches_sound leftSecond rightSecond matched.2]
    | logicalOr leftFirst leftSecond =>
        cases right <;>
          simp only [stateTermMatches, Bool.false_eq_true] at matched
        case logicalOr rightFirst rightSecond =>
          simp only [Bool.and_eq_true] at matched
          rw [stateTermMatches_sound leftFirst rightFirst matched.1,
            stateTermMatches_sound leftSecond rightSecond matched.2]
  termination_by 2 * sizeOf left

  private theorem stateTermsMatch_sound {arity : Nat}
      (left right : List (Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature arity))
      (matched : stateTermsMatch left right = true) : left = right := by
    cases left with
    | nil =>
        cases right <;>
          simp only [stateTermsMatch, Bool.false_eq_true] at matched
        rfl
    | cons leftHead leftTail =>
        cases right <;>
          simp only [stateTermsMatch, Bool.false_eq_true] at matched
        case cons rightHead rightTail =>
          simp only [Bool.and_eq_true] at matched
          rw [stateTermMatches_sound leftHead rightHead matched.1,
            stateTermsMatch_sound leftTail rightTail matched.2]
  termination_by 2 * sizeOf left + 1
end

private def stateActionMatches {arity : Nat} :
    Lanius.FunctionalView.Core.Stateful.Action arity →
    Lanius.FunctionalView.Core.Stateful.Action arity → Bool
  | .setI32Index leftBase leftIndex leftValue,
      .setI32Index rightBase rightIndex rightValue =>
      decide (leftBase = rightBase) &&
        stateTermMatches leftIndex rightIndex &&
        stateTermMatches leftValue rightValue

private theorem stateActionMatches_sound {arity : Nat}
    (left right : Lanius.FunctionalView.Core.Stateful.Action arity)
    (matched : stateActionMatches left right = true) : left = right := by
  cases left with
  | setI32Index leftBase leftIndex leftValue =>
      cases right with
      | setI32Index rightBase rightIndex rightValue =>
          simp only [stateActionMatches, Bool.and_eq_true] at matched
          have baseEq := of_decide_eq_true matched.1.1
          have indexEq := stateTermMatches_sound leftIndex rightIndex
            matched.1.2
          have valueEq := stateTermMatches_sound leftValue rightValue
            matched.2
          simp_all

private def stateCommandMatches {arity : Nat} :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions arity →
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions arity → Bool
  | .skip, .skip | .breakLoop, .breakLoop |
      .continueLoop, .continueLoop => true
  | .sequence leftFirst leftSecond, .sequence rightFirst rightSecond =>
      stateCommandMatches leftFirst rightFirst &&
        stateCommandMatches leftSecond rightSecond
  | .letValue leftType leftInitializer leftBody,
      .letValue rightType rightInitializer rightBody =>
      decide (leftType = rightType) &&
        stateTermMatches leftInitializer rightInitializer &&
        stateCommandMatches leftBody rightBody
  | .setLocal leftTarget leftValue, .setLocal rightTarget rightValue =>
      decide (leftTarget = rightTarget) &&
        stateTermMatches leftValue rightValue
  | .updateLocal leftOperation leftTarget leftValue,
      .updateLocal rightOperation rightTarget rightValue =>
      decide (leftOperation = rightOperation ∧ leftTarget = rightTarget) &&
        stateTermMatches leftValue rightValue
  | .action left, .action right => stateActionMatches left right
  | .ifThenElse leftCondition leftThen leftElse,
      .ifThenElse rightCondition rightThen rightElse =>
      stateTermMatches leftCondition rightCondition &&
        stateCommandMatches leftThen rightThen &&
        stateCommandMatches leftElse rightElse
  | .whileLoop leftCondition leftBody,
      .whileLoop rightCondition rightBody =>
      stateTermMatches leftCondition rightCondition &&
        stateCommandMatches leftBody rightBody
  | .returnValue none, .returnValue none => true
  | .returnValue (some left), .returnValue (some right) =>
      stateTermMatches left right
  | _, _ => false

theorem stateCommandMatches_sound {arity : Nat}
    (left right : Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions arity)
    (matched : stateCommandMatches left right = true) : left = right := by
  cases left with
  | skip =>
      cases right <;>
        simp only [stateCommandMatches, Bool.false_eq_true] at matched
      rfl
  | sequence leftFirst leftSecond =>
      cases right <;>
        simp only [stateCommandMatches, Bool.false_eq_true] at matched
      case sequence rightFirst rightSecond =>
        simp only [Bool.and_eq_true] at matched
        rw [stateCommandMatches_sound leftFirst rightFirst matched.1,
          stateCommandMatches_sound leftSecond rightSecond matched.2]
  | letValue leftType leftInitializer leftBody =>
      cases right <;>
        simp only [stateCommandMatches, Bool.false_eq_true] at matched
      case letValue rightType rightInitializer rightBody =>
        simp only [Bool.and_eq_true, decide_eq_true_eq] at matched
        rw [matched.1.1,
          stateTermMatches_sound leftInitializer rightInitializer matched.1.2,
          stateCommandMatches_sound leftBody rightBody matched.2]
  | setLocal leftTarget leftValue =>
      cases right <;>
        simp only [stateCommandMatches, Bool.false_eq_true] at matched
      case setLocal rightTarget rightValue =>
        simp only [Bool.and_eq_true, decide_eq_true_eq] at matched
        rw [matched.1,
          stateTermMatches_sound leftValue rightValue matched.2]
  | updateLocal leftOperation leftTarget leftValue =>
      cases right <;>
        simp only [stateCommandMatches, Bool.false_eq_true] at matched
      case updateLocal rightOperation rightTarget rightValue =>
        simp only [Bool.and_eq_true, decide_eq_true_eq] at matched
        rw [matched.1.1, matched.1.2,
          stateTermMatches_sound leftValue rightValue matched.2]
  | action leftAction =>
      cases right <;>
        simp only [stateCommandMatches, Bool.false_eq_true] at matched
      case action rightAction =>
        rw [stateActionMatches_sound leftAction rightAction matched]
  | ifThenElse leftCondition leftThen leftElse =>
      cases right <;>
        simp only [stateCommandMatches, Bool.false_eq_true] at matched
      case ifThenElse rightCondition rightThen rightElse =>
        simp only [Bool.and_eq_true] at matched
        rw [stateTermMatches_sound leftCondition rightCondition matched.1.1,
          stateCommandMatches_sound leftThen rightThen matched.1.2,
          stateCommandMatches_sound leftElse rightElse matched.2]
  | whileLoop leftCondition leftBody =>
      cases right <;>
        simp only [stateCommandMatches, Bool.false_eq_true] at matched
      case whileLoop rightCondition rightBody =>
        simp only [Bool.and_eq_true] at matched
        rw [stateTermMatches_sound leftCondition rightCondition matched.1,
          stateCommandMatches_sound leftBody rightBody matched.2]
  | returnValue leftValue =>
      cases right <;> try
        simp only [stateCommandMatches, Bool.false_eq_true] at matched
      case returnValue rightValue =>
        cases leftValue <;> cases rightValue <;> try
          simp only [stateCommandMatches, Bool.false_eq_true] at matched
        · rfl
        · rename_i leftTerm rightTerm
          rw [stateTermMatches_sound leftTerm rightTerm matched]
  | breakLoop =>
      cases right <;>
        simp only [stateCommandMatches, Bool.false_eq_true] at matched
      rfl
  | continueLoop =>
      cases right <;>
        simp only [stateCommandMatches, Bool.false_eq_true] at matched
      rfl
termination_by sizeOf left

/-- Executable equality check for the scalar-literal subset of FunctionalView
    commands generated by the parser extractor. -/
def parserFunctionalCommandMatches {arity : Nat} :=
  @stateCommandMatches arity

theorem parserFunctionalCommandMatches_sound {arity : Nat}
    (left right : Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions arity)
    (matched : parserFunctionalCommandMatches left right = true) :
    left = right :=
  stateCommandMatches_sound left right matched

/-- Branches retained by projection from the incomplete-state command. -/
def stateTerminalCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 18 :=
  match stateIncompleteCommand with
  | .letValue _ _ (.sequence (.ifThenElse _ terminal _) .skip) => terminal
  | _ => .skip

def stateNonterminalCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 18 :=
  match stateIncompleteCommand with
  | .letValue _ _ (.sequence (.ifThenElse _ _ nonterminal) .skip) =>
      nonterminal
  | _ => .skip

private def stateTerminalSuccessCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 19 :=
  match stateTerminalCommand with
  | .letValue _ _ (.sequence (.ifThenElse _ success _) _) => success
  | _ => .skip

private def stateTerminalFullCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 20 :=
  match stateTerminalSuccessCommand with
  | .letValue _ _ (.sequence (.ifThenElse _ full _) _) => full
  | _ => .skip

/-- The terminal transition seed as it occurs inside the source-derived
    `append_state` call.  Its slots are those of the state body after binding
    the RHS symbol and successful scanner position. -/
private def stateTerminalSeedTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 19 :=
  .apply (.call extractedParserStateSeedFunction.id
      (List.replicate 7 parserI32Type) (.structure 1)) [
    stateSlot ⟨13, by omega⟩,
    .apply (.binary .add parserI32Type parserI32Type parserI32Type)
      [stateSlot ⟨14, by omega⟩, stateLiteral 1],
    stateSlot ⟨15, by omega⟩,
    stateSlot ⟨12, by omega⟩,
    .apply (.constant 38 parserI32Type) [],
    .apply (.binary .divide parserI32Type parserI32Type parserI32Type)
      [stateSlot ⟨11, by omega⟩, stateLiteral 2],
    stateSlot ⟨17, by omega⟩]

private def stateTerminalAppendArguments : List
    (Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 19) := [
  stateSlot ⟨3, by omega⟩,
  stateSlot ⟨4, by omega⟩,
  stateSlot ⟨5, by omega⟩,
  stateSlot ⟨18, by omega⟩,
  stateTerminalSeedTerm,
  stateSlot ⟨10, by omega⟩]

private def stateTerminalAppendLayout : Layout 19 :=
  Layout.push (Layout.push stateAfterBindingsLayout 29) 30

private theorem stateTerminalAppendArguments_toCore :
    Lanius.FunctionalView.Core.toCoreExprs stateTerminalAppendLayout
      stateTerminalAppendArguments =
      parserRecognizeTerminalAppendArguments := by
  rfl

private def stateTerminalAppendTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 19 :=
  .apply (.call extractedParserAppendStateFunction.id [
      .slice parserI32Type, parserI32Type, parserI32Type, parserI32Type,
      .structure 1, parserI32Type] (.structure 2))
    stateTerminalAppendArguments

private def stateTerminalFullCondition :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 20 :=
  .apply (.binary .equal parserI32Type parserI32Type (.scalar .bool)) [
    .apply (.field (.structure 2) 0 parserI32Type)
      [stateSlot ⟨19, by omega⟩],
    .apply (.constant 41 parserI32Type) []]

private def stateTerminalFullResult :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 20 :=
  .apply (.call extractedParserAppendOrFullFunction.id
      [.structure 2, parserI32Type] (.structure 0)) [
    stateSlot ⟨19, by omega⟩,
    stateSlot ⟨11, by omega⟩]

private def stateTerminalStateCountTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 20 :=
  .apply (.field (.structure 2) 2 parserI32Type)
    [stateSlot ⟨19, by omega⟩]

private def stateTerminalSeedTermMatches :
    Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 19 → Bool
  | .apply (.call function argumentTypes resultType) [
      .reference (.slot production),
      .apply (.binary .add addLeft addRight addResult) [
        .reference (.slot dot),
        .reference (.literal (.signed .i32 one))],
      .reference (.slot origin),
      .reference (.slot current),
      .apply (.constant childTag childTagType) [],
      .apply (.binary .divide divideLeft divideRight divideResult) [
        .reference (.slot position),
        .reference (.literal (.signed .i32 two))],
      .reference (.slot symbol)] =>
      function == extractedParserStateSeedFunction.id &&
      argumentTypes == List.replicate 7 parserI32Type &&
      resultType == .structure 1 && production == ⟨13, by omega⟩ &&
      addLeft == parserI32Type && addRight == parserI32Type &&
      addResult == parserI32Type && dot == ⟨14, by omega⟩ && one == 1 &&
      origin == ⟨15, by omega⟩ && current == ⟨12, by omega⟩ &&
      childTag == 38 && childTagType == parserI32Type &&
      divideLeft == parserI32Type && divideRight == parserI32Type &&
      divideResult == parserI32Type && position == ⟨11, by omega⟩ &&
      two == 2 && symbol == ⟨17, by omega⟩
  | _ => false

private theorem stateTerminalSeedTermMatches_sound
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 19)
    (matched : stateTerminalSeedTermMatches term = true) :
    term = stateTerminalSeedTerm := by
  simp only [stateTerminalSeedTermMatches] at matched
  split at matched <;>
    simp_all [stateTerminalSeedTerm, stateSlot, stateLiteral]

private def stateTerminalAppendTermMatches :
    Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 19 → Bool
  | .apply (.call function argumentTypes resultType) [
      .reference (.slot workspace),
      .reference (.slot stateBase),
      .reference (.slot capacity),
      .reference (.slot nextPosition),
      seed,
      .reference (.slot stateCount)] =>
      function == extractedParserAppendStateFunction.id &&
      argumentTypes == [.slice parserI32Type, parserI32Type, parserI32Type,
        parserI32Type, .structure 1, parserI32Type] &&
      resultType == .structure 2 && workspace == ⟨3, by omega⟩ &&
      stateBase == ⟨4, by omega⟩ && capacity == ⟨5, by omega⟩ &&
      nextPosition == ⟨18, by omega⟩ &&
      stateTerminalSeedTermMatches seed && stateCount == ⟨10, by omega⟩
  | _ => false

private theorem stateTerminalAppendTermMatches_sound
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 19)
    (matched : stateTerminalAppendTermMatches term = true) :
    term = stateTerminalAppendTerm := by
  simp only [stateTerminalAppendTermMatches] at matched
  split at matched <;> try contradiction
  rename_i function argumentTypes resultType workspace stateBase capacity
    nextPosition seed stateCount
  simp only [Bool.and_eq_true] at matched
  have seedEq := stateTerminalSeedTermMatches_sound seed matched.1.2
  simp_all [stateTerminalAppendTerm, stateTerminalAppendArguments, stateSlot]

private def stateTerminalFullConditionMatches :
    Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 20 → Bool
  | .apply (.binary .equal leftType rightType resultType) [
      .apply (.field structureType field fieldType)
        [.reference (.slot outcome)],
      .apply (.constant fullConstant constantType) []] =>
      leftType == parserI32Type && rightType == parserI32Type &&
      resultType == .scalar .bool && structureType == .structure 2 &&
      field == 0 && fieldType == parserI32Type &&
      outcome == ⟨19, by omega⟩ && fullConstant == 41 &&
      constantType == parserI32Type
  | _ => false

private theorem stateTerminalFullConditionMatches_sound
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 20)
    (matched : stateTerminalFullConditionMatches term = true) :
    term = stateTerminalFullCondition := by
  simp only [stateTerminalFullConditionMatches] at matched
  split at matched <;>
    simp_all [stateTerminalFullCondition, stateSlot]

private def stateTerminalFullResultMatches :
    Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 20 → Bool
  | .apply (.call function argumentTypes resultType) [
      .reference (.slot outcome), .reference (.slot position)] =>
      function == extractedParserAppendOrFullFunction.id &&
      argumentTypes == [.structure 2, parserI32Type] &&
      resultType == .structure 0 && outcome == ⟨19, by omega⟩ &&
      position == ⟨11, by omega⟩
  | _ => false

private theorem stateTerminalFullResultMatches_sound
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 20)
    (matched : stateTerminalFullResultMatches term = true) :
    term = stateTerminalFullResult := by
  simp only [stateTerminalFullResultMatches] at matched
  split at matched <;> simp_all [stateTerminalFullResult, stateSlot]

private def stateTerminalStateCountTermMatches :
    Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 20 → Bool
  | .apply (.field structureType field fieldType)
      [.reference (.slot outcome)] =>
      structureType == .structure 2 && field == 2 &&
      fieldType == parserI32Type && outcome == ⟨19, by omega⟩
  | _ => false

private theorem stateTerminalStateCountTermMatches_sound
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 20)
    (matched : stateTerminalStateCountTermMatches term = true) :
    term = stateTerminalStateCountTerm := by
  simp only [stateTerminalStateCountTermMatches] at matched
  split at matched <;>
    simp_all [stateTerminalStateCountTerm, stateSlot]

/-- Executable recognition of the exact state-value term shape.  This avoids
    requiring equality on all Core values merely to inspect a mechanically
    reified command. -/
private def stateValueTermMatches {arity : Nat}
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (workspace base state : Fin arity) (field : ConstantId) : Bool :=
  match term with
  | .apply (.call function arguments result)
      [.reference (.slot workspace'), .reference (.slot base'),
        .reference (.slot state'),
        .apply (.constant field' fieldType) []] =>
      function == extractedParserStateValueFunction.id &&
      arguments ==
        [.slice parserI32Type, parserI32Type, parserI32Type, parserI32Type] &&
      result == parserI32Type && workspace' == workspace && base' == base &&
      state' == state && field' == field && fieldType == parserI32Type
  | _ => false

private def stateRhsLengthTermMatches {arity : Nat}
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (grammar production : Fin arity) : Bool :=
  match term with
  | .apply (.call function arguments result)
      [.reference (.slot grammar'), .reference (.slot production')] =>
      function == extractedParserRhsLengthFunction.id &&
      arguments == [.slice parserI32Type, parserI32Type] &&
      result == parserI32Type && grammar' == grammar &&
      production' == production
  | _ => false

private def stateRhsSymbolTermMatches {arity : Nat}
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (grammar production dot : Fin arity) : Bool :=
  match term with
  | .apply (.call function arguments result)
      [.reference (.slot grammar'), .reference (.slot production'),
        .reference (.slot dot')] =>
      function == extractedParserRhsSymbolFunction.id &&
      arguments == [.slice parserI32Type, parserI32Type, parserI32Type] &&
      result == parserI32Type && grammar' == grammar &&
      production' == production && dot' == dot
  | _ => false

private def stateScanTerminalTermMatches {arity : Nat}
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (grammar tokens tokenCount position symbol : Fin arity) : Bool :=
  match term with
  | .apply (.call function arguments result)
      [.reference (.slot grammar'), .reference (.slot tokens'),
        .reference (.slot tokenCount'), .reference (.slot position'),
        .reference (.slot symbol')] =>
      function == extractedParserScanTerminalFunction.id &&
      arguments == [.slice parserI32Type, .slice parserI32Type, parserI32Type,
        parserI32Type, parserI32Type] && result == parserI32Type &&
      grammar' == grammar && tokens' == tokens && tokenCount' == tokenCount &&
      position' == position && symbol' == symbol
  | _ => false

private def stateGreaterEqualZeroTermMatches {arity : Nat}
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (value : Fin arity) : Bool :=
  match term with
  | .apply (.binary .greaterEqual leftType rightType resultType)
      [.reference (.slot value'),
        .reference (.literal (.signed .i32 zero))] =>
      leftType == parserI32Type && rightType == parserI32Type &&
      resultType == .scalar .bool && value' == value && zero == 0
  | _ => false

private theorem stateValueTermMatches_sound {arity : Nat}
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (workspace base state : Fin arity) (field : ConstantId)
    (matched : stateValueTermMatches term workspace base state field = true) :
    term = stateValueTerm workspace base state field := by
  simp only [stateValueTermMatches] at matched
  split at matched <;> simp_all [stateValueTerm]

private theorem stateRhsLengthTermMatches_sound {arity : Nat}
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (grammar production : Fin arity)
    (matched : stateRhsLengthTermMatches term grammar production = true) :
    term = stateRhsLengthTerm grammar production := by
  simp only [stateRhsLengthTermMatches] at matched
  split at matched <;> simp_all [stateRhsLengthTerm]

private theorem stateRhsSymbolTermMatches_sound {arity : Nat}
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (grammar production dot : Fin arity)
    (matched : stateRhsSymbolTermMatches term grammar production dot = true) :
    term = stateRhsSymbolTerm grammar production dot := by
  simp only [stateRhsSymbolTermMatches] at matched
  split at matched <;> simp_all [stateRhsSymbolTerm]

private theorem stateScanTerminalTermMatches_sound {arity : Nat}
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (grammar tokens tokenCount position symbol : Fin arity)
    (matched : stateScanTerminalTermMatches term grammar tokens tokenCount
      position symbol = true) :
    term = stateScanTerminalTerm grammar tokens tokenCount position symbol := by
  simp only [stateScanTerminalTermMatches] at matched
  split at matched <;> simp_all [stateScanTerminalTerm]

private theorem stateGreaterEqualZeroTermMatches_sound {arity : Nat}
    (term : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (value : Fin arity)
    (matched : stateGreaterEqualZeroTermMatches term value = true) :
    term = stateGreaterEqualZeroTerm value := by
  simp only [stateGreaterEqualZeroTermMatches] at matched
  split at matched <;> simp_all [stateGreaterEqualZeroTerm]

private def stateCommandIsSkip {arity : Nat} :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions arity → Bool
  | .skip => true
  | _ => false

private theorem stateCommandIsSkip_sound {arity : Nat}
    (command : Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions arity)
    (matched : stateCommandIsSkip command = true) : command = .skip := by
  cases command <;> simp_all [stateCommandIsSkip]

private def stateTerminalFullCommandMatches :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 20 → Bool
  | .sequence (.returnValue (some result)) trailing =>
      stateTerminalFullResultMatches result && stateCommandIsSkip trailing
  | _ => false

private theorem stateTerminalFullCommand_matches :
    stateTerminalFullCommandMatches stateTerminalFullCommand = true := by
  native_decide

private theorem stateTerminalFullCommand_shape :
    stateTerminalFullCommand =
      .sequence (.returnValue (some stateTerminalFullResult)) .skip := by
  have matched := stateTerminalFullCommand_matches
  generalize commandEq : stateTerminalFullCommand = command at matched ⊢
  cases command <;> try { simp [stateTerminalFullCommandMatches] at matched }
  case sequence first trailing =>
    cases first <;> try { simp [stateTerminalFullCommandMatches] at matched }
    case returnValue result =>
      cases result <;> try { simp [stateTerminalFullCommandMatches] at matched }
      case some result =>
        simp only [stateTerminalFullCommandMatches, Bool.and_eq_true]
          at matched
        have resultEq := stateTerminalFullResultMatches_sound result matched.1
        have trailingEq := stateCommandIsSkip_sound trailing matched.2
        simp_all

private def stateTerminalSuccessCommandMatches :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 19 → Bool
  | .letValue appendType appendTerm
      (.sequence (.ifThenElse fullCondition _ notFull)
        (.sequence (.setLocal target stateCountTerm) trailing)) =>
      appendType == .structure 2 &&
      stateTerminalAppendTermMatches appendTerm &&
      stateTerminalFullConditionMatches fullCondition &&
      stateCommandIsSkip notFull && target == ⟨10, by omega⟩ &&
      stateTerminalStateCountTermMatches stateCountTerm &&
      stateCommandIsSkip trailing
  | _ => false

private theorem stateTerminalSuccessCommand_matches :
    stateTerminalSuccessCommandMatches stateTerminalSuccessCommand = true := by
  native_decide

/-- Exact append-control structure projected from `parser.lani::recognize`.
    The full branch remains a projection of the same command rather than an
    independently maintained copy. -/
private theorem stateTerminalSuccessCommand_shape :
    stateTerminalSuccessCommand =
      .letValue (.structure 2) stateTerminalAppendTerm
        (.sequence
          (.ifThenElse stateTerminalFullCondition
            stateTerminalFullCommand .skip)
          (.sequence
            (.setLocal ⟨10, by omega⟩ stateTerminalStateCountTerm)
            .skip)) := by
  have matched := stateTerminalSuccessCommand_matches
  generalize commandEq : stateTerminalSuccessCommand = command at matched ⊢
  cases command <;> try { simp [stateTerminalSuccessCommandMatches] at matched }
  case letValue appendType appendTerm body =>
    cases body <;> try { simp [stateTerminalSuccessCommandMatches] at matched }
    case sequence control continuation =>
      cases control <;>
        try { simp [stateTerminalSuccessCommandMatches] at matched }
      case ifThenElse fullCondition full notFull =>
        cases continuation <;>
          try { simp [stateTerminalSuccessCommandMatches] at matched }
        case sequence assignment trailing =>
          cases assignment <;>
            try { simp [stateTerminalSuccessCommandMatches] at matched }
          case setLocal target stateCountTerm =>
            simp only [stateTerminalSuccessCommandMatches,
              Bool.and_eq_true] at matched
            have appendEq := stateTerminalAppendTermMatches_sound appendTerm
              matched.1.1.1.1.1.2
            have conditionEq := stateTerminalFullConditionMatches_sound
              fullCondition matched.1.1.1.1.2
            have notFullEq := stateCommandIsSkip_sound notFull
              matched.1.1.1.2
            have stateCountEq := stateTerminalStateCountTermMatches_sound
              stateCountTerm matched.1.2
            have trailingEq := stateCommandIsSkip_sound trailing matched.2
            simp_all [stateTerminalFullCommand]

private def stateIncompleteCommandMatches :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 17 → Bool
  | .letValue symbolType symbolTerm
      (.sequence (.ifThenElse terminalTest _ _) trailing) =>
      symbolType == parserI32Type &&
      stateRhsSymbolTermMatches symbolTerm ⟨0, by omega⟩ ⟨13, by omega⟩
        ⟨14, by omega⟩ &&
      stateLessTermMatches terminalTest ⟨17, by omega⟩ ⟨6, by omega⟩ &&
      stateCommandIsSkip trailing
  | _ => false

private theorem stateIncompleteCommand_matches :
    stateIncompleteCommandMatches stateIncompleteCommand = true := by
  native_decide

/-- Exact constructor-level shape of the incomplete-state branch projected
    from `parser.lani::recognize`. -/
private theorem stateIncompleteCommand_shape :
    stateIncompleteCommand =
      .letValue parserI32Type
        (stateRhsSymbolTerm ⟨0, by omega⟩ ⟨13, by omega⟩
          ⟨14, by omega⟩)
        (.sequence
          (.ifThenElse (stateLessTerm ⟨17, by omega⟩ ⟨6, by omega⟩)
            stateTerminalCommand stateNonterminalCommand)
          .skip) := by
  have matched := stateIncompleteCommand_matches
  generalize commandEq : stateIncompleteCommand = command at matched ⊢
  cases command <;> try { simp [stateIncompleteCommandMatches] at matched }
  case letValue symbolType symbolTerm body =>
    cases body <;> try { simp [stateIncompleteCommandMatches] at matched }
    case sequence first second =>
      cases first <;> try { simp [stateIncompleteCommandMatches] at matched }
      case ifThenElse terminalTest terminal nonterminal =>
        simp only [stateIncompleteCommandMatches, Bool.and_eq_true] at matched
        have symbolTypeEq := matched.1.1.1
        have symbolMatched := matched.1.1.2
        have testMatched := matched.1.2
        have trailingMatched := matched.2
        have symbolEq := stateRhsSymbolTermMatches_sound symbolTerm
          ⟨0, by omega⟩ ⟨13, by omega⟩ ⟨14, by omega⟩ symbolMatched
        have testEq := stateLessTermMatches_sound terminalTest
          ⟨17, by omega⟩ ⟨6, by omega⟩ testMatched
        have trailingEq := stateCommandIsSkip_sound second trailingMatched
        simp_all [stateTerminalCommand, stateNonterminalCommand]

private def stateTerminalCommandMatches :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 18 → Bool
  | .letValue nextType nextTerm
      (.sequence (.ifThenElse matchedTest _ miss) trailing) =>
      nextType == parserI32Type &&
      stateScanTerminalTermMatches nextTerm ⟨0, by omega⟩ ⟨1, by omega⟩
        ⟨2, by omega⟩ ⟨11, by omega⟩ ⟨17, by omega⟩ &&
      stateGreaterEqualZeroTermMatches matchedTest ⟨18, by omega⟩ &&
      stateCommandIsSkip miss && stateCommandIsSkip trailing
  | _ => false

private theorem stateTerminalCommand_matches :
    stateTerminalCommandMatches stateTerminalCommand = true := by
  native_decide

/-- Exact outer control shape of the terminal branch.  The successful append
    path remains projected from the source command. -/
private theorem stateTerminalCommand_shape :
    stateTerminalCommand =
      .letValue parserI32Type
        (stateScanTerminalTerm ⟨0, by omega⟩ ⟨1, by omega⟩
          ⟨2, by omega⟩ ⟨11, by omega⟩ ⟨17, by omega⟩)
        (.sequence
          (.ifThenElse (stateGreaterEqualZeroTerm ⟨18, by omega⟩)
            stateTerminalSuccessCommand .skip)
          .skip) := by
  have matched := stateTerminalCommand_matches
  generalize commandEq : stateTerminalCommand = command at matched ⊢
  cases command <;> try { simp [stateTerminalCommandMatches] at matched }
  case letValue nextType nextTerm body =>
    cases body <;> try { simp [stateTerminalCommandMatches] at matched }
    case sequence first trailing =>
      cases first <;> try { simp [stateTerminalCommandMatches] at matched }
      case ifThenElse matchedTest success miss =>
        simp only [stateTerminalCommandMatches, Bool.and_eq_true] at matched
        have nextTypeEq := matched.1.1.1.1
        have nextMatched := matched.1.1.1.2
        have testMatched := matched.1.1.2
        have missMatched := matched.1.2
        have trailingMatched := matched.2
        have nextEq := stateScanTerminalTermMatches_sound nextTerm
          ⟨0, by omega⟩ ⟨1, by omega⟩ ⟨2, by omega⟩ ⟨11, by omega⟩
          ⟨17, by omega⟩ nextMatched
        have testEq := stateGreaterEqualZeroTermMatches_sound matchedTest
          ⟨18, by omega⟩ testMatched
        have missEq := stateCommandIsSkip_sound miss missMatched
        have trailingEq := stateCommandIsSkip_sound trailing trailingMatched
        simp_all [stateTerminalSuccessCommand]

private def stateAdvanceCommandMatches :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 17 → Bool
  | .sequence (.setLocal target value) .skip =>
      target == ⟨12, by omega⟩ &&
      stateValueTermMatches value ⟨3, by omega⟩ ⟨4, by omega⟩
        ⟨12, by omega⟩ 32
  | _ => false

private theorem stateAdvanceCommand_matches :
    stateAdvanceCommandMatches stateAdvanceCommand = true := by
  native_decide

private theorem stateAdvanceCommandMatches_sound
    (command : Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 17)
    (matched : stateAdvanceCommandMatches command = true) :
    command =
      .sequence
        (.setLocal ⟨12, by omega⟩
          (stateValueTerm ⟨3, by omega⟩ ⟨4, by omega⟩
            ⟨12, by omega⟩ 32))
        .skip := by
  cases command <;> try { simp [stateAdvanceCommandMatches] at matched }
  case sequence first second =>
    cases first <;> try { simp [stateAdvanceCommandMatches] at matched }
    case setLocal target value =>
      cases second <;> simp [stateAdvanceCommandMatches] at matched
      case skip =>
        rcases matched with ⟨targetEq, valueMatched⟩
        have valueEq := stateValueTermMatches_sound value
          ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ 32 valueMatched
        simp_all

/-- Exact cursor-advance command projected from the reified state body. -/
private theorem stateAdvanceCommand_shape :
    stateAdvanceCommand =
      .sequence
        (.setLocal ⟨12, by omega⟩
          (stateValueTerm ⟨3, by omega⟩ ⟨4, by omega⟩
            ⟨12, by omega⟩ 32))
        .skip := by
  exact stateAdvanceCommandMatches_sound stateAdvanceCommand
    stateAdvanceCommand_matches

/-- Checked constructor-level decomposition of the one reified state body.
    The final branch is intentionally not compared with a second syntax tree:
    `stateAfterBindingsCommand` projects it from this same command. -/
private def stateBodyCommandMatches :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 13 → Bool
  | .letValue productionType productionTerm afterProduction =>
      match afterProduction with
      | .letValue dotType dotTerm afterDot =>
          match afterDot with
          | .letValue originType originTerm afterOrigin =>
              match afterOrigin with
              | .letValue rhsLengthType rhsLengthTerm _ =>
                  productionType == parserI32Type &&
                  stateValueTermMatches productionTerm ⟨3, by omega⟩
                    ⟨4, by omega⟩ ⟨12, by omega⟩ 28 &&
                  dotType == parserI32Type &&
                  stateValueTermMatches dotTerm ⟨3, by omega⟩
                    ⟨4, by omega⟩ ⟨12, by omega⟩ 29 &&
                  originType == parserI32Type &&
                  stateValueTermMatches originTerm ⟨3, by omega⟩
                    ⟨4, by omega⟩ ⟨12, by omega⟩ 30 &&
                  rhsLengthType == parserI32Type &&
                  stateRhsLengthTermMatches rhsLengthTerm ⟨0, by omega⟩
                    ⟨13, by omega⟩
              | _ => false
          | _ => false
      | _ => false
  | _ => false

private theorem stateBodyCommand_matches :
    stateBodyCommandMatches stateBodyCommand = true := by
  native_decide

/-- Exact lexical decomposition recovered from the executable constructor
    check.  No second body is reified or maintained. -/
private theorem stateBodyCommand_shape :
    stateBodyCommand =
      .letValue parserI32Type
        (stateValueTerm ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ 28)
        (.letValue parserI32Type
          (stateValueTerm ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ 29)
          (.letValue parserI32Type
            (stateValueTerm ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ 30)
            (.letValue parserI32Type
              (stateRhsLengthTerm ⟨0, by omega⟩ ⟨13, by omega⟩)
              stateAfterBindingsCommand))) := by
  have matched := stateBodyCommand_matches
  generalize commandEq : stateBodyCommand = command at matched ⊢
  cases command <;> simp [stateBodyCommandMatches] at matched
  case letValue productionType productionTerm afterProduction =>
    cases afterProduction <;> simp [stateBodyCommandMatches] at matched
    case letValue dotType dotTerm afterDot =>
      cases afterDot <;> simp [stateBodyCommandMatches] at matched
      case letValue originType originTerm afterOrigin =>
        cases afterOrigin <;> simp [stateBodyCommandMatches] at matched
        case letValue rhsLengthType rhsLengthTerm afterBindings =>
          rcases matched with
            ⟨⟨⟨⟨⟨⟨⟨_, productionMatched⟩, _⟩, dotMatched⟩, _⟩,
              originMatched⟩, _⟩, rhsLengthMatched⟩
          have productionEq := stateValueTermMatches_sound productionTerm
            ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ 28
            productionMatched
          have dotEq := stateValueTermMatches_sound dotTerm
            ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ 29 dotMatched
          have originEq := stateValueTermMatches_sound originTerm
            ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ 30 originMatched
          have rhsLengthEq := stateRhsLengthTermMatches_sound rhsLengthTerm
            ⟨0, by omega⟩ ⟨13, by omega⟩ rhsLengthMatched
          simp_all [stateAfterBindingsCommand]

private def coreAfterFourBindings : Stmt → Stmt
  | .letLocal _ _ _
      (.letLocal _ _ _
        (.letLocal _ _ _
          (.letLocal _ _ _ body))) => body
  | _ => .skip

def stateLoopCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 13 :=
  .whileLoop stateLoopCondition stateBodyCommand

theorem stateLoopCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      stateLoopLayout 25 stateLoopCommand = parserRecognizeStateLoop := by
  rw [stateLoopCommand, Lanius.FunctionalView.Core.Stateful.toCoreStmt,
    stateBodyCommand, parserRecognizeStateBodyView_toCore_exactly]
  exact extractedParserRecognize_state_loop_shape.symm

/-! ### Reusing the verified state loop inside the position body -/

def positionStateLayout : Layout 16 :=
  Layout.push positionLoopLayout 24

def stateIntoPositionEmbedding :
    Lanius.FunctionalView.Embedding 13 16 where
  slot := fun index =>
    [0, 1, 2, 3, 5, 6, 7, 9, 10, 11, 12, 14, 15].get index
  injective := by
    exact Lanius.FunctionalView.Embedding.listGetInjective
      ([0, 1, 2, 3, 5, 6, 7, 9, 10, 11, 12, 14, 15] :
        List (Fin 16)) (by decide)

theorem stateIntoPositionLayout_extends :
    Layout.Extends stateIntoPositionEmbedding stateLoopLayout
      positionStateLayout := by
  apply Layout.Extends.ofFn
  native_decide

abbrev positionStateLoopCommand :=
  Lanius.FunctionalView.Stateful.Command.rename
    Lanius.FunctionalView.Core.Stateful.actionRenamer
    stateIntoPositionEmbedding stateLoopCommand

theorem positionStateLoopCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      positionStateLayout 25 positionStateLoopCommand =
      parserRecognizeStateLoop := by
  rw [positionStateLoopCommand,
    Lanius.FunctionalView.Core.Stateful.toCoreStmt_rename
      stateIntoPositionLayout_extends 25 stateLoopCommand,
    stateLoopCommand_toCore]

def positionActivityCondition :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 15 :=
  .apply (.binary .greaterEqual parserI32Type parserI32Type (.scalar .bool)) [
    stateChartHeadTerm ⟨3, by omega⟩ ⟨14, by omega⟩,
    stateLiteral 0]

def positionActivityCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 15 :=
  .ifThenElse positionActivityCondition
    (.sequence
      (.setLocal ⟨13, by omega⟩ (stateSlot ⟨14, by omega⟩))
      .skip)
    .skip

def positionAdvanceCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 16 :=
  .sequence
    (.updateLocal .add ⟨14, by omega⟩ (stateLiteral 1))
    .skip

def positionStateScopeCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 15 :=
  .letValue parserI32Type (stateChartHeadTerm ⟨3, by omega⟩ ⟨14, by omega⟩)
    (.sequence positionStateLoopCommand positionAdvanceCommand)

def positionExpectedBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 15 :=
  .sequence positionActivityCommand positionStateScopeCommand

/-- Constructor-level decomposition of the one mechanically reified position
    body.  The nested loop is the renamed verified state command above. -/
theorem positionBodyCommand_shape :
    positionBodyCommand = positionExpectedBodyCommand := by
  apply stateCommandMatches_sound
  native_decide

/-! ### Reusing compact loop proofs inside the state body

The prediction loop was proved against its ten live locals.  At its concrete
source position those locals are embedded in the twenty-two bindings visible
after state, symbol, and prediction setup.  The larger view below is recovered
from the same checked Core loop; the equality theorem establishes that this is
exactly the generic scoped renaming of the compact command.
-/

private def statePredictionLayout : Layout 22 := fun index =>
  [0, 2, 3, 4, 8, 9, 11, 13, 14, 15, 18, 23, 24,
    25, 26, 27, 28, 29, 30, 31, 32, 33].get index

private def statePredictionContext : Context :=
  let c13 := stateLoopContext
  let c14 := c13.bind 25 parserI32Type
  let c15 := c14.bind 26 parserI32Type
  let c16 := c15.bind 27 parserI32Type
  let c17 := c16.bind 28 parserI32Type
  let c18 := c17.bind 29 parserI32Type
  let c19 := c18.bind 30 parserI32Type
  let c20 := c19.bind 31 parserI32Type
  let c21 := c20.bind 32 parserI32Type
  c21.bind 33 parserI32Type

private def statePredictionLoopReification? :=
  reifyCommand? verifiedParserCore (.structure 0) statePredictionContext true
    statePredictionLayout 34 parserRecognizePredictionLoop

private theorem statePredictionLoopReification_exists :
    statePredictionLoopReification?.isSome := by
  native_decide

private def parserRecognizeStatePredictionLoopView :=
  statePredictionLoopReification?.get
    statePredictionLoopReification_exists

private theorem parserRecognizeStatePredictionLoopView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      statePredictionLayout 34
      parserRecognizeStatePredictionLoopView.command =
      parserRecognizePredictionLoop :=
  parserRecognizeStatePredictionLoopView.toCoreExactly

def predictionIntoStateEmbedding :
    Lanius.FunctionalView.Embedding 10 22 where
  slot := fun index => [0, 3, 4, 5, 9, 10, 11, 19, 20, 21].get index
  injective := by
    exact Lanius.FunctionalView.Embedding.listGetInjective
      ([0, 3, 4, 5, 9, 10, 11, 19, 20, 21] : List (Fin 22)) (by decide)

private theorem predictionIntoStateLayout_extends :
    Layout.Extends predictionIntoStateEmbedding predictionLoopLayout
      statePredictionLayout := by
  apply Layout.Extends.ofFn
  native_decide

/-- The compact prediction proof command placed in its concrete enclosing
    environment.  Its correspondence with the separately reified larger view
    is established through the Core conversion theorem, not assumed by
    definitional equality: the two views contain proof-sensitive `Fin` terms. -/
abbrev statePredictionLoopCommand :=
  Lanius.FunctionalView.Stateful.Command.rename
      Lanius.FunctionalView.Core.Stateful.actionRenamer
      predictionIntoStateEmbedding predictionLoopCommand

/-- The compact command embedded into the state-body frame emits precisely
    the prediction loop extracted from `parser.lani`; renaming introduces no
    proof-only surrogate statement. -/
private theorem statePredictionLoopCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      statePredictionLayout 34 statePredictionLoopCommand =
      parserRecognizePredictionLoop := by
  rw [statePredictionLoopCommand,
    Lanius.FunctionalView.Core.Stateful.toCoreStmt_rename
      predictionIntoStateLayout_extends 34 predictionLoopCommand,
    predictionLoopCommand_toCore]

/-- The already-proved prediction traversal executes in the real state-body
    lexical environment, and every enclosing local outside its ten live slots
    is framed unchanged. -/
noncomputable def RecognizerPredictionConfig.evaluates_in_state_environment
    (config : RecognizerPredictionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell position first count)
    (beforeLarge : Lanius.FunctionalView.Env 22)
    (related : Lanius.FunctionalView.Env.Extends
      predictionIntoStateEmbedding config.functionalRuntime.environment
      beforeLarge) :
    Lanius.FunctionalView.Stateful.Command.RenameResult
      (predictionStatefulMachine workspaceLayout words grammarCell)
      Lanius.FunctionalView.Core.Stateful.actionRenamer
      predictionIntoStateEmbedding config.functionalRuntime.world beforeLarge
      predictionLoopCommand config.functional_run.completion
      config.functional_run.after.world
      config.functional_run.after.environment := by
  let calls := RecognizerCallRegistry.calls workspaceLayout words grammarCell
  have actionSound :
      Lanius.FunctionalView.Core.Stateful.actionRenamer.Sound
        (Lanius.FunctionalView.Core.Stateful.termMachine
          (Lanius.FunctionalView.Core.Effectful.evaluateOperation
            verifiedParserCore calls))
        (Lanius.FunctionalView.Core.Stateful.machineWith verifiedParserCore
          (Lanius.FunctionalView.Core.Effectful.evaluateOperation
            verifiedParserCore calls)) :=
    Lanius.FunctionalView.Core.Stateful.actionRenamer_sound verifiedParserCore
      (Lanius.FunctionalView.Core.Effectful.evaluateOperation
        verifiedParserCore calls)
  have compact := config.functional_run_evaluates
  have actionSound' :
      @Lanius.FunctionalView.Stateful.ActionRenamer.Sound
        Lanius.FunctionalView.Core.signature
        Lanius.FunctionalView.Core.Stateful.actions
        Lanius.FunctionalView.Core.Stateful.actionRenamer
        (predictionTermMachine workspaceLayout words grammarCell)
        (predictionStatefulMachine workspaceLayout words grammarCell) := by
    intro source target embedding world small large related action
    have specialized := actionSound embedding world small large related action
    simpa [predictionTermMachine, predictionStatefulMachine,
      Lanius.FunctionalView.Core.Effectful.machine,
      Lanius.FunctionalView.Core.Stateful.termMachine, calls] using specialized
  exact compact.renameResult actionSound' predictionIntoStateEmbedding
    beforeLarge related

/-! #### Nullable completion in the nonterminal branch -/

/-- State-body bindings visible after the chart-head local `36` is bound. -/
private def stateNullableLayout : Layout 23 := fun index =>
  [0, 2, 3, 4, 8, 9, 11, 13, 14, 15, 18, 23, 24,
    25, 26, 27, 28, 29, 30, 31, 32, 33, 36].get index

def nullableIntoStateEmbedding :
    Lanius.FunctionalView.Embedding 12 23 where
  slot := fun index => [0, 3, 4, 5, 10, 11, 12, 13, 14, 15, 18, 22].get index
  injective := by
    exact Lanius.FunctionalView.Embedding.listGetInjective
      ([0, 3, 4, 5, 10, 11, 12, 13, 14, 15, 18, 22] :
        List (Fin 23)) (by decide)

private theorem nullableIntoStateLayout_extends :
    Layout.Extends nullableIntoStateEmbedding nullableLoopLayout
      stateNullableLayout := by
  apply Layout.Extends.ofFn
  native_decide

abbrev stateNullableLoopCommand :=
  Lanius.FunctionalView.Stateful.Command.rename
    Lanius.FunctionalView.Core.Stateful.actionRenamer
    nullableIntoStateEmbedding nullableLoopCommand

/-- The embedded nullable command is exactly the loop extracted from the
    nonterminal branch of `parser.lani::recognize`. -/
private theorem stateNullableLoopCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      stateNullableLayout 37 stateNullableLoopCommand =
      parserRecognizeNullableLoop := by
  rw [stateNullableLoopCommand,
    Lanius.FunctionalView.Core.Stateful.toCoreStmt_rename
      nullableIntoStateLayout_extends 37 nullableLoopCommand,
    nullableLoopCommand_toCore]

noncomputable def RecognizerNullableConfig.evaluates_in_state_environment
    (config : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected)
    (beforeLarge : Lanius.FunctionalView.Env 23)
    (related : Lanius.FunctionalView.Env.Extends
      nullableIntoStateEmbedding config.functionalRuntime.environment
      beforeLarge) :
    Lanius.FunctionalView.Stateful.Command.RenameResult
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      Lanius.FunctionalView.Core.Stateful.actionRenamer nullableIntoStateEmbedding
      config.functionalRuntime.world beforeLarge nullableLoopCommand
      config.functional_run.completion config.functional_run.after.world
      config.functional_run.after.environment := by
  let calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
    words grammarCell
  have actionSound :
      Lanius.FunctionalView.Core.Stateful.actionRenamer.Sound
        (Lanius.FunctionalView.Core.Stateful.termMachine
          (Lanius.FunctionalView.Core.Effectful.evaluateOperation
            verifiedParserCore calls))
        (Lanius.FunctionalView.Core.Stateful.machineWith verifiedParserCore
          (Lanius.FunctionalView.Core.Effectful.evaluateOperation
            verifiedParserCore calls)) :=
    Lanius.FunctionalView.Core.Stateful.actionRenamer_sound verifiedParserCore
      (Lanius.FunctionalView.Core.Effectful.evaluateOperation
        verifiedParserCore calls)
  have actionSound' :
      @Lanius.FunctionalView.Stateful.ActionRenamer.Sound
        Lanius.FunctionalView.Core.signature
        Lanius.FunctionalView.Core.Stateful.actions
        Lanius.FunctionalView.Core.Stateful.actionRenamer
        (nullableTermMachine workspaceLayout grammar words grammarCell)
        (nullableStatefulMachine workspaceLayout grammar words grammarCell) := by
    intro source target embedding world small large related action
    have specialized := actionSound embedding world small large related action
    simpa [nullableTermMachine, nullableStatefulMachine,
      Lanius.FunctionalView.Core.Effectful.machine,
      Lanius.FunctionalView.Core.Stateful.termMachine, calls] using specialized
  exact config.functional_run_evaluates.renameResult actionSound'
    nullableIntoStateEmbedding beforeLarge related

/-! #### Parent completion in the completed-state branch -/

/-- State-body bindings visible after completed-production locals `29` and
    `30` are bound. -/
private def stateParentLayout : Layout 19 := fun index =>
  [0, 2, 3, 4, 8, 9, 11, 13, 14, 15, 18, 23, 24,
    25, 26, 27, 28, 29, 30].get index

def parentIntoStateEmbedding :
    Lanius.FunctionalView.Embedding 10 19 where
  slot := fun index => [0, 3, 4, 5, 10, 6, 11, 12, 17, 18].get index
  injective := by
    exact Lanius.FunctionalView.Embedding.listGetInjective
      ([0, 3, 4, 5, 10, 6, 11, 12, 17, 18] : List (Fin 19)) (by decide)

private theorem parentIntoStateLayout_extends :
    Layout.Extends parentIntoStateEmbedding parentLoopLayout
      stateParentLayout := by
  apply Layout.Extends.ofFn
  native_decide

abbrev stateParentLoopCommand :=
  Lanius.FunctionalView.Stateful.Command.rename
    Lanius.FunctionalView.Core.Stateful.actionRenamer
    parentIntoStateEmbedding parentLoopCommand

/-- The embedded parent command is exactly the loop extracted from the
    completed-state branch of `parser.lani::recognize`. -/
private theorem stateParentLoopCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      stateParentLayout 31 stateParentLoopCommand =
      parserRecognizeParentLoop := by
  rw [stateParentLoopCommand,
    Lanius.FunctionalView.Core.Stateful.toCoreStmt_rename
      parentIntoStateLayout_extends 31 parentLoopCommand,
    parentLoopCommand_toCore]

/-! #### Source-derived state-branch shells -/

/-- The nonterminal shell is still the command projected from the one reified
    recognizer body.  The only substituted subcommands are generic renamings
    of the already-verified prediction and nullable loops; their exact Core
    correspondence is checked above. -/
private theorem stateNonterminalCommand_shape :
    stateNonterminalCommand =
      .letValue parserI32Type
        (stateSubtractTerm ⟨17, by omega⟩ ⟨6, by omega⟩)
        (.letValue parserI32Type
          (stateIndexAddTerm ⟨0, by omega⟩ ⟨7, by omega⟩
            ⟨18, by omega⟩)
          (.letValue parserI32Type
            (stateIndexAddTerm ⟨0, by omega⟩ ⟨8, by omega⟩
              ⟨18, by omega⟩)
            (.letValue parserI32Type (stateLiteral 0)
              (.sequence statePredictionLoopCommand
                (.letValue parserI32Type
                  (stateChartHeadTerm ⟨3, by omega⟩ ⟨11, by omega⟩)
                  (.sequence stateNullableLoopCommand .skip)))))) := by
  apply stateCommandMatches_sound
  native_decide

/-- The completed-state shell projected from the extracted recognizer: obtain
    the completed production's LHS, enter its origin chart, then execute the
    generic parent-replay loop in the enlarged lexical frame. -/
private theorem stateCompleteCommand_shape :
    stateCompleteCommand =
      .letValue parserI32Type
        (stateLhsTerm ⟨0, by omega⟩ ⟨13, by omega⟩)
        (.letValue parserI32Type
          (stateChartHeadTerm ⟨3, by omega⟩ ⟨15, by omega⟩)
          (.sequence stateParentLoopCommand .skip)) := by
  apply stateCommandMatches_sound
  native_decide

noncomputable abbrev stateTermMachine
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId) :=
  Lanius.FunctionalView.Core.Stateful.termMachine
    (Lanius.FunctionalView.Core.Effectful.evaluateOperation verifiedParserCore
      (RecognizerStateCallRegistry.calls workspaceLayout grammar words tokens
        grammarCell tokensCell))

noncomputable abbrev stateStatefulMachine
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId) :=
  Lanius.FunctionalView.Core.Stateful.machineWith verifiedParserCore
    (Lanius.FunctionalView.Core.Effectful.evaluateOperation verifiedParserCore
      (RecognizerStateCallRegistry.calls workspaceLayout grammar words tokens
        grammarCell tokensCell))

/-- The enclosing position loop uses the same call-capable parser machine as
    its nested state loop.  These aliases make that shared semantic boundary
    explicit without constructing another evaluator. -/
noncomputable abbrev positionTermMachine := stateTermMachine

noncomputable abbrev positionStatefulMachine := stateStatefulMachine

/-! The branch theorems below are deliberately semantic combinators over the
    exact source-derived shells.  They isolate lexical-scope bookkeeping from
    the recognizer-specific construction of prediction, nullable, and parent
    configurations. -/

private theorem functionalSequenceSkip
    {termSignature : Lanius.FunctionalView.Signature}
    {actions : Lanius.FunctionalView.Stateful.ActionSignature termSignature}
    {arity : Nat}
    {termMachine : Lanius.FunctionalView.Machine termSignature}
    {machine : Lanius.FunctionalView.Stateful.Machine termMachine actions}
    {beforeWorld afterWorld : termMachine.World}
    {beforeEnvironment afterEnvironment : Lanius.FunctionalView.Env arity}
    {command : Lanius.FunctionalView.Stateful.Command termSignature actions arity}
    {completion : Lanius.FunctionalView.Stateful.Completion}
    (evaluated : Lanius.FunctionalView.Stateful.Command.Evaluates termMachine
      machine beforeWorld beforeEnvironment command completion afterWorld
      afterEnvironment) :
    Lanius.FunctionalView.Stateful.Command.Evaluates termMachine machine
      beforeWorld beforeEnvironment (.sequence command .skip) completion
      afterWorld afterEnvironment := by
  cases completion with
  | next => exact .sequenceNext evaluated .skip
  | returned value => exact .sequenceStop evaluated (by simp)
  | breakLoop => exact .sequenceStop evaluated (by simp)
  | continueLoop => exact .sequenceStop evaluated (by simp)

theorem stateNonterminalCommand_evaluates_of_prediction_stop
    (world afterWorld :
      Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 18)
    (nonterminal first count : Nat)
    (afterPrediction : Lanius.FunctionalView.Env 22)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (stops : completion ≠ .next)
    (nonterminalResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment
      (stateSubtractTerm ⟨17, by omega⟩ ⟨6, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat nonterminal), world))
    (firstResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world (environment.push (.signed .i32 (Int.ofNat nonterminal)))
      (stateIndexAddTerm ⟨0, by omega⟩ ⟨7, by omega⟩
        ⟨18, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat first), world))
    (countResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world ((environment.push (.signed .i32 (Int.ofNat nonterminal))).push
        (.signed .i32 (Int.ofNat first)))
      (stateIndexAddTerm ⟨0, by omega⟩ ⟨8, by omega⟩
        ⟨18, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat count), world))
    (predictionResult :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        world
        ((((environment.push (.signed .i32 (Int.ofNat nonterminal))).push
          (.signed .i32 (Int.ofNat first))).push
          (.signed .i32 (Int.ofNat count))).push (.signed .i32 0))
        statePredictionLoopCommand completion afterWorld afterPrediction) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateNonterminalCommand completion afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.pop afterPrediction)))) := by
  have zeroResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world (((environment.push (.signed .i32 (Int.ofNat nonterminal))).push
        (.signed .i32 (Int.ofNat first))).push
        (.signed .i32 (Int.ofNat count))) (stateLiteral 0) =
      .ok (.signed .i32 0, world) := by rfl
  have predictionScope :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        world
        ((((environment.push (.signed .i32 (Int.ofNat nonterminal))).push
          (.signed .i32 (Int.ofNat first))).push
          (.signed .i32 (Int.ofNat count))).push (.signed .i32 0))
        (.sequence statePredictionLoopCommand
          (.letValue parserI32Type
            (stateChartHeadTerm ⟨3, by omega⟩ ⟨11, by omega⟩)
            (.sequence stateNullableLoopCommand .skip)))
        completion afterWorld afterPrediction :=
    Lanius.FunctionalView.Stateful.Command.Evaluates.sequenceStop
      predictionResult stops
  rw [stateNonterminalCommand_shape]
  exact Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
    nonterminalResult
    (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue firstResult
      (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue countResult
        (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue zeroResult
          predictionScope)))

theorem stateNonterminalCommand_evaluates_of_nullable
    (world predictionWorld afterWorld :
      Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 18)
    (nonterminal first count : Nat) (chartHead : Int)
    (afterPrediction : Lanius.FunctionalView.Env 22)
    (afterNullable : Lanius.FunctionalView.Env 23)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (nonterminalResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment
      (stateSubtractTerm ⟨17, by omega⟩ ⟨6, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat nonterminal), world))
    (firstResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world (environment.push (.signed .i32 (Int.ofNat nonterminal)))
      (stateIndexAddTerm ⟨0, by omega⟩ ⟨7, by omega⟩
        ⟨18, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat first), world))
    (countResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world ((environment.push (.signed .i32 (Int.ofNat nonterminal))).push
        (.signed .i32 (Int.ofNat first)))
      (stateIndexAddTerm ⟨0, by omega⟩ ⟨8, by omega⟩
        ⟨18, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat count), world))
    (predictionResult :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        world
        ((((environment.push (.signed .i32 (Int.ofNat nonterminal))).push
          (.signed .i32 (Int.ofNat first))).push
          (.signed .i32 (Int.ofNat count))).push (.signed .i32 0))
        statePredictionLoopCommand .next predictionWorld afterPrediction)
    (chartHeadResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      predictionWorld afterPrediction
      (stateChartHeadTerm ⟨3, by omega⟩ ⟨11, by omega⟩) =
      .ok (.signed .i32 chartHead, predictionWorld))
    (nullableResult :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        predictionWorld (afterPrediction.push (.signed .i32 chartHead))
        stateNullableLoopCommand completion afterWorld afterNullable) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateNonterminalCommand completion afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.pop
              (Lanius.FunctionalView.Stateful.Env.pop afterNullable))))) := by
  have zeroResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world (((environment.push (.signed .i32 (Int.ofNat nonterminal))).push
        (.signed .i32 (Int.ofNat first))).push
        (.signed .i32 (Int.ofNat count))) (stateLiteral 0) =
      .ok (.signed .i32 0, world) := by rfl
  have nullableScope := functionalSequenceSkip nullableResult
  have chartScope :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        predictionWorld afterPrediction
        (.letValue parserI32Type
          (stateChartHeadTerm ⟨3, by omega⟩ ⟨11, by omega⟩)
          (.sequence stateNullableLoopCommand .skip))
        completion afterWorld
        (Lanius.FunctionalView.Stateful.Env.pop afterNullable) :=
    Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
      chartHeadResult nullableScope
  have predictionScope :=
    Lanius.FunctionalView.Stateful.Command.Evaluates.sequenceNext
      predictionResult chartScope
  rw [stateNonterminalCommand_shape]
  exact Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
    nonterminalResult
    (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue firstResult
      (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue countResult
        (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue zeroResult
          predictionScope)))

theorem stateCompleteCommand_evaluates_of_parent
    (world afterWorld : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 17)
    (lhs : Nat) (chartHead : Int)
    (afterParent : Lanius.FunctionalView.Env 19)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (lhsResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateLhsTerm ⟨0, by omega⟩ ⟨13, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat lhs), world))
    (chartHeadResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world (environment.push (.signed .i32 (Int.ofNat lhs)))
      (stateChartHeadTerm ⟨3, by omega⟩ ⟨15, by omega⟩) =
      .ok (.signed .i32 chartHead, world))
    (parentResult : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world ((environment.push (.signed .i32 (Int.ofNat lhs))).push
        (.signed .i32 chartHead)) stateParentLoopCommand completion afterWorld
      afterParent) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateCompleteCommand completion afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop afterParent)) := by
  have parentScope := functionalSequenceSkip parentResult
  rw [stateCompleteCommand_shape]
  exact Lanius.FunctionalView.Stateful.Command.Evaluates.letValue lhsResult
    (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue chartHeadResult
      parentScope)

noncomputable def RecognizerParentConfig.evaluates_in_state_environment
    (config : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin)
    (beforeLarge : Lanius.FunctionalView.Env 19)
    (related : Lanius.FunctionalView.Env.Extends parentIntoStateEmbedding
      config.functionalRuntime.environment beforeLarge) :
    Lanius.FunctionalView.Stateful.Command.RenameResult
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      Lanius.FunctionalView.Core.Stateful.actionRenamer parentIntoStateEmbedding
      config.functionalRuntime.world beforeLarge parentLoopCommand
      config.functional_run.completion config.functional_run.after.world
      config.functional_run.after.environment := by
  let calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
    words grammarCell
  have actionSound :
      Lanius.FunctionalView.Core.Stateful.actionRenamer.Sound
        (Lanius.FunctionalView.Core.Stateful.termMachine
          (Lanius.FunctionalView.Core.Effectful.evaluateOperation
            verifiedParserCore calls))
        (Lanius.FunctionalView.Core.Stateful.machineWith verifiedParserCore
          (Lanius.FunctionalView.Core.Effectful.evaluateOperation
            verifiedParserCore calls)) :=
    Lanius.FunctionalView.Core.Stateful.actionRenamer_sound verifiedParserCore
      (Lanius.FunctionalView.Core.Effectful.evaluateOperation
        verifiedParserCore calls)
  have actionSound' :
      @Lanius.FunctionalView.Stateful.ActionRenamer.Sound
        Lanius.FunctionalView.Core.signature
        Lanius.FunctionalView.Core.Stateful.actions
        Lanius.FunctionalView.Core.Stateful.actionRenamer
        (parentTermMachine workspaceLayout grammar words grammarCell)
        (parentStatefulMachine workspaceLayout grammar words grammarCell) := by
    intro source target embedding world small large related action
    have specialized := actionSound embedding world small large related action
    simpa [parentTermMachine, parentStatefulMachine,
      Lanius.FunctionalView.Core.Effectful.machine,
      Lanius.FunctionalView.Core.Stateful.termMachine, calls] using specialized
  exact config.functional_run_evaluates.renameResult actionSound'
    parentIntoStateEmbedding beforeLarge related

/-- Functional world for every slice visible to the state loop. -/
def stateWorld (words : List Int) (tokens : List Nat)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId) :
    Lanius.FunctionalView.Core.ReadOnly.World :=
  recognizerWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell

theorem stateWorld_finds_grammar :
    (stateWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell).i32Slice? grammarCell = some words := by
  exact recognizerWorld_finds_grammar

theorem stateWorld_finds_workspace
    (grammarDistinct : grammarCell ≠ workspaceCell)
    (tokensDistinct : tokensCell ≠ workspaceCell) :
    (stateWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell).i32Slice? workspaceCell = some workspaceValues := by
  exact recognizerWorld_finds_workspace grammarDistinct.symm

theorem stateWorld_finds_tokens
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime) :
    (stateWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell).i32Slice? tokensCell =
      some (tokens.map Int.ofNat) := by
  by_cases sameCell : tokensCell = grammarCell
  · subst tokensCell
    have encodedValues : signedI32Values words =
        signedI32Values (tokens.map Int.ofNat) := by
      have backing := invariant.grammarBacking.symm.trans
        invariant.tokensBacking
      have cellEquality := Option.some.inj backing
      have valueEquality := congrArg Cell.value cellEquality
      have arrayEquality := Option.some.inj valueEquality
      injection arrayEquality
    have valuesAgree : words = tokens.map Int.ofNat :=
      signedI32Values_injective encodedValues
    simpa [stateWorld, valuesAgree] using
      (recognizerWorld_finds_grammar
        (words := tokens.map Int.ofNat) (tokens := tokens)
        (workspaceValues := workspaceValues) (grammarCell := grammarCell)
        (tokensCell := grammarCell) (workspaceCell := workspaceCell))
  · exact recognizerWorld_finds_tokens sameCell
      invariant.tokensWorkspaceDistinct

private theorem stateWorld_set_workspace
    (grammarDistinct : grammarCell ≠ workspaceCell)
    (tokensDistinct : tokensCell ≠ workspaceCell) :
    Lanius.FunctionalView.Core.ReadOnly.World.setI32Slice
        (stateWorld words tokens beforeValues grammarCell tokensCell
          workspaceCell)
        workspaceCell afterValues =
      stateWorld words tokens afterValues grammarCell tokensCell
        workspaceCell := by
  exact recognizerWorld_set_workspace grammarDistinct.symm
    tokensDistinct.symm

private theorem stateWorld_represents
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime) :
    Lanius.FunctionalView.Core.ReadOnly.World.Represents
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell) runtime := by
  exact recognizerWorld_represents invariant

/-- Persistent values selected by `stateLoopLayout`. -/
def stateEnvironment (words : List Int) (tokens : List Nat)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (kindCount lhsOffsetsOffset
      lhsCountsOffset lhsProductionsOffset stateCount position : Nat)
    (current : Int) : Lanius.FunctionalView.Env 13
  | ⟨0, _⟩ => parserGrammarValue words grammarCell
  | ⟨1, _⟩ => parserTokensValue tokens tokensCell
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat tokens.length)
  | ⟨3, _⟩ => workspaceValue workspaceValues workspaceCell
  | ⟨4, _⟩ => .signed .i32
      (Int.ofNat (stateBase workspaceLayout.tokenCount))
  | ⟨5, _⟩ => .signed .i32 (Int.ofNat workspaceLayout.capacity)
  | ⟨6, _⟩ => .signed .i32 (Int.ofNat kindCount)
  | ⟨7, _⟩ => .signed .i32 (Int.ofNat lhsOffsetsOffset)
  | ⟨8, _⟩ => .signed .i32 (Int.ofNat lhsCountsOffset)
  | ⟨9, _⟩ => .signed .i32 (Int.ofNat lhsProductionsOffset)
  | ⟨10, _⟩ => .signed .i32 (Int.ofNat stateCount)
  | ⟨11, _⟩ => .signed .i32 (Int.ofNat position)
  | ⟨12, _⟩ => .signed .i32 current

/-- Persistent source values selected by `positionLoopLayout`. -/
def positionEnvironment (words : List Int) (tokens : List Nat)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (grammarLayout : PackedGrammarLayout) (stateCount furthest position : Nat) :
    Lanius.FunctionalView.Env 15
  | ⟨0, _⟩ => parserGrammarValue words grammarCell
  | ⟨1, _⟩ => parserTokensValue tokens tokensCell
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat tokens.length)
  | ⟨3, _⟩ => workspaceValue workspaceValues workspaceCell
  | ⟨4, _⟩ => .signed .i32
      (Int.ofNat (finalPosition workspaceLayout.tokenCount))
  | ⟨5, _⟩ => .signed .i32
      (Int.ofNat (stateBase workspaceLayout.tokenCount))
  | ⟨6, _⟩ => .signed .i32 (Int.ofNat workspaceLayout.capacity)
  | ⟨7, _⟩ => .signed .i32 (Int.ofNat grammar.grammar.n_kinds)
  | ⟨8, _⟩ => .signed .i32 (Int.ofNat grammar.grammar.start_nonterminal)
  | ⟨9, _⟩ => .signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset)
  | ⟨10, _⟩ => .signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset)
  | ⟨11, _⟩ =>
      .signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset)
  | ⟨12, _⟩ => .signed .i32 (Int.ofNat stateCount)
  | ⟨13, _⟩ => .signed .i32 (Int.ofNat furthest)
  | ⟨14, _⟩ => .signed .i32 (Int.ofNat position)

/-- Persistent environment before the position statement binds its two
    counters.  It is definitionally the prefix of `positionEnvironment`, so
    entering the two lexical scopes cannot introduce a second semantic model
    of the recognizer state. -/
def positionStatementEnvironment (words : List Int)
    (tokens : List Nat) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (grammarLayout : PackedGrammarLayout) (stateCount : Nat) :
    Lanius.FunctionalView.Env 13
  | ⟨0, _⟩ => parserGrammarValue words grammarCell
  | ⟨1, _⟩ => parserTokensValue tokens tokensCell
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat tokens.length)
  | ⟨3, _⟩ => workspaceValue workspaceValues workspaceCell
  | ⟨4, _⟩ => .signed .i32
      (Int.ofNat (finalPosition workspaceLayout.tokenCount))
  | ⟨5, _⟩ => .signed .i32
      (Int.ofNat (stateBase workspaceLayout.tokenCount))
  | ⟨6, _⟩ => .signed .i32 (Int.ofNat workspaceLayout.capacity)
  | ⟨7, _⟩ => .signed .i32 (Int.ofNat grammar.grammar.n_kinds)
  | ⟨8, _⟩ => .signed .i32
      (Int.ofNat grammar.grammar.start_nonterminal)
  | ⟨9, _⟩ => .signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset)
  | ⟨10, _⟩ => .signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset)
  | ⟨11, _⟩ =>
      .signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset)
  | ⟨12, _⟩ => .signed .i32 (Int.ofNat stateCount)

theorem positionStatementEnvironment_push_zeroes
    (words : List Int) (tokens : List Nat) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (grammarLayout : PackedGrammarLayout) (stateCount : Nat) :
    ((positionStatementEnvironment words tokens workspaceValues grammarCell
      tokensCell workspaceCell workspaceLayout grammar grammarLayout
      stateCount).push (.signed .i32 0)).push (.signed .i32 0) =
      positionEnvironment words tokens workspaceValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar grammarLayout stateCount 0 0 := by
  apply Lanius.FunctionalView.Env.eq_ofFn
  rfl

/-- The compact state-loop environment is precisely the embedded portion of
    the enclosing position scope.  The final-position, start-nonterminal, and
    furthest slots are the framed values intentionally absent from the state
    loop's proof view. -/
theorem stateEnvironment_extends_positionEnvironment
    (words : List Int) (tokens : List Nat) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (grammarLayout : PackedGrammarLayout) (stateCount furthest position : Nat)
    (candidate : Int) :
    Lanius.FunctionalView.Env.Extends stateIntoPositionEmbedding
      (stateEnvironment words tokens workspaceValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar.grammar.n_kinds
        grammarLayout.lhsOffsetsOffset grammarLayout.lhsCountsOffset
        grammarLayout.lhsProductionsOffset stateCount position candidate)
      ((positionEnvironment words tokens workspaceValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar grammarLayout stateCount furthest
        position).push (.signed .i32 candidate)) := by
  apply Lanius.FunctionalView.Env.Extends.ofFn
  rfl

/-- Exactly the final-position, start-nonterminal, and furthest slots are
    outside the compact state-loop embedding. -/
private theorem stateIntoPositionEmbedding_outside_iff :
    ∀ index : Fin 16,
      (∀ source, stateIntoPositionEmbedding.slot source ≠ index) ↔
        index = ⟨4, by omega⟩ ∨ index = ⟨8, by omega⟩ ∨
          index = ⟨13, by omega⟩ := by
  native_decide

/-- Changing state-loop-owned values preserves the three enclosing position
    values framed outside the state embedding. -/
theorem positionStateFrame_preserved
    (words : List Int) (tokens : List Nat)
    (beforeValues afterValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (grammarLayout : PackedGrammarLayout)
    (beforeCount afterCount furthest position : Nat)
    (beforeCandidate afterCandidate : Int) :
    Lanius.FunctionalView.Env.PreservesOutside stateIntoPositionEmbedding
      ((positionEnvironment words tokens beforeValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar grammarLayout beforeCount furthest
        position).push (.signed .i32 beforeCandidate))
      ((positionEnvironment words tokens afterValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar grammarLayout afterCount furthest
        position).push (.signed .i32 afterCandidate)) := by
  intro index outside
  rcases (stateIntoPositionEmbedding_outside_iff index).mp outside with
    rfl | rfl | rfl <;> rfl

/-- Semantic interpretation of the exact seventeen-slot environment after
    the state body has decoded its current Earley item.  This is the shared
    boundary for all source-derived state branches. -/
structure StateAfterBindingsEnvironment
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (position current production dot origin rhsLength : Nat)
    (environment : Lanius.FunctionalView.Env 17) : Prop where
  grammarEq : environment ⟨0, by omega⟩ = parserGrammarValue words grammarCell
  tokensEq : environment ⟨1, by omega⟩ = parserTokensValue tokens tokensCell
  tokenCountEq : environment ⟨2, by omega⟩ =
    .signed .i32 (Int.ofNat tokens.length)
  workspaceEq : environment ⟨3, by omega⟩ =
    workspaceValue workspaceValues workspaceCell
  stateBaseEq : environment ⟨4, by omega⟩ =
    .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))
  capacityEq : environment ⟨5, by omega⟩ =
    .signed .i32 (Int.ofNat workspaceLayout.capacity)
  kindCountEq : environment ⟨6, by omega⟩ =
    .signed .i32 (Int.ofNat grammar.grammar.n_kinds)
  lhsOffsetsEq : environment ⟨7, by omega⟩ =
    .signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset)
  lhsCountsEq : environment ⟨8, by omega⟩ =
    .signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset)
  lhsProductionsEq : environment ⟨9, by omega⟩ =
    .signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset)
  stateCountEq : environment ⟨10, by omega⟩ =
    .signed .i32 (Int.ofNat workspace.states.length)
  positionEq : environment ⟨11, by omega⟩ =
    .signed .i32 (Int.ofNat position)
  currentEq : environment ⟨12, by omega⟩ =
    .signed .i32 (Int.ofNat current)
  productionEq : environment ⟨13, by omega⟩ =
    .signed .i32 (Int.ofNat production)
  dotEq : environment ⟨14, by omega⟩ =
    .signed .i32 (Int.ofNat dot)
  originEq : environment ⟨15, by omega⟩ =
    .signed .i32 (Int.ofNat origin)
  rhsLengthEq : environment ⟨16, by omega⟩ =
    .signed .i32 (Int.ofNat rhsLength)

/-- Reinterpret the decoded-state source frame after a workspace update.
    FunctionalView mutates the workspace world and state-count slot; the slice
    value itself depends only on the stable backing cell and capacity-sized
    list length, so every other source local is framed automatically. -/
theorem StateAfterBindingsEnvironment.after_workspace_update
    (meaning : StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell position current production dot origin rhsLength environment)
    (afterWorkspace : LogicalWorkspace) (afterValues : List Int)
    (sameLength : afterValues.length = beforeValues.length) :
    StateAfterBindingsEnvironment grammarLayout grammar words tokens
      workspaceLayout afterWorkspace afterValues grammarCell tokensCell
      workspaceCell position current production dot origin rhsLength
      (Lanius.FunctionalView.Stateful.Env.set environment ⟨10, by omega⟩
        (.signed .i32 (Int.ofNat afterWorkspace.states.length))) := by
  let countSlot : Fin 17 := 10
  let afterEnvironment := Lanius.FunctionalView.Stateful.Env.set environment
    countSlot (.signed .i32 (Int.ofNat afterWorkspace.states.length))
  have unchanged (index : Fin 17) (differentValue : index.val ≠ 10) :
      afterEnvironment index = environment index := by
    apply Lanius.FunctionalView.Stateful.Env.set_other
    intro same
    have countSlotValue : countSlot.val = 10 := by rfl
    exact differentValue ((congrArg Fin.val same).trans countSlotValue)
  exact {
    grammarEq := (unchanged 0 (by decide)).trans meaning.grammarEq
    tokensEq := (unchanged 1 (by decide)).trans meaning.tokensEq
    tokenCountEq := (unchanged 2 (by decide)).trans meaning.tokenCountEq
    workspaceEq := by
      calc
        afterEnvironment 3 = environment 3 := unchanged 3 (by decide)
        _ = workspaceValue beforeValues workspaceCell := meaning.workspaceEq
        _ = workspaceValue afterValues workspaceCell := by
          simp [workspaceValue, sameLength]
    stateBaseEq := (unchanged 4 (by decide)).trans meaning.stateBaseEq
    capacityEq := (unchanged 5 (by decide)).trans meaning.capacityEq
    kindCountEq := (unchanged 6 (by decide)).trans meaning.kindCountEq
    lhsOffsetsEq := (unchanged 7 (by decide)).trans meaning.lhsOffsetsEq
    lhsCountsEq := (unchanged 8 (by decide)).trans meaning.lhsCountsEq
    lhsProductionsEq := (unchanged 9 (by decide)).trans
      meaning.lhsProductionsEq
    stateCountEq := by
      exact Lanius.FunctionalView.Stateful.Env.set_same environment countSlot _
    positionEq := (unchanged 11 (by decide)).trans meaning.positionEq
    currentEq := (unchanged 12 (by decide)).trans meaning.currentEq
    productionEq := (unchanged 13 (by decide)).trans meaning.productionEq
    dotEq := (unchanged 14 (by decide)).trans meaning.dotEq
    originEq := (unchanged 15 (by decide)).trans meaning.originEq
    rhsLengthEq := (unchanged 16 (by decide)).trans meaning.rhsLengthEq
  }

/-- Evaluate the source nonterminal-number subtraction under the enclosing
    state call model.  The term is call-free, so the generic read-only
    arithmetic proof transfers without exposing registry internals. -/
theorem stateSubtractTerm_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (leftSlot rightSlot : Fin arity) (left right : Nat)
    (leftEq : environment leftSlot = .signed .i32 (Int.ofNat left))
    (rightEq : environment rightSlot = .signed .i32 (Int.ofNat right))
    (lower : right ≤ left) (bounded : left - right ≤ 2147483647) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateSubtractTerm leftSlot rightSlot) =
      .ok (.signed .i32 (Int.ofNat (left - right)), world) := by
  let calls := RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell
  have leftResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment (stateSlot leftSlot) =
      .ok (.signed .i32 (Int.ofNat left), world) :=
    Lanius.FunctionalView.Term.evaluate_slot leftEq
  have rightResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment (stateSlot rightSlot) =
      .ok (.signed .i32 (Int.ofNat right), world) :=
    Lanius.FunctionalView.Term.evaluate_slot rightEq
  have readOnly :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_subtract
      (leftType := parserI32Type) (rightType := parserI32Type)
      (outputType := parserI32Type) leftResult rightResult lower bounded
  have agreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore) (calls := calls) (world := world)
      (environment := environment) (stateSubtractTerm leftSlot rightSlot)
      (by rfl)
  exact agreement.trans readOnly

/-- Evaluate one `slice[base + row]` source term.  This is shared by the LHS
    offset and LHS count bindings and keeps packed-table bounds explicit. -/
theorem stateIndexAddTerm_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell cell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (sliceSlot baseSlot rowSlot : Fin arity) (values : List Int)
    (base row : Nat)
    (sliceEq : environment sliceSlot =
      .slice parserI32Type cell [] 0 values.length)
    (baseEq : environment baseSlot = .signed .i32 (Int.ofNat base))
    (rowEq : environment rowSlot = .signed .i32 (Int.ofNat row))
    (found : world.i32Slice? cell = some values)
    (sumBound : base + row ≤ 2147483647)
    (indexBound : base + row < values.length) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateIndexAddTerm sliceSlot baseSlot rowSlot) =
      .ok (.signed .i32 (values.get ⟨base + row, indexBound⟩), world) := by
  let calls := RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell
  let machine := Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore
  have sliceResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot sliceSlot) =
      .ok (.slice parserI32Type cell [] 0 values.length, world) :=
    Lanius.FunctionalView.Term.evaluate_slot sliceEq
  have baseResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot baseSlot) =
      .ok (.signed .i32 (Int.ofNat base), world) :=
    Lanius.FunctionalView.Term.evaluate_slot baseEq
  have rowResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot rowSlot) =
      .ok (.signed .i32 (Int.ofNat row), world) :=
    Lanius.FunctionalView.Term.evaluate_slot rowEq
  have addressResult :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_add
      (leftType := parserI32Type) (rightType := parserI32Type)
      (outputType := parserI32Type) baseResult rowResult sumBound
  have readOnly :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_index
      (baseType := .slice parserI32Type) (indexType := parserI32Type)
      (elementType := parserI32Type) sliceResult addressResult found indexBound
  have agreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore) (calls := calls) (world := world)
      (environment := environment)
      (stateIndexAddTerm sliceSlot baseSlot rowSlot) (by rfl)
  exact agreement.trans readOnly

/-- Evaluate the completed production's LHS through the actual state-loop
    registry rather than a separately maintained call interpretation. -/
theorem stateLhsTerm_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (grammarSlot productionSlot : Fin arity) (production : Nat)
    (productionBound : production < grammar.productionCount)
    (grammarEq : environment grammarSlot =
      parserGrammarValue words grammarCell)
    (productionEq : environment productionSlot =
      .signed .i32 (Int.ofNat production))
    (grammarFound : world.i32Slice? grammarCell = some words) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateLhsTerm grammarSlot productionSlot) =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨production, productionBound⟩).lhs), world) := by
  let machine := stateTermMachine workspaceLayout grammar words tokens
    grammarCell tokensCell
  have grammarResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot grammarSlot) =
      .ok (parserGrammarValue words grammarCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot grammarEq
  have productionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot productionSlot) =
      .ok (.signed .i32 (Int.ofNat production), world) :=
    Lanius.FunctionalView.Term.evaluate_slot productionEq
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [stateSlot grammarSlot, stateSlot productionSlot] =
      .ok ([parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production)], world) :=
    Lanius.FunctionalView.evaluateTerms_cons grammarResult
      (Lanius.FunctionalView.evaluateTerms_cons productionResult
        (Lanius.FunctionalView.evaluateTerms_nil machine world environment))
  have rowBound : production < grammar.productionLhs.length := by simpa
  have traversal := RecognizerTraversalCallRegistry.calls_at_lhs
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (grammarCell := grammarCell) world production grammarFound
    rowBound
  have routed := RecognizerStateCallRegistry.calls_at_traversal
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (tokens := tokens) (grammarCell := grammarCell)
    (tokensCell := tokensCell) world extractedParserLhsFunction.id
    [parserGrammarValue words grammarCell,
      .signed .i32 (Int.ofNat production)] (by native_decide)
    (by native_decide)
  have rowValue : grammar.productionLhs.get ⟨production, rowBound⟩ =
      (grammar.productionAt ⟨production, productionBound⟩).lhs := by
    simpa using grammar.productionLhs_get ⟨production, productionBound⟩
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell).evaluate world
      extractedParserLhsFunction.id [parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production)] = _
  rw [routed]
  rw [rowValue] at traversal
  exact traversal

/-- Evaluate the shared `workspace[chart_word(position, 0)]` expression in
    FunctionalView.  The chart address call and packed workspace read stay in
    one world, so no host/Core barrier is introduced by the proof model. -/
theorem stateChartHeadTerm_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell workspaceCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (workspaceSlot positionSlot : Fin arity)
    (workspace : LogicalWorkspace) (workspaceValues : List Int)
    (position : Nat)
    (workspaceEq : environment workspaceSlot =
      workspaceValue workspaceValues workspaceCell)
    (positionEq : environment positionSlot =
      .signed .i32 (Int.ofNat position))
    (workspaceFound : world.i32Slice? workspaceCell = some workspaceValues)
    (valuesLength : workspaceValues.length = workspaceLayout.workspaceLength)
    (encoded : EncodesWorkspace workspaceLayout workspace
      (listWords workspaceValues))
    (positionBound : position ≤ finalPosition workspaceLayout.tokenCount) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateChartHeadTerm workspaceSlot positionSlot) =
      .ok (.signed .i32 (chartHeadValue workspace position), world) := by
  let machine := stateTermMachine workspaceLayout grammar words tokens
    grammarCell tokensCell
  have workspaceResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot workspaceSlot) =
      .ok (workspaceValue workspaceValues workspaceCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot workspaceEq
  have positionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot positionSlot) =
      .ok (.signed .i32 (Int.ofNat position), world) :=
    Lanius.FunctionalView.Term.evaluate_slot positionEq
  let fieldTerm : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity :=
    .apply (.constant 25 parserI32Type) []
  have fieldReadOnly : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment fieldTerm = .ok (.signed .i32 0, world) :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_constant
      verifiedParser_find_constants.1
  have fieldAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerStateCallRegistry.calls workspaceLayout grammar words
        tokens grammarCell tokensCell)
      (world := world) (environment := environment) fieldTerm (by rfl)
  have fieldResult : Lanius.FunctionalView.Term.evaluate machine world
      environment fieldTerm = .ok (.signed .i32 0, world) :=
    fieldAgreement.trans fieldReadOnly
  have addressArguments : Lanius.FunctionalView.evaluateTerms machine world
      environment [stateSlot positionSlot, fieldTerm] =
      .ok ([.signed .i32 (Int.ofNat position), .signed .i32 0], world) :=
    Lanius.FunctionalView.evaluateTerms_cons positionResult
      (Lanius.FunctionalView.evaluateTerms_cons fieldResult
        (Lanius.FunctionalView.evaluateTerms_nil machine world environment))
  have addressResult : Lanius.FunctionalView.Term.evaluate machine world
      environment
        (.apply (.call extractedParserChartWordFunction.id
          [parserI32Type, parserI32Type] parserI32Type)
          [stateSlot positionSlot, fieldTerm]) =
      .ok (.signed .i32 (Int.ofNat (chartWord position 0)), world) := by
    apply Lanius.FunctionalView.Term.evaluate_apply addressArguments
    exact RecognizerStateCallRegistry.calls_at_chart_word
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (tokens := tokens) (grammarCell := grammarCell)
      (tokensCell := tokensCell) world position 0 positionBound (by decide)
  have addressBound : chartWord position 0 < workspaceValues.length := by
    rw [valuesLength]
    exact workspaceLayout.chart_address_valid positionBound (by decide)
  have indexOperation : machine.evalOperation world
      (.index (.slice parserI32Type) parserI32Type parserI32Type)
      [workspaceValue workspaceValues workspaceCell,
        .signed .i32 (Int.ofNat (chartWord position 0))] =
      .ok (.signed .i32 (workspaceValues.get
        ⟨chartWord position 0, addressBound⟩), world) := by
    change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
      verifiedParserCore world
        (.index (.slice parserI32Type) parserI32Type parserI32Type)
        [.slice parserI32Type workspaceCell [] 0 workspaceValues.length,
          .signed .i32 (Int.ofNat (chartWord position 0))] = _
    exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_index
      workspaceFound addressBound
  have indexed := Lanius.FunctionalView.Term.evaluate_apply2 workspaceResult
    addressResult indexOperation
  have chartRead : workspaceValues.get
      ⟨chartWord position 0, addressBound⟩ = chartHeadValue workspace position := by
    have concrete := encoded.chartHead position positionBound
    rw [listWords_get workspaceValues (chartWord position 0) addressBound]
      at concrete
    exact concrete
  rw [chartRead] at indexed
  exact indexed

/-- Functional evaluation of the exact terminal transition seed projected
    from the recognizer.  Arithmetic remains in the generic read-only term
    semantics; only the source `state_seed` helper reaches the call registry. -/
private theorem stateTerminalSeedTerm_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 19)
    (production dot origin current position symbol : Nat)
    (productionEq : environment ⟨13, by omega⟩ =
      .signed .i32 (Int.ofNat production))
    (dotEq : environment ⟨14, by omega⟩ =
      .signed .i32 (Int.ofNat dot))
    (originEq : environment ⟨15, by omega⟩ =
      .signed .i32 (Int.ofNat origin))
    (currentEq : environment ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat current))
    (positionEq : environment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat position))
    (symbolEq : environment ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat symbol))
    (dotSuccBound : dot + 1 ≤ 2147483647)
    (positionBound : position ≤ 2147483647) :
    let seed := recognizerTerminalSeed production dot origin current position
      symbol
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateTerminalSeedTerm =
      .ok (stateSeedValue seed, world) := by
  dsimp only
  let seed := recognizerTerminalSeed production dot origin current position
    symbol
  let machine := stateTermMachine workspaceLayout grammar words tokens
    grammarCell tokensCell
  let calls := RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell
  have productionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨13, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat production), world) :=
    Lanius.FunctionalView.Term.evaluate_slot productionEq
  let dotSuccTerm : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 19 :=
    .apply (.binary .add parserI32Type parserI32Type parserI32Type)
      [stateSlot ⟨14, by omega⟩, stateLiteral 1]
  have dotReadOnly : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment (stateSlot ⟨14, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat dot), world) :=
    Lanius.FunctionalView.Term.evaluate_slot dotEq
  have oneReadOnly : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment (stateLiteral 1) =
      .ok (.signed .i32 1, world) := by rfl
  have dotSuccReadOnly :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_add
      (leftType := parserI32Type) (rightType := parserI32Type)
      (outputType := parserI32Type) dotReadOnly oneReadOnly dotSuccBound
  have dotSuccAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore) (calls := calls) (world := world)
      (environment := environment) dotSuccTerm (by rfl)
  have dotSuccResult : Lanius.FunctionalView.Term.evaluate machine world
      environment dotSuccTerm =
      .ok (.signed .i32 (Int.ofNat (dot + 1)), world) := by
    exact dotSuccAgreement.trans dotSuccReadOnly
  have originResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨15, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat origin), world) :=
    Lanius.FunctionalView.Term.evaluate_slot originEq
  have currentResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨12, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat current), world) :=
    Lanius.FunctionalView.Term.evaluate_slot currentEq
  let childTagTerm : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 19 :=
    .apply (.constant 38 parserI32Type) []
  have childTagReadOnly :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_constant
      (program := verifiedParserCore) (world := world)
      (environment := environment) (type := parserI32Type)
      verifiedParser_child_token_constant
  have childTagAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore) (calls := calls) (world := world)
      (environment := environment) childTagTerm (by native_decide)
  have childTagResult : Lanius.FunctionalView.Term.evaluate machine world
      environment childTagTerm = .ok (.signed .i32 1, world) :=
    childTagAgreement.trans childTagReadOnly
  let tokenIndexTerm : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 19 :=
    .apply (.binary .divide parserI32Type parserI32Type parserI32Type)
      [stateSlot ⟨11, by omega⟩, stateLiteral 2]
  have positionReadOnly : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment (stateSlot ⟨11, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat position), world) :=
    Lanius.FunctionalView.Term.evaluate_slot positionEq
  have tokenIndexReadOnly :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_divide_two
      (leftType := parserI32Type) (rightType := parserI32Type)
      (outputType := parserI32Type) positionReadOnly (by omega)
  have tokenIndexAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore) (calls := calls) (world := world)
      (environment := environment) tokenIndexTerm (by rfl)
  have tokenIndexResult : Lanius.FunctionalView.Term.evaluate machine world
      environment tokenIndexTerm =
      .ok (.signed .i32 (Int.ofNat (position / 2)), world) :=
    tokenIndexAgreement.trans tokenIndexReadOnly
  have symbolResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨17, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat symbol), world) :=
    Lanius.FunctionalView.Term.evaluate_slot symbolEq
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [stateSlot ⟨13, by omega⟩, dotSuccTerm,
        stateSlot ⟨15, by omega⟩, stateSlot ⟨12, by omega⟩,
        childTagTerm, tokenIndexTerm, stateSlot ⟨17, by omega⟩] =
      .ok (parserStateSeedArgumentsValues seed, world) := by
    simpa [seed, recognizerTerminalSeed, parserStateSeedArgumentsValues,
      previousValue, encodeStateId, childTag, childPayload, childKind] using
      Lanius.FunctionalView.evaluateTerms_cons productionResult
        (Lanius.FunctionalView.evaluateTerms_cons dotSuccResult
          (Lanius.FunctionalView.evaluateTerms_cons originResult
            (Lanius.FunctionalView.evaluateTerms_cons currentResult
              (Lanius.FunctionalView.evaluateTerms_cons childTagResult
                (Lanius.FunctionalView.evaluateTerms_cons tokenIndexResult
                  (Lanius.FunctionalView.evaluateTerms_cons symbolResult
                    (Lanius.FunctionalView.evaluateTerms_nil machine world
                      environment)))))))
  have routed := RecognizerStateCallRegistry.calls_at_traversal
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (tokens := tokens) (grammarCell := grammarCell)
    (tokensCell := tokensCell) world extractedParserStateSeedFunction.id
    (parserStateSeedArgumentsValues seed) (by native_decide)
    (by native_decide)
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell).evaluate world
      extractedParserStateSeedFunction.id
      (parserStateSeedArgumentsValues seed) = _
  rw [routed]
  exact RecognizerTraversalCallRegistry.calls_at_seed world seed

/-- Left-to-right evaluation of the exact terminal `append_state` argument
    list projected from `parser.lani::recognize`. -/
private theorem stateTerminalAppendArguments_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell workspaceCell : CellId)
    (workspace : LogicalWorkspace) (workspaceValues : List Int)
    (environment : Lanius.FunctionalView.Env 19)
    (production dot origin current position symbol nextPosition : Nat)
    (workspaceEq : environment ⟨3, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (baseEq : environment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (capacityEq : environment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat workspaceLayout.capacity))
    (stateCountEq : environment ⟨10, by omega⟩ =
      .signed .i32 (Int.ofNat workspace.states.length))
    (positionEq : environment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat position))
    (currentEq : environment ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat current))
    (productionEq : environment ⟨13, by omega⟩ =
      .signed .i32 (Int.ofNat production))
    (dotEq : environment ⟨14, by omega⟩ =
      .signed .i32 (Int.ofNat dot))
    (originEq : environment ⟨15, by omega⟩ =
      .signed .i32 (Int.ofNat origin))
    (symbolEq : environment ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat symbol))
    (nextPositionEq : environment ⟨18, by omega⟩ =
      .signed .i32 (Int.ofNat nextPosition))
    (dotSuccBound : dot + 1 ≤ 2147483647)
    (positionBound : position ≤ 2147483647) :
    let seed := recognizerTerminalSeed production dot origin current position
      symbol
    let world := stateWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell
    Lanius.FunctionalView.evaluateTerms
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateTerminalAppendArguments =
      .ok ([workspaceValue workspaceValues workspaceCell,
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
        .signed .i32 (Int.ofNat workspaceLayout.capacity),
        .signed .i32 (Int.ofNat nextPosition), stateSeedValue seed,
        .signed .i32 (Int.ofNat workspace.states.length)], world) := by
  dsimp only
  let seed := recognizerTerminalSeed production dot origin current position
    symbol
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let machine := stateTermMachine workspaceLayout grammar words tokens
    grammarCell tokensCell
  have workspaceResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨3, by omega⟩) =
      .ok (workspaceValue workspaceValues workspaceCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot workspaceEq
  have baseResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨4, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat
        (stateBase workspaceLayout.tokenCount)), world) :=
    Lanius.FunctionalView.Term.evaluate_slot baseEq
  have capacityResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨5, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat workspaceLayout.capacity), world) :=
    Lanius.FunctionalView.Term.evaluate_slot capacityEq
  have nextPositionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨18, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat nextPosition), world) :=
    Lanius.FunctionalView.Term.evaluate_slot nextPositionEq
  have seedResult : Lanius.FunctionalView.Term.evaluate machine world
      environment stateTerminalSeedTerm = .ok (stateSeedValue seed, world) := by
    exact stateTerminalSeedTerm_evaluates workspaceLayout grammar words tokens
      grammarCell tokensCell world environment production dot origin current
      position symbol productionEq dotEq originEq currentEq positionEq symbolEq
      dotSuccBound positionBound
  have stateCountResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨10, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat workspace.states.length), world) :=
    Lanius.FunctionalView.Term.evaluate_slot stateCountEq
  simpa only [stateTerminalAppendArguments] using
    Lanius.FunctionalView.evaluateTerms_cons workspaceResult
      (Lanius.FunctionalView.evaluateTerms_cons baseResult
        (Lanius.FunctionalView.evaluateTerms_cons capacityResult
          (Lanius.FunctionalView.evaluateTerms_cons nextPositionResult
            (Lanius.FunctionalView.evaluateTerms_cons seedResult
              (Lanius.FunctionalView.evaluateTerms_cons stateCountResult
                (Lanius.FunctionalView.evaluateTerms_nil machine world
                  environment))))))

/-- Functional execution of the terminal workspace append, sharing the exact
    intermediate Core argument execution with the existing recognizer proof. -/
private theorem RecognizerTerminalAppendInvariant.functional_append
    (invariant : RecognizerTerminalAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId)
    (environment : Lanius.FunctionalView.Env 19)
    (workspaceEq : environment ⟨3, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (baseEq : environment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (capacityEq : environment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat workspaceLayout.capacity))
    (stateCountEq : environment ⟨10, by omega⟩ =
      .signed .i32 (Int.ofNat workspace.states.length))
    (positionEq : environment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat position))
    (currentEq : environment ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat stateId))
    (productionEq : environment ⟨13, by omega⟩ =
      .signed .i32 (Int.ofNat production))
    (dotEq : environment ⟨14, by omega⟩ =
      .signed .i32 (Int.ofNat dot))
    (originEq : environment ⟨15, by omega⟩ =
      .signed .i32 (Int.ofNat origin))
    (symbolEq : environment ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat semanticKind))
    (nextPositionEq : environment ⟨18, by omega⟩ =
      .signed .i32 (Int.ofNat nextPosition)) :
    let seed := recognizerTerminalSeed production dot origin stateId position
      semanticKind
    let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace nextPosition
      seed workspaceValues
    let world := stateWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell
    let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
      workspaceCell
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateTerminalAppendTerm =
      .ok (appendOutcomeValue outcome, afterWorld) := by
  dsimp only
  let seed := recognizerTerminalSeed production dot origin stateId position
    semanticKind
  let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace nextPosition
    seed workspaceValues
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
    workspaceCell
  let machine := stateTermMachine workspaceLayout grammar words tokens
    grammarCell tokensCell
  let callValues : List Value := [
    workspaceValue workspaceValues workspaceCell,
    .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
    .signed .i32 (Int.ofNat workspaceLayout.capacity),
    .signed .i32 (Int.ofNat nextPosition), stateSeedValue seed,
    .signed .i32 (Int.ofNat workspace.states.length)]
  have positionI32 : position ≤ 2147483647 := by
    exact Nat.le_trans (Nat.le_add_right position 2)
      invariant.terminal.positionAdvanceI32
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment stateTerminalAppendArguments = .ok (callValues, world) := by
    change Lanius.FunctionalView.evaluateTerms
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell) world environment stateTerminalAppendArguments =
      .ok (callValues, world)
    exact stateTerminalAppendArguments_evaluates workspaceLayout grammar words
      tokens grammarCell tokensCell workspaceCell workspace workspaceValues
      environment production dot origin stateId position semanticKind nextPosition
      workspaceEq baseEq capacityEq stateCountEq positionEq currentEq
      productionEq dotEq originEq symbolEq nextPositionEq invariant.dotSuccI32
      positionI32
  let appended := invariant.evaluate_append
  have grammarDistinct := invariant.terminal.recognizer.grammarWorkspaceDistinct
  have tokensDistinct := invariant.terminal.recognizer.tokensWorkspaceDistinct
  let input : AppendStateCall.Input workspaceLayout world callValues := {
    workspace := workspace
    values := workspaceValues
    cell := workspaceCell
    position := nextPosition
    seed := seed
    valuesLength := invariant.terminal.recognizer.workspaceLength
    encoded := invariant.terminal.recognizer.workspaceEncoded
    positionBound := invariant.nextPositionBound
    seedOriginBound := invariant.originBound
    found := by
      simpa [world] using stateWorld_finds_workspace
        (words := words) (tokens := tokens) (workspaceValues := workspaceValues)
        grammarDistinct tokensDistinct
    argumentsEq := rfl
  }
  have argumentsExecution : ArgumentsEvaluateTo verifiedParserCore runtime
      (Lanius.FunctionalView.Core.toCoreExprs stateTerminalAppendLayout
        stateTerminalAppendArguments) callValues appended.argumentsState := by
    rw [stateTerminalAppendArguments_toCore]
    simpa [callValues, seed, appended] using appended.argumentsEvaluation
  have worldRepresents :
      Lanius.FunctionalView.Core.ReadOnly.World.Represents world
        appended.argumentsState := by
    simpa [world, appended] using stateWorld_represents
      appended.argumentsInvariant
  have worldOwned :
      (Lanius.FunctionalView.Core.ReadOnly.World.owns world).holds
        appended.argumentsState :=
    (Lanius.FunctionalView.Core.ReadOnly.World.owns_iff_represents
      appended.argumentsInvariant.wellFormed).2 worldRepresents
  have traversalResult :=
    RecognizerTraversalCallRegistry.calls_at_append_input
      (grammar := grammar) (words := words) (grammarCell := grammarCell)
      input runtime appended.argumentsState stateTerminalAppendLayout
      stateTerminalAppendArguments appended.argumentsInvariant.wellFormed
      worldOwned argumentsExecution
  have routed := RecognizerStateCallRegistry.calls_at_traversal
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (tokens := tokens) (grammarCell := grammarCell)
    (tokensCell := tokensCell) world extractedParserAppendStateFunction.id
    callValues (by native_decide) (by native_decide)
  have outcomeEq : input.outcome = outcome := by rfl
  have afterWorldEq : input.afterWorld = afterWorld := by
    change Lanius.FunctionalView.Core.ReadOnly.World.setI32Slice world
        workspaceCell nextValues = afterWorld
    simpa [world, afterWorld] using stateWorld_set_workspace
      (words := words) (tokens := tokens) (beforeValues := workspaceValues)
      (afterValues := nextValues) grammarDistinct tokensDistinct
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell).evaluate world
      extractedParserAppendStateFunction.id callValues =
      .ok (appendOutcomeValue outcome, afterWorld)
  rw [routed]
  rw [outcomeEq, afterWorldEq] at traversalResult
  exact traversalResult

private theorem stateTerminalFullCondition_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 19)
    (outcome : AppendOutcome) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world (environment.push (appendOutcomeValue outcome))
      stateTerminalFullCondition =
      .ok (.boolean (decide (outcome.status = .full)), world) := by
  have agreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerStateCallRegistry.calls workspaceLayout grammar words
        tokens grammarCell tokensCell) (world := world)
      (environment := environment.push (appendOutcomeValue outcome))
      stateTerminalFullCondition (by native_decide)
  have readOnlyResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world (environment.push (appendOutcomeValue outcome))
      stateTerminalFullCondition =
      .ok (.boolean (decide (outcome.status = .full)), world) := by
    rcases outcome with ⟨status, stateId, stateCount, inserted⟩
    cases status <;> rfl
  change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerStateCallRegistry.calls workspaceLayout grammar words tokens
          grammarCell tokensCell)) world
      (environment.push (appendOutcomeValue outcome))
      stateTerminalFullCondition = _
  exact agreement.trans readOnlyResult

private theorem stateTerminalStateCountTerm_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 19)
    (outcome : AppendOutcome) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world (environment.push (appendOutcomeValue outcome))
      stateTerminalStateCountTerm =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), world) := by
  have agreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerStateCallRegistry.calls workspaceLayout grammar words
        tokens grammarCell tokensCell) (world := world)
      (environment := environment.push (appendOutcomeValue outcome))
      stateTerminalStateCountTerm (by native_decide)
  have readOnlyResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world (environment.push (appendOutcomeValue outcome))
      stateTerminalStateCountTerm =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), world) := by
    rfl
  change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerStateCallRegistry.calls workspaceLayout grammar words tokens
          grammarCell tokensCell)) world
      (environment.push (appendOutcomeValue outcome))
      stateTerminalStateCountTerm = _
  exact agreement.trans readOnlyResult

private theorem stateTerminalFullResult_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 19)
    (outcome : AppendOutcome) (position : Nat)
    (positionEq : environment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat position)) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world (environment.push (appendOutcomeValue outcome))
      stateTerminalFullResult =
      .ok (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position), world) := by
  let machine := stateTermMachine workspaceLayout grammar words tokens
    grammarCell tokensCell
  let extended := environment.push (appendOutcomeValue outcome)
  have outcomeResult : Lanius.FunctionalView.Term.evaluate machine world
      extended (stateSlot ⟨19, by omega⟩) =
      .ok (appendOutcomeValue outcome, world) := by rfl
  have positionResult : Lanius.FunctionalView.Term.evaluate machine world
      extended (stateSlot ⟨11, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat position), world) := by
    apply Lanius.FunctionalView.Term.evaluate_slot
    change environment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat position)
    exact positionEq
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      extended [stateSlot ⟨19, by omega⟩, stateSlot ⟨11, by omega⟩] =
      .ok ([appendOutcomeValue outcome,
        .signed .i32 (Int.ofNat position)], world) :=
    Lanius.FunctionalView.evaluateTerms_cons outcomeResult
      (Lanius.FunctionalView.evaluateTerms_cons positionResult
        (Lanius.FunctionalView.evaluateTerms_nil machine world extended))
  have routed := RecognizerStateCallRegistry.calls_at_traversal
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (tokens := tokens) (grammarCell := grammarCell)
    (tokensCell := tokensCell) world extractedParserAppendOrFullFunction.id
    [appendOutcomeValue outcome, .signed .i32 (Int.ofNat position)]
    (by native_decide) (by native_decide)
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell).evaluate world
      extractedParserAppendOrFullFunction.id
      [appendOutcomeValue outcome, .signed .i32 (Int.ofNat position)] = _
  rw [routed]
  exact RecognizerTraversalCallRegistry.calls_at_append_or_full world outcome
    (Int.ofNat position)

/-- The successful terminal append updates the outer state-count binding and
    closes only the lexical append-result binding. -/
private theorem RecognizerTerminalAppendInvariant.functional_success_ok
    (invariant : RecognizerTerminalAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId)
    (environment : Lanius.FunctionalView.Env 19)
    (workspaceEq : environment ⟨3, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (baseEq : environment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (capacityEq : environment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat workspaceLayout.capacity))
    (stateCountEq : environment ⟨10, by omega⟩ =
      .signed .i32 (Int.ofNat workspace.states.length))
    (positionEq : environment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat position))
    (currentEq : environment ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat stateId))
    (productionEq : environment ⟨13, by omega⟩ =
      .signed .i32 (Int.ofNat production))
    (dotEq : environment ⟨14, by omega⟩ =
      .signed .i32 (Int.ofNat dot))
    (originEq : environment ⟨15, by omega⟩ =
      .signed .i32 (Int.ofNat origin))
    (symbolEq : environment ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat semanticKind))
    (nextPositionEq : environment ⟨18, by omega⟩ =
      .signed .i32 (Int.ofNat nextPosition))
    (statusOk :
      let seed := recognizerTerminalSeed production dot origin stateId position
        semanticKind
      (appendLogical workspaceLayout.capacity nextPosition seed
        workspace).1.status = .ok) :
    let seed := recognizerTerminalSeed production dot origin stateId position
      semanticKind
    let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace nextPosition
      seed workspaceValues
    let beforeWorld := stateWorld words tokens workspaceValues grammarCell
      tokensCell workspaceCell
    let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
      workspaceCell
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld environment stateTerminalSuccessCommand .next afterWorld
      (Lanius.FunctionalView.Stateful.Env.set environment ⟨10, by omega⟩
        (.signed .i32 (Int.ofNat outcome.stateCount))) := by
  dsimp only
  let seed := recognizerTerminalSeed production dot origin stateId position
    semanticKind
  let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace nextPosition
    seed workspaceValues
  let beforeWorld := stateWorld words tokens workspaceValues grammarCell
    tokensCell workspaceCell
  let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
    workspaceCell
  let resultEnvironment := environment.push (appendOutcomeValue outcome)
  have appendResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld environment stateTerminalAppendTerm =
      .ok (appendOutcomeValue outcome, afterWorld) := by
    exact invariant.functional_append environment workspaceEq baseEq capacityEq
      stateCountEq positionEq currentEq productionEq dotEq originEq symbolEq
      nextPositionEq
  have statusOk' : outcome.status = .ok := by
    simpa [outcome, seed] using statusOk
  have fullCondition : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      afterWorld resultEnvironment stateTerminalFullCondition =
      .ok (.boolean false, afterWorld) := by
    have evaluated := stateTerminalFullCondition_evaluates
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (tokens := tokens) (grammarCell := grammarCell)
      (tokensCell := tokensCell) afterWorld environment outcome
    rw [statusOk'] at evaluated
    simpa [resultEnvironment] using evaluated
  have countResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      afterWorld resultEnvironment stateTerminalStateCountTerm =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), afterWorld) := by
    simpa [resultEnvironment] using stateTerminalStateCountTerm_evaluates
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (tokens := tokens) (grammarCell := grammarCell)
      (tokensCell := tokensCell) afterWorld environment outcome
  let afterCount := Lanius.FunctionalView.Stateful.Env.set resultEnvironment
    ⟨10, by omega⟩ (.signed .i32 (Int.ofNat outcome.stateCount))
  have continuation : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      afterWorld resultEnvironment
      (.sequence
        (.ifThenElse stateTerminalFullCondition stateTerminalFullCommand .skip)
        (.sequence
          (.setLocal ⟨10, by omega⟩ stateTerminalStateCountTerm) .skip))
      .next afterWorld afterCount :=
    .sequenceNext (.ifFalse fullCondition .skip)
      (.sequenceNext (.setLocal countResult) .skip)
  rw [stateTerminalSuccessCommand_shape]
  have assembled : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld environment
      (.letValue (.structure 2) stateTerminalAppendTerm
        (.sequence
          (.ifThenElse stateTerminalFullCondition stateTerminalFullCommand
            .skip)
          (.sequence
            (.setLocal ⟨10, by omega⟩ stateTerminalStateCountTerm) .skip)))
      .next afterWorld (Lanius.FunctionalView.Stateful.Env.pop afterCount) :=
    .letValue appendResult continuation
  have popped : Lanius.FunctionalView.Stateful.Env.pop afterCount =
      Lanius.FunctionalView.Stateful.Env.set environment ⟨10, by omega⟩
        (.signed .i32 (Int.ofNat outcome.stateCount)) := by
    funext candidate
    simp [afterCount, resultEnvironment,
      Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push, Fin.ext_iff]
    rfl
  have outcomeCountEq : outcome.stateCount =
      (appendLogical workspaceLayout.capacity nextPosition seed
        workspace).2.states.length := by
    simpa [outcome] using appendLogical_stateCount_eq
      workspaceLayout.capacity nextPosition seed workspace
  rw [popped, outcomeCountEq] at assembled
  simpa [beforeWorld, afterWorld, nextValues, seed] using assembled

/-- A capacity-full terminal append returns the source diagnostic immediately;
    the state-count assignment is unreachable. -/
private theorem RecognizerTerminalAppendInvariant.functional_success_full
    (invariant : RecognizerTerminalAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId)
    (environment : Lanius.FunctionalView.Env 19)
    (workspaceEq : environment ⟨3, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (baseEq : environment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (capacityEq : environment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat workspaceLayout.capacity))
    (stateCountEq : environment ⟨10, by omega⟩ =
      .signed .i32 (Int.ofNat workspace.states.length))
    (positionEq : environment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat position))
    (currentEq : environment ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat stateId))
    (productionEq : environment ⟨13, by omega⟩ =
      .signed .i32 (Int.ofNat production))
    (dotEq : environment ⟨14, by omega⟩ =
      .signed .i32 (Int.ofNat dot))
    (originEq : environment ⟨15, by omega⟩ =
      .signed .i32 (Int.ofNat origin))
    (symbolEq : environment ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat semanticKind))
    (nextPositionEq : environment ⟨18, by omega⟩ =
      .signed .i32 (Int.ofNat nextPosition))
    (statusFull :
      let seed := recognizerTerminalSeed production dot origin stateId position
        semanticKind
      (appendLogical workspaceLayout.capacity nextPosition seed
        workspace).1.status = .full) :
    let seed := recognizerTerminalSeed production dot origin stateId position
      semanticKind
    let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace nextPosition
      seed workspaceValues
    let beforeWorld := stateWorld words tokens workspaceValues grammarCell
      tokensCell workspaceCell
    let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
      workspaceCell
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld environment stateTerminalSuccessCommand
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld environment := by
  dsimp only
  let seed := recognizerTerminalSeed production dot origin stateId position
    semanticKind
  let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace nextPosition
    seed workspaceValues
  let beforeWorld := stateWorld words tokens workspaceValues grammarCell
    tokensCell workspaceCell
  let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
    workspaceCell
  let resultEnvironment := environment.push (appendOutcomeValue outcome)
  have appendResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld environment stateTerminalAppendTerm =
      .ok (appendOutcomeValue outcome, afterWorld) := by
    exact invariant.functional_append environment workspaceEq baseEq capacityEq
      stateCountEq positionEq currentEq productionEq dotEq originEq symbolEq
      nextPositionEq
  have statusFull' : outcome.status = .full := by
    simpa [outcome, seed] using statusFull
  have fullCondition : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      afterWorld resultEnvironment stateTerminalFullCondition =
      .ok (.boolean true, afterWorld) := by
    have evaluated := stateTerminalFullCondition_evaluates
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (tokens := tokens) (grammarCell := grammarCell)
      (tokensCell := tokensCell) afterWorld environment outcome
    rw [statusFull'] at evaluated
    simpa [resultEnvironment] using evaluated
  have fullResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      afterWorld resultEnvironment stateTerminalFullResult =
      .ok (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position), afterWorld) := by
    simpa [resultEnvironment] using stateTerminalFullResult_evaluates
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (tokens := tokens) (grammarCell := grammarCell)
      (tokensCell := tokensCell) afterWorld environment outcome position
      positionEq
  have returned : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      afterWorld resultEnvironment (.returnValue (some stateTerminalFullResult))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment :=
    .returnSome fullResult
  have fullBranch : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      afterWorld resultEnvironment stateTerminalFullCommand
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment := by
    rw [stateTerminalFullCommand_shape]
    exact .sequenceStop returned (by intro impossible; cases impossible)
  have selected : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      afterWorld resultEnvironment
      (.ifThenElse stateTerminalFullCondition stateTerminalFullCommand .skip)
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment :=
    .ifTrue fullCondition fullBranch
  have continuation : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      afterWorld resultEnvironment
      (.sequence
        (.ifThenElse stateTerminalFullCondition stateTerminalFullCommand .skip)
        (.sequence
          (.setLocal ⟨10, by omega⟩ stateTerminalStateCountTerm) .skip))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment :=
    .sequenceStop selected (by intro impossible; cases impossible)
  rw [stateTerminalSuccessCommand_shape]
  have assembled : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld environment
      (.letValue (.structure 2) stateTerminalAppendTerm
        (.sequence
          (.ifThenElse stateTerminalFullCondition stateTerminalFullCommand
            .skip)
          (.sequence
            (.setLocal ⟨10, by omega⟩ stateTerminalStateCountTerm) .skip)))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop resultEnvironment) :=
    .letValue appendResult continuation
  have popped : Lanius.FunctionalView.Stateful.Env.pop resultEnvironment =
      environment := by simp [resultEnvironment]
  have outcomeCountEq : outcome.stateCount =
      (appendLogical workspaceLayout.capacity nextPosition seed
        workspace).2.states.length := by
    simpa [outcome] using appendLogical_stateCount_eq
      workspaceLayout.capacity nextPosition seed workspace
  rw [popped, outcomeCountEq] at assembled
  simpa [beforeWorld, afterWorld, nextValues, seed] using assembled

/-- Evaluate one packed-state field through the actual enclosing recognizer
    call registry.  The local slots are parameters because the same extracted
    helper appears at several lexical depths. -/
private theorem stateValueTerm_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell workspaceCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (workspaceSlot baseSlot stateSlot : Fin arity)
    (workspace : LogicalWorkspace) (state : EarleyState)
    (workspaceValues : List Int) (stateId field : Nat)
    (fieldConstant : ConstantId)
    (workspaceValueEq : environment workspaceSlot =
      workspaceValue workspaceValues workspaceCell)
    (stateBaseEq : environment baseSlot =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (stateIdEq : environment stateSlot =
      .signed .i32 (Int.ofNat stateId))
    (workspaceFound : world.i32Slice? workspaceCell = some workspaceValues)
    (valuesLength : workspaceValues.length = workspaceLayout.workspaceLength)
    (encoded : EncodesWorkspace workspaceLayout workspace
      (listWords workspaceValues))
    (foundState : workspace.state? stateId = some state)
    (fieldBound : field < stateWords)
    (constantFound : verifiedParserCore.constant? fieldConstant = some {
      id := fieldConstant
      type := parserI32Type
      value := .signed .i32 (Int.ofNat field)
    }) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment
        (stateValueTerm workspaceSlot baseSlot stateSlot fieldConstant) =
      .ok (.signed .i32 (stateFieldValue workspace stateId state field),
        world) := by
  let machine := stateTermMachine workspaceLayout grammar words tokens
    grammarCell tokensCell
  have workspaceResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (.reference (.slot workspaceSlot)) =
      .ok (workspaceValue workspaceValues workspaceCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot workspaceValueEq
  have baseResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (.reference (.slot baseSlot)) =
      .ok (.signed .i32
        (Int.ofNat (stateBase workspaceLayout.tokenCount)), world) :=
    Lanius.FunctionalView.Term.evaluate_slot stateBaseEq
  have stateResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (.reference (.slot stateSlot)) =
      .ok (.signed .i32 (Int.ofNat stateId), world) :=
    Lanius.FunctionalView.Term.evaluate_slot stateIdEq
  let constantTerm : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity :=
    .apply (.constant fieldConstant parserI32Type) []
  have constantAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerStateCallRegistry.calls workspaceLayout grammar words
        tokens grammarCell tokensCell)
      (world := world) (environment := environment) constantTerm (by rfl)
  have constantReadOnly : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment constantTerm =
      .ok (.signed .i32 (Int.ofNat field), world) :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_constant constantFound
  have constantResult : Lanius.FunctionalView.Term.evaluate machine world
      environment constantTerm =
      .ok (.signed .i32 (Int.ofNat field), world) :=
    constantAgreement.trans constantReadOnly
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [.reference (.slot workspaceSlot),
        .reference (.slot baseSlot), .reference (.slot stateSlot),
        constantTerm] =
      .ok ([workspaceValue workspaceValues workspaceCell,
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
        .signed .i32 (Int.ofNat stateId), .signed .i32 (Int.ofNat field)],
        world) :=
    Lanius.FunctionalView.evaluateTerms_cons workspaceResult
      (Lanius.FunctionalView.evaluateTerms_cons baseResult
        (Lanius.FunctionalView.evaluateTerms_cons stateResult
          (Lanius.FunctionalView.evaluateTerms_cons constantResult
            (Lanius.FunctionalView.evaluateTerms_nil machine world
              environment))))
  have addressBound : stateWord (stateBase workspaceLayout.tokenCount)
      stateId field < workspaceValues.length := by
    rw [valuesLength]
    exact encoded.state_address_valid foundState fieldBound
  have addressValue := workspaceLayout.state_value_eq_address
    (encoded.state_id_lt_capacity foundState) fieldBound
  have valueFound :
      ((workspaceValues.drop 0).take workspaceValues.length)[stateWord
        (stateBase workspaceLayout.tokenCount) stateId field]? =
      some (workspaceValues.get ⟨stateWord
        (stateBase workspaceLayout.tokenCount) stateId field,
        addressBound⟩) := by
    simpa using List.getElem?_eq_getElem addressBound
  have traversalResult :=
    RecognizerTraversalCallRegistry.calls_at_state_value
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (grammarCell := grammarCell) world workspaceValues
      workspaceCell 0 workspaceValues.length
      (stateWord (stateBase workspaceLayout.tokenCount) stateId field)
      (Int.ofNat (stateBase workspaceLayout.tokenCount)) (Int.ofNat stateId)
      (Int.ofNat field) (workspaceValues.get ⟨stateWord
        (stateBase workspaceLayout.tokenCount) stateId field, addressBound⟩)
      addressValue addressBound workspaceFound (by simp) valueFound
  have routed := RecognizerStateCallRegistry.calls_at_traversal
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (tokens := tokens) (grammarCell := grammarCell)
    (tokensCell := tokensCell) world extractedParserStateValueFunction.id
    [workspaceValue workspaceValues workspaceCell,
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
      .signed .i32 (Int.ofNat stateId), .signed .i32 (Int.ofNat field)]
    (by native_decide) (by native_decide)
  have fieldValue : workspaceValues.get ⟨stateWord
      (stateBase workspaceLayout.tokenCount) stateId field, addressBound⟩ =
      stateFieldValue workspace stateId state field := by
    have concrete := encoded.stateField stateId state foundState field fieldBound
    rw [listWords_get workspaceValues _ addressBound] at concrete
    exact concrete
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerStateCallRegistry.calls workspaceLayout grammar words tokens
    grammarCell tokensCell).evaluate world
      extractedParserStateValueFunction.id [
        workspaceValue workspaceValues workspaceCell,
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
        .signed .i32 (Int.ofNat stateId),
        .signed .i32 (Int.ofNat field)] = _
  rw [routed]
  rw [fieldValue] at traversalResult
  exact traversalResult

/-- Evaluate an extracted production-RHS length call through the enclosing
    recognizer registry. -/
private theorem stateRhsLengthTerm_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (grammarSlot productionSlot : Fin arity) (production : Nat)
    (productionBound : production < grammar.productionCount)
    (grammarValueEq : environment grammarSlot =
      parserGrammarValue words grammarCell)
    (productionValueEq : environment productionSlot =
      .signed .i32 (Int.ofNat production))
    (grammarFound : world.i32Slice? grammarCell = some words) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateRhsLengthTerm grammarSlot productionSlot) =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨production, productionBound⟩).rhs.length),
        world) := by
  let machine := stateTermMachine workspaceLayout grammar words tokens
    grammarCell tokensCell
  have grammarResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (.reference (.slot grammarSlot)) =
      .ok (parserGrammarValue words grammarCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot grammarValueEq
  have productionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (.reference (.slot productionSlot)) =
      .ok (.signed .i32 (Int.ofNat production), world) :=
    Lanius.FunctionalView.Term.evaluate_slot productionValueEq
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [.reference (.slot grammarSlot),
        .reference (.slot productionSlot)] =
      .ok ([parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production)], world) :=
    Lanius.FunctionalView.evaluateTerms_cons grammarResult
      (Lanius.FunctionalView.evaluateTerms_cons productionResult
        (Lanius.FunctionalView.evaluateTerms_nil machine world environment))
  have rowBound : production < grammar.rhsLengths.length := by simpa
  have traversalResult := RecognizerTraversalCallRegistry.calls_at_rhs_length
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (grammarCell := grammarCell) world production grammarFound
    rowBound
  have routed := RecognizerStateCallRegistry.calls_at_traversal
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (tokens := tokens) (grammarCell := grammarCell)
    (tokensCell := tokensCell) world extractedParserRhsLengthFunction.id
    [parserGrammarValue words grammarCell,
      .signed .i32 (Int.ofNat production)]
    (by native_decide) (by native_decide)
  have rowValue : grammar.rhsLengths.get ⟨production, rowBound⟩ =
      (grammar.productionAt ⟨production, productionBound⟩).rhs.length := by
    simpa using grammar.rhsLengths_get ⟨production, productionBound⟩
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerStateCallRegistry.calls workspaceLayout grammar words tokens
    grammarCell tokensCell).evaluate world
      extractedParserRhsLengthFunction.id [
        parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production)] = _
  rw [routed]
  rw [rowValue] at traversalResult
  exact traversalResult

/-- Evaluate the exact RHS-symbol call that introduces the incomplete-state
    branch's local symbol. -/
private theorem stateRhsSymbolTerm_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (grammarSlot productionSlot dotSlot : Fin arity)
    (production dot : Nat)
    (productionBound : production < grammar.productionCount)
    (dotBound : dot <
      (grammar.productionAt ⟨production, productionBound⟩).rhs.length)
    (grammarValueEq : environment grammarSlot =
      parserGrammarValue words grammarCell)
    (productionValueEq : environment productionSlot =
      .signed .i32 (Int.ofNat production))
    (dotValueEq : environment dotSlot = .signed .i32 (Int.ofNat dot))
    (grammarFound : world.i32Slice? grammarCell = some words) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment
        (stateRhsSymbolTerm grammarSlot productionSlot dotSlot) =
      .ok (.signed .i32 (Int.ofNat
        ((grammar.productionAt ⟨production, productionBound⟩).rhs.get
          ⟨dot, dotBound⟩)), world) := by
  let machine := stateTermMachine workspaceLayout grammar words tokens
    grammarCell tokensCell
  have grammarResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (.reference (.slot grammarSlot)) =
      .ok (parserGrammarValue words grammarCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot grammarValueEq
  have productionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (.reference (.slot productionSlot)) =
      .ok (.signed .i32 (Int.ofNat production), world) :=
    Lanius.FunctionalView.Term.evaluate_slot productionValueEq
  have dotResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (.reference (.slot dotSlot)) =
      .ok (.signed .i32 (Int.ofNat dot), world) :=
    Lanius.FunctionalView.Term.evaluate_slot dotValueEq
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [.reference (.slot grammarSlot),
        .reference (.slot productionSlot), .reference (.slot dotSlot)] =
      .ok ([parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production),
        .signed .i32 (Int.ofNat dot)], world) :=
    Lanius.FunctionalView.evaluateTerms_cons grammarResult
      (Lanius.FunctionalView.evaluateTerms_cons productionResult
        (Lanius.FunctionalView.evaluateTerms_cons dotResult
          (Lanius.FunctionalView.evaluateTerms_nil machine world environment)))
  have traversalResult := RecognizerTraversalCallRegistry.calls_at_rhs_symbol
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (grammarCell := grammarCell) world production dot
    grammarFound productionBound dotBound
  have routed := RecognizerStateCallRegistry.calls_at_traversal
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (tokens := tokens) (grammarCell := grammarCell)
    (tokensCell := tokensCell) world extractedParserRhsSymbolFunction.id
    [parserGrammarValue words grammarCell,
      .signed .i32 (Int.ofNat production), .signed .i32 (Int.ofNat dot)]
    (by native_decide) (by native_decide)
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerStateCallRegistry.calls workspaceLayout grammar words tokens
    grammarCell tokensCell).evaluate world
      extractedParserRhsSymbolFunction.id [
        parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production),
        .signed .i32 (Int.ofNat dot)] = _
  rw [routed]
  exact traversalResult

/-- Evaluate the terminal scanner call embedded in the projected terminal
    branch under the state-loop call registry. -/
private theorem stateScanTerminalTerm_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (grammarSlot tokensSlot tokenCountSlot positionSlot symbolSlot : Fin arity)
    (position symbol : Nat)
    (grammarValueEq : environment grammarSlot =
      parserGrammarValue words grammarCell)
    (tokensValueEq : environment tokensSlot =
      parserTokensValue tokens tokensCell)
    (tokenCountValueEq : environment tokenCountSlot =
      .signed .i32 (Int.ofNat tokens.length))
    (positionValueEq : environment positionSlot =
      .signed .i32 (Int.ofNat position))
    (symbolValueEq : environment symbolSlot =
      .signed .i32 (Int.ofNat symbol))
    (grammarFound : world.i32Slice? grammarCell = some words)
    (tokensFound : world.i32Slice? tokensCell =
      some (tokens.map Int.ofNat)) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment
        (stateScanTerminalTerm grammarSlot tokensSlot tokenCountSlot
          positionSlot symbolSlot) =
      .ok (scanTerminalValue (scanTerminal grammar tokens position symbol),
        world) := by
  let machine := stateTermMachine workspaceLayout grammar words tokens
    grammarCell tokensCell
  have grammarResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (.reference (.slot grammarSlot)) =
      .ok (parserGrammarValue words grammarCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot grammarValueEq
  have tokensResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (.reference (.slot tokensSlot)) =
      .ok (parserTokensValue tokens tokensCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot tokensValueEq
  have tokenCountResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (.reference (.slot tokenCountSlot)) =
      .ok (.signed .i32 (Int.ofNat tokens.length), world) :=
    Lanius.FunctionalView.Term.evaluate_slot tokenCountValueEq
  have positionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (.reference (.slot positionSlot)) =
      .ok (.signed .i32 (Int.ofNat position), world) :=
    Lanius.FunctionalView.Term.evaluate_slot positionValueEq
  have symbolResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (.reference (.slot symbolSlot)) =
      .ok (.signed .i32 (Int.ofNat symbol), world) :=
    Lanius.FunctionalView.Term.evaluate_slot symbolValueEq
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [.reference (.slot grammarSlot),
        .reference (.slot tokensSlot), .reference (.slot tokenCountSlot),
        .reference (.slot positionSlot), .reference (.slot symbolSlot)] =
      .ok ([parserGrammarValue words grammarCell,
        parserTokensValue tokens tokensCell,
        .signed .i32 (Int.ofNat tokens.length),
        .signed .i32 (Int.ofNat position),
        .signed .i32 (Int.ofNat symbol)], world) :=
    Lanius.FunctionalView.evaluateTerms_cons grammarResult
      (Lanius.FunctionalView.evaluateTerms_cons tokensResult
        (Lanius.FunctionalView.evaluateTerms_cons tokenCountResult
          (Lanius.FunctionalView.evaluateTerms_cons positionResult
            (Lanius.FunctionalView.evaluateTerms_cons symbolResult
              (Lanius.FunctionalView.evaluateTerms_nil machine world
                environment)))))
  have registryResult := RecognizerStateCallRegistry.calls_at_scan_terminal
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (tokens := tokens) (grammarCell := grammarCell)
    (tokensCell := tokensCell) world position symbol grammarFound tokensFound
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  exact registryResult

/-- The four candidate-field bindings at the front of the exact reified state
    body are a reusable functional scope.  Branch proofs start in the
    resulting seventeen-slot environment and this theorem closes all four
    lexical bindings afterwards. -/
theorem stateBodyCommand_evaluates_of_afterBindings
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell workspaceCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 13)
    (workspace : LogicalWorkspace) (candidate : EarleyState)
    (workspaceValues : List Int) (current : Nat)
    (productionBound : candidate.production < grammar.productionCount)
    (workspaceValueEq : environment ⟨3, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (stateBaseEq : environment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (currentEq : environment ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat current))
    (grammarValueEq : environment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell)
    (workspaceFound : world.i32Slice? workspaceCell = some workspaceValues)
    (grammarFound : world.i32Slice? grammarCell = some words)
    (valuesLength : workspaceValues.length = workspaceLayout.workspaceLength)
    (encoded : EncodesWorkspace workspaceLayout workspace
      (listWords workspaceValues))
    (foundState : workspace.state? current = some candidate)
    (branchResult : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world
      ((((environment.push
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
      world environment stateBodyCommand completion afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.pop afterEnvironment)))) := by
  let productionValue : Value :=
    .signed .i32 (Int.ofNat candidate.production)
  let dotValue : Value := .signed .i32 (Int.ofNat candidate.dot)
  let originValue : Value := .signed .i32 (Int.ofNat candidate.origin)
  let rhsLengthValue : Value := .signed .i32 (Int.ofNat
    (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)
  let afterProduction := environment.push productionValue
  let afterDot := afterProduction.push dotValue
  let afterOrigin := afterDot.push originValue
  have productionResult := stateValueTerm_evaluates workspaceLayout grammar
    words tokens grammarCell tokensCell workspaceCell world environment
    ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ workspace candidate
    workspaceValues current 0 28 workspaceValueEq stateBaseEq
    currentEq workspaceFound valuesLength encoded foundState
    (by decide) verifiedParser_find_constants.2.1
  have productionResult' : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell) world environment
      (stateValueTerm ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ 28) =
      .ok (productionValue, world) := by
    simpa [productionValue, stateFieldValue] using productionResult
  have workspaceAfterProduction : afterProduction ⟨3, by omega⟩ =
      workspaceValue workspaceValues workspaceCell := by
    calc
      afterProduction ⟨3, by omega⟩ = environment ⟨3, by omega⟩ := by
        simpa [afterProduction] using
          Lanius.FunctionalView.Env.push_before environment productionValue
            (⟨3, by omega⟩ : Fin 13)
      _ = workspaceValue workspaceValues workspaceCell := workspaceValueEq
  have baseAfterProduction : afterProduction ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)) := by
    calc
      afterProduction ⟨4, by omega⟩ = environment ⟨4, by omega⟩ := by
        simpa [afterProduction] using
          Lanius.FunctionalView.Env.push_before environment productionValue
            (⟨4, by omega⟩ : Fin 13)
      _ = .signed .i32
          (Int.ofNat (stateBase workspaceLayout.tokenCount)) := stateBaseEq
  have currentAfterProduction : afterProduction ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat current) := by
    calc
      afterProduction ⟨12, by omega⟩ = environment ⟨12, by omega⟩ := by
        simpa [afterProduction] using
          Lanius.FunctionalView.Env.push_before environment productionValue
            (⟨12, by omega⟩ : Fin 13)
      _ = .signed .i32 (Int.ofNat current) := currentEq
  have dotResult := stateValueTerm_evaluates workspaceLayout grammar words tokens
    grammarCell tokensCell workspaceCell world afterProduction
    ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ workspace candidate
    workspaceValues current 1 29 workspaceAfterProduction baseAfterProduction
    currentAfterProduction workspaceFound
    valuesLength encoded foundState (by decide)
    verifiedParser_find_constants.2.2.1
  have dotResult' : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell) world afterProduction
      (stateValueTerm ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ 29) =
      .ok (dotValue, world) := by
    simpa [dotValue, stateFieldValue] using dotResult
  have workspaceAfterDot : afterDot ⟨3, by omega⟩ =
      workspaceValue workspaceValues workspaceCell := by
    calc
      afterDot ⟨3, by omega⟩ = afterProduction ⟨3, by omega⟩ := by
        simpa [afterDot] using
          Lanius.FunctionalView.Env.push_before afterProduction dotValue
            (⟨3, by omega⟩ : Fin 14)
      _ = workspaceValue workspaceValues workspaceCell :=
        workspaceAfterProduction
  have baseAfterDot : afterDot ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)) := by
    calc
      afterDot ⟨4, by omega⟩ = afterProduction ⟨4, by omega⟩ := by
        simpa [afterDot] using
          Lanius.FunctionalView.Env.push_before afterProduction dotValue
            (⟨4, by omega⟩ : Fin 14)
      _ = .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)) :=
        baseAfterProduction
  have currentAfterDot : afterDot ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat current) := by
    calc
      afterDot ⟨12, by omega⟩ = afterProduction ⟨12, by omega⟩ := by
        simpa [afterDot] using
          Lanius.FunctionalView.Env.push_before afterProduction dotValue
            (⟨12, by omega⟩ : Fin 14)
      _ = .signed .i32 (Int.ofNat current) := currentAfterProduction
  have originResult := stateValueTerm_evaluates workspaceLayout grammar words
    tokens grammarCell tokensCell workspaceCell world afterDot
    ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ workspace candidate
    workspaceValues current 2 30 workspaceAfterDot baseAfterDot currentAfterDot
    workspaceFound valuesLength encoded foundState
    (by decide) verifiedParser_find_constants.2.2.2.1
  have originResult' : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell) world afterDot
      (stateValueTerm ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ 30) =
      .ok (originValue, world) := by
    simpa [originValue, stateFieldValue] using originResult
  have grammarAfterProduction : afterProduction ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell := by
    calc
      afterProduction ⟨0, by omega⟩ = environment ⟨0, by omega⟩ := by
        simpa [afterProduction] using
          Lanius.FunctionalView.Env.push_before environment productionValue
            (⟨0, by omega⟩ : Fin 13)
      _ = parserGrammarValue words grammarCell := grammarValueEq
  have grammarAfterDot : afterDot ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell := by
    calc
      afterDot ⟨0, by omega⟩ = afterProduction ⟨0, by omega⟩ := by
        simpa [afterDot] using
          Lanius.FunctionalView.Env.push_before afterProduction dotValue
            (⟨0, by omega⟩ : Fin 14)
      _ = parserGrammarValue words grammarCell := grammarAfterProduction
  have grammarAfterOrigin : afterOrigin ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell := by
    calc
      afterOrigin ⟨0, by omega⟩ = afterDot ⟨0, by omega⟩ := by
        simpa [afterOrigin] using
          Lanius.FunctionalView.Env.push_before afterDot originValue
            (⟨0, by omega⟩ : Fin 15)
      _ = parserGrammarValue words grammarCell := grammarAfterDot
  have productionAfterProduction : afterProduction ⟨13, by omega⟩ =
      productionValue := by
    simpa [afterProduction] using
      Lanius.FunctionalView.Env.push_last environment productionValue
  have productionAfterDot : afterDot ⟨13, by omega⟩ = productionValue := by
    calc
      afterDot ⟨13, by omega⟩ = afterProduction ⟨13, by omega⟩ := by
        simpa [afterDot] using
          Lanius.FunctionalView.Env.push_before afterProduction dotValue
            (⟨13, by omega⟩ : Fin 14)
      _ = productionValue := productionAfterProduction
  have productionAfterOrigin : afterOrigin ⟨13, by omega⟩ =
      .signed .i32 (Int.ofNat candidate.production) := by
    calc
      afterOrigin ⟨13, by omega⟩ = afterDot ⟨13, by omega⟩ := by
        simpa [afterOrigin] using
          Lanius.FunctionalView.Env.push_before afterDot originValue
            (⟨13, by omega⟩ : Fin 15)
      _ = productionValue := productionAfterDot
      _ = .signed .i32 (Int.ofNat candidate.production) := by
        rfl
  have rhsResult := stateRhsLengthTerm_evaluates workspaceLayout grammar words
    tokens grammarCell tokensCell world afterOrigin ⟨0, by omega⟩
    ⟨13, by omega⟩ candidate.production productionBound grammarAfterOrigin
    productionAfterOrigin grammarFound
  rw [stateBodyCommand_shape]
  exact .letValue productionResult'
    (.letValue (by simpa [afterProduction, productionValue] using dotResult')
      (.letValue (by
        simpa [afterDot, afterProduction, productionValue, dotValue] using
          originResult')
        (.letValue (by
          simpa [afterOrigin, afterDot, afterProduction, productionValue,
            dotValue, originValue] using rhsResult) (by
              simpa [afterOrigin, afterDot, afterProduction, productionValue,
                dotValue, originValue, rhsLengthValue] using branchResult))))

theorem stateLessTerm_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (left right : Fin arity) (leftValue rightValue : Nat)
    (leftEq : environment left = .signed .i32 (Int.ofNat leftValue))
    (rightEq : environment right = .signed .i32 (Int.ofNat rightValue)) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateLessTerm left right) =
      .ok (.boolean (decide (leftValue < rightValue)), world) := by
  have leftResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (.reference (.slot left)) =
      .ok (.signed .i32 (Int.ofNat leftValue), world) :=
    Lanius.FunctionalView.Term.evaluate_slot leftEq
  have rightResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (.reference (.slot right)) =
      .ok (.signed .i32 (Int.ofNat rightValue), world) :=
    Lanius.FunctionalView.Term.evaluate_slot rightEq
  apply Lanius.FunctionalView.Term.evaluate_apply2 leftResult rightResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedParserCore world
      (.binary .less parserI32Type parserI32Type (.scalar .bool))
      [.signed .i32 (Int.ofNat leftValue),
        .signed .i32 (Int.ofNat rightValue)] = _
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_less
    leftValue rightValue

private theorem stateGreaterEqualZeroTerm_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (slot : Fin arity) (value : Int)
    (valueEq : environment slot = .signed .i32 value) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateGreaterEqualZeroTerm slot) =
      .ok (.boolean (decide (value ≥ 0)), world) := by
  have valueResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (.reference (.slot slot)) =
      .ok (.signed .i32 value, world) :=
    Lanius.FunctionalView.Term.evaluate_slot valueEq
  have zeroResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (.reference (.literal (.signed .i32 0))) =
      .ok (.signed .i32 0, world) := by
    rfl
  apply Lanius.FunctionalView.Term.evaluate_apply2 valueResult zeroResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedParserCore world
      (.binary .greaterEqual parserI32Type parserI32Type (.scalar .bool))
      [.signed .i32 value, .signed .i32 0] = _
  exact
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_greaterEqual_int
      value 0

/-- A failed scan executes the exact terminal branch without entering the
    append path. -/
theorem stateTerminalCommand_evaluates_miss
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 18)
    (position symbol : Nat)
    (grammarValueEq : environment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell)
    (tokensValueEq : environment ⟨1, by omega⟩ =
      parserTokensValue tokens tokensCell)
    (tokenCountValueEq : environment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat tokens.length))
    (positionValueEq : environment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat position))
    (symbolValueEq : environment ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat symbol))
    (grammarFound : world.i32Slice? grammarCell = some words)
    (tokensFound : world.i32Slice? tokensCell =
      some (tokens.map Int.ofNat))
    (scanMiss : scanTerminal grammar tokens position symbol = none) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateTerminalCommand .next world environment := by
  have scanResult := stateScanTerminalTerm_evaluates workspaceLayout grammar
    words tokens grammarCell tokensCell world environment ⟨0, by omega⟩
    ⟨1, by omega⟩ ⟨2, by omega⟩ ⟨11, by omega⟩ ⟨17, by omega⟩
    position symbol grammarValueEq tokensValueEq tokenCountValueEq
    positionValueEq symbolValueEq grammarFound tokensFound
  rw [scanMiss] at scanResult
  let afterScan := environment.push (.signed .i32 (-1))
  have scanLocal : afterScan ⟨18, by omega⟩ = .signed .i32 (-1) := by
    simpa [afterScan] using Lanius.FunctionalView.Env.push_last environment
      (.signed .i32 (-1))
  have conditionResult := stateGreaterEqualZeroTerm_evaluates workspaceLayout
    grammar words tokens grammarCell tokensCell world afterScan
    ⟨18, by omega⟩ (-1) scanLocal
  have conditionFalse : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world afterScan (stateGreaterEqualZeroTerm ⟨18, by omega⟩) =
      .ok (.boolean false, world) := by
    simpa using conditionResult
  have selected : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world afterScan
      (.ifThenElse (stateGreaterEqualZeroTerm ⟨18, by omega⟩)
        stateTerminalSuccessCommand .skip)
      .next world afterScan := .ifFalse conditionFalse .skip
  rw [stateTerminalCommand_shape]
  simpa [afterScan, scanTerminalValue] using
    Lanius.FunctionalView.Stateful.Command.Evaluates.letValue scanResult
      (functionalSequenceSkip selected)

/-- A successful scan enters the projected append path, while this theorem
    handles scanner evaluation, local binding, control selection, and scope
    closure. -/
private theorem stateTerminalCommand_evaluates_success
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 18)
    (position symbol nextPosition : Nat)
    (grammarValueEq : environment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell)
    (tokensValueEq : environment ⟨1, by omega⟩ =
      parserTokensValue tokens tokensCell)
    (tokenCountValueEq : environment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat tokens.length))
    (positionValueEq : environment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat position))
    (symbolValueEq : environment ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat symbol))
    (grammarFound : world.i32Slice? grammarCell = some words)
    (tokensFound : world.i32Slice? tokensCell =
      some (tokens.map Int.ofNat))
    (scanSuccess : scanTerminal grammar tokens position symbol =
      some nextPosition)
    (branchResult : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world (environment.push (.signed .i32 (Int.ofNat nextPosition)))
      stateTerminalSuccessCommand completion branchWorld branchEnvironment) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateTerminalCommand completion branchWorld
      (Lanius.FunctionalView.Stateful.Env.pop branchEnvironment) := by
  have scanResult := stateScanTerminalTerm_evaluates workspaceLayout grammar
    words tokens grammarCell tokensCell world environment ⟨0, by omega⟩
    ⟨1, by omega⟩ ⟨2, by omega⟩ ⟨11, by omega⟩ ⟨17, by omega⟩
    position symbol grammarValueEq tokensValueEq tokenCountValueEq
    positionValueEq symbolValueEq grammarFound tokensFound
  rw [scanSuccess] at scanResult
  let afterScan := environment.push
    (.signed .i32 (Int.ofNat nextPosition))
  have scanLocal : afterScan ⟨18, by omega⟩ =
      .signed .i32 (Int.ofNat nextPosition) := by
    simpa [afterScan] using Lanius.FunctionalView.Env.push_last environment
      (.signed .i32 (Int.ofNat nextPosition))
  have conditionResult := stateGreaterEqualZeroTerm_evaluates workspaceLayout
    grammar words tokens grammarCell tokensCell world afterScan
    ⟨18, by omega⟩ (Int.ofNat nextPosition) scanLocal
  have conditionTrue : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world afterScan (stateGreaterEqualZeroTerm ⟨18, by omega⟩) =
      .ok (.boolean true, world) := by
    simpa using conditionResult
  have selected : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world afterScan
      (.ifThenElse (stateGreaterEqualZeroTerm ⟨18, by omega⟩)
        stateTerminalSuccessCommand .skip)
      completion branchWorld branchEnvironment :=
    .ifTrue conditionTrue (by simpa [afterScan] using branchResult)
  rw [stateTerminalCommand_shape]
  simpa [scanTerminalValue] using
    Lanius.FunctionalView.Stateful.Command.Evaluates.letValue scanResult
      (functionalSequenceSkip selected)

/-- The complete terminal command on a successful, non-full append.  Scanner
    evaluation, append mutation, capacity control, and lexical scope closure
    are all discharged here. -/
theorem RecognizerTerminalAppendInvariant.functional_terminal_ok
    (invariant : RecognizerTerminalAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId)
    (environment : Lanius.FunctionalView.Env 18)
    (grammarEq : environment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell)
    (tokensEq : environment ⟨1, by omega⟩ =
      parserTokensValue tokens tokensCell)
    (tokenCountEq : environment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat tokens.length))
    (workspaceEq : environment ⟨3, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (baseEq : environment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (capacityEq : environment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat workspaceLayout.capacity))
    (stateCountEq : environment ⟨10, by omega⟩ =
      .signed .i32 (Int.ofNat workspace.states.length))
    (positionEq : environment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat position))
    (currentEq : environment ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat stateId))
    (productionEq : environment ⟨13, by omega⟩ =
      .signed .i32 (Int.ofNat production))
    (dotEq : environment ⟨14, by omega⟩ =
      .signed .i32 (Int.ofNat dot))
    (originEq : environment ⟨15, by omega⟩ =
      .signed .i32 (Int.ofNat origin))
    (symbolEq : environment ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat semanticKind))
    (statusOk :
      let seed := recognizerTerminalSeed production dot origin stateId position
        semanticKind
      (appendLogical workspaceLayout.capacity nextPosition seed
        workspace).1.status = .ok) :
    let seed := recognizerTerminalSeed production dot origin stateId position
      semanticKind
    let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace nextPosition
      seed workspaceValues
    let beforeWorld := stateWorld words tokens workspaceValues grammarCell
      tokensCell workspaceCell
    let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
      workspaceCell
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld environment stateTerminalCommand .next afterWorld
      (Lanius.FunctionalView.Stateful.Env.set environment ⟨10, by omega⟩
        (.signed .i32 (Int.ofNat outcome.stateCount))) := by
  dsimp only
  let seed := recognizerTerminalSeed production dot origin stateId position
    semanticKind
  let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace nextPosition
    seed workspaceValues
  let beforeWorld := stateWorld words tokens workspaceValues grammarCell
    tokensCell workspaceCell
  let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
    workspaceCell
  let afterScan := environment.push
    (.signed .i32 (Int.ofNat nextPosition))
  have lift (index : Fin 18) (value : Value)
      (found : environment index = value) :
      afterScan ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩ = value := by
    calc
      afterScan ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩ =
          environment index := by
        exact Lanius.FunctionalView.Env.push_before environment
          (.signed .i32 (Int.ofNat nextPosition)) index
      _ = value := found
  have scanLocal : afterScan ⟨18, by omega⟩ =
      .signed .i32 (Int.ofNat nextPosition) := by
    simpa [afterScan] using Lanius.FunctionalView.Env.push_last environment
      (.signed .i32 (Int.ofNat nextPosition))
  have branchResult := invariant.functional_success_ok afterScan
    (lift ⟨3, by omega⟩ _ workspaceEq) (lift ⟨4, by omega⟩ _ baseEq)
    (lift ⟨5, by omega⟩ _ capacityEq)
    (lift ⟨10, by omega⟩ _ stateCountEq)
    (lift ⟨11, by omega⟩ _ positionEq)
    (lift ⟨12, by omega⟩ _ currentEq)
    (lift ⟨13, by omega⟩ _ productionEq)
    (lift ⟨14, by omega⟩ _ dotEq)
    (lift ⟨15, by omega⟩ _ originEq)
    (lift ⟨17, by omega⟩ _ symbolEq) scanLocal statusOk
  have evaluated := stateTerminalCommand_evaluates_success workspaceLayout
    grammar words tokens grammarCell tokensCell beforeWorld environment position
    semanticKind nextPosition grammarEq tokensEq tokenCountEq positionEq
    symbolEq stateWorld_finds_grammar
    (stateWorld_finds_tokens invariant.terminal.recognizer)
    invariant.scanResult branchResult
  have environmentResult :
      Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.set afterScan ⟨10, by omega⟩
          (.signed .i32 (Int.ofNat outcome.stateCount))) =
      Lanius.FunctionalView.Stateful.Env.set environment ⟨10, by omega⟩
        (.signed .i32 (Int.ofNat outcome.stateCount)) := by
    funext candidate
    simp [afterScan, Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push, Fin.ext_iff]
    rfl
  rw [environmentResult] at evaluated
  simpa [beforeWorld, afterWorld, nextValues, seed, outcome] using evaluated

/-- The complete terminal command on a capacity-full append. -/
theorem RecognizerTerminalAppendInvariant.functional_terminal_full
    (invariant : RecognizerTerminalAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId)
    (environment : Lanius.FunctionalView.Env 18)
    (grammarEq : environment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell)
    (tokensEq : environment ⟨1, by omega⟩ =
      parserTokensValue tokens tokensCell)
    (tokenCountEq : environment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat tokens.length))
    (workspaceEq : environment ⟨3, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (baseEq : environment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (capacityEq : environment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat workspaceLayout.capacity))
    (stateCountEq : environment ⟨10, by omega⟩ =
      .signed .i32 (Int.ofNat workspace.states.length))
    (positionEq : environment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat position))
    (currentEq : environment ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat stateId))
    (productionEq : environment ⟨13, by omega⟩ =
      .signed .i32 (Int.ofNat production))
    (dotEq : environment ⟨14, by omega⟩ =
      .signed .i32 (Int.ofNat dot))
    (originEq : environment ⟨15, by omega⟩ =
      .signed .i32 (Int.ofNat origin))
    (symbolEq : environment ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat semanticKind))
    (statusFull :
      let seed := recognizerTerminalSeed production dot origin stateId position
        semanticKind
      (appendLogical workspaceLayout.capacity nextPosition seed
        workspace).1.status = .full) :
    let seed := recognizerTerminalSeed production dot origin stateId position
      semanticKind
    let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace nextPosition
      seed workspaceValues
    let beforeWorld := stateWorld words tokens workspaceValues grammarCell
      tokensCell workspaceCell
    let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
      workspaceCell
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld environment stateTerminalCommand
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld environment := by
  dsimp only
  let seed := recognizerTerminalSeed production dot origin stateId position
    semanticKind
  let outcome := (appendLogical workspaceLayout.capacity nextPosition seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace nextPosition
    seed workspaceValues
  let beforeWorld := stateWorld words tokens workspaceValues grammarCell
    tokensCell workspaceCell
  let afterWorld := stateWorld words tokens nextValues grammarCell tokensCell
    workspaceCell
  let afterScan := environment.push
    (.signed .i32 (Int.ofNat nextPosition))
  have lift (index : Fin 18) (value : Value)
      (found : environment index = value) :
      afterScan ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩ = value := by
    calc
      afterScan ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩ =
          environment index := by
        exact Lanius.FunctionalView.Env.push_before environment
          (.signed .i32 (Int.ofNat nextPosition)) index
      _ = value := found
  have scanLocal : afterScan ⟨18, by omega⟩ =
      .signed .i32 (Int.ofNat nextPosition) := by
    simpa [afterScan] using Lanius.FunctionalView.Env.push_last environment
      (.signed .i32 (Int.ofNat nextPosition))
  have branchResult := invariant.functional_success_full afterScan
    (lift ⟨3, by omega⟩ _ workspaceEq) (lift ⟨4, by omega⟩ _ baseEq)
    (lift ⟨5, by omega⟩ _ capacityEq)
    (lift ⟨10, by omega⟩ _ stateCountEq)
    (lift ⟨11, by omega⟩ _ positionEq)
    (lift ⟨12, by omega⟩ _ currentEq)
    (lift ⟨13, by omega⟩ _ productionEq)
    (lift ⟨14, by omega⟩ _ dotEq)
    (lift ⟨15, by omega⟩ _ originEq)
    (lift ⟨17, by omega⟩ _ symbolEq) scanLocal statusFull
  have evaluated := stateTerminalCommand_evaluates_success workspaceLayout
    grammar words tokens grammarCell tokensCell beforeWorld environment position
    semanticKind nextPosition grammarEq tokensEq tokenCountEq positionEq
    symbolEq stateWorld_finds_grammar
    (stateWorld_finds_tokens invariant.terminal.recognizer)
    invariant.scanResult branchResult
  simpa [afterScan, beforeWorld, afterWorld, nextValues, seed, outcome] using
    evaluated

/-- Execute the exact incomplete-state command once its selected semantic
    branch has been proved.  This theorem performs the source-derived RHS
    lookup, binds local `29`, selects terminal versus nonterminal, and closes
    that lexical scope. -/
theorem stateIncompleteCommand_evaluates_of_symbol
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 17)
    (production dot symbol : Nat)
    (productionBound : production < grammar.productionCount)
    (dotBound : dot <
      (grammar.productionAt ⟨production, productionBound⟩).rhs.length)
    (symbolEq : symbol =
      (grammar.productionAt ⟨production, productionBound⟩).rhs.get
        ⟨dot, dotBound⟩)
    (kindCount : Nat)
    (grammarValueEq : environment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell)
    (productionValueEq : environment ⟨13, by omega⟩ =
      .signed .i32 (Int.ofNat production))
    (dotValueEq : environment ⟨14, by omega⟩ =
      .signed .i32 (Int.ofNat dot))
    (kindCountEq : environment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat kindCount))
    (grammarFound : world.i32Slice? grammarCell = some words)
    (terminal : Bool)
    (terminalEq : decide (symbol < kindCount) = terminal)
    (branchResult : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world (environment.push (.signed .i32 (Int.ofNat symbol)))
      (if terminal then stateTerminalCommand else stateNonterminalCommand)
      completion branchWorld branchEnvironment) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateIncompleteCommand completion branchWorld
      (Lanius.FunctionalView.Stateful.Env.pop branchEnvironment) := by
  have symbolResult' := stateRhsSymbolTerm_evaluates workspaceLayout grammar
    words tokens grammarCell tokensCell world environment ⟨0, by omega⟩
    ⟨13, by omega⟩ ⟨14, by omega⟩ production dot productionBound
    dotBound grammarValueEq productionValueEq dotValueEq grammarFound
  have symbolResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment
        (stateRhsSymbolTerm ⟨0, by omega⟩ ⟨13, by omega⟩
          ⟨14, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat symbol), world) := by
    simpa [symbolEq] using symbolResult'
  let afterSymbol := environment.push (.signed .i32 (Int.ofNat symbol))
  have symbolLocal : afterSymbol ⟨17, by omega⟩ =
      .signed .i32 (Int.ofNat symbol) := by
    simpa [afterSymbol] using Lanius.FunctionalView.Env.push_last environment
      (.signed .i32 (Int.ofNat symbol))
  have kindCountLocal : afterSymbol ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat kindCount) := by
    calc
      afterSymbol ⟨6, by omega⟩ = environment ⟨6, by omega⟩ := by
        simpa [afterSymbol] using
          Lanius.FunctionalView.Env.push_before environment
            (.signed .i32 (Int.ofNat symbol)) (⟨6, by omega⟩ : Fin 17)
      _ = .signed .i32 (Int.ofNat kindCount) := kindCountEq
  have conditionResult := stateLessTerm_evaluates workspaceLayout grammar words
    tokens grammarCell tokensCell world afterSymbol ⟨17, by omega⟩
    ⟨6, by omega⟩ symbol kindCount symbolLocal kindCountLocal
  rw [terminalEq] at conditionResult
  rw [stateIncompleteCommand_shape]
  cases terminal with
  | false =>
      have selected : Lanius.FunctionalView.Stateful.Command.Evaluates
          (stateTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          world afterSymbol
          (.ifThenElse (stateLessTerm ⟨17, by omega⟩ ⟨6, by omega⟩)
            stateTerminalCommand stateNonterminalCommand)
          completion branchWorld branchEnvironment :=
        .ifFalse conditionResult (by simpa [afterSymbol] using branchResult)
      exact .letValue symbolResult (functionalSequenceSkip selected)
  | true =>
      have selected : Lanius.FunctionalView.Stateful.Command.Evaluates
          (stateTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          world afterSymbol
          (.ifThenElse (stateLessTerm ⟨17, by omega⟩ ⟨6, by omega⟩)
            stateTerminalCommand stateNonterminalCommand)
          completion branchWorld branchEnvironment :=
        .ifTrue conditionResult (by simpa [afterSymbol] using branchResult)
      exact .letValue symbolResult (functionalSequenceSkip selected)

/-- Compose the projected incomplete branch and cursor advance when the
    decoded state has another RHS symbol. -/
private theorem stateAfterBindingsCommand_evaluates_incomplete
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 17)
    (dot rhsLength : Nat)
    (dotEq : environment ⟨14, by omega⟩ =
      .signed .i32 (Int.ofNat dot))
    (rhsLengthEq : environment ⟨16, by omega⟩ =
      .signed .i32 (Int.ofNat rhsLength))
    (incomplete : dot < rhsLength)
    (branchResult : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateIncompleteCommand .next branchWorld
      branchEnvironment)
    (advanceResult : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      branchWorld branchEnvironment stateAdvanceCommand completion afterWorld
      afterEnvironment) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateAfterBindingsCommand completion afterWorld
      afterEnvironment := by
  have conditionResult := stateLessTerm_evaluates workspaceLayout grammar words
    tokens grammarCell tokensCell world environment ⟨14, by omega⟩
    ⟨16, by omega⟩ dot rhsLength dotEq rhsLengthEq
  have conditionTrue : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateLessTerm ⟨14, by omega⟩ ⟨16, by omega⟩) =
      .ok (.boolean true, world) := by
    simpa [incomplete] using conditionResult
  rw [stateAfterBindingsCommand_shape]
  exact .sequenceNext (.ifTrue conditionTrue branchResult) advanceResult

/-- Compose the projected completed-state branch and cursor advance. -/
private theorem stateAfterBindingsCommand_evaluates_complete
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 17)
    (dot rhsLength : Nat)
    (dotEq : environment ⟨14, by omega⟩ =
      .signed .i32 (Int.ofNat dot))
    (rhsLengthEq : environment ⟨16, by omega⟩ =
      .signed .i32 (Int.ofNat rhsLength))
    (complete : ¬ dot < rhsLength)
    (branchResult : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateCompleteCommand .next branchWorld
      branchEnvironment)
    (advanceResult : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      branchWorld branchEnvironment stateAdvanceCommand completion afterWorld
      afterEnvironment) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateAfterBindingsCommand completion afterWorld
      afterEnvironment := by
  have conditionResult := stateLessTerm_evaluates workspaceLayout grammar words
    tokens grammarCell tokensCell world environment ⟨14, by omega⟩
    ⟨16, by omega⟩ dot rhsLength dotEq rhsLengthEq
  have conditionFalse : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateLessTerm ⟨14, by omega⟩ ⟨16, by omega⟩) =
      .ok (.boolean false, world) := by
    simpa [complete] using conditionResult
  rw [stateAfterBindingsCommand_shape]
  exact .sequenceNext (.ifFalse conditionFalse branchResult) advanceResult

theorem stateLoopCondition_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat) (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 13) (current : Int)
    (currentEq : environment ⟨12, by omega⟩ = .signed .i32 current) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment stateLoopCondition =
      .ok (.boolean (decide (current ≥ 0)), world) := by
  have currentResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateSlot ⟨12, by omega⟩) =
      .ok (.signed .i32 current, world) :=
    Lanius.FunctionalView.Term.evaluate_slot currentEq
  have zeroResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateLiteral 0) =
      .ok (.signed .i32 0, world) := by
    rfl
  apply Lanius.FunctionalView.Term.evaluate_apply2 currentResult zeroResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedParserCore world
      (.binary .greaterEqual parserI32Type parserI32Type (.scalar .bool))
      [.signed .i32 current, .signed .i32 0] = _
  exact
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_greaterEqual_int
      current 0

theorem positionLoopCondition_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat) (grammarCell tokensCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 15) (position finalPosition : Nat)
    (positionEq : environment ⟨14, by omega⟩ =
      .signed .i32 (Int.ofNat position))
    (finalPositionEq : environment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat finalPosition)) :
    Lanius.FunctionalView.Term.evaluate
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment positionLoopCondition =
      .ok (.boolean (decide (position ≤ finalPosition)), world) := by
  have positionResult : Lanius.FunctionalView.Term.evaluate
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (.reference (.slot ⟨14, by omega⟩)) =
      .ok (.signed .i32 (Int.ofNat position), world) :=
    Lanius.FunctionalView.Term.evaluate_slot positionEq
  have finalResult : Lanius.FunctionalView.Term.evaluate
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (.reference (.slot ⟨4, by omega⟩)) =
      .ok (.signed .i32 (Int.ofNat finalPosition), world) :=
    Lanius.FunctionalView.Term.evaluate_slot finalPositionEq
  apply Lanius.FunctionalView.Term.evaluate_apply2 positionResult finalResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedParserCore world
      (.binary .lessEqual parserI32Type parserI32Type (.scalar .bool))
      [.signed .i32 (Int.ofNat position),
        .signed .i32 (Int.ofNat finalPosition)] = _
  simp [Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
    evalBinaryValue, evalSignedBinary, bind, Except.bind]
  rfl

theorem positionActivityCondition_evaluates
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (stateCount furthest position : Nat)
    (workspaceFound :
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell).i32Slice? workspaceCell = some workspaceValues)
    (valuesLength : workspaceValues.length = workspaceLayout.workspaceLength)
    (encoded : EncodesWorkspace workspaceLayout workspace
      (listWords workspaceValues))
    (positionBound : position ≤ finalPosition workspaceLayout.tokenCount) :
    Lanius.FunctionalView.Term.evaluate
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      (positionEnvironment words tokens workspaceValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar grammarLayout
        stateCount furthest position)
      positionActivityCondition =
      .ok (.boolean (decide (chartHeadValue workspace position ≥ 0)),
        stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell) := by
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let environment := positionEnvironment words tokens workspaceValues grammarCell
    tokensCell workspaceCell workspaceLayout grammar grammarLayout
    stateCount furthest position
  have headResult := stateChartHeadTerm_evaluates workspaceLayout grammar words
    tokens grammarCell tokensCell workspaceCell world environment
    ⟨3, by omega⟩ ⟨14, by omega⟩ workspace workspaceValues position
    (by rfl) (by rfl)
    workspaceFound valuesLength encoded positionBound
  have zeroResult : Lanius.FunctionalView.Term.evaluate
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateLiteral 0) =
      .ok (.signed .i32 0, world) := by
    rfl
  apply Lanius.FunctionalView.Term.evaluate_apply2 headResult zeroResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedParserCore world
      (.binary .greaterEqual parserI32Type parserI32Type (.scalar .bool))
      [.signed .i32 (chartHeadValue workspace position), .signed .i32 0] = _
  exact
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_greaterEqual_int
      (chartHeadValue workspace position) 0

theorem extractedParserRecognize_state_body_shape :
    parserRecognizeStateLoopBody =
      .letLocal 25 parserI32Type (parserRecognizeStateValueCall 24 28)
        (.letLocal 26 parserI32Type (parserRecognizeStateValueCall 24 29)
          (.letLocal 27 parserI32Type (parserRecognizeStateValueCall 24 30)
            (.letLocal 28 parserI32Type
              (.call extractedParserRhsLengthFunction.id [.local 0, .local 25])
              parserRecognizeStateAfterBindings))) := by
  rfl

/-- The branch projected from the reified body is exactly the corresponding
    branch of the checked Core recognizer. -/
private theorem stateAfterBindingsCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      stateAfterBindingsLayout 29 stateAfterBindingsCommand =
      parserRecognizeStateAfterBindings := by
  have whole := parserRecognizeStateBodyView_toCore_exactly
  change Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
    stateLoopLayout 25 stateBodyCommand = parserRecognizeStateLoopBody at whole
  rw [stateBodyCommand_shape, extractedParserRecognize_state_body_shape] at whole
  have projected := congrArg coreAfterFourBindings whole
  simp only [Lanius.FunctionalView.Core.Stateful.toCoreStmt,
    coreAfterFourBindings] at projected
  exact projected

private def coreIncompleteProjection : Stmt → Stmt
  | .sequence (.ifThenElse _ incomplete _) _ => incomplete
  | _ => .skip

private def coreCompleteProjection : Stmt → Stmt
  | .sequence (.ifThenElse _ _ complete) _ => complete
  | _ => .skip

theorem extractedParserRecognize_state_after_bindings_shape :
    parserRecognizeStateAfterBindings =
      .sequence
        (.ifThenElse
          (.binary .less (.local 26) (.local 28))
          parserRecognizeStateIncompleteBranch
          parserRecognizeStateCompleteBranch)
        (parserRecognizeCursorAdvanceStatement 24) := by
  rfl

/-- Both semantic branches are mechanically projected from the exact reified
    state body and round-trip to the corresponding extracted Core branches. -/
private theorem stateIncompleteCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      stateAfterBindingsLayout 29 stateIncompleteCommand =
      parserRecognizeStateIncompleteBranch := by
  have whole := stateAfterBindingsCommand_toCore
  rw [stateAfterBindingsCommand_shape,
    extractedParserRecognize_state_after_bindings_shape] at whole
  have projected := congrArg coreIncompleteProjection whole
  simp only [Lanius.FunctionalView.Core.Stateful.toCoreStmt,
    coreIncompleteProjection] at projected
  exact projected

private theorem stateCompleteCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      stateAfterBindingsLayout 29 stateCompleteCommand =
      parserRecognizeStateCompleteBranch := by
  have whole := stateAfterBindingsCommand_toCore
  rw [stateAfterBindingsCommand_shape,
    extractedParserRecognize_state_after_bindings_shape] at whole
  have projected := congrArg coreCompleteProjection whole
  simp only [Lanius.FunctionalView.Core.Stateful.toCoreStmt,
    coreCompleteProjection] at projected
  exact projected

theorem extractedParserRecognize_state_incomplete_shape :
    parserRecognizeStateIncompleteBranch =
      .letLocal 29 parserI32Type
        (.call extractedParserRhsSymbolFunction.id
          [.local 0, .local 25, .local 26])
        (.sequence
          (.ifThenElse
            (.binary .less (.local 29) (.local 11))
            parserRecognizeTerminalStatement
            parserRecognizeStateNonterminalBranch)
          .skip) := by
  rfl

private def coreTerminalProjection : Stmt → Stmt
  | .letLocal _ _ _ (.sequence (.ifThenElse _ terminal _) .skip) => terminal
  | _ => .skip

private def coreNonterminalProjection : Stmt → Stmt
  | .letLocal _ _ _ (.sequence (.ifThenElse _ _ nonterminal) .skip) =>
      nonterminal
  | _ => .skip

/-- The projected FunctionalView branches are the exact terminal and
    nonterminal statements extracted from `parser.lani::recognize`. -/
private theorem stateTerminalCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      (Layout.push stateAfterBindingsLayout 29) 30 stateTerminalCommand =
      parserRecognizeTerminalStatement := by
  have whole := stateIncompleteCommand_toCore
  rw [stateIncompleteCommand_shape,
    extractedParserRecognize_state_incomplete_shape] at whole
  have projected := congrArg coreTerminalProjection whole
  simp only [Lanius.FunctionalView.Core.Stateful.toCoreStmt,
    coreTerminalProjection] at projected
  exact projected

private theorem stateNonterminalCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      (Layout.push stateAfterBindingsLayout 29) 30 stateNonterminalCommand =
      parserRecognizeStateNonterminalBranch := by
  have whole := stateIncompleteCommand_toCore
  rw [stateIncompleteCommand_shape,
    extractedParserRecognize_state_incomplete_shape] at whole
  have projected := congrArg coreNonterminalProjection whole
  simp only [Lanius.FunctionalView.Core.Stateful.toCoreStmt,
    coreNonterminalProjection] at projected
  exact projected

theorem extractedParserRecognize_state_nonterminal_shape :
    parserRecognizeStateNonterminalBranch =
      .letLocal 30 parserI32Type
        (.binary .subtract (.local 29) (.local 11))
        (.letLocal 31 parserI32Type
          (.index (.local 0) (.binary .add (.local 13) (.local 30)))
          (.letLocal 32 parserI32Type
            (.index (.local 0) (.binary .add (.local 14) (.local 30)))
            (.letLocal 33 parserI32Type (.value (.signed .i32 0))
              (.sequence parserRecognizePredictionLoop
                (.letLocal 36 parserI32Type
                  (.index (.local 4)
                    (.call extractedParserChartWordFunction.id
                      [.local 23, .constant 25]))
                  (.sequence parserRecognizeNullableLoop .skip)))))) := by
  rfl

theorem extractedParserRecognize_state_complete_shape :
    parserRecognizeStateCompleteBranch =
      .letLocal 29 parserI32Type
        (.call extractedParserLhsFunction.id [.local 0, .local 25])
        (.letLocal 30 parserI32Type
          (.index (.local 4)
            (.call extractedParserChartWordFunction.id
              [.local 27, .constant 25]))
          (.sequence parserRecognizeParentLoop .skip)) := by
  rfl

/-- A chart-head read through the extracted `chart_word` helper, stated
    against the logical workspace.  Centralizing this trace avoids giving the
    nullable, parent, and outer-position loops separate copies of the same
    call/index proof. -/
structure RecognizerChartHeadRead
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (before : State) (positionLocal position : Nat)
    (beforeInvariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell before) where
  after : State
  evaluation : Evaluates verifiedParserCore before
    (parserRecognizeChartHeadExpr positionLocal)
    (.signed .i32 (chartHeadValue workspace position)) after
  effect : ModifiesOnly CellSet.empty before after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell after

noncomputable def RecognizerInvariant.read_chart_head
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime)
    (positionLocal position : Nat)
    (positionFound : runtime.local? positionLocal =
      some (.signed .i32 (Int.ofNat position)))
    (positionBound : position ≤ finalPosition workspaceLayout.tokenCount) :
    RecognizerChartHeadRead grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell runtime
      positionLocal position invariant := by
  let after := parserChartWordCallState runtime (Int.ofNat position) 0
  have workspaceResult : Evaluates verifiedParserCore runtime (.local 4)
      (workspaceValue workspaceValues workspaceCell) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 4 _
      invariant.workspaceLocal⟩
  have positionResult : Evaluates verifiedParserCore runtime
      (.local positionLocal) (.signed .i32 (Int.ofNat position)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime positionLocal _
      positionFound⟩
  have fieldResult : Evaluates verifiedParserCore runtime (.constant 25)
      (.signed .i32 0) runtime := by
    refine ⟨2, ?_⟩
    simp [evalExpr, verifiedParser_find_constants.1]
  have arguments : ArgumentsEvaluateTo verifiedParserCore runtime
      [.local positionLocal, .constant 25]
      [.signed .i32 (Int.ofNat position), .signed .i32 0] runtime :=
    ArgumentsEvaluateTo.cons positionResult
      (ArgumentsEvaluateTo.singleton fieldResult)
  have addressCall : Evaluates verifiedParserCore runtime
      (.call extractedParserChartWordFunction.id
        [.local positionLocal, .constant 25])
      (.signed .i32 (Int.ofNat (chartWord position 0))) after := by
    have call := extractedParserChartWordCall_evaluates runtime runtime
      [.local positionLocal, .constant 25] (Int.ofNat position) 0
      invariant.wellFormed arguments
    have addressValue :
        parserChartWordValue verifiedParserCore.target
            (Int.ofNat position) 0 = Int.ofNat (chartWord position 0) := by
      simpa using workspaceLayout.chart_value_eq_address
        (position := position) (field := 0) positionBound (by decide)
    rw [addressValue] at call
    simpa [after, parserChartWordCallState] using call
  have addressBound : chartWord position 0 < workspaceValues.length := by
    rw [invariant.workspaceLength]
    exact workspaceLayout.chart_address_valid positionBound (by decide)
  have effect : ModifiesOnly CellSet.empty runtime after := by
    exact parserChartWordCallState_effect
  have afterBacking : after.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values workspaceValues))
    } := effect.empty_preserves_entry invariant.wellFormed
      invariant.workspaceBacking
  have indexed := evaluatesSignedI32SliceIndex verifiedParserCore runtime
    runtime after workspaceValues (.local 4)
    (.call extractedParserChartWordFunction.id
      [.local positionLocal, .constant 25])
    workspaceCell (chartWord position 0) addressBound workspaceResult
    addressCall afterBacking
  have chartRead : workspaceValues.get ⟨chartWord position 0, addressBound⟩ =
      chartHeadValue workspace position := by
    have concrete := invariant.workspaceEncoded.chartHead position positionBound
    rw [listWords_get workspaceValues (chartWord position 0) addressBound]
      at concrete
    exact concrete
  rw [chartRead] at indexed
  have afterWellFormed : StateWellFormed after :=
    parserChartWordCallState_well_formed invariant.wellFormed
  exact {
    after := after
    evaluation := by
      simpa [parserRecognizeChartHeadExpr, after] using indexed
    effect := effect
    invariant := invariant.after_empty_effect effect afterWellFormed
  }

/-- Common entry protocol for every recognizer loop that starts from a chart
    head.  It performs the exact artifact-derived read, binds one fresh cursor
    local, and classifies the logical chart as active or already finished.
    Nullable replay, parent completion, the state loop, and the root loop can
    build their algorithm-specific frames on top of this ownership boundary. -/
structure RecognizerChartLoopEntry
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (source : State) (chartPositionLocal chartPosition cursorLocal : Nat)
    (sourceInvariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell source)
    (workspaceWithinGrammar : WorkspaceWithinGrammar grammar workspace)
    (stateBaseLocal : source.local? 8 = some
      (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))))
    (chartPositionFound : source.local? chartPositionLocal =
      some (.signed .i32 (Int.ofNat chartPosition)))
    (chartPositionBound : chartPosition ≤
      finalPosition workspaceLayout.tokenCount) where
  headRead : RecognizerChartHeadRead grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell source chartPositionLocal chartPosition sourceInvariant
  cursorCell : CellId
  cursorCellEq : cursorCell = headRead.after.nextCell
  bound : State
  boundEq : bound = headRead.after.bindLocal cursorLocal
    (.signed .i32 (chartHeadValue workspace chartPosition))
  cursor :
    (Sigma fun current : Nat => Sigma fun remaining : List Nat =>
      RecognizerChartCursorInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell cursorCell bound chartPosition cursorLocal current
        remaining)
    ⊕ RecognizerChartCursorFinished grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell cursorCell bound chartPosition cursorLocal

noncomputable def RecognizerInvariant.enter_chart_loop
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell source)
    (workspaceWithinGrammar : WorkspaceWithinGrammar grammar workspace)
    (stateBaseLocal : source.local? 8 = some
      (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))))
    (chartPositionLocal chartPosition cursorLocal : Nat)
    (chartPositionFound : source.local? chartPositionLocal =
      some (.signed .i32 (Int.ofNat chartPosition)))
    (chartPositionBound : chartPosition ≤
      finalPosition workspaceLayout.tokenCount)
    (cursorAfterBase : 8 < cursorLocal) :
    RecognizerChartLoopEntry grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell source
      chartPositionLocal chartPosition cursorLocal invariant
      workspaceWithinGrammar stateBaseLocal chartPositionFound
      chartPositionBound := by
  let headRead := invariant.read_chart_head chartPositionLocal chartPosition
    chartPositionFound chartPositionBound
  let cursorCell := headRead.after.nextCell
  let bound := headRead.after.bindLocal cursorLocal
    (.signed .i32 (chartHeadValue workspace chartPosition))
  have stateBaseAfterRead : headRead.after.local? 8 = some
      (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))) :=
    headRead.effect.empty_preserves_local invariant.wellFormed stateBaseLocal
  have stateBaseAtBound : bound.local? 8 = some
      (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount))) := by
    exact (bindLocal_preserves_other_local headRead.invariant.wellFormed
      (Nat.ne_of_gt cursorAfterBase)).trans stateBaseAfterRead
  have cursorOwned : (Assertion.localPointsTo cursorLocal cursorCell
      (some (.signed .i32 (chartHeadValue workspace chartPosition)))).holds
      bound := by
    simpa [bound, cursorCell] using bindLocal_owns_fresh headRead.after
      cursorLocal (.signed .i32 (chartHeadValue workspace chartPosition))
      headRead.invariant.wellFormed
  have cursorFrameSeparate : ChartCursorFrameSeparated bound cursorCell := by
    simpa [bound, cursorCell, ChartCursorFrameSeparated] using
      bindLocal_fresh_disjoint_from_frame headRead.after cursorLocal
        (.signed .i32 (chartHeadValue workspace chartPosition))
        verifiedParserChartCursorBindings headRead.invariant.wellFormed (by
          intro member
          have framed := (ChartCursorFramedLocal_source_frame cursorLocal).mpr
            member
          exact (Nat.ne_of_gt
            (Nat.lt_of_le_of_lt framed.le8 cursorAfterBase)) rfl)
  have cursorBackingDistinct : cursorCell ≠ grammarCell ∧
      cursorCell ≠ tokensCell ∧ cursorCell ≠ workspaceCell := by
    simpa [cursorCell] using
      (⟨Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
          headRead.invariant.wellFormed headRead.invariant.grammarBacking,
        Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
          headRead.invariant.wellFormed headRead.invariant.tokensBacking,
        Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
          headRead.invariant.wellFormed headRead.invariant.workspaceBacking⟩)
  have cursorDifferent (fixed : Nat) (bound : fixed ≤ 5) :
      cursorLocal ≠ fixed :=
    Nat.ne_of_gt (Nat.lt_of_le_of_lt bound
      (Nat.lt_trans (by decide) cursorAfterBase))
  cases chartEq : workspace.chart chartPosition with
  | nil =>
      have cursorValue : chartHeadValue workspace chartPosition = -1 := by
        simp [chartHeadValue, chartEq, encodeStateId]
      exact {
        headRead := headRead
        cursorCell := cursorCell
        cursorCellEq := rfl
        bound := bound
        boundEq := rfl
        cursor := .inr {
          recognizer := by
            simpa [bound] using
              (headRead.invariant.after_bind_local cursorLocal
              (.signed .i32 (chartHeadValue workspace chartPosition))
              (cursorDifferent 0 (by decide))
              (cursorDifferent 1 (by decide))
              (cursorDifferent 2 (by decide))
              (cursorDifferent 3 (by decide))
              (cursorDifferent 4 (by decide))
              (cursorDifferent 5 (by decide)))
          workspaceWithinGrammar := workspaceWithinGrammar
          stateBaseLocal := stateBaseAtBound
          cursorOwned := by simpa [cursorValue] using cursorOwned
          cursorFrameSeparate := cursorFrameSeparate
          cursorBackingDistinct := cursorBackingDistinct
          chartPositionBound := chartPositionBound
        }
      }
  | cons current remaining =>
      have cursorValue : chartHeadValue workspace chartPosition =
          Int.ofNat current := by
        simp [chartHeadValue, chartEq, encodeStateId]
      exact {
        headRead := headRead
        cursorCell := cursorCell
        cursorCellEq := rfl
        bound := bound
        boundEq := rfl
        cursor := .inl ⟨current, remaining, {
          recognizer := by
            simpa [bound] using
              (headRead.invariant.after_bind_local cursorLocal
              (.signed .i32 (chartHeadValue workspace chartPosition))
              (cursorDifferent 0 (by decide))
              (cursorDifferent 1 (by decide))
              (cursorDifferent 2 (by decide))
              (cursorDifferent 3 (by decide))
              (cursorDifferent 4 (by decide))
              (cursorDifferent 5 (by decide)))
          workspaceWithinGrammar := workspaceWithinGrammar
          stateBaseLocal := stateBaseAtBound
          cursorOwned := by simpa [cursorValue] using cursorOwned
          cursorFrameSeparate := cursorFrameSeparate
          cursorBackingDistinct := cursorBackingDistinct
          chartPositionBound := chartPositionBound
          cursor := by simpa [chartEq] using ChartCursor.atHead current remaining
      }⟩
      }

/-- Restore a temporary lexical scope around an operation that has already
    established a recognizer invariant for its result workspace.  The body
    may mutate declared cells; only the six persistent parameter bindings must
    still identify the same backing cells.  This is the shared frame rule used
    by all branches of the enclosing recognizer loops. -/
theorem RecognizerInvariant.restore_temporary
    (before bound completed : State)
    (beforeWellFormed : StateWellFormed before)
    (entered : StoreEffect CellSet.empty before bound)
    (bodyEffect : ModifiesOnly writes bound completed)
    (parameterCellId : ∀ id, id ∈ verifiedParserRecognizerParameterIds →
      bound.cellId? id = before.cellId? id)
    (completedInvariant : RecognizerInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell completed) :
    RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      (restoreLocals before completed) := by
  let scopeEffect : StoreEffect writes before completed :=
    (entered.weaken CellSet.empty_subset).trans_same bodyEffect.toStoreEffect
  have restoredWellFormed : StateWellFormed
      (restoreLocals before completed) :=
    scopeEffect.restoreLocals_wellFormed beforeWellFormed
      completedInvariant.wellFormed
  have restoredParameterLocal (id : VarId)
      (idBound : id ∈ verifiedParserRecognizerParameterIds) :
      (restoreLocals before completed).local? id = completed.local? id := by
    have completedCellId : completed.cellId? id = bound.cellId? id := by
      unfold State.cellId?
      rw [bodyEffect.locals]
    have restoredCellId :
        (restoreLocals before completed).cellId? id = before.cellId? id := by
      rfl
    have cellIdEqual :
        (restoreLocals before completed).cellId? id = completed.cellId? id := by
      rw [restoredCellId, completedCellId, parameterCellId id idBound]
    unfold State.local?
    rw [cellIdEqual]
    cases found : completed.cellId? id with
    | none => rfl
    | some cell =>
        simp only [Option.bind_some]
        rfl
  exact {
    grammarEncoded := completedInvariant.grammarEncoded
    grammarWellFormed := completedInvariant.grammarWellFormed
    wordsI32 := completedInvariant.wordsI32
    tokensI32 := completedInvariant.tokensI32
    workspaceLength := completedInvariant.workspaceLength
    workspaceTokenCount := completedInvariant.workspaceTokenCount
    workspaceEncoded := completedInvariant.workspaceEncoded
    derivations := completedInvariant.derivations
    wellFormed := restoredWellFormed
    grammarLocal := by
      rw [restoredParameterLocal 0 (by simp)]
      exact completedInvariant.grammarLocal
    grammarLengthLocal := by
      rw [restoredParameterLocal 1 (by simp)]
      exact completedInvariant.grammarLengthLocal
    tokensLocal := by
      rw [restoredParameterLocal 2 (by simp)]
      exact completedInvariant.tokensLocal
    tokenCountLocal := by
      rw [restoredParameterLocal 3 (by simp)]
      exact completedInvariant.tokenCountLocal
    workspaceLocal := by
      rw [restoredParameterLocal 4 (by simp)]
      exact completedInvariant.workspaceLocal
    workspaceLengthLocal := by
      rw [restoredParameterLocal 5 (by simp)]
      exact completedInvariant.workspaceLengthLocal
    grammarBacking := completedInvariant.grammarBacking
    tokensBacking := completedInvariant.tokensBacking
    workspaceBacking := completedInvariant.workspaceBacking
    grammarWorkspaceDistinct := completedInvariant.grammarWorkspaceDistinct
    tokensWorkspaceDistinct := completedInvariant.tokensWorkspaceDistinct
  }

/-- Local ownership for a persistent local survives the same temporary-scope
    pattern.  Its local mapping is restored from the caller while its owned
    cell value comes from the completed body state. -/
theorem localPointsTo_restore_temporary
    (before bound completed : State) (id : VarId) (cell : CellId)
    (value : Option Value)
    (bodyEffect : ModifiesOnly writes bound completed)
    (parameterCellId : bound.cellId? id = before.cellId? id)
    (completedOwned :
      (Assertion.localPointsTo id cell value).holds completed) :
    (Assertion.localPointsTo id cell value).holds
      (restoreLocals before completed) := by
  constructor
  · change before.cellId? id = some cell
    calc
      before.cellId? id = bound.cellId? id := parameterCellId.symm
      _ = completed.cellId? id := by
        unfold State.cellId?
        rw [bodyEffect.locals]
      _ = some cell := completedOwned.1
  · change completed.cellEntry? cell = some { id := cell, value := value }
    exact completedOwned.2

/-- Persistent state of the Earley state-chain loop.  The loop owns its
    current-state cursor and the mutable state count, while the grammar table
    offsets and current chart position remain framed across every nested
    prediction, scan, nullable-replay, and parent-completion operation. -/
structure RecognizerStateLoopInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (runtime : State) (position current : Nat) (remaining : List Nat) : Type where
  chartCursor : RecognizerChartCursorInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell cursorCell runtime position 24 current remaining
  appendFrame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime position
  kindCountLocal : runtime.local? 11 = some
    (.signed .i32 (Int.ofNat grammar.grammar.n_kinds))
  lhsOffsetsOffsetLocal : runtime.local? 13 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset))
  lhsCountsOffsetLocal : runtime.local? 14 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset))
  lhsProductionsOffsetLocal : runtime.local? 15 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset))
  positionLocal : runtime.local? 23 = some
    (.signed .i32 (Int.ofNat position))
  positionAdvanceI32 : position + 2 ≤ 2147483647
  persistentSeparate : StateLoopFrameSeparated runtime workspaceCell
    stateCountCell cursorCell
  cursorStateCountDistinct : cursorCell ≠ stateCountCell

/-- Read the next state-chain link through the exact call term used by the
    projected cursor-advance command. -/
private theorem RecognizerStateLoopInvariant.functional_next
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current
      remaining)
    (environment : Lanius.FunctionalView.Env 17)
    (workspaceValueEq : environment ⟨3, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (stateBaseEq : environment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (currentEq : environment ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat current)) :
    Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      environment
        (stateValueTerm ⟨3, by omega⟩ ⟨4, by omega⟩
          ⟨12, by omega⟩ 32) =
      .ok (.signed .i32 (encodeStateId remaining.head?),
        stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell) := by
  let candidate := Classical.choose invariant.chartCursor.state_at_cursor
  have candidateFacts :=
    Classical.choose_spec invariant.chartCursor.state_at_cursor
  have found : workspace.state? current = some candidate := candidateFacts.1
  have positionEq : candidate.position = position := candidateFacts.2
  have evaluated := stateValueTerm_evaluates workspaceLayout grammar words
    tokens grammarCell tokensCell workspaceCell
    (stateWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell)
    environment ⟨3, by omega⟩ ⟨4, by omega⟩ ⟨12, by omega⟩ workspace
    candidate workspaceValues current 4 32 workspaceValueEq stateBaseEq
    currentEq (stateWorld_finds_workspace
      invariant.chartCursor.recognizer.grammarWorkspaceDistinct
      invariant.chartCursor.recognizer.tokensWorkspaceDistinct)
    invariant.chartCursor.recognizer.workspaceLength
    invariant.chartCursor.recognizer.workspaceEncoded found (by decide)
    verifiedParser_find_constants.2.2.2.2
  have nextValue : stateFieldValue workspace current candidate 4 =
      encodeStateId remaining.head? := by
    simp only [stateFieldValue, stateNextValue]
    rw [positionEq, invariant.chartCursor.cursor.nextAfter]
  rw [nextValue] at evaluated
  exact evaluated

/-- Functional execution of the projected outer state cursor advance. -/
theorem RecognizerStateLoopInvariant.functional_advance
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current
      remaining)
    (environment : Lanius.FunctionalView.Env 17)
    (workspaceValueEq : environment ⟨3, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (stateBaseEq : environment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (currentEq : environment ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat current)) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      environment stateAdvanceCommand .next
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      (Lanius.FunctionalView.Stateful.Env.set environment ⟨12, by omega⟩
        (.signed .i32 (encodeStateId remaining.head?))) := by
  have nextResult := invariant.functional_next environment workspaceValueEq
    stateBaseEq currentEq
  rw [stateAdvanceCommand_shape]
  exact .sequenceNext (.setLocal nextResult) .skip

theorem RecognizerStateLoopInvariant.persistentLocalsSeparate
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current
      remaining) :
    ∀ id, StateLoopPersistentLocal id →
      runtime.cellId? id ≠ some workspaceCell ∧
      (id ≠ 18 → runtime.cellId? id ≠ some stateCountCell) ∧
      runtime.cellId? id ≠ some cursorCell := by
  intro id persistent
  by_cases notStateCount : id ≠ 18
  · have preserved :=
      (StateLoopPreservedLocal_iff id).mpr ⟨persistent, notStateCount⟩
    have framed := (StateLoopPreservedLocal_source_frame id).mp preserved
    refine ⟨?_, ?_, ?_⟩
    · intro cellId
      exact invariant.persistentSeparate workspaceCell
        ⟨id, framed, cellId⟩ (Or.inl rfl)
    · intro _ cellId
      exact invariant.persistentSeparate stateCountCell
        ⟨id, framed, cellId⟩ (Or.inr (Or.inl rfl))
    · intro cellId
      exact invariant.persistentSeparate cursorCell
        ⟨id, framed, cellId⟩ (Or.inr (Or.inr rfl))
  · have same : id = 18 := Classical.byContradiction notStateCount
    subst id
    have stateCountId := invariant.appendFrame.stateCountOwned.1
    refine ⟨?_, ?_, ?_⟩
    · intro workspaceId
      exact invariant.appendFrame.stateCountBackingDistinct.2.2
        (Option.some.inj (stateCountId.symm.trans workspaceId))
    · intro impossible
      exact False.elim (impossible rfl)
    · intro cursorId
      exact invariant.cursorStateCountDistinct
        (Option.some.inj (stateCountId.symm.trans cursorId)).symm

/-- Reframed state-loop ownership after a nested operation has possibly
    extended the logical workspace. `progress` records the exact alternative
    needed by the outer lexicographic termination proof. -/
structure RecognizerStateGrowthFrame
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (beforeWorkspace nextWorkspace : LogicalWorkspace)
    (nextValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (after : State) (position current : Nat) (beforeRemaining : List Nat) where
  nextRemaining : List Nat
  invariant : RecognizerStateLoopInvariant grammarLayout grammar words tokens
    workspaceLayout nextWorkspace nextValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell after position current nextRemaining
  progress :
    (nextWorkspace.states.length = beforeWorkspace.states.length ∧
      nextRemaining = beforeRemaining) ∨
    beforeWorkspace.states.length < nextWorkspace.states.length

/-- Compose progress across two nested workspace-growing operations.  The
    final state-loop invariant already refers to the outer cursor; this lemma
    only rebases its termination witness from the intermediate workspace to
    the workspace at the start of the state operation. -/
def RecognizerStateGrowthFrame.prepend
    (frame : RecognizerStateGrowthFrame grammarLayout grammar words tokens
      workspaceLayout middleWorkspace nextWorkspace nextValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell after position current
      middleRemaining)
    (prefixGrowth : WorkspaceAppendClosure workspaceLayout.capacity
      beforeWorkspace middleWorkspace)
    (prefixProgress :
      (middleWorkspace.states.length = beforeWorkspace.states.length ∧
        middleRemaining = beforeRemaining) ∨
      beforeWorkspace.states.length < middleWorkspace.states.length) :
    RecognizerStateGrowthFrame grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace nextWorkspace nextValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell after position current
      beforeRemaining := {
  nextRemaining := frame.nextRemaining
  invariant := frame.invariant
  progress := by
    rcases frame.progress with unchanged | grew
    · rcases unchanged with ⟨nextCount, nextRemaining⟩
      rcases prefixProgress with prefixUnchanged | prefixGrew
      · exact .inl ⟨nextCount.trans prefixUnchanged.1,
          nextRemaining.trans prefixUnchanged.2⟩
      · exact .inr (by omega)
    · exact .inr (Nat.lt_of_le_of_lt prefixGrowth.state_count_le grew)
}

/-- Common result expected by the outer state loop from any nested parser
    operation. Algorithm-specific invariants have already been reframed into
    the state cursor and its lexicographic progress witness. -/
abbrev RecognizerStateOperationOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position current : Nat) (beforeRemaining : List Nat) :
    State → Completion → Prop :=
  WorkspaceLoopOutcome workspaceLayout.capacity beforeWorkspace
    (parserCapacityCompletion position)
    (fun nextWorkspace nextValues after =>
      RecognizerStateGrowthFrame grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace nextWorkspace nextValues grammarCell
        tokensCell workspaceCell stateCountCell cursorCell after position current
        beforeRemaining)
    (fun workspace workspaceValues after =>
      RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
        workspace workspaceValues grammarCell tokensCell workspaceCell after)

/-- A semantic state branch has one post-state shared by its physical Core
    refinement and its FunctionalView execution.  Both normal and capacity
    outcomes name the resulting logical workspace explicitly; this prevents
    later cursor composition from recovering an unrelated witness hidden in a
    proof of `WorkspaceLoopOutcome`. -/
inductive RecognizerStateBranchSynchronizedOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position current : Nat) (beforeRemaining : List Nat)
    (production dot origin rhsLength : Nat)
    (afterWorld : Lanius.FunctionalView.Core.ReadOnly.World)
    (afterEnvironment : Lanius.FunctionalView.Env 17) :
    State → Completion → Type where
  | completed (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (frame : RecognizerStateGrowthFrame grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace workspace workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell cursorCell physicalAfter
        position current beforeRemaining)
      (worldEq : afterWorld = stateWorld words tokens workspaceValues grammarCell
        tokensCell workspaceCell)
      (environmentMeaning : StateAfterBindingsEnvironment grammarLayout grammar
        words tokens workspaceLayout workspace workspaceValues grammarCell
        tokensCell workspaceCell position current production dot origin
        rhsLength afterEnvironment) :
      RecognizerStateBranchSynchronizedOutcome grammarLayout grammar words
        tokens workspaceLayout beforeWorkspace grammarCell tokensCell
        workspaceCell stateCountCell cursorCell position current beforeRemaining
        production dot origin rhsLength afterWorld afterEnvironment physicalAfter
        .next
  | full (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (terminal : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter) :
      RecognizerStateBranchSynchronizedOutcome grammarLayout grammar words
        tokens workspaceLayout beforeWorkspace grammarCell tokensCell
        workspaceCell stateCountCell cursorCell position current beforeRemaining
        production dot origin rhsLength afterWorld afterEnvironment physicalAfter
        (parserCapacityCompletion position stateCount)

def RecognizerStateBranchSynchronizedOutcome.physical
    (outcome : RecognizerStateBranchSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position current beforeRemaining
      production dot origin rhsLength afterWorld afterEnvironment physicalAfter
      completion) :
    RecognizerStateOperationOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position current beforeRemaining physicalAfter
      completion := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter growth frame _ _ =>
      exact .completed workspace workspaceValues physicalAfter growth frame
  | full workspace workspaceValues physicalAfter growth terminal stateCount
      wellFormed =>
      exact .full workspace workspaceValues physicalAfter growth terminal
        stateCount wellFormed

/-- Eliminate a branch outcome without asking Lean to invert the nontrivial
    `toCoreCompletion` index used by synchronized source executions. -/
theorem RecognizerStateBranchSynchronizedOutcome.view
    (outcome : RecognizerStateBranchSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position current beforeRemaining
      production dot origin rhsLength afterWorld afterEnvironment physicalAfter
      completion) :
    (∃ workspace workspaceValues stateCount,
      ∃ growth : WorkspaceAppendClosure workspaceLayout.capacity
          beforeWorkspace workspace,
      ∃ terminal : RecognizerInvariant grammarLayout grammar words tokens
          workspaceLayout workspace workspaceValues grammarCell tokensCell
          workspaceCell physicalAfter,
      ∃ wellFormed : StateWellFormed physicalAfter,
      completion = parserCapacityCompletion position stateCount) ∨
    (∃ workspace workspaceValues,
      ∃ growth : WorkspaceAppendClosure workspaceLayout.capacity
          beforeWorkspace workspace,
      ∃ frame : RecognizerStateGrowthFrame grammarLayout grammar words tokens
          workspaceLayout beforeWorkspace workspace workspaceValues grammarCell
          tokensCell workspaceCell stateCountCell cursorCell physicalAfter
          position current beforeRemaining,
      completion = .next ∧
      afterWorld = stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell ∧
      StateAfterBindingsEnvironment grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell position current production dot origin rhsLength
        afterEnvironment) := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter growth frame worldEq
      environmentMeaning =>
      exact .inr ⟨workspace, workspaceValues, growth, frame, rfl, worldEq,
        environmentMeaning⟩
  | full workspace workspaceValues physicalAfter growth terminal stateCount
      wellFormed =>
      exact .inl ⟨workspace, workspaceValues, stateCount, growth, terminal,
        wellFormed, rfl⟩

/-- Restore the enclosing state-loop frame after any nested workspace-growing
    parser operation. The caller supplies only the nested operation's semantic
    result and its actual write footprint; cursor and persistent-local framing
    are reconstructed once here. -/
noncomputable def RecognizerStateLoopInvariant.reframe_growth
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace beforeValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    (nextWorkspace : LogicalWorkspace) (nextValues : List Int) (after : State)
    (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
      nextWorkspace)
    (recognizer : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextValues grammarCell tokensCell
      workspaceCell after)
    (workspaceWithinGrammar : WorkspaceWithinGrammar grammar nextWorkspace)
    (stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32
        (Int.ofNat nextWorkspace.states.length)))).holds after)
    (writes : CellSet) (effect : ModifiesOnly writes before after)
    (frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        verifiedParserStateLoopPreservedBindings) writes)
    (cursorNotWritten : ¬ writes cursorCell) :
    RecognizerStateGrowthFrame grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace nextWorkspace nextValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell after position current
      remaining := by
  have cursorOwned := effect.preserves_localPointsTo
    invariant.chartCursor.recognizer.wellFormed
    invariant.chartCursor.cursorOwned cursorNotWritten
  have preservePersistent (id : VarId)
      (persistent : StateLoopPersistentLocal id) (idNotCount : id ≠ 18)
      (value : Value) (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint
      invariant.chartCursor.recognizer.wellFormed frameDisjoint
      ((StateLoopPreservedLocal_source_frame id).mp
        ((StateLoopPreservedLocal_iff id).mpr
          ⟨persistent, idNotCount⟩)) found
  have build (nextRemaining : List Nat)
      (cursor : ChartCursor (nextWorkspace.chart position) current
        nextRemaining)
      (progress :
        (nextWorkspace.states.length = beforeWorkspace.states.length ∧
          nextRemaining = remaining) ∨
        beforeWorkspace.states.length < nextWorkspace.states.length) :
      RecognizerStateGrowthFrame grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace nextWorkspace nextValues grammarCell
        tokensCell workspaceCell stateCountCell cursorCell after position current
        remaining := {
    nextRemaining := nextRemaining
    invariant := {
      chartCursor := {
        recognizer := recognizer
        workspaceWithinGrammar := workspaceWithinGrammar
        stateBaseLocal := preservePersistent 8 (by
          simp [StateLoopPersistentLocal]) (by decide) _
          invariant.chartCursor.stateBaseLocal
        cursorOwned := cursorOwned
        cursorFrameSeparate := by
          unfold ChartCursorFrameSeparated
          rw [effect.localBindingFrameFootprint_eq
            verifiedParserChartCursorBindings]
          exact invariant.chartCursor.cursorFrameSeparate
        cursorBackingDistinct := invariant.chartCursor.cursorBackingDistinct
        chartPositionBound := invariant.chartCursor.chartPositionBound
        cursor := cursor
      }
      appendFrame := {
        recognizer := recognizer
        positionBound := invariant.appendFrame.positionBound
        stateBaseLocal := preservePersistent 8 (by
          simp [StateLoopPersistentLocal]) (by decide) _
          invariant.appendFrame.stateBaseLocal
        stateCapacityLocal := preservePersistent 9 (by
          simp [StateLoopPersistentLocal]) (by decide) _
          invariant.appendFrame.stateCapacityLocal
        stateCountLocal := Assertion.localPointsTo_local 18 stateCountCell _
          after stateCountOwned
        stateCountOwned := stateCountOwned
        stateCountBackingDistinct :=
          invariant.appendFrame.stateCountBackingDistinct
        stateCountParameterSeparate := by
          unfold RecognizerParameterFrameSeparated
          rw [effect.localBindingFrameFootprint_eq
            verifiedParserRecognizerParameterFrame]
          exact invariant.appendFrame.stateCountParameterSeparate
      }
      kindCountLocal := preservePersistent 11 (by
        simp [StateLoopPersistentLocal]) (by decide) _ invariant.kindCountLocal
      lhsOffsetsOffsetLocal := preservePersistent 13 (by
        simp [StateLoopPersistentLocal]) (by decide) _
        invariant.lhsOffsetsOffsetLocal
      lhsCountsOffsetLocal := preservePersistent 14 (by
        simp [StateLoopPersistentLocal]) (by decide) _
        invariant.lhsCountsOffsetLocal
      lhsProductionsOffsetLocal := preservePersistent 15 (by
        simp [StateLoopPersistentLocal]) (by decide) _
        invariant.lhsProductionsOffsetLocal
      positionLocal := preservePersistent 23 (by
        simp [StateLoopPersistentLocal]) (by decide) _ invariant.positionLocal
      positionAdvanceI32 := invariant.positionAdvanceI32
      persistentSeparate := by
        unfold StateLoopFrameSeparated
        rw [effect.localBindingFrameFootprint_eq
          verifiedParserStateLoopPreservedBindings]
        exact invariant.persistentSeparate
      cursorStateCountDistinct := invariant.cursorStateCountDistinct
    }
    progress := progress
  }
  by_cases sameCount :
      nextWorkspace.states.length = beforeWorkspace.states.length
  · have sameWorkspace := growth.eq_of_state_count_eq sameCount
    subst nextWorkspace
    exact build remaining invariant.chartCursor.cursor
      (.inl ⟨sameCount, rfl⟩)
  · let candidate := Classical.choose invariant.chartCursor.state_at_cursor
    have candidateFacts :=
      Classical.choose_spec invariant.chartCursor.state_at_cursor
    have foundAfter := growth.preserves_existing_state candidateFacts.1
    have listedAtState := recognizer.workspaceEncoded.wellFormed
      |>.everyStateCharted current candidate foundAfter
    have listed : current ∈ nextWorkspace.chart position := by
      have candidatePosition : candidate.position = position := candidateFacts.2
      rw [candidatePosition] at listedAtState
      exact listedAtState
    have cursorExists := existsChartCursor_of_mem
      (recognizer.workspaceEncoded.wellFormed.chartIdsUnique position) listed
    let nextRemaining := Classical.choose cursorExists
    have nextCursor := Classical.choose_spec cursorExists
    exact build nextRemaining (Classical.choice nextCursor) (.inr (by
      have countLe := growth.state_count_le
      omega))

def RecognizerStateLoopInvariant.after_empty_effect
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    RecognizerStateLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell after position current remaining := {
  chartCursor := invariant.chartCursor.after_empty_effect effect afterWellFormed
  appendFrame := invariant.appendFrame.after_empty_effect effect afterWellFormed
  kindCountLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.kindCountLocal
  lhsOffsetsOffsetLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.lhsOffsetsOffsetLocal
  lhsCountsOffsetLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.lhsCountsOffsetLocal
  lhsProductionsOffsetLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed
      invariant.lhsProductionsOffsetLocal
  positionLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.positionLocal
  positionAdvanceI32 := invariant.positionAdvanceI32
  persistentSeparate := by
    unfold StateLoopFrameSeparated
    rw [effect.localBindingFrameFootprint_eq
      verifiedParserStateLoopPreservedBindings]
    exact invariant.persistentSeparate
  cursorStateCountDistinct := invariant.cursorStateCountDistinct
}

def RecognizerStateLoopInvariant.after_bind_local
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining)
    (id : VarId) (value : Value) (cursorBefore : 24 < id) :
    RecognizerStateLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell (runtime.bindLocal id value)
      position current remaining := by
  have persistentBefore : 23 < id := Nat.lt_trans (by decide) cursorBefore
  have different (fixed : Nat) (bound : fixed ≤ 23) : id ≠ fixed :=
    Nat.ne_of_gt (Nat.lt_of_le_of_lt bound persistentBefore)
  exact {
    chartCursor := invariant.chartCursor.after_bind_local id value
      (Nat.lt_trans (by decide) cursorBefore) cursorBefore
    appendFrame := invariant.appendFrame.after_bind_local id value
      (different 0 (by decide)) (different 1 (by decide))
      (different 2 (by decide)) (different 3 (by decide))
      (different 4 (by decide)) (different 5 (by decide))
      (Nat.lt_trans (by decide) cursorBefore)
      (different 8 (by decide)) (different 9 (by decide))
      (different 18 (by decide))
    kindCountLocal :=
      (bindLocal_preserves_other_local invariant.chartCursor.recognizer.wellFormed
        (different 11 (by decide))).trans invariant.kindCountLocal
    lhsOffsetsOffsetLocal :=
      (bindLocal_preserves_other_local invariant.chartCursor.recognizer.wellFormed
        (different 13 (by decide))).trans invariant.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal :=
      (bindLocal_preserves_other_local invariant.chartCursor.recognizer.wellFormed
        (different 14 (by decide))).trans invariant.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal :=
      (bindLocal_preserves_other_local invariant.chartCursor.recognizer.wellFormed
        (different 15 (by decide))).trans invariant.lhsProductionsOffsetLocal
    positionLocal :=
      (bindLocal_preserves_other_local invariant.chartCursor.recognizer.wellFormed
        (different 23 (by decide))).trans invariant.positionLocal
    positionAdvanceI32 := invariant.positionAdvanceI32
    persistentSeparate := by
      unfold StateLoopFrameSeparated
      intro cell framed written
      obtain ⟨queried, preserved, cellId⟩ := framed
      have queriedBound := (StateLoopPreservedLocal_iff queried).mp
        ((StateLoopPreservedLocal_source_frame queried).mpr preserved) |>.1
      have notEqual : id ≠ queried := different queried queriedBound.le23
      apply invariant.persistentSeparate cell
        ⟨queried, preserved, ?_⟩ written
      simpa [State.bindLocal, State.bindCell, State.cellId?, notEqual] using
        cellId
    cursorStateCountDistinct := invariant.cursorStateCountDistinct
  }

/-- State-loop frame after its cursor has consumed the final chart item and
    contains the concrete `-1` sentinel. -/
structure RecognizerStateFinishedInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (runtime : State) (position : Nat) : Type where
  chartCursor : RecognizerChartCursorFinished grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell cursorCell runtime position 24
  appendFrame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime position
  kindCountLocal : runtime.local? 11 = some
    (.signed .i32 (Int.ofNat grammar.grammar.n_kinds))
  lhsOffsetsOffsetLocal : runtime.local? 13 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset))
  lhsCountsOffsetLocal : runtime.local? 14 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset))
  lhsProductionsOffsetLocal : runtime.local? 15 = some
    (.signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset))
  positionLocal : runtime.local? 23 = some
    (.signed .i32 (Int.ofNat position))
  positionAdvanceI32 : position + 2 ≤ 2147483647
  persistentSeparate : StateLoopFrameSeparated runtime workspaceCell
    stateCountCell cursorCell
  cursorStateCountDistinct : cursorCell ≠ stateCountCell

theorem RecognizerStateFinishedInvariant.condition_negative
    (invariant : RecognizerStateFinishedInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position) :
    Evaluates verifiedParserCore runtime
      (.binary .greaterEqual (.local 24) (.value (.signed .i32 0)))
      (.boolean false) runtime :=
  invariant.chartCursor.condition_negative

/-- Any state-loop persistent local survives a write to its separately owned
    cursor cell. -/
theorem RecognizerStateLoopInvariant.preserve_local_after_cursor
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    (effect : ModifiesOnly (CellSet.singleton cursorCell) before after)
    (id : VarId) (persistent : StateLoopPersistentLocal id)
    (value : Value) (found : before.local? id = some value) :
    after.local? id = some value := by
  apply effect.preserves_local invariant.chartCursor.recognizer.wellFormed found
  intro cell cellId written
  change cell = cursorCell at written
  subst cell
  exact invariant.persistentLocalsSeparate id persistent |>.2.2 cellId

/-- Recombine the state-loop frame with a cursor advance to a nonempty chart
    suffix. -/
def RecognizerStateLoopInvariant.after_cursor_effect
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    (afterCursor : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell after position 24 next nextRemaining)
    (effect : ModifiesOnly (CellSet.singleton cursorCell) before after) :
    RecognizerStateLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell after position next nextRemaining := by
  let appendFrame := invariant.appendFrame.after_scalar_effect cursorCell effect
    afterCursor.recognizer
    (invariant.persistentLocalsSeparate 8 (by
      simp [StateLoopPersistentLocal]) |>.2.2)
    (invariant.persistentLocalsSeparate 9 (by
      simp [StateLoopPersistentLocal]) |>.2.2)
    invariant.cursorStateCountDistinct.symm
  exact {
    chartCursor := afterCursor
    appendFrame := appendFrame
    kindCountLocal := invariant.preserve_local_after_cursor effect 11 (by
      simp [StateLoopPersistentLocal]) _ invariant.kindCountLocal
    lhsOffsetsOffsetLocal := invariant.preserve_local_after_cursor effect 13 (by
      simp [StateLoopPersistentLocal]) _ invariant.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal := invariant.preserve_local_after_cursor effect 14 (by
      simp [StateLoopPersistentLocal]) _ invariant.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal := invariant.preserve_local_after_cursor effect 15
      (by simp [StateLoopPersistentLocal]) _
      invariant.lhsProductionsOffsetLocal
    positionLocal := invariant.preserve_local_after_cursor effect 23 (by
      simp [StateLoopPersistentLocal]) _ invariant.positionLocal
    positionAdvanceI32 := invariant.positionAdvanceI32
    persistentSeparate := by
      unfold StateLoopFrameSeparated
      rw [effect.localBindingFrameFootprint_eq
        verifiedParserStateLoopPreservedBindings]
      exact invariant.persistentSeparate
    cursorStateCountDistinct := invariant.cursorStateCountDistinct
  }

/-- Recombine the state-loop frame with the final cursor write that installs
    the loop sentinel. -/
def RecognizerStateLoopInvariant.after_cursor_exhaustion
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current [])
    (afterCursor : RecognizerChartCursorFinished grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell after position 24)
    (effect : ModifiesOnly (CellSet.singleton cursorCell) before after) :
    RecognizerStateFinishedInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell after position := by
  let appendFrame := invariant.appendFrame.after_scalar_effect cursorCell effect
    afterCursor.recognizer
    (invariant.persistentLocalsSeparate 8 (by
      simp [StateLoopPersistentLocal]) |>.2.2)
    (invariant.persistentLocalsSeparate 9 (by
      simp [StateLoopPersistentLocal]) |>.2.2)
    invariant.cursorStateCountDistinct.symm
  exact {
    chartCursor := afterCursor
    appendFrame := appendFrame
    kindCountLocal := invariant.preserve_local_after_cursor effect 11 (by
      simp [StateLoopPersistentLocal]) _ invariant.kindCountLocal
    lhsOffsetsOffsetLocal := invariant.preserve_local_after_cursor effect 13 (by
      simp [StateLoopPersistentLocal]) _ invariant.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal := invariant.preserve_local_after_cursor effect 14 (by
      simp [StateLoopPersistentLocal]) _ invariant.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal := invariant.preserve_local_after_cursor effect 15
      (by simp [StateLoopPersistentLocal]) _
      invariant.lhsProductionsOffsetLocal
    positionLocal := invariant.preserve_local_after_cursor effect 23 (by
      simp [StateLoopPersistentLocal]) _ invariant.positionLocal
    positionAdvanceI32 := invariant.positionAdvanceI32
    persistentSeparate := by
      unfold StateLoopFrameSeparated
      rw [effect.localBindingFrameFootprint_eq
        verifiedParserStateLoopPreservedBindings]
      exact invariant.persistentSeparate
    cursorStateCountDistinct := invariant.cursorStateCountDistinct
  }

theorem RecognizerStateLoopInvariant.read_lhs_offset
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining)
    (nonterminal : Nat)
    (nonterminalBound : nonterminal < grammar.grammar.n_nonterminals)
    (nonterminalLocal : runtime.local? 30 =
      some (.signed .i32 (Int.ofNat nonterminal))) :
    Evaluates verifiedParserCore runtime
      (.index (.local 0) (.binary .add (.local 13) (.local 30)))
      (.signed .i32 (Int.ofNat (grammar.lhsOffsets.get
        ⟨nonterminal, by
          simpa [grammar.lhsOffsets_length,
            invariant.chartCursor.recognizer.grammarWellFormed.lhsIndexCount]
            using nonterminalBound⟩))) runtime := by
  have rowBound : nonterminal < grammar.lhsOffsets.length := by
    simpa [grammar.lhsOffsets_length,
      invariant.chartCursor.recognizer.grammarWellFormed.lhsIndexCount] using
      nonterminalBound
  simpa using invariant.chartCursor.recognizer.read_packed_nat_table
    13 30 grammarLayout.lhsOffsetsOffset nonterminal grammar.lhsOffsets
    invariant.chartCursor.recognizer.grammarEncoded.lhsOffsets
    invariant.lhsOffsetsOffsetLocal nonterminalLocal rowBound

theorem RecognizerStateLoopInvariant.read_lhs_count
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining)
    (nonterminal : Nat)
    (nonterminalBound : nonterminal < grammar.grammar.n_nonterminals)
    (nonterminalLocal : runtime.local? 30 =
      some (.signed .i32 (Int.ofNat nonterminal))) :
    Evaluates verifiedParserCore runtime
      (.index (.local 0) (.binary .add (.local 14) (.local 30)))
      (.signed .i32 (Int.ofNat (grammar.lhsCounts.get
        ⟨nonterminal, by
          simpa [grammar.lhsCounts_length,
            invariant.chartCursor.recognizer.grammarWellFormed.lhsIndexCount]
            using nonterminalBound⟩))) runtime := by
  have rowBound : nonterminal < grammar.lhsCounts.length := by
    simpa [grammar.lhsCounts_length,
      invariant.chartCursor.recognizer.grammarWellFormed.lhsIndexCount] using
      nonterminalBound
  simpa using invariant.chartCursor.recognizer.read_packed_nat_table
    14 30 grammarLayout.lhsCountsOffset nonterminal grammar.lhsCounts
    invariant.chartCursor.recognizer.grammarEncoded.lhsCounts
    invariant.lhsCountsOffsetLocal nonterminalLocal rowBound

/-- Exact trace of the four temporary state-header bindings at the start of
    one state-chain iteration.  The semantic candidate is read once from the
    chart cursor; each generated accessor call is then related to that same
    candidate before its result enters the next lexical scope. -/
structure RecognizerStateCandidateBindings
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
    (productionBound : candidate.production < grammar.productionCount) where
  afterProductionRead : State
  productionEvaluation : Evaluates verifiedParserCore before
    (parserRecognizeStateValueCall 24 28)
    (.signed .i32 (Int.ofNat candidate.production)) afterProductionRead
  productionEffect : ModifiesOnly CellSet.empty before afterProductionRead
  afterProductionWellFormed : StateWellFormed afterProductionRead
  afterDotRead : State
  dotEvaluation : Evaluates verifiedParserCore
    (afterProductionRead.bindLocal 25
      (.signed .i32 (Int.ofNat candidate.production)))
    (parserRecognizeStateValueCall 24 29)
    (.signed .i32 (Int.ofNat candidate.dot)) afterDotRead
  dotEffect : ModifiesOnly CellSet.empty
    (afterProductionRead.bindLocal 25
      (.signed .i32 (Int.ofNat candidate.production))) afterDotRead
  afterDotWellFormed : StateWellFormed afterDotRead
  afterOriginRead : State
  originEvaluation : Evaluates verifiedParserCore
    (afterDotRead.bindLocal 26 (.signed .i32 (Int.ofNat candidate.dot)))
    (parserRecognizeStateValueCall 24 30)
    (.signed .i32 (Int.ofNat candidate.origin)) afterOriginRead
  originEffect : ModifiesOnly CellSet.empty
    (afterDotRead.bindLocal 26 (.signed .i32 (Int.ofNat candidate.dot)))
    afterOriginRead
  afterOriginWellFormed : StateWellFormed afterOriginRead
  afterRhsLengthRead : State
  rhsLengthEvaluation : Evaluates verifiedParserCore
    (afterOriginRead.bindLocal 27
      (.signed .i32 (Int.ofNat candidate.origin)))
    (.call extractedParserRhsLengthFunction.id [.local 0, .local 25])
    (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length))
    afterRhsLengthRead
  rhsLengthEffect : ModifiesOnly CellSet.empty
    (afterOriginRead.bindLocal 27
      (.signed .i32 (Int.ofNat candidate.origin))) afterRhsLengthRead
  afterRhsLengthWellFormed : StateWellFormed afterRhsLengthRead
  invariant : RecognizerStateLoopInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell
    (afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)))
    position current remaining
  productionLocal :
    (afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length))).local?
      25 = some (.signed .i32 (Int.ofNat candidate.production))
  productionCell : CellId
  productionOwned : (Assertion.localPointsTo 25 productionCell
    (some (.signed .i32 (Int.ofNat candidate.production)))).holds
      (afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)))
  productionCellDistinct : productionCell ≠ workspaceCell ∧
    productionCell ≠ stateCountCell ∧ productionCell ≠ cursorCell
  dotLocal :
    (afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length))).local?
      26 = some (.signed .i32 (Int.ofNat candidate.dot))
  dotCell : CellId
  dotOwned : (Assertion.localPointsTo 26 dotCell
    (some (.signed .i32 (Int.ofNat candidate.dot)))).holds
      (afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)))
  dotCellDistinct : dotCell ≠ workspaceCell ∧
    dotCell ≠ stateCountCell ∧ dotCell ≠ cursorCell
  originLocal :
    (afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length))).local?
      27 = some (.signed .i32 (Int.ofNat candidate.origin))
  originCell : CellId
  originOwned : (Assertion.localPointsTo 27 originCell
    (some (.signed .i32 (Int.ofNat candidate.origin)))).holds
      (afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)))
  originCellDistinct : originCell ≠ workspaceCell ∧
    originCell ≠ stateCountCell ∧ originCell ≠ cursorCell
  rhsLengthLocal :
    (afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length))).local?
      28 = some (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length))

noncomputable def RecognizerStateLoopInvariant.bind_candidate_fields
    (invariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount) :
    RecognizerStateCandidateBindings grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      invariant candidate found productionBound := by
  let productionRead := invariant.chartCursor.read_production candidate found
  have productionEvaluation : Evaluates verifiedParserCore runtime
      (parserRecognizeStateValueCall 24 28)
      (.signed .i32 (Int.ofNat candidate.production)) productionRead.after := by
    simpa [stateFieldValue] using productionRead.evaluation
  let afterProduction := invariant.after_empty_effect productionRead.effect
    productionRead.invariant.recognizer.wellFormed
  let productionScope := productionRead.after.bindLocal 25
    (.signed .i32 (Int.ofNat candidate.production))
  let productionInvariant := afterProduction.after_bind_local 25
    (.signed .i32 (Int.ofNat candidate.production)) (by decide)
  let dotRead := productionInvariant.chartCursor.read_dot candidate found
  have dotEvaluation : Evaluates verifiedParserCore productionScope
      (parserRecognizeStateValueCall 24 29)
      (.signed .i32 (Int.ofNat candidate.dot)) dotRead.after := by
    simpa [productionScope, productionInvariant, stateFieldValue] using
      dotRead.evaluation
  let afterDot := productionInvariant.after_empty_effect dotRead.effect
    dotRead.invariant.recognizer.wellFormed
  let dotScope := dotRead.after.bindLocal 26
    (.signed .i32 (Int.ofNat candidate.dot))
  let dotInvariant := afterDot.after_bind_local 26
    (.signed .i32 (Int.ofNat candidate.dot)) (by decide)
  let originRead := dotInvariant.chartCursor.read_origin candidate found
  have originEvaluation : Evaluates verifiedParserCore dotScope
      (parserRecognizeStateValueCall 24 30)
      (.signed .i32 (Int.ofNat candidate.origin)) originRead.after := by
    simpa [dotScope, dotInvariant, stateFieldValue] using originRead.evaluation
  let afterOrigin := dotInvariant.after_empty_effect originRead.effect
    originRead.invariant.recognizer.wellFormed
  let originScope := originRead.after.bindLocal 27
    (.signed .i32 (Int.ofNat candidate.origin))
  let originInvariant := afterOrigin.after_bind_local 27
    (.signed .i32 (Int.ofNat candidate.origin)) (by decide)
  have productionAtProductionScope : productionScope.local? 25 = some
      (.signed .i32 (Int.ofNat candidate.production)) := by
    simpa [productionScope] using bindLocal_finds_local productionRead.after 25
      (.signed .i32 (Int.ofNat candidate.production))
      productionRead.invariant.recognizer.wellFormed
  have productionAtDotRead : dotRead.after.local? 25 = some
      (.signed .i32 (Int.ofNat candidate.production)) :=
    dotRead.effect.empty_preserves_local
      productionInvariant.chartCursor.recognizer.wellFormed
      productionAtProductionScope
  have productionAtDotScope : dotScope.local? 25 = some
      (.signed .i32 (Int.ofNat candidate.production)) :=
    (bindLocal_preserves_other_local dotRead.invariant.recognizer.wellFormed
      (by decide : 26 ≠ 25)).trans productionAtDotRead
  have dotAtDotScope : dotScope.local? 26 = some
      (.signed .i32 (Int.ofNat candidate.dot)) := by
    simpa [dotScope] using bindLocal_finds_local dotRead.after 26
      (.signed .i32 (Int.ofNat candidate.dot))
      dotRead.invariant.recognizer.wellFormed
  have productionAtOriginRead : originRead.after.local? 25 = some
      (.signed .i32 (Int.ofNat candidate.production)) :=
    originRead.effect.empty_preserves_local
      dotInvariant.chartCursor.recognizer.wellFormed productionAtDotScope
  have dotAtOriginRead : originRead.after.local? 26 = some
      (.signed .i32 (Int.ofNat candidate.dot)) :=
    originRead.effect.empty_preserves_local
      dotInvariant.chartCursor.recognizer.wellFormed dotAtDotScope
  have productionAtOriginScope : originScope.local? 25 = some
      (.signed .i32 (Int.ofNat candidate.production)) :=
    (bindLocal_preserves_other_local originRead.invariant.recognizer.wellFormed
      (by decide : 27 ≠ 25)).trans productionAtOriginRead
  have dotAtOriginScope : originScope.local? 26 = some
      (.signed .i32 (Int.ofNat candidate.dot)) :=
    (bindLocal_preserves_other_local originRead.invariant.recognizer.wellFormed
      (by decide : 27 ≠ 26)).trans dotAtOriginRead
  have originAtOriginScope : originScope.local? 27 = some
      (.signed .i32 (Int.ofNat candidate.origin)) := by
    simpa [originScope] using bindLocal_finds_local originRead.after 27
      (.signed .i32 (Int.ofNat candidate.origin))
      originRead.invariant.recognizer.wellFormed
  have productionResult : Evaluates verifiedParserCore originScope (.local 25)
      (.signed .i32 (Int.ofNat candidate.production)) originScope :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore originScope 25 _
      productionAtOriginScope⟩
  let rhsRead := originInvariant.chartCursor.read_rhs_length
    candidate.production productionBound (.local 25) productionResult
  have rhsLengthValue : grammar.rhsLengths.get
      ⟨candidate.production, by simpa using productionBound⟩ =
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length :=
    by simpa using (grammar.rhsLengths_get
      ⟨candidate.production, productionBound⟩)
  have rhsLengthEvaluation : Evaluates verifiedParserCore originScope
      (.call extractedParserRhsLengthFunction.id [.local 0, .local 25])
      (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length))
      rhsRead.after := by
    simpa only [rhsLengthValue] using rhsRead.evaluation
  let afterRhs := originInvariant.after_empty_effect rhsRead.effect
    rhsRead.invariant.recognizer.wellFormed
  let rhsLength :=
    (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
  let rhsScope := rhsRead.after.bindLocal 28
    (.signed .i32 (Int.ofNat rhsLength))
  let rhsInvariant := afterRhs.after_bind_local 28
    (.signed .i32 (Int.ofNat rhsLength)) (by decide)
  have productionAtRhsRead : rhsRead.after.local? 25 = some
      (.signed .i32 (Int.ofNat candidate.production)) :=
    rhsRead.effect.empty_preserves_local
      originInvariant.chartCursor.recognizer.wellFormed productionAtOriginScope
  have dotAtRhsRead : rhsRead.after.local? 26 = some
      (.signed .i32 (Int.ofNat candidate.dot)) :=
    rhsRead.effect.empty_preserves_local
      originInvariant.chartCursor.recognizer.wellFormed dotAtOriginScope
  have originAtRhsRead : rhsRead.after.local? 27 = some
      (.signed .i32 (Int.ofNat candidate.origin)) :=
    rhsRead.effect.empty_preserves_local
      originInvariant.chartCursor.recognizer.wellFormed originAtOriginScope
  let productionCell := productionRead.after.nextCell
  have productionOwnedAtProductionScope :
      (Assertion.localPointsTo 25 productionCell
        (some (.signed .i32 (Int.ofNat candidate.production)))).holds
        productionScope := by
    simpa [productionCell, productionScope] using
      bindLocal_owns_fresh productionRead.after 25
        (.signed .i32 (Int.ofNat candidate.production))
        productionRead.invariant.recognizer.wellFormed
  have productionOwnedAtDotRead :
      (Assertion.localPointsTo 25 productionCell
        (some (.signed .i32 (Int.ofNat candidate.production)))).holds
        dotRead.after :=
    dotRead.effect.empty_preserves_assertion
      productionInvariant.chartCursor.recognizer.wellFormed _
      productionOwnedAtProductionScope
  have productionOwnedAtDotScope :
      (Assertion.localPointsTo 25 productionCell
        (some (.signed .i32 (Int.ofNat candidate.production)))).holds
        dotScope := by
    simpa [dotScope] using bindLocal_preserves_localPointsTo_of_ne
      dotRead.after 26 25 (.signed .i32 (Int.ofNat candidate.dot))
      productionCell (some (.signed .i32 (Int.ofNat candidate.production)))
      dotRead.invariant.recognizer.wellFormed (by decide)
      productionOwnedAtDotRead
  have productionOwnedAtOriginRead :
      (Assertion.localPointsTo 25 productionCell
        (some (.signed .i32 (Int.ofNat candidate.production)))).holds
        originRead.after :=
    originRead.effect.empty_preserves_assertion
      dotInvariant.chartCursor.recognizer.wellFormed _
      productionOwnedAtDotScope
  have productionOwnedAtOriginScope :
      (Assertion.localPointsTo 25 productionCell
        (some (.signed .i32 (Int.ofNat candidate.production)))).holds
        originScope := by
    simpa [originScope] using bindLocal_preserves_localPointsTo_of_ne
      originRead.after 27 25 (.signed .i32 (Int.ofNat candidate.origin))
      productionCell (some (.signed .i32 (Int.ofNat candidate.production)))
      originRead.invariant.recognizer.wellFormed (by decide)
      productionOwnedAtOriginRead
  have productionOwnedAtRhsRead :
      (Assertion.localPointsTo 25 productionCell
        (some (.signed .i32 (Int.ofNat candidate.production)))).holds
        rhsRead.after :=
    rhsRead.effect.empty_preserves_assertion
      originInvariant.chartCursor.recognizer.wellFormed _
      productionOwnedAtOriginScope
  have productionOwned :
      (Assertion.localPointsTo 25 productionCell
        (some (.signed .i32 (Int.ofNat candidate.production)))).holds
        rhsScope := by
    simpa [rhsScope] using bindLocal_preserves_localPointsTo_of_ne
      rhsRead.after 28 25 (.signed .i32 (Int.ofNat rhsLength))
      productionCell (some (.signed .i32 (Int.ofNat candidate.production)))
      rhsRead.invariant.recognizer.wellFormed (by decide)
      productionOwnedAtRhsRead
  let dotCell := dotRead.after.nextCell
  have dotOwnedAtDotScope : (Assertion.localPointsTo 26 dotCell
      (some (.signed .i32 (Int.ofNat candidate.dot)))).holds dotScope := by
    simpa [dotCell, dotScope] using bindLocal_owns_fresh dotRead.after 26
      (.signed .i32 (Int.ofNat candidate.dot))
      dotRead.invariant.recognizer.wellFormed
  have dotOwnedAtOriginRead : (Assertion.localPointsTo 26 dotCell
      (some (.signed .i32 (Int.ofNat candidate.dot)))).holds
      originRead.after :=
    originRead.effect.empty_preserves_assertion
      dotInvariant.chartCursor.recognizer.wellFormed _ dotOwnedAtDotScope
  have dotOwnedAtOriginScope : (Assertion.localPointsTo 26 dotCell
      (some (.signed .i32 (Int.ofNat candidate.dot)))).holds originScope := by
    simpa [originScope] using bindLocal_preserves_localPointsTo_of_ne
      originRead.after 27 26 (.signed .i32 (Int.ofNat candidate.origin))
      dotCell (some (.signed .i32 (Int.ofNat candidate.dot)))
      originRead.invariant.recognizer.wellFormed (by decide)
      dotOwnedAtOriginRead
  have dotOwnedAtRhsRead : (Assertion.localPointsTo 26 dotCell
      (some (.signed .i32 (Int.ofNat candidate.dot)))).holds rhsRead.after :=
    rhsRead.effect.empty_preserves_assertion
      originInvariant.chartCursor.recognizer.wellFormed _ dotOwnedAtOriginScope
  have dotOwned : (Assertion.localPointsTo 26 dotCell
      (some (.signed .i32 (Int.ofNat candidate.dot)))).holds rhsScope := by
    simpa [rhsScope] using bindLocal_preserves_localPointsTo_of_ne
      rhsRead.after 28 26 (.signed .i32 (Int.ofNat rhsLength)) dotCell
      (some (.signed .i32 (Int.ofNat candidate.dot)))
      rhsRead.invariant.recognizer.wellFormed (by decide) dotOwnedAtRhsRead
  let originCell := originRead.after.nextCell
  have originOwnedAtOriginScope : (Assertion.localPointsTo 27 originCell
      (some (.signed .i32 (Int.ofNat candidate.origin)))).holds
      originScope := by
    simpa [originCell, originScope] using bindLocal_owns_fresh
      originRead.after 27 (.signed .i32 (Int.ofNat candidate.origin))
      originRead.invariant.recognizer.wellFormed
  have originOwnedAtRhsRead : (Assertion.localPointsTo 27 originCell
      (some (.signed .i32 (Int.ofNat candidate.origin)))).holds
      rhsRead.after :=
    rhsRead.effect.empty_preserves_assertion
      originInvariant.chartCursor.recognizer.wellFormed _
      originOwnedAtOriginScope
  have originOwned : (Assertion.localPointsTo 27 originCell
      (some (.signed .i32 (Int.ofNat candidate.origin)))).holds rhsScope := by
    simpa [rhsScope] using bindLocal_preserves_localPointsTo_of_ne
      rhsRead.after 28 27 (.signed .i32 (Int.ofNat rhsLength)) originCell
      (some (.signed .i32 (Int.ofNat candidate.origin)))
      rhsRead.invariant.recognizer.wellFormed (by decide) originOwnedAtRhsRead
  have productionCellDistinct : productionCell ≠ workspaceCell ∧
      productionCell ≠ stateCountCell ∧ productionCell ≠ cursorCell := by
    exact ⟨Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        productionRead.invariant.recognizer.wellFormed
        productionRead.invariant.recognizer.workspaceBacking,
      Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        productionRead.invariant.recognizer.wellFormed
        afterProduction.appendFrame.stateCountOwned.2,
      Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        productionRead.invariant.recognizer.wellFormed
        productionRead.invariant.cursorOwned.2⟩
  have dotCellDistinct : dotCell ≠ workspaceCell ∧
      dotCell ≠ stateCountCell ∧ dotCell ≠ cursorCell := by
    exact ⟨Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        dotRead.invariant.recognizer.wellFormed
        dotRead.invariant.recognizer.workspaceBacking,
      Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        dotRead.invariant.recognizer.wellFormed
        afterDot.appendFrame.stateCountOwned.2,
      Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        dotRead.invariant.recognizer.wellFormed
        dotRead.invariant.cursorOwned.2⟩
  have originCellDistinct : originCell ≠ workspaceCell ∧
      originCell ≠ stateCountCell ∧ originCell ≠ cursorCell := by
    exact ⟨Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        originRead.invariant.recognizer.wellFormed
        originRead.invariant.recognizer.workspaceBacking,
      Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        originRead.invariant.recognizer.wellFormed
        afterOrigin.appendFrame.stateCountOwned.2,
      Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        originRead.invariant.recognizer.wellFormed
        originRead.invariant.cursorOwned.2⟩
  exact {
    afterProductionRead := productionRead.after
    productionEvaluation := productionEvaluation
    productionEffect := productionRead.effect
    afterProductionWellFormed := productionRead.invariant.recognizer.wellFormed
    afterDotRead := dotRead.after
    dotEvaluation := by simpa [productionScope, productionInvariant] using
      dotEvaluation
    dotEffect := by simpa [productionScope, productionInvariant] using
      dotRead.effect
    afterDotWellFormed := dotRead.invariant.recognizer.wellFormed
    afterOriginRead := originRead.after
    originEvaluation := by simpa [dotScope, dotInvariant] using originEvaluation
    originEffect := by simpa [dotScope, dotInvariant] using originRead.effect
    afterOriginWellFormed := originRead.invariant.recognizer.wellFormed
    afterRhsLengthRead := rhsRead.after
    rhsLengthEvaluation := by
      simpa [originScope, originInvariant, rhsLength] using rhsLengthEvaluation
    rhsLengthEffect := by simpa [originScope, originInvariant] using rhsRead.effect
    afterRhsLengthWellFormed := rhsRead.invariant.recognizer.wellFormed
    invariant := by simpa [rhsScope, rhsLength] using rhsInvariant
    productionLocal :=
      (bindLocal_preserves_other_local rhsRead.invariant.recognizer.wellFormed
        (by decide : 28 ≠ 25)).trans productionAtRhsRead
    productionCell := productionCell
    productionOwned := by simpa [rhsScope, rhsLength] using productionOwned
    productionCellDistinct := productionCellDistinct
    dotLocal :=
      (bindLocal_preserves_other_local rhsRead.invariant.recognizer.wellFormed
        (by decide : 28 ≠ 26)).trans dotAtRhsRead
    dotCell := dotCell
    dotOwned := by simpa [rhsScope, rhsLength] using dotOwned
    dotCellDistinct := dotCellDistinct
    originLocal :=
      (bindLocal_preserves_other_local rhsRead.invariant.recognizer.wellFormed
        (by decide : 28 ≠ 27)).trans originAtRhsRead
    originCell := originCell
    originOwned := by simpa [rhsScope, rhsLength] using originOwned
    originCellDistinct := originCellDistinct
    rhsLengthLocal := by
      simpa [rhsLength] using bindLocal_finds_local rhsRead.after 28
        (.signed .i32 (Int.ofNat rhsLength))
        rhsRead.invariant.recognizer.wellFormed
  }

/-- Exact lexical and ownership boundary between a completed state and its
    parent-replay loop.  The LHS and origin cursor are both artifact-derived;
    active and empty origin charts share this one entry contract. -/
structure RecognizerStateParentEntry
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
    (completedLhs : Nat) where
  completedLhsEq : completedLhs =
    (grammar.productionAt ⟨candidate.production, productionBound⟩).lhs
  afterLhsRead : State
  lhsEvaluation : Evaluates verifiedParserCore
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)))
    (.call extractedParserLhsFunction.id [.local 0, .local 25])
    (.signed .i32 (Int.ofNat completedLhs)) afterLhsRead
  lhsEffect : ModifiesOnly CellSet.empty
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)))
    afterLhsRead
  afterLhsWellFormed : StateWellFormed afterLhsRead
  lhsCell : CellId
  boundLhs : State
  boundLhsEq : boundLhs = afterLhsRead.bindLocal 29
    (.signed .i32 (Int.ofNat completedLhs))
  lhsInvariant : RecognizerStateLoopInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell stateCursorCell boundLhs position current
    remaining
  originAtLhs : boundLhs.local? 27 =
    some (.signed .i32 (Int.ofNat candidate.origin))
  chartEntry : RecognizerChartLoopEntry grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell boundLhs 27 candidate.origin 30
    lhsInvariant.chartCursor.recognizer
    lhsInvariant.chartCursor.workspaceWithinGrammar
    lhsInvariant.chartCursor.stateBaseLocal originAtLhs
    (bindings.invariant.chartCursor.recognizer.workspaceEncoded.originsBound
      current candidate found)
  cursor :
    (Sigma fun parent : Nat => Sigma fun parentRemaining : List Nat =>
      RecognizerParentLoopInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell chartEntry.cursorCell chartEntry.bound
        position current completedLhs candidate.origin parent parentRemaining)
    ⊕ RecognizerParentFinishedInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell chartEntry.cursorCell chartEntry.bound
        position current completedLhs candidate.origin

noncomputable def RecognizerStateCandidateBindings.enter_parent
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound)
    (_completed : candidate.dot =
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length) :
    Sigma fun completedLhs =>
      RecognizerStateParentEntry grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell stateCursorCell before position current
        remaining beforeInvariant candidate found productionBound bindings
        completedLhs := by
  let completedLhs :=
    (grammar.productionAt ⟨candidate.production, productionBound⟩).lhs
  have productionResult : Evaluates verifiedParserCore
      (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)))
      (.local 25) (.signed .i32 (Int.ofNat candidate.production))
      (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length))) :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore _ 25 _ bindings.productionLocal⟩
  let lhsRead := bindings.invariant.chartCursor.read_lhs candidate.production
    productionBound (.local 25) productionResult
  have lhsEvaluation : Evaluates verifiedParserCore
      (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)))
      (.call extractedParserLhsFunction.id [.local 0, .local 25])
      (.signed .i32 (Int.ofNat completedLhs)) lhsRead.after := by
    have lhsValue : grammar.productionLhs.get
        ⟨candidate.production, by simpa using productionBound⟩ = completedLhs := by
      simpa [completedLhs] using grammar.productionLhs_get
        ⟨candidate.production, productionBound⟩
    simpa only [lhsValue] using lhsRead.evaluation
  let afterLhs := bindings.invariant.after_empty_effect lhsRead.effect
    lhsRead.invariant.recognizer.wellFormed
  let lhsCell := lhsRead.after.nextCell
  let boundLhs := lhsRead.after.bindLocal 29
    (.signed .i32 (Int.ofNat completedLhs))
  let lhsInvariant := afterLhs.after_bind_local 29
    (.signed .i32 (Int.ofNat completedLhs)) (by decide)
  have originAfterRead : lhsRead.after.local? 27 =
      some (.signed .i32 (Int.ofNat candidate.origin)) :=
    lhsRead.effect.empty_preserves_local
      bindings.invariant.chartCursor.recognizer.wellFormed bindings.originLocal
  have originAtLhs : boundLhs.local? 27 =
      some (.signed .i32 (Int.ofNat candidate.origin)) := by
    exact (bindLocal_preserves_other_local lhsRead.invariant.recognizer.wellFormed
      (by decide : 29 ≠ 27)).trans originAfterRead
  have originBound : candidate.origin ≤
      finalPosition workspaceLayout.tokenCount :=
    bindings.invariant.chartCursor.recognizer.workspaceEncoded.originsBound
      current candidate found
  let chartEntry := lhsInvariant.chartCursor.recognizer.enter_chart_loop
    lhsInvariant.chartCursor.workspaceWithinGrammar
    lhsInvariant.chartCursor.stateBaseLocal 27 candidate.origin 30 originAtLhs
    originBound (by decide)
  have lhsOwned : (Assertion.localPointsTo 29 lhsCell
      (some (.signed .i32 (Int.ofNat completedLhs)))).holds boundLhs := by
    simpa [boundLhs, lhsCell] using bindLocal_owns_fresh lhsRead.after 29
      (.signed .i32 (Int.ofNat completedLhs))
      lhsRead.invariant.recognizer.wellFormed
  have lhsCellDistinct : lhsCell ≠ workspaceCell ∧ lhsCell ≠ stateCountCell :=
    ⟨Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        lhsRead.invariant.recognizer.wellFormed
        lhsRead.invariant.recognizer.workspaceBacking,
      Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
        lhsRead.invariant.recognizer.wellFormed
        afterLhs.appendFrame.stateCountOwned.2⟩
  have sourceCellId (id : VarId) (different : id ≠ 29) :
      boundLhs.cellId? id =
        (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
          (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length))).cellId? id := by
    rw [show boundLhs = lhsRead.after.bindLocal 29
      (.signed .i32 (Int.ofNat completedLhs)) by rfl]
    rw [bindLocal_preserves_other_cellId _ 29 id _ different.symm]
    unfold State.cellId?
    rw [lhsRead.effect.locals]
  have externalAtLhs (id : VarId) (preserved : ParentPreservedLocal id) :
      boundLhs.cellId? id ≠ some workspaceCell ∧
      boundLhs.cellId? id ≠ some stateCountCell := by
    rcases preserved with parameter | shared
    · have separated := bindings.invariant.persistentLocalsSeparate id
          (Or.inl parameter)
      have different : id ≠ 29 := by
        have bound := (mem_verifiedParserRecognizerParameterIds_iff id).mp parameter
        exact Nat.ne_of_lt (Nat.lt_of_le_of_lt bound (by decide))
      rw [sourceCellId id different]
      exact ⟨separated.1, separated.2.1 (by
        have bound := (mem_verifiedParserRecognizerParameterIds_iff id).mp parameter
        exact Nat.ne_of_lt (Nat.lt_of_le_of_lt bound (by decide)))⟩
    · rw [mem_verifiedParserParentLoopPreservedFrameIds_iff] at shared
      rcases shared with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
      · rw [sourceCellId 4 (by decide)]
        exact ⟨bindings.invariant.persistentLocalsSeparate 4 (by
          simp [StateLoopPersistentLocal]) |>.1,
          bindings.invariant.persistentLocalsSeparate 4 (by
            simp [StateLoopPersistentLocal]) |>.2.1 (by decide)⟩
      · rw [sourceCellId 8 (by decide)]
        exact ⟨bindings.invariant.persistentLocalsSeparate 8 (by
          simp [StateLoopPersistentLocal]) |>.1,
          bindings.invariant.persistentLocalsSeparate 8 (by
            simp [StateLoopPersistentLocal]) |>.2.1 (by decide)⟩
      · rw [sourceCellId 0 (by decide)]
        exact ⟨bindings.invariant.persistentLocalsSeparate 0 (by
          simp [StateLoopPersistentLocal]) |>.1,
          bindings.invariant.persistentLocalsSeparate 0 (by
            simp [StateLoopPersistentLocal]) |>.2.1 (by decide)⟩
      · rw [sourceCellId 11 (by decide)]
        exact ⟨bindings.invariant.persistentLocalsSeparate 11 (by
          simp [StateLoopPersistentLocal]) |>.1,
          bindings.invariant.persistentLocalsSeparate 11 (by
            simp [StateLoopPersistentLocal]) |>.2.1 (by decide)⟩
      · exact ⟨fun same => lhsCellDistinct.1
            (Option.some.inj (lhsOwned.1.symm.trans same)),
          fun same => lhsCellDistinct.2
            (Option.some.inj (lhsOwned.1.symm.trans same))⟩
      · rw [sourceCellId 9 (by decide)]
        exact ⟨bindings.invariant.persistentLocalsSeparate 9 (by
          simp [StateLoopPersistentLocal]) |>.1,
          bindings.invariant.persistentLocalsSeparate 9 (by
            simp [StateLoopPersistentLocal]) |>.2.1 (by decide)⟩
      · rw [sourceCellId 23 (by decide)]
        exact ⟨bindings.invariant.persistentLocalsSeparate 23 (by
          simp [StateLoopPersistentLocal]) |>.1,
          bindings.invariant.persistentLocalsSeparate 23 (by
            simp [StateLoopPersistentLocal]) |>.2.1 (by decide)⟩
      · rw [sourceCellId 24 (by decide)]
        exact ⟨fun same =>
            bindings.invariant.chartCursor.cursorBackingDistinct.2.2
              (Option.some.inj
                (bindings.invariant.chartCursor.cursorOwned.1.symm.trans same)),
          fun same => bindings.invariant.cursorStateCountDistinct
            (Option.some.inj
              (bindings.invariant.chartCursor.cursorOwned.1.symm.trans same))⟩
  have parentCursorFresh : CellSet.Disjoint
      (localBindingFrameFootprint chartEntry.bound
        verifiedParserParentPreservedBindings)
      (CellSet.singleton chartEntry.cursorCell) := by
    rw [chartEntry.boundEq, chartEntry.cursorCellEq]
    simpa using bindLocal_fresh_disjoint_from_frame chartEntry.headRead.after 30
      (.signed .i32 (chartHeadValue workspace candidate.origin))
      verifiedParserParentPreservedBindings chartEntry.headRead.invariant.wellFormed
      (by
        rw [LocalBindingFrame.ContainsCoreId,
          verifiedParserParentPreservedBindings_core_ids]
        native_decide)
  have parentSeparated : ParentFrameSeparated chartEntry.bound workspaceCell
      stateCountCell chartEntry.cursorCell := by
    intro cell framed written
    obtain ⟨id, sourceMember, cellId⟩ := framed
    have preserved := (ParentPreservedLocal_source_frame id).mpr sourceMember
    have idLt : id < 30 := Nat.lt_of_le_of_lt
      (ParentPersistentLocal.le29 id
        ((ParentPreservedLocal_iff id).mp preserved).1) (by decide)
    have atHead : chartEntry.headRead.after.cellId? id = some cell := by
      exact (bindLocal_preserves_other_cellId chartEntry.headRead.after 30 id _
        (Nat.ne_of_gt idLt)).symm.trans (by
          rw [chartEntry.boundEq] at cellId
          exact cellId)
    have atLhs : boundLhs.cellId? id = some cell := by
      unfold State.cellId? at atHead ⊢
      rw [chartEntry.headRead.effect.locals] at atHead
      exact atHead
    change cell = workspaceCell ∨ cell = stateCountCell ∨
      cell = chartEntry.cursorCell at written
    rcases written with rfl | rfl | rfl
    · exact (externalAtLhs id preserved).1 atLhs
    · exact (externalAtLhs id preserved).2 atLhs
    · exact parentCursorFresh chartEntry.cursorCell
        ⟨id, sourceMember, cellId⟩ rfl
  let afterHeadFrame := lhsInvariant.appendFrame.after_empty_effect
    chartEntry.headRead.effect chartEntry.headRead.invariant.wellFormed
  let parentAppendFrame := afterHeadFrame.after_bind_local 30
    (.signed .i32 (chartHeadValue workspace candidate.origin))
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide) (by decide) (by decide)
  have preserveLocal (id : VarId) (different : 30 ≠ id) (value : Value)
      (foundLocal : boundLhs.local? id = some value) :
      chartEntry.bound.local? id = some value := by
    have afterRead := chartEntry.headRead.effect.empty_preserves_local
      lhsInvariant.chartCursor.recognizer.wellFormed foundLocal
    rw [chartEntry.boundEq]
    exact (bindLocal_preserves_other_local
      chartEntry.headRead.invariant.wellFormed different).trans afterRead
  have completedLhsBound : completedLhs < grammar.grammar.n_nonterminals := by
    simpa [completedLhs] using
      bindings.invariant.chartCursor.recognizer.grammarWellFormed
        |>.production_validation.lhsInBounds
          ⟨candidate.production, productionBound⟩
  have candidatePosition : candidate.position = position := by
    obtain ⟨cursorState, cursorFound, cursorPosition⟩ :=
      beforeInvariant.chartCursor.state_at_cursor
    rw [found] at cursorFound
    injection cursorFound with stateEqual
    subst cursorState
    exact cursorPosition
  have completedRecognizes : RecognizesSymbol grammar tokens
      (grammar.grammar.n_kinds + completedLhs) candidate.origin position := by
    have candidateSound :=
      bindings.invariant.chartCursor.recognizer.languageSound current candidate
        found
    have completed := candidateSound.complete completedLhsBound _completed
    simpa [completedLhs, candidatePosition] using completed
  have completedStored : StoredCompletion grammar workspace current completedLhs
      candidate.origin position := {
    state := candidate
    found := found
    productionBound := by simpa [EarleyState.key] using productionBound
    lhs := by simp [completedLhs]
    complete := _completed
    originEq := rfl
    positionEq := candidatePosition
  }
  have completedAtLhs : boundLhs.local? 24 =
      some (.signed .i32 (Int.ofNat current)) :=
    Assertion.localPointsTo_local 24 stateCursorCell _ boundLhs
      lhsInvariant.chartCursor.cursorOwned
  have completedLhsAtLhs : boundLhs.local? 29 =
      some (.signed .i32 (Int.ofNat completedLhs)) :=
    Assertion.localPointsTo_local 29 lhsCell _ boundLhs lhsOwned
  have cursorCountDistinct : chartEntry.cursorCell ≠ stateCountCell := by
    rw [chartEntry.cursorCellEq]
    exact Lanius.Separation.StateWellFormed.nextCell_ne_of_entry
      chartEntry.headRead.invariant.wellFormed afterHeadFrame.stateCountOwned.2
  refine ⟨completedLhs, {
    completedLhsEq := rfl
    afterLhsRead := lhsRead.after
    lhsEvaluation := lhsEvaluation
    lhsEffect := lhsRead.effect
    afterLhsWellFormed := lhsRead.invariant.recognizer.wellFormed
    lhsCell := lhsCell
    boundLhs := boundLhs
    boundLhsEq := rfl
    lhsInvariant := by simpa [boundLhs, lhsInvariant] using lhsInvariant
    originAtLhs := originAtLhs
    chartEntry := chartEntry
    cursor := ?_
  }⟩
  cases chartEntry.cursor with
  | inl active =>
      obtain ⟨parent, parentRemaining, parentCursor⟩ := active
      exact .inl ⟨parent, parentRemaining, {
        chartCursor := parentCursor
        appendFrame := by
          rw [chartEntry.boundEq]
          exact parentAppendFrame
        kindCountLocal := preserveLocal 11 (by decide) _
          lhsInvariant.kindCountLocal
        positionLocal := preserveLocal 23 (by decide) _
          lhsInvariant.positionLocal
        completedLocal := preserveLocal 24 (by decide) _ completedAtLhs
        completedLhsLocal := preserveLocal 29 (by decide) _ completedLhsAtLhs
        completedLhsBound := completedLhsBound
        completedStored := completedStored
        completedRecognizes := completedRecognizes
        persistentSeparate := parentSeparated
        cursorStateCountDistinct := cursorCountDistinct
      }⟩
  | inr finished =>
      exact .inr {
        chartCursor := finished
        appendFrame := by
          rw [chartEntry.boundEq]
          exact parentAppendFrame
        kindCountLocal := preserveLocal 11 (by decide) _
          lhsInvariant.kindCountLocal
        positionLocal := preserveLocal 23 (by decide) _
          lhsInvariant.positionLocal
        completedLocal := preserveLocal 24 (by decide) _ completedAtLhs
        completedLhsLocal := preserveLocal 29 (by decide) _ completedLhsAtLhs
        completedLhsBound := completedLhsBound
        completedStored := completedStored
        completedRecognizes := completedRecognizes
        persistentSeparate := parentSeparated
        cursorStateCountDistinct := cursorCountDistinct
      }

/-- Physical compatibility view used while outer Core-local restoration is
    migrated.  It deliberately carries no FunctionalView fields, so legacy
    callers cannot accidentally eliminate a dependently indexed synchronized
    result. -/
private structure CoreExecutionOutcome
    (program : Program) (before : State) (statement : Stmt) (writes : CellSet)
    (result : State → Completion → Prop) where
  after : State
  completion : Completion
  execution : Executes program before statement completion after
  effect : ModifiesOnly writes before after
  outcome : result after completion

/-- A physical execution whose completion is fixed by an enclosing semantic
    run.  Unlike `CoreExecutionOutcome`, this form does not existentially hide
    the completion and therefore preserves dependent synchronization. -/
private structure FixedCoreExecutionOutcome
    (program : Program) (before : State) (statement : Stmt) (writes : CellSet)
    (completion : Completion) (result : State → Prop) where
  after : State
  execution : Executes program before statement completion after
  effect : ModifiesOnly writes before after
  outcome : result after

/-- The source-derived completed-state entry is already one of the compact
    FunctionalView parent configurations.  Keeping this definition beside the
    physical scope executor makes that executor a projection of the same run,
    rather than a second active/sentinel implementation. -/
noncomputable def RecognizerStateParentEntry.functionalConfig
    (entry : RecognizerStateParentEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs) :
    RecognizerParentConfig grammarLayout grammar words tokens workspaceLayout
      grammarCell tokensCell workspaceCell stateCountCell
      entry.chartEntry.cursorCell position current completedLhs
      candidate.origin :=
  match entry.cursor with
  | .inl ⟨parent, parentRemaining, invariant⟩ => .active {
      workspace := workspace
      workspaceValues := workspaceValues
      runtime := entry.chartEntry.bound
      current := parent
      remaining := parentRemaining
      invariant := invariant
    }
  | .inr invariant => .sentinel {
      workspace := workspace
      workspaceValues := workspaceValues
      runtime := entry.chartEntry.bound
      invariant := invariant
    }

/-- Parent replay while both completion-specific lexical bindings are live. -/
structure RecognizerStateParentInnerExecution
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
      completedLhs) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore entry.chartEntry.bound
    (.sequence parserRecognizeParentLoop .skip) completion after
  effect : ModifiesOnly
    (parentFrameMutableCells workspaceCell stateCountCell
      entry.chartEntry.cursorCell) entry.chartEntry.bound after
  completionEq : completion =
    Lanius.FunctionalView.Core.Stateful.toCoreCompletion
      entry.functionalConfig.functional_run.completion
  outcome : RecognizerParentSynchronizedOutcome grammarLayout grammar words
    tokens workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell entry.chartEntry.cursorCell position current completedLhs
    candidate.origin entry.functionalConfig.functional_run.after after
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
      entry.functionalConfig.functional_run.completion)

private noncomputable def RecognizerStateParentInnerExecution.physical
    (execution : RecognizerStateParentInnerExecution grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs entry) :
    CoreExecutionOutcome verifiedParserCore entry.chartEntry.bound
      (.sequence parserRecognizeParentLoop .skip)
      (parentFrameMutableCells workspaceCell stateCountCell
        entry.chartEntry.cursorCell)
      (RecognizerParentLoopOutcome grammarLayout grammar words tokens
        workspaceLayout workspace grammarCell tokensCell workspaceCell
        stateCountCell entry.chartEntry.cursorCell position current completedLhs
        candidate.origin) := {
  after := execution.after
  completion := Lanius.FunctionalView.Core.Stateful.toCoreCompletion
    entry.functionalConfig.functional_run.completion
  execution := by
    rw [← execution.completionEq]
    exact execution.execution
  effect := execution.effect
  outcome := execution.outcome.physical
}

/-- Compatibility view that preserves the synchronized parent result while
    presenting the physical execution at the FunctionalView completion.  The
    enclosing source scope uses this view so restoration cannot discard the
    compact world and environment reached by normal parent replay. -/
private noncomputable def RecognizerStateParentInnerExecution.synchronizedPhysical
    (execution : RecognizerStateParentInnerExecution grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs entry) :
    FixedCoreExecutionOutcome verifiedParserCore entry.chartEntry.bound
      (.sequence parserRecognizeParentLoop .skip)
      (parentFrameMutableCells workspaceCell stateCountCell
        entry.chartEntry.cursorCell)
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
        entry.functionalConfig.functional_run.completion)
      (fun after => RecognizerParentSynchronizedOutcome grammarLayout grammar
        words tokens workspaceLayout workspace grammarCell tokensCell
        workspaceCell stateCountCell entry.chartEntry.cursorCell position current
        completedLhs candidate.origin entry.functionalConfig.functional_run.after
        after (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
          entry.functionalConfig.functional_run.completion)) := {
  after := execution.after
  execution := by
    rw [← execution.completionEq]
    exact execution.execution
  effect := execution.effect
  outcome := execution.outcome
}

noncomputable def RecognizerStateParentEntry.execute_inner
    (entry : RecognizerStateParentEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs) :
    RecognizerStateParentInnerExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs entry := by
  generalize runEq : entry.functionalConfig.functional_run = loop
  obtain ⟨completion, functionalAfter, trace, result⟩ := loop
  have sourceCompletionEq :
      entry.functionalConfig.functional_run.completion = completion := by
    simpa using congrArg
      (fun run => run.completion) runEq
  have sourceAfterEq : entry.functionalConfig.functional_run.after =
      functionalAfter := by
    simpa using congrArg (fun run => run.after) runEq
  have runtimeEq : entry.functionalConfig.runtime = entry.chartEntry.bound := by
    cases cursorEq : entry.cursor <;>
      simp [RecognizerStateParentEntry.functionalConfig, cursorEq]
  have workspaceEq : entry.functionalConfig.workspace = workspace := by
    cases cursorEq : entry.cursor <;>
      simp [RecognizerStateParentEntry.functionalConfig, cursorEq]
  have loopExecution : Executes verifiedParserCore entry.chartEntry.bound
      parserRecognizeParentLoop
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
      result.physicalAfter := by
    rw [← runtimeEq]
    exact result.execution
  have loopEffect : ModifiesOnly
      (parentFrameMutableCells workspaceCell stateCountCell
        entry.chartEntry.cursorCell) entry.chartEntry.bound
      result.physicalAfter := by
    rw [← runtimeEq]
    simpa [parentFrameMutableCells] using result.effect
  have existsResult : ∃ result :
      RecognizerStateParentInnerExecution grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell stateCursorCell before position current
        remaining beforeInvariant candidate found productionBound bindings
        completedLhs entry, True := by
    cases completion with
    | next =>
        cases result.outcome with
        | completed nextWorkspace nextValues physicalAfter growth finished
            worldEq environmentEq =>
            have growth' := growth
            rw [workspaceEq] at growth'
            exact ⟨{
              after := result.physicalAfter
              completion := .next
              execution := executesSequence
                (by simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion]
                  using loopExecution)
                (executesSkip verifiedParserCore result.physicalAfter)
              effect := loopEffect
              completionEq := by
                simpa [sourceCompletionEq,
                  Lanius.FunctionalView.Core.Stateful.toCoreCompletion]
              outcome := by
                simpa [sourceCompletionEq, sourceAfterEq,
                  Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
                  (RecognizerParentSynchronizedOutcome.completed nextWorkspace
                    nextValues result.physicalAfter growth' finished worldEq
                    environmentEq)
            }, trivial⟩
    | returned value =>
        cases result.outcome with
        | full finalWorkspace finalValues physicalAfter growth terminal
            stateCount wellFormed =>
            have growth' := growth
            rw [workspaceEq] at growth'
            exact ⟨{
              after := result.physicalAfter
              completion := parserCapacityCompletion position stateCount
              execution := executesSequenceReturned
                (by simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion]
                  using loopExecution)
              effect := loopEffect
              completionEq := by
                simpa [sourceCompletionEq,
                  Lanius.FunctionalView.Core.Stateful.toCoreCompletion,
                  parserCapacityCompletion]
              outcome := by
                simpa [sourceCompletionEq, sourceAfterEq,
                  Lanius.FunctionalView.Core.Stateful.toCoreCompletion,
                  parserCapacityCompletion] using
                  (RecognizerParentSynchronizedOutcome.full finalWorkspace
                    finalValues result.physicalAfter growth' terminal stateCount
                    wellFormed)
            }, trivial⟩
    | breakLoop => cases result.outcome
    | continueLoop => cases result.outcome
  exact Classical.choose existsResult

/-- Parent replay after its two source-local bindings have closed.  Normal
    completion retains the exact compact FunctionalView world/environment and
    the restored physical state-loop frame.  Capacity exhaustion carries only
    the terminal physical result because no source continuation observes an
    environment after a returned completion. -/
inductive RecognizerStateParentSynchronizedOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position current : Nat) (beforeRemaining : List Nat)
    (completedLhs : Nat)
    (after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (parentTermMachine workspaceLayout grammar words grammarCell) 10) :
    State → Completion → Type where
  | completed (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (frame : RecognizerStateGrowthFrame grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace workspace workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell cursorCell physicalAfter
        position current beforeRemaining)
      (worldEq : after.world = parentWorld words tokens workspaceValues
        grammarCell tokensCell workspaceCell)
      (environmentEq : after.environment = parentEnvironment words
        workspaceValues grammarCell workspaceCell workspaceLayout
        workspace.states.length grammar.grammar.n_kinds position current
        completedLhs (-1)) :
      RecognizerStateParentSynchronizedOutcome grammarLayout grammar words
        tokens workspaceLayout beforeWorkspace grammarCell tokensCell
        workspaceCell stateCountCell cursorCell position current beforeRemaining
        completedLhs after physicalAfter .next
  | full (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (terminal : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter) :
      RecognizerStateParentSynchronizedOutcome grammarLayout grammar words
        tokens workspaceLayout beforeWorkspace grammarCell tokensCell
        workspaceCell stateCountCell cursorCell position current beforeRemaining
        completedLhs after physicalAfter
        (parserCapacityCompletion position stateCount)

def RecognizerStateParentSynchronizedOutcome.physical
    (outcome : RecognizerStateParentSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position current beforeRemaining
      completedLhs after physicalAfter completion) :
    RecognizerStateOperationOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position current beforeRemaining physicalAfter
      completion := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter growth frame _ _ =>
      exact .completed workspace workspaceValues physicalAfter growth frame
  | full workspace workspaceValues physicalAfter growth terminal stateCount
      wellFormed =>
      exact .full workspace workspaceValues physicalAfter growth terminal
        stateCount wellFormed

theorem RecognizerStateParentSynchronizedOutcome.view
    (outcome : RecognizerStateParentSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position current beforeRemaining
      completedLhs after physicalAfter completion) :
    (completion = .next ∧
      ∃ workspace : LogicalWorkspace,
      ∃ workspaceValues : List Int,
      ∃ growth : WorkspaceAppendClosure workspaceLayout.capacity
          beforeWorkspace workspace,
      ∃ frame : RecognizerStateGrowthFrame grammarLayout grammar words tokens
          workspaceLayout beforeWorkspace workspace workspaceValues grammarCell
          tokensCell workspaceCell stateCountCell cursorCell physicalAfter
          position current beforeRemaining,
        after.world = parentWorld words tokens workspaceValues grammarCell
          tokensCell workspaceCell ∧
        after.environment = parentEnvironment words workspaceValues grammarCell
          workspaceCell workspaceLayout workspace.states.length
          grammar.grammar.n_kinds position current completedLhs (-1)) ∨
    (∃ workspace : LogicalWorkspace,
      ∃ workspaceValues : List Int,
      ∃ growth : WorkspaceAppendClosure workspaceLayout.capacity
          beforeWorkspace workspace,
      ∃ terminal : RecognizerInvariant grammarLayout grammar words tokens
          workspaceLayout workspace workspaceValues grammarCell tokensCell
          workspaceCell physicalAfter,
      ∃ stateCount : Nat,
      ∃ wellFormed : StateWellFormed physicalAfter,
        completion = parserCapacityCompletion position stateCount) := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter growth frame worldEq
      environmentEq =>
      exact .inl ⟨rfl, workspace, workspaceValues, growth, frame, worldEq,
        environmentEq⟩
  | full workspace workspaceValues physicalAfter growth terminal stateCount
      wellFormed =>
      exact .inr ⟨workspace, workspaceValues, growth, terminal, stateCount,
        wellFormed, rfl⟩

/-- Complete-state operation after both parent-replay temporaries have been
    hidden and the enclosing state cursor has been restored. -/
structure RecognizerStateParentExecution
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
      completedLhs) where
  after : State
  execution : Executes verifiedParserCore
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)))
    parserRecognizeStateCompleteBranch
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
      entry.functionalConfig.functional_run.completion) after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell))
    (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)))
    after
  outcome : RecognizerStateParentSynchronizedOutcome grammarLayout grammar words
    tokens workspaceLayout workspace grammarCell tokensCell workspaceCell
    stateCountCell stateCursorCell position current remaining completedLhs
    entry.functionalConfig.functional_run.after after
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
      entry.functionalConfig.functional_run.completion)

noncomputable def RecognizerStateParentEntry.execute
    (entry : RecognizerStateParentEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs) :
    RecognizerStateParentExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound bindings
      completedLhs entry := by
  let inner := entry.execute_inner
  let physical := inner.synchronizedPhysical
  obtain ⟨innerAfter, innerExecution, innerEffect, innerOutcome⟩ := physical
  let writes := parentFrameMutableCells workspaceCell stateCountCell
    entry.chartEntry.cursorCell
  let retainedWrites := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton stateCountCell)
  let afterCursor := restoreLocals entry.chartEntry.headRead.after innerAfter
  let after := restoreLocals entry.afterLhsRead afterCursor
  have enteredCursor : StoreEffect CellSet.empty
      entry.chartEntry.headRead.after entry.chartEntry.bound := by
    rw [entry.chartEntry.boundEq]
    exact bindLocal_effect entry.chartEntry.headRead.after 30
      (.signed .i32 (chartHeadValue workspace candidate.origin))
  have cursorScopeStore : StoreEffect writes entry.chartEntry.headRead.after
      innerAfter := (enteredCursor.weaken CellSet.empty_subset).trans_same
        (by simpa [writes] using innerEffect.toStoreEffect)
  have cursorClosed : ModifiesOnly writes entry.chartEntry.headRead.after
      afterCursor := by
    simpa [afterCursor] using cursorScopeStore.restoreLocals
  have fromLhsBound : ModifiesOnly writes entry.boundLhs afterCursor := by
    simpa [writes] using
      (entry.chartEntry.headRead.effect.weaken CellSet.empty_subset).trans_same
        cursorClosed
  have fromLhsBoundRetained : ModifiesOnly retainedWrites entry.boundLhs
      afterCursor := by
    apply fromLhsBound.hideFreshWritesExcept
    intro cell written
    change cell = workspaceCell ∨ cell = stateCountCell ∨
      cell = entry.chartEntry.cursorCell at written
    rcases written with rfl | rfl | rfl
    · exact .inl (.inl rfl)
    · exact .inl (.inr rfl)
    · exact .inr (by
        rw [entry.chartEntry.cursorCellEq]
        exact entry.chartEntry.headRead.effect.nextCell)
  have enteredLhs : StoreEffect CellSet.empty entry.afterLhsRead
      entry.boundLhs := by
    rw [entry.boundLhsEq]
    exact bindLocal_effect entry.afterLhsRead 29
      (.signed .i32 (Int.ofNat completedLhs))
  have lhsScopeStore : StoreEffect retainedWrites entry.afterLhsRead
      afterCursor := (enteredLhs.weaken CellSet.empty_subset).trans_same
        fromLhsBoundRetained.toStoreEffect
  have lhsClosed : ModifiesOnly retainedWrites entry.afterLhsRead after := by
    simpa [after] using lhsScopeStore.restoreLocals
  have effect : ModifiesOnly retainedWrites
      (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)))
      after := (entry.lhsEffect.weaken CellSet.empty_subset).trans_same lhsClosed
  have bodyExecution : Executes verifiedParserCore entry.boundLhs
      (.letLocal 30 parserI32Type (parserRecognizeChartHeadExpr 27)
        (.sequence parserRecognizeParentLoop .skip))
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
        entry.functionalConfig.functional_run.completion)
      afterCursor := by
    have innerAtBound : Executes verifiedParserCore
        (entry.chartEntry.headRead.after.bindLocal 30
          (.signed .i32 (chartHeadValue workspace candidate.origin)))
        (.sequence parserRecognizeParentLoop .skip)
        (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
          entry.functionalConfig.functional_run.completion)
        innerAfter := by
      simpa [entry.chartEntry.boundEq] using innerExecution
    have scopedExecution := executesLetLocal (id := 30) (type := parserI32Type)
      entry.chartEntry.headRead.evaluation innerAtBound
    simpa [parserRecognizeChartHeadExpr, afterCursor,
      entry.chartEntry.boundEq] using scopedExecution
  have execution : Executes verifiedParserCore
      (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length)))
      parserRecognizeStateCompleteBranch
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
        entry.functionalConfig.functional_run.completion) after := by
    rw [extractedParserRecognize_state_complete_shape]
    have bodyAtBound : Executes verifiedParserCore
        (entry.afterLhsRead.bindLocal 29
          (.signed .i32 (Int.ofNat completedLhs)))
        (.letLocal 30 parserI32Type (parserRecognizeChartHeadExpr 27)
          (.sequence parserRecognizeParentLoop .skip))
        (Lanius.FunctionalView.Core.Stateful.toCoreCompletion
          entry.functionalConfig.functional_run.completion)
        afterCursor := by
      simpa [entry.boundLhsEq] using bodyExecution
    have scopedExecution := executesLetLocal (id := 29) (type := parserI32Type)
      entry.lhsEvaluation bodyAtBound
    simpa [after, entry.boundLhsEq, parserRecognizeChartHeadExpr] using
      scopedExecution
  have afterWellFormed : StateWellFormed after := by
    have innerWellFormed : StateWellFormed innerAfter := by
      rcases innerOutcome.view with completedResult | fullResult
      · rcases completedResult with ⟨_, _, _, _, finished, _, _⟩
        exact finished.chartCursor.recognizer.wellFormed
      · rcases fullResult with ⟨_, _, _, _, _, wellFormed, _⟩
        exact wellFormed
    have cursorWellFormed := cursorScopeStore.restoreLocals_wellFormed
      entry.chartEntry.headRead.invariant.wellFormed innerWellFormed
    exact lhsScopeStore.restoreLocals_wellFormed
      entry.afterLhsWellFormed
      cursorWellFormed
  have existsResult : ∃ result :
      RecognizerStateParentExecution grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell stateCursorCell before position current
        remaining beforeInvariant candidate found productionBound bindings
        completedLhs entry, True := by
    rcases innerOutcome.view with completedResult | fullResult
    · rcases completedResult with ⟨completionEq, nextWorkspace, nextValues,
        growth, finished, worldEq, environmentEq⟩
      have cursorParameterCellId : ∀ id,
          id ∈ verifiedParserRecognizerParameterIds →
          entry.chartEntry.bound.cellId? id =
            entry.chartEntry.headRead.after.cellId? id := by
        intro id member
        rw [entry.chartEntry.boundEq]
        apply bindLocal_preserves_other_cellId
        have bound := (mem_verifiedParserRecognizerParameterIds_iff id).mp member
        exact Nat.ne_of_gt
          (Nat.lt_of_le_of_lt bound (by decide : 5 < 30))
      have afterCursorRecognizer : RecognizerInvariant grammarLayout grammar
          words tokens workspaceLayout nextWorkspace nextValues grammarCell
          tokensCell workspaceCell afterCursor := by
        simpa [afterCursor] using RecognizerInvariant.restore_temporary
          entry.chartEntry.headRead.after entry.chartEntry.bound innerAfter
          entry.chartEntry.headRead.invariant.wellFormed enteredCursor
          innerEffect cursorParameterCellId finished.chartCursor.recognizer
      have lhsParameterCellId : ∀ id,
          id ∈ verifiedParserRecognizerParameterIds →
          entry.boundLhs.cellId? id = entry.afterLhsRead.cellId? id := by
        intro id member
        rw [entry.boundLhsEq]
        apply bindLocal_preserves_other_cellId
        have bound := (mem_verifiedParserRecognizerParameterIds_iff id).mp member
        exact Nat.ne_of_gt
          (Nat.lt_of_le_of_lt bound (by decide : 5 < 29))
      have restoredRecognizer : RecognizerInvariant grammarLayout grammar
          words tokens workspaceLayout nextWorkspace nextValues grammarCell
          tokensCell workspaceCell after := by
        simpa [after] using RecognizerInvariant.restore_temporary
          entry.afterLhsRead entry.boundLhs afterCursor
          entry.afterLhsWellFormed
          enteredLhs fromLhsBoundRetained lhsParameterCellId
          afterCursorRecognizer
      have countAtCursorBound : entry.chartEntry.bound.cellId? 18 =
          entry.chartEntry.headRead.after.cellId? 18 := by
        rw [entry.chartEntry.boundEq]
        exact bindLocal_preserves_other_cellId _ 30 18 _ (by decide)
      have countAfterCursor : (Assertion.localPointsTo 18 stateCountCell
          (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))).holds
          afterCursor := by
        simpa [afterCursor] using localPointsTo_restore_temporary
          entry.chartEntry.headRead.after entry.chartEntry.bound innerAfter
          18 stateCountCell
          (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))
          innerEffect countAtCursorBound finished.appendFrame.stateCountOwned
      have countAtLhsBound : entry.boundLhs.cellId? 18 =
          entry.afterLhsRead.cellId? 18 := by
        rw [entry.boundLhsEq]
        exact bindLocal_preserves_other_cellId _ 29 18 _ (by decide)
      have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
          (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))).holds
          after := by
        simpa [after] using localPointsTo_restore_temporary
          entry.afterLhsRead entry.boundLhs afterCursor 18 stateCountCell
          (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))
          fromLhsBoundRetained countAtLhsBound countAfterCursor
      have frameDisjoint : CellSet.Disjoint
          (localBindingFrameFootprint
            (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
              (grammar.productionAt ⟨candidate.production,
                productionBound⟩).rhs.length)))
            verifiedParserStateLoopPreservedBindings) retainedWrites := by
        intro cell framed written
        obtain ⟨id, sourceMember, cellId⟩ := framed
        have ⟨persistent, notCount⟩ :=
          (StateLoopPreservedLocal_iff id).mp
            ((StateLoopPreservedLocal_source_frame id).mpr sourceMember)
        have separated := bindings.invariant.persistentLocalsSeparate id
          persistent
        change cell = workspaceCell ∨ cell = stateCountCell at written
        rcases written with rfl | rfl
        · exact separated.1 cellId
        · exact separated.2.1 notCount cellId
      have stateCursorNotWritten : ¬ retainedWrites stateCursorCell := by
        simpa [retainedWrites, CellSet.union, CellSet.singleton, not_or] using
          ⟨bindings.invariant.chartCursor.cursorBackingDistinct.2.2,
            bindings.invariant.cursorStateCountDistinct⟩
      let frame := bindings.invariant.reframe_growth nextWorkspace nextValues
        after growth restoredRecognizer finished.chartCursor.workspaceWithinGrammar
        stateCountOwned retainedWrites effect frameDisjoint
        stateCursorNotWritten
      exact ⟨{
        after := after
        execution := execution
        effect := by simpa [retainedWrites] using effect
        outcome := by
          simpa [completionEq] using
            (RecognizerStateParentSynchronizedOutcome.completed nextWorkspace
              nextValues after growth frame worldEq environmentEq)
      }, trivial⟩
    · rcases fullResult with ⟨finalWorkspace, finalValues, growth, terminal,
        stateCount, _, completionEq⟩
      have sourceCoreCompletionEq :
          Lanius.FunctionalView.Core.Stateful.toCoreCompletion
              entry.functionalConfig.functional_run.completion =
            parserCapacityCompletion position stateCount := by
        simpa using completionEq
      have sourceStops :
          entry.functionalConfig.functional_run.completion ≠ .next := by
        intro sourceNext
        rw [sourceNext] at sourceCoreCompletionEq
        simp [Lanius.FunctionalView.Core.Stateful.toCoreCompletion,
          parserCapacityCompletion] at sourceCoreCompletionEq
      have cursorParameterCellId : ∀ id,
          id ∈ verifiedParserRecognizerParameterIds →
          entry.chartEntry.bound.cellId? id =
            entry.chartEntry.headRead.after.cellId? id := by
        intro id member
        rw [entry.chartEntry.boundEq]
        apply bindLocal_preserves_other_cellId
        have bound := (mem_verifiedParserRecognizerParameterIds_iff id).mp member
        exact Nat.ne_of_gt
          (Nat.lt_of_le_of_lt bound (by decide : 5 < 30))
      have afterCursorRecognizer : RecognizerInvariant grammarLayout grammar
          words tokens workspaceLayout finalWorkspace finalValues grammarCell
          tokensCell workspaceCell afterCursor := by
        simpa [afterCursor] using RecognizerInvariant.restore_temporary
          entry.chartEntry.headRead.after entry.chartEntry.bound innerAfter
          entry.chartEntry.headRead.invariant.wellFormed enteredCursor
          innerEffect cursorParameterCellId terminal
      have lhsParameterCellId : ∀ id,
          id ∈ verifiedParserRecognizerParameterIds →
          entry.boundLhs.cellId? id = entry.afterLhsRead.cellId? id := by
        intro id member
        rw [entry.boundLhsEq]
        apply bindLocal_preserves_other_cellId
        have bound := (mem_verifiedParserRecognizerParameterIds_iff id).mp member
        exact Nat.ne_of_gt
          (Nat.lt_of_le_of_lt bound (by decide : 5 < 29))
      have restoredRecognizer : RecognizerInvariant grammarLayout grammar
          words tokens workspaceLayout finalWorkspace finalValues grammarCell
          tokensCell workspaceCell after := by
        simpa [after] using RecognizerInvariant.restore_temporary
          entry.afterLhsRead entry.boundLhs afterCursor
          entry.afterLhsWellFormed enteredLhs fromLhsBoundRetained
          lhsParameterCellId afterCursorRecognizer
      exact ⟨{
        after := after
        execution := execution
        effect := by simpa [retainedWrites] using effect
        outcome := by
          simpa [completionEq] using
            (RecognizerStateParentSynchronizedOutcome.full finalWorkspace
              finalValues after growth restoredRecognizer stateCount
              afterWellFormed)
      }, trivial⟩
  exact Classical.choose existsResult

/-- The completed-state branch as one semantic operation: establish the
    parent entry and immediately execute it.  Keeping the dependent LHS and
    entry witnesses packaged prevents the outer branch proof from reopening
    their implementation details. -/
noncomputable def RecognizerStateCandidateBindings.execute_complete
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell stateCursorCell before position current
      remaining beforeInvariant candidate found productionBound)
    (completed : candidate.dot =
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length) :
    Sigma fun completedLhs => Sigma fun entry :
      RecognizerStateParentEntry grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell stateCursorCell before position current
        remaining beforeInvariant candidate found productionBound bindings
        completedLhs =>
      RecognizerStateParentExecution grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell stateCursorCell before position current
        remaining beforeInvariant candidate found productionBound bindings
        completedLhs entry := by
  let prepared := bindings.enter_parent completed
  obtain ⟨completedLhs, entry⟩ := prepared
  exact ⟨completedLhs, entry, entry.execute⟩

structure RecognizerStateScopedExecution
    (before innerAfter : State) (completion : Completion) (writes : CellSet)
    (candidate : EarleyState)
    (beforeInvariant : RecognizerStateLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position current remaining
      beforeInvariant candidate found productionBound) where
  after : State
  execution : Executes verifiedParserCore before parserRecognizeStateLoopBody
    completion after
  effect : ModifiesOnly writes before after
  wellFormed : StateWellFormed after
  cells : after.cells = innerAfter.cells

/-- Close the production, dot, origin, and RHS-length scopes around one
    proved state action.  This isolates the state-chain proof from the
    generated nesting depth while retaining the exact artifact statement. -/
noncomputable def RecognizerStateCandidateBindings.close_scopes
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound)
    (innerAfter : State) (completion : Completion) (writes : CellSet)
    (innerExecution : Executes verifiedParserCore
      (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.length)))
      parserRecognizeStateAfterBindings completion innerAfter)
    (innerEffect : ModifiesOnly writes
      (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.length))) innerAfter)
    (innerWellFormed : StateWellFormed innerAfter) :
    RecognizerStateScopedExecution runtime innerAfter completion writes
      candidate beforeInvariant found productionBound bindings := by
  let productionScope := bindings.afterProductionRead.bindLocal 25
    (.signed .i32 (Int.ofNat candidate.production))
  let dotScope := bindings.afterDotRead.bindLocal 26
    (.signed .i32 (Int.ofNat candidate.dot))
  let originScope := bindings.afterOriginRead.bindLocal 27
    (.signed .i32 (Int.ofNat candidate.origin))
  let rhsLength :=
    (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
  let rhsScope := bindings.afterRhsLengthRead.bindLocal 28
    (.signed .i32 (Int.ofNat rhsLength))
  let afterRhs := restoreLocals bindings.afterRhsLengthRead innerAfter
  let afterOrigin := restoreLocals bindings.afterOriginRead afterRhs
  let afterDot := restoreLocals bindings.afterDotRead afterOrigin
  let afterProduction := restoreLocals bindings.afterProductionRead afterDot
  have enteredRhs : StoreEffect CellSet.empty bindings.afterRhsLengthRead
      rhsScope := by
    simpa [rhsScope] using bindLocal_effect bindings.afterRhsLengthRead 28
      (.signed .i32 (Int.ofNat rhsLength))
  have rhsScopeEffect : StoreEffect writes bindings.afterRhsLengthRead
      innerAfter := (enteredRhs.weaken CellSet.empty_subset).trans_same
        innerEffect.toStoreEffect
  have closedRhs : ModifiesOnly writes bindings.afterRhsLengthRead afterRhs := by
    simpa [afterRhs] using rhsScopeEffect.restoreLocals
  have afterRhsWellFormed : StateWellFormed afterRhs :=
    rhsScopeEffect.restoreLocals_wellFormed
      bindings.afterRhsLengthWellFormed innerWellFormed
  have rhsBodyEffect : ModifiesOnly writes originScope afterRhs :=
    (bindings.rhsLengthEffect.weaken CellSet.empty_subset).trans_same closedRhs
  have enteredOrigin : StoreEffect CellSet.empty bindings.afterOriginRead
      originScope := by
    simpa [originScope] using bindLocal_effect bindings.afterOriginRead 27
      (.signed .i32 (Int.ofNat candidate.origin))
  have originScopeEffect : StoreEffect writes bindings.afterOriginRead
      afterRhs := (enteredOrigin.weaken CellSet.empty_subset).trans_same
        rhsBodyEffect.toStoreEffect
  have closedOrigin : ModifiesOnly writes bindings.afterOriginRead
      afterOrigin := by
    simpa [afterOrigin] using originScopeEffect.restoreLocals
  have afterOriginWellFormed : StateWellFormed afterOrigin :=
    originScopeEffect.restoreLocals_wellFormed
      bindings.afterOriginWellFormed afterRhsWellFormed
  have originBodyEffect : ModifiesOnly writes dotScope afterOrigin :=
    (bindings.originEffect.weaken CellSet.empty_subset).trans_same closedOrigin
  have enteredDot : StoreEffect CellSet.empty bindings.afterDotRead dotScope := by
    simpa [dotScope] using bindLocal_effect bindings.afterDotRead 26
      (.signed .i32 (Int.ofNat candidate.dot))
  have dotScopeEffect : StoreEffect writes bindings.afterDotRead afterOrigin :=
    (enteredDot.weaken CellSet.empty_subset).trans_same
      originBodyEffect.toStoreEffect
  have closedDot : ModifiesOnly writes bindings.afterDotRead afterDot := by
    simpa [afterDot] using dotScopeEffect.restoreLocals
  have afterDotWellFormed : StateWellFormed afterDot :=
    dotScopeEffect.restoreLocals_wellFormed bindings.afterDotWellFormed
      afterOriginWellFormed
  have dotBodyEffect : ModifiesOnly writes productionScope afterDot :=
    (bindings.dotEffect.weaken CellSet.empty_subset).trans_same closedDot
  have enteredProduction : StoreEffect CellSet.empty
      bindings.afterProductionRead productionScope := by
    simpa [productionScope] using bindLocal_effect bindings.afterProductionRead
      25 (.signed .i32 (Int.ofNat candidate.production))
  have productionScopeEffect : StoreEffect writes
      bindings.afterProductionRead afterDot :=
    (enteredProduction.weaken CellSet.empty_subset).trans_same
      dotBodyEffect.toStoreEffect
  have closedProduction : ModifiesOnly writes bindings.afterProductionRead
      afterProduction := by
    simpa [afterProduction] using productionScopeEffect.restoreLocals
  have afterProductionWellFormed : StateWellFormed afterProduction :=
    productionScopeEffect.restoreLocals_wellFormed
      bindings.afterProductionWellFormed afterDotWellFormed
  have outerEffect : ModifiesOnly writes runtime afterProduction :=
    (bindings.productionEffect.weaken CellSet.empty_subset).trans_same
      closedProduction
  have rhsExecution : Executes verifiedParserCore originScope
      (.letLocal 28 parserI32Type
        (.call extractedParserRhsLengthFunction.id [.local 0, .local 25])
        parserRecognizeStateAfterBindings) completion afterRhs := by
    simpa [originScope, rhsScope, afterRhs, rhsLength] using
      executesLetLocal (type := parserI32Type) bindings.rhsLengthEvaluation
        innerExecution
  have originExecution : Executes verifiedParserCore dotScope
      (.letLocal 27 parserI32Type (parserRecognizeStateValueCall 24 30)
        (.letLocal 28 parserI32Type
          (.call extractedParserRhsLengthFunction.id [.local 0, .local 25])
          parserRecognizeStateAfterBindings)) completion afterOrigin := by
    simpa [dotScope, originScope, afterOrigin] using
      executesLetLocal (type := parserI32Type) bindings.originEvaluation
        rhsExecution
  have dotExecution : Executes verifiedParserCore productionScope
      (.letLocal 26 parserI32Type (parserRecognizeStateValueCall 24 29)
        (.letLocal 27 parserI32Type (parserRecognizeStateValueCall 24 30)
          (.letLocal 28 parserI32Type
            (.call extractedParserRhsLengthFunction.id [.local 0, .local 25])
            parserRecognizeStateAfterBindings))) completion afterDot := by
    simpa [productionScope, dotScope, afterDot] using
      executesLetLocal (type := parserI32Type) bindings.dotEvaluation
        originExecution
  have productionExecution : Executes verifiedParserCore runtime
      (.letLocal 25 parserI32Type (parserRecognizeStateValueCall 24 28)
        (.letLocal 26 parserI32Type (parserRecognizeStateValueCall 24 29)
          (.letLocal 27 parserI32Type (parserRecognizeStateValueCall 24 30)
            (.letLocal 28 parserI32Type
              (.call extractedParserRhsLengthFunction.id [.local 0, .local 25])
              parserRecognizeStateAfterBindings)))) completion
      afterProduction := by
    simpa [productionScope, afterProduction] using
      executesLetLocal (type := parserI32Type) bindings.productionEvaluation
        dotExecution
  exact {
    after := afterProduction
    execution := by
      rw [extractedParserRecognize_state_body_shape]
      exact productionExecution
    effect := outerEffect
    wellFormed := afterProductionWellFormed
    cells := by
      simp [afterProduction, afterDot, afterOrigin, afterRhs, restoreLocals]
  }

/-- Transfer a physical cell fact from the inner candidate scope to its
    restored caller state. -/
theorem RecognizerStateScopedExecution.transfer_entry
    (closed : RecognizerStateScopedExecution
      (grammarLayout := grammarLayout) (grammar := grammar) (words := words)
      (tokens := tokens) (workspaceLayout := workspaceLayout)
      (workspace := beforeWorkspace) (workspaceValues := beforeValues)
      (grammarCell := grammarCell) (tokensCell := tokensCell)
      (workspaceCell := workspaceCell) (stateCountCell := stateCountCell)
      (cursorCell := cursorCell) (before := before) (innerAfter := innerAfter)
      (position := position) (current := current) (remaining := remaining)
      (beforeInvariant := beforeInvariant) (candidate := candidate)
      (found := found) (productionBound := productionBound)
      (bindings := bindings) (completion := completion)
      (writes := stateLoopMutableCells workspaceCell stateCountCell cursorCell))
    (cell : CellId) (entry : Cell)
    (innerEntry : innerAfter.cellEntry? cell = some entry) :
    closed.after.cellEntry? cell = some entry := by
  unfold State.cellEntry? at innerEntry ⊢
  rw [closed.cells]
  exact innerEntry

/-- Persistent state-loop locals retain their caller mapping and value when a
    candidate scope is restored. -/
theorem RecognizerStateScopedExecution.preserve_persistent_local
    (closed : RecognizerStateScopedExecution
      (grammarLayout := grammarLayout) (grammar := grammar) (words := words)
      (tokens := tokens) (workspaceLayout := workspaceLayout)
      (workspace := beforeWorkspace) (workspaceValues := beforeValues)
      (grammarCell := grammarCell) (tokensCell := tokensCell)
      (workspaceCell := workspaceCell) (stateCountCell := stateCountCell)
      (cursorCell := cursorCell) (before := before) (innerAfter := innerAfter)
      (position := position) (current := current) (remaining := remaining)
      (beforeInvariant := beforeInvariant) (candidate := candidate)
      (found := found) (productionBound := productionBound)
      (bindings := bindings) (completion := completion)
    (writes := stateLoopMutableCells workspaceCell stateCountCell cursorCell))
    (id : VarId) (persistent : StateLoopPreservedLocal id)
    (value : Value) (localEq : before.local? id = some value) :
    closed.after.local? id = some value :=
  closed.effect.preserves_local_of_disjoint
    beforeInvariant.chartCursor.recognizer.wellFormed
    beforeInvariant.persistentSeparate
    ((StateLoopPreservedLocal_source_frame id).mp persistent) localEq

/-- Reconstruct the recognizer resource frame after candidate locals are
    restored.  The logical workspace comes from the proved inner operation;
    the local mappings come from the caller, and physical array contents are
    transferred by cell identity. -/
theorem RecognizerStateScopedExecution.restore_recognizer
    (closed : RecognizerStateScopedExecution
      (grammarLayout := grammarLayout) (grammar := grammar) (words := words)
      (tokens := tokens) (workspaceLayout := workspaceLayout)
      (workspace := beforeWorkspace) (workspaceValues := beforeValues)
      (grammarCell := grammarCell) (tokensCell := tokensCell)
      (workspaceCell := workspaceCell) (stateCountCell := stateCountCell)
      (cursorCell := cursorCell) (before := before) (innerAfter := innerAfter)
      (position := position) (current := current) (remaining := remaining)
      (beforeInvariant := beforeInvariant) (candidate := candidate)
      (found := found) (productionBound := productionBound)
      (bindings := bindings) (completion := completion)
      (writes := stateLoopMutableCells workspaceCell stateCountCell cursorCell))
    (inner : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextValues grammarCell tokensCell
      workspaceCell innerAfter) :
    RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
      nextWorkspace nextValues grammarCell tokensCell workspaceCell
      closed.after := by
  let writes := stateLoopMutableCells workspaceCell stateCountCell cursorCell
  have grammarNotWritten : ¬ writes grammarCell := by
    simpa [writes, stateLoopMutableCells, CellSet.union, CellSet.singleton,
      not_or] using
      ⟨beforeInvariant.chartCursor.recognizer.grammarWorkspaceDistinct,
        beforeInvariant.appendFrame.stateCountBackingDistinct.1.symm,
        beforeInvariant.chartCursor.cursorBackingDistinct.1.symm⟩
  have tokensNotWritten : ¬ writes tokensCell := by
    simpa [writes, stateLoopMutableCells, CellSet.union, CellSet.singleton,
      not_or] using
      ⟨beforeInvariant.chartCursor.recognizer.tokensWorkspaceDistinct,
        beforeInvariant.appendFrame.stateCountBackingDistinct.2.1.symm,
        beforeInvariant.chartCursor.cursorBackingDistinct.2.1.symm⟩
  have parameterFrameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        verifiedParserRecognizerParameterFrame) writes :=
    CellSet.Disjoint.mono_left
      (localBindingFrameFootprint_mono (fun id member =>
        (StateLoopPreservedLocal_source_frame id).mp (Or.inl member)))
      beforeInvariant.persistentSeparate
  have sameLength : nextValues.length = beforeValues.length := by
    rw [inner.workspaceLength, beforeInvariant.chartCursor.recognizer.workspaceLength]
  apply beforeInvariant.chartCursor.recognizer.after_workspace_and_scalar_effect
    writes (by simpa [writes] using closed.effect) closed.wellFormed
    grammarNotWritten tokensNotWritten parameterFrameDisjoint nextWorkspace
    nextValues sameLength inner.workspaceEncoded inner.derivations
  exact closed.transfer_entry workspaceCell _ inner.workspaceBacking

/-- Restore an active state-loop invariant after closing candidate fields. -/
noncomputable def RecognizerStateScopedExecution.restore_invariant
    (closed : RecognizerStateScopedExecution
      (grammarLayout := grammarLayout) (grammar := grammar) (words := words)
      (tokens := tokens) (workspaceLayout := workspaceLayout)
      (workspace := beforeWorkspace) (workspaceValues := beforeValues)
      (grammarCell := grammarCell) (tokensCell := tokensCell)
      (workspaceCell := workspaceCell) (stateCountCell := stateCountCell)
      (cursorCell := cursorCell) (before := before) (innerAfter := innerAfter)
      (position := position) (current := current) (remaining := remaining)
      (beforeInvariant := beforeInvariant) (candidate := candidate)
      (found := found) (productionBound := productionBound)
      (bindings := bindings) (completion := .next)
      (writes := stateLoopMutableCells workspaceCell stateCountCell cursorCell))
    (inner : RecognizerStateLoopInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell innerAfter position next
      nextRemaining) :
    RecognizerStateLoopInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell closed.after position next
      nextRemaining := by
  have recognizer := closed.restore_recognizer
    inner.chartCursor.recognizer
  have cursorOwned : (Assertion.localPointsTo 24 cursorCell
      (some (.signed .i32 (Int.ofNat next)))).holds closed.after := by
    constructor
    · unfold State.cellId?
      rw [closed.effect.locals]
      exact beforeInvariant.chartCursor.cursorOwned.1
    · exact closed.transfer_entry cursorCell _ inner.chartCursor.cursorOwned.2
  have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))).holds
      closed.after := by
    constructor
    · unfold State.cellId?
      rw [closed.effect.locals]
      exact beforeInvariant.appendFrame.stateCountOwned.1
    · exact closed.transfer_entry stateCountCell _
        inner.appendFrame.stateCountOwned.2
  exact {
    chartCursor := {
      recognizer := recognizer
      workspaceWithinGrammar := inner.chartCursor.workspaceWithinGrammar
      stateBaseLocal := closed.preserve_persistent_local 8 (by
        simp [StateLoopPreservedLocal]) _
        beforeInvariant.chartCursor.stateBaseLocal
      cursorOwned := cursorOwned
      cursorFrameSeparate := by
        unfold ChartCursorFrameSeparated
        rw [closed.effect.localBindingFrameFootprint_eq
          verifiedParserChartCursorBindings]
        exact beforeInvariant.chartCursor.cursorFrameSeparate
      cursorBackingDistinct := beforeInvariant.chartCursor.cursorBackingDistinct
      chartPositionBound := inner.chartCursor.chartPositionBound
      cursor := inner.chartCursor.cursor
    }
    appendFrame := {
      recognizer := recognizer
      positionBound := inner.appendFrame.positionBound
      stateBaseLocal := closed.preserve_persistent_local 8 (by
        simp [StateLoopPreservedLocal]) _ beforeInvariant.appendFrame.stateBaseLocal
      stateCapacityLocal := closed.preserve_persistent_local 9 (by
        simp [StateLoopPreservedLocal]) _
        beforeInvariant.appendFrame.stateCapacityLocal
      stateCountLocal := Assertion.localPointsTo_local 18 stateCountCell _
        closed.after stateCountOwned
      stateCountOwned := stateCountOwned
      stateCountBackingDistinct :=
        beforeInvariant.appendFrame.stateCountBackingDistinct
      stateCountParameterSeparate := by
        unfold RecognizerParameterFrameSeparated
        rw [closed.effect.localBindingFrameFootprint_eq
          verifiedParserRecognizerParameterFrame]
        exact beforeInvariant.appendFrame.stateCountParameterSeparate
    }
    kindCountLocal := closed.preserve_persistent_local 11 (by
      simp [StateLoopPreservedLocal]) _ beforeInvariant.kindCountLocal
    lhsOffsetsOffsetLocal := closed.preserve_persistent_local 13 (by
      simp [StateLoopPreservedLocal]) _ beforeInvariant.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal := closed.preserve_persistent_local 14 (by
      simp [StateLoopPreservedLocal]) _ beforeInvariant.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal := closed.preserve_persistent_local 15 (by
      simp [StateLoopPreservedLocal]) _
      beforeInvariant.lhsProductionsOffsetLocal
    positionLocal := closed.preserve_persistent_local 23 (by
      simp [StateLoopPreservedLocal]) _ beforeInvariant.positionLocal
    positionAdvanceI32 := beforeInvariant.positionAdvanceI32
    persistentSeparate := by
      unfold StateLoopFrameSeparated
      rw [closed.effect.localBindingFrameFootprint_eq
        verifiedParserStateLoopPreservedBindings]
      exact beforeInvariant.persistentSeparate
    cursorStateCountDistinct := beforeInvariant.cursorStateCountDistinct
  }

/-- Restore an exhausted state-loop invariant after closing candidate fields. -/
noncomputable def RecognizerStateScopedExecution.restore_finished
    (closed : RecognizerStateScopedExecution
      (grammarLayout := grammarLayout) (grammar := grammar) (words := words)
      (tokens := tokens) (workspaceLayout := workspaceLayout)
      (workspace := beforeWorkspace) (workspaceValues := beforeValues)
      (grammarCell := grammarCell) (tokensCell := tokensCell)
      (workspaceCell := workspaceCell) (stateCountCell := stateCountCell)
      (cursorCell := cursorCell) (before := before) (innerAfter := innerAfter)
      (position := position) (current := current) (remaining := remaining)
      (beforeInvariant := beforeInvariant) (candidate := candidate)
      (found := found) (productionBound := productionBound)
      (bindings := bindings) (completion := .next)
      (writes := stateLoopMutableCells workspaceCell stateCountCell cursorCell))
    (inner : RecognizerStateFinishedInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell innerAfter position) :
    RecognizerStateFinishedInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell closed.after position := by
  have recognizer := closed.restore_recognizer
    inner.chartCursor.recognizer
  have cursorOwned : (Assertion.localPointsTo 24 cursorCell
      (some (.signed .i32 (-1)))).holds closed.after := by
    constructor
    · unfold State.cellId?
      rw [closed.effect.locals]
      exact beforeInvariant.chartCursor.cursorOwned.1
    · exact closed.transfer_entry cursorCell _ inner.chartCursor.cursorOwned.2
  have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))).holds
      closed.after := by
    constructor
    · unfold State.cellId?
      rw [closed.effect.locals]
      exact beforeInvariant.appendFrame.stateCountOwned.1
    · exact closed.transfer_entry stateCountCell _
        inner.appendFrame.stateCountOwned.2
  exact {
    chartCursor := {
      recognizer := recognizer
      workspaceWithinGrammar := inner.chartCursor.workspaceWithinGrammar
      stateBaseLocal := closed.preserve_persistent_local 8 (by
        simp [StateLoopPreservedLocal]) _
        beforeInvariant.chartCursor.stateBaseLocal
      cursorOwned := cursorOwned
      cursorFrameSeparate := by
        unfold ChartCursorFrameSeparated
        rw [closed.effect.localBindingFrameFootprint_eq
          verifiedParserChartCursorBindings]
        exact beforeInvariant.chartCursor.cursorFrameSeparate
      cursorBackingDistinct := beforeInvariant.chartCursor.cursorBackingDistinct
      chartPositionBound := inner.chartCursor.chartPositionBound
    }
    appendFrame := {
      recognizer := recognizer
      positionBound := inner.appendFrame.positionBound
      stateBaseLocal := closed.preserve_persistent_local 8 (by
        simp [StateLoopPreservedLocal]) _ beforeInvariant.appendFrame.stateBaseLocal
      stateCapacityLocal := closed.preserve_persistent_local 9 (by
        simp [StateLoopPreservedLocal]) _
        beforeInvariant.appendFrame.stateCapacityLocal
      stateCountLocal := Assertion.localPointsTo_local 18 stateCountCell _
        closed.after stateCountOwned
      stateCountOwned := stateCountOwned
      stateCountBackingDistinct :=
        beforeInvariant.appendFrame.stateCountBackingDistinct
      stateCountParameterSeparate := by
        unfold RecognizerParameterFrameSeparated
        rw [closed.effect.localBindingFrameFootprint_eq
          verifiedParserRecognizerParameterFrame]
        exact beforeInvariant.appendFrame.stateCountParameterSeparate
    }
    kindCountLocal := closed.preserve_persistent_local 11 (by
      simp [StateLoopPreservedLocal]) _ beforeInvariant.kindCountLocal
    lhsOffsetsOffsetLocal := closed.preserve_persistent_local 13 (by
      simp [StateLoopPreservedLocal]) _ beforeInvariant.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal := closed.preserve_persistent_local 14 (by
      simp [StateLoopPreservedLocal]) _ beforeInvariant.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal := closed.preserve_persistent_local 15 (by
      simp [StateLoopPreservedLocal]) _
      beforeInvariant.lhsProductionsOffsetLocal
    positionLocal := closed.preserve_persistent_local 23 (by
      simp [StateLoopPreservedLocal]) _ beforeInvariant.positionLocal
    positionAdvanceI32 := beforeInvariant.positionAdvanceI32
    persistentSeparate := by
      unfold StateLoopFrameSeparated
      rw [closed.effect.localBindingFrameFootprint_eq
        verifiedParserStateLoopPreservedBindings]
      exact beforeInvariant.persistentSeparate
    cursorStateCountDistinct := beforeInvariant.cursorStateCountDistinct
  }

/-- The extracted state-loop branch test denotes exactly whether the current
    Earley item still has an unconsumed RHS symbol.  Keeping this fact attached
    to the candidate binding prevents the terminal, prediction, and completion
    proofs from choosing their branch independently of the decoded state. -/
theorem RecognizerStateCandidateBindings.evaluate_incomplete_test
    (bindings : RecognizerStateCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position current remaining
      beforeInvariant candidate found productionBound) :
    Evaluates verifiedParserCore
      (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.length)))
      (.binary .less (.local 26) (.local 28))
      (.boolean (decide (candidate.dot <
        (grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.length)))
      (bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.length))) := by
  let bound := bindings.afterRhsLengthRead.bindLocal 28 (.signed .i32
    (Int.ofNat (grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.length))
  have dotResult : Evaluates verifiedParserCore bound (.local 26)
      (.signed .i32 (Int.ofNat candidate.dot)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 26 _
      (by simpa [bound] using bindings.dotLocal)⟩
  have lengthResult : Evaluates verifiedParserCore bound (.local 28)
      (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.length)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 28 _
      (by simpa [bound] using bindings.rhsLengthLocal)⟩
  simpa [bound] using evaluatesNatLessThreaded bound bound bound
    (.local 26) (.local 28) candidate.dot
    (grammar.productionAt ⟨candidate.production,
      productionBound⟩).rhs.length dotResult lengthResult


end Lanius.Extraction.ParserRecognize
