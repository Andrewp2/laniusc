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
/-! ## Nonterminal-prediction row loop -/

def parserRecognizePredictionLoop : Stmt :=
  (recognizerWhileLoops extractedParserRecognizeBody)[4]?.getD .skip

def parserRecognizePredictionLoopBody : Stmt :=
  match parserRecognizePredictionLoop with
  | .whileLoop _ body => body
  | _ => .skip

/-- Source declarations accessed by the prediction loop itself. -/
def verifiedParserPredictionLoopAccessFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedAccessFrameForCore
    parserRecognizePredictionLoop (by native_decide)

def verifiedParserPredictionLoopAccessFrameIds : List VarId :=
  verifiedParserPredictionLoopAccessFrame.ids

/-- The exact source-declaration frame live at entry to the prediction loop,
    including declarations used only by the continuation after it. -/
def verifiedParserPredictionLoopLiveFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedLiveFrameBeforeCore
    parserRecognizePredictionLoop (by native_decide)

def verifiedParserPredictionLoopLiveFrameIds : List VarId :=
  verifiedParserPredictionLoopLiveFrame.ids

theorem verifiedParser_prediction_loop_access_frame :
    verifiedParserPredictionLoopAccessFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("predicted_index", 33, .readWrite),
      ("count", 32, .read),
      ("grammar", 0, .read),
      ("lhs_productions_offset", 15, .read),
      ("first", 31, .read),
      ("workspace", 4, .read),
      ("state_base", 8, .read),
      ("state_capacity", 9, .read),
      ("position", 23, .read),
      ("state_count", 18, .readWrite)] := by
  native_decide

theorem verifiedParser_prediction_loop_access_frame_ids :
    verifiedParserPredictionLoopAccessFrameIds =
      [33, 32, 0, 15, 31, 4, 8, 9, 23, 18] := by
  native_decide

theorem verifiedParser_prediction_loop_live_frame :
    verifiedParserPredictionLoopLiveFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("predicted_index", 33, .readWrite),
      ("count", 32, .read),
      ("grammar", 0, .read),
      ("lhs_productions_offset", 15, .read),
      ("first", 31, .read),
      ("workspace", 4, .read),
      ("state_base", 8, .read),
      ("state_capacity", 9, .read),
      ("position", 23, .read),
      ("state_count", 18, .readWrite),
      ("expected_nonterminal", 30, .read),
      ("production", 25, .read),
      ("dot", 26, .read),
      ("origin", 27, .read),
      ("state_id", 24, .read)] := by
  native_decide

theorem verifiedParser_prediction_loop_live_frame_ids :
    verifiedParserPredictionLoopLiveFrameIds =
      [33, 32, 0, 15, 31, 4, 8, 9, 23, 18, 30, 25, 26, 27, 24] := by
  native_decide

/-- Loop-access bindings whose cells are shared with the surrounding proof.
    `predicted_index` is excluded because the loop invariant owns its cell
    separately. -/
def verifiedParserPredictionLoopSharedFrame :
    LocalAccessFrame :=
  verifiedParserPredictionLoopAccessFrame.excludingName "predicted_index"

def verifiedParserPredictionLoopSharedFrameIds : List VarId :=
  verifiedParserPredictionLoopSharedFrame.ids

theorem verifiedParser_prediction_loop_shared_frame_ids :
    verifiedParserPredictionLoopSharedFrameIds =
      [32, 0, 15, 31, 4, 8, 9, 23, 18] := by
  native_decide

@[simp] theorem mem_verifiedParserPredictionLoopSharedFrameIds_iff
    (id : Nat) :
    id ∈ verifiedParserPredictionLoopSharedFrameIds ↔
      id = 32 ∨ id = 0 ∨ id = 15 ∨ id = 31 ∨ id = 4 ∨
        id = 8 ∨ id = 9 ∨ id = 23 ∨ id = 18 := by
  rw [verifiedParser_prediction_loop_shared_frame_ids]
  simp only [List.mem_cons, List.not_mem_nil, or_false]

/-- Source-derived portion of the prediction frame that is preserved while
    the loop appends a state.  Both mutable loop locals are excluded by name,
    rather than by repeating their generated numeric IDs in effect proofs. -/
def verifiedParserPredictionLoopPreservedFrame :
    LocalAccessFrame :=
  verifiedParserPredictionLoopSharedFrame.excludingName "state_count"

def verifiedParserPredictionLoopPreservedFrameIds : List VarId :=
  verifiedParserPredictionLoopPreservedFrame.ids

def verifiedParserPredictionLoopPersistentBindings : LocalBindingFrame :=
  LocalBindingFrame.union verifiedParserRecognizerParameterFrame
    verifiedParserPredictionLoopSharedFrame.bindings

def verifiedParserPredictionLoopPreservedBindings : LocalBindingFrame :=
  LocalBindingFrame.union verifiedParserRecognizerParameterFrame
    verifiedParserPredictionLoopPreservedFrame.bindings

theorem verifiedParser_prediction_loop_preserved_frame_ids :
    verifiedParserPredictionLoopPreservedFrameIds =
      [32, 0, 15, 31, 4, 8, 9, 23] := by
  native_decide

theorem verifiedParserPredictionLoopPersistentBindings_core_ids :
    verifiedParserPredictionLoopPersistentBindings.coreIds =
      verifiedParserRecognizerParameterIds ++
        verifiedParserPredictionLoopSharedFrameIds := by
  native_decide

theorem verifiedParserPredictionLoopPreservedBindings_core_ids :
    verifiedParserPredictionLoopPreservedBindings.coreIds =
      verifiedParserRecognizerParameterIds ++
        verifiedParserPredictionLoopPreservedFrameIds := by
  native_decide

@[simp] theorem mem_verifiedParserPredictionLoopPreservedFrameIds_iff
    (id : Nat) :
    id ∈ verifiedParserPredictionLoopPreservedFrameIds ↔
      id = 32 ∨ id = 0 ∨ id = 15 ∨ id = 31 ∨ id = 4 ∨
        id = 8 ∨ id = 9 ∨ id = 23 := by
  rw [verifiedParser_prediction_loop_preserved_frame_ids]
  simp only [List.mem_cons, List.not_mem_nil, or_false]

/-- The fifth extracted loop walks the compact production row for the
    nonterminal expected by the state currently being processed. -/
theorem extractedParserRecognize_prediction_loop_shape :
    parserRecognizePredictionLoop =
      .whileLoop (.binary .less (.local 33) (.local 32))
        (.letLocal 34 parserI32Type
          (.index (.local 0)
            (.binary .add
              (.binary .add (.local 15) (.local 31)) (.local 33)))
          parserRecognizePredictionAppendStatement) := by
  rfl

theorem extractedParserRecognize_prediction_loop_body_shape :
    parserRecognizePredictionLoopBody =
      .letLocal 34 parserI32Type
        (.index (.local 0)
          (.binary .add
            (.binary .add (.local 15) (.local 31)) (.local 33)))
        parserRecognizePredictionAppendStatement := by
  rfl

/-! ## Artifact-derived FunctionalView for prediction

The view retains exactly the live recognizer locals needed by the prediction
row.  Both lexical temporaries (`production` and `appended`) are recovered by
the checked reifier, so the proof command is mechanically pinned to the real
source-extracted loop rather than maintained as a second AST.
-/

def predictionLoopLayout : Layout 10 := fun index =>
  [0, 4, 8, 9, 15, 18, 23, 31, 32, 33].get index

private def predictionLoopContext : Context :=
  let c0 := Context.empty.bind 0 (.slice parserI32Type)
  let c1 := c0.bind 4 (.slice parserI32Type)
  let c2 := c1.bind 8 parserI32Type
  let c3 := c2.bind 9 parserI32Type
  let c4 := c3.bind 15 parserI32Type
  let c5 := c4.bind 18 parserI32Type
  let c6 := c5.bind 23 parserI32Type
  let c7 := c6.bind 31 parserI32Type
  let c8 := c7.bind 32 parserI32Type
  c8.bind 33 parserI32Type

private def predictionLoopReification? :=
  reifyCommand? verifiedParserCore (.structure 0) predictionLoopContext true
    predictionLoopLayout 34 parserRecognizePredictionLoop

private theorem predictionLoopReification_exists :
    predictionLoopReification?.isSome := by
  native_decide

/-- Complete mutable FunctionalView command recovered from the checked
    prediction loop. -/
def parserRecognizePredictionLoopView :=
  predictionLoopReification?.get predictionLoopReification_exists

theorem parserRecognizePredictionLoopView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      predictionLoopLayout 34 parserRecognizePredictionLoopView.command =
      parserRecognizePredictionLoop :=
  parserRecognizePredictionLoopView.toCoreExactly

private def predictionBodyReification? :=
  reifyCommand? verifiedParserCore (.structure 0) predictionLoopContext true
    predictionLoopLayout 34 parserRecognizePredictionLoopBody

private theorem predictionBodyReification_exists :
    predictionBodyReification?.isSome := by
  native_decide

private def parserRecognizePredictionBodyView :=
  predictionBodyReification?.get predictionBodyReification_exists

private def predictionSlot {arity : Nat} (index : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .reference (.slot index)

private def predictionLiteral {arity : Nat} (value : Int) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .reference (.literal (.signed .i32 value))

private def predictionConstant {arity : Nat} (id : ConstantId) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.constant id parserI32Type) []

private def predictionBinary {arity : Nat} (operation : BinaryOp)
    (left right : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.binary operation parserI32Type parserI32Type
    (if operation = .less ∨ operation = .equal then .scalar .bool
      else parserI32Type)) [left, right]

private def predictionNegativeOne {arity : Nat} :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.unary .negate parserI32Type parserI32Type)
    [predictionLiteral 1]

private def predictionProductionTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 10 :=
  .apply (.index (.slice parserI32Type) parserI32Type parserI32Type) [
    predictionSlot ⟨0, by omega⟩,
    predictionBinary .add
      (predictionBinary .add (predictionSlot ⟨4, by omega⟩)
        (predictionSlot ⟨7, by omega⟩))
      (predictionSlot ⟨9, by omega⟩)]

private def predictionSeedTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 11 :=
  .apply (.call extractedParserStateSeedFunction.id
    (List.replicate 7 parserI32Type) (.structure 1)) [
      predictionSlot ⟨10, by omega⟩,
      predictionLiteral 0,
      predictionSlot ⟨6, by omega⟩,
      predictionNegativeOne,
      predictionConstant 37,
      predictionNegativeOne,
      predictionNegativeOne]

private def predictionAppendArguments : List
    (Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 11) := [
  predictionSlot ⟨1, by omega⟩,
  predictionSlot ⟨2, by omega⟩,
  predictionSlot ⟨3, by omega⟩,
  predictionSlot ⟨6, by omega⟩,
  predictionSeedTerm,
  predictionSlot ⟨5, by omega⟩]

private theorem predictionAppendArguments_toCore :
    Lanius.FunctionalView.Core.toCoreExprs
      (Layout.push predictionLoopLayout 34) predictionAppendArguments =
      recognizerAppendArguments (.local 23)
        parserRecognizePredictionSeedCall := by
  rfl

private def predictionAppendTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 11 :=
  .apply (.call extractedParserAppendStateFunction.id [
    .slice parserI32Type, parserI32Type, parserI32Type, parserI32Type,
    .structure 1, parserI32Type] (.structure 2)) predictionAppendArguments

private def predictionFullCondition :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 12 :=
  predictionBinary .equal
    (.apply (.field (.structure 2) 0 parserI32Type)
      [predictionSlot ⟨11, by omega⟩])
    (predictionConstant 41)

private def predictionFullResult :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 12 :=
  .apply (.call extractedParserAppendOrFullFunction.id
    [.structure 2, parserI32Type] (.structure 0)) [
      predictionSlot ⟨11, by omega⟩,
      predictionSlot ⟨6, by omega⟩]

private def predictionBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 10 :=
  .letValue parserI32Type predictionProductionTerm
    (.letValue (.structure 2) predictionAppendTerm
      (.sequence
        (.ifThenElse predictionFullCondition
          (.sequence (.returnValue (some predictionFullResult)) .skip)
          .skip)
        (.sequence
          (.setLocal ⟨5, by omega⟩
            (.apply (.field (.structure 2) 2 parserI32Type)
              [predictionSlot ⟨11, by omega⟩]))
          (.sequence
            (.updateLocal .add ⟨9, by omega⟩ (predictionLiteral 1))
            .skip))))

private theorem predictionBodyCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      predictionLoopLayout 34 predictionBodyCommand =
      parserRecognizePredictionLoopBody := by
  rfl

private def predictionLoopCondition :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 10 :=
  predictionBinary .less
    (predictionSlot ⟨9, by omega⟩)
    (predictionSlot ⟨8, by omega⟩)

def predictionLoopCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 10 :=
  .whileLoop predictionLoopCondition predictionBodyCommand

theorem predictionLoopCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      predictionLoopLayout 34 predictionLoopCommand =
      parserRecognizePredictionLoop := by
  rfl

def predictionWorld (words : List Int) (tokens : List Nat)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId) :
    Lanius.FunctionalView.Core.ReadOnly.World :=
  recognizerWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell

/-- The ten live values retained by the mechanically selected prediction
    layout.  Temporary `production` and `appended` bindings are introduced by
    `Command.letValue`, never stored in this persistent environment. -/
def predictionEnvironment
    (words workspaceValues : List Int) (grammarCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (lhsProductionsOffset position first
      count index stateCount : Nat) : Lanius.FunctionalView.Env 10
  | ⟨0, _⟩ => parserGrammarValue words grammarCell
  | ⟨1, _⟩ => workspaceValue workspaceValues workspaceCell
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat
      (stateBase workspaceLayout.tokenCount))
  | ⟨3, _⟩ => .signed .i32 (Int.ofNat workspaceLayout.capacity)
  | ⟨4, _⟩ => .signed .i32 (Int.ofNat lhsProductionsOffset)
  | ⟨5, _⟩ => .signed .i32 (Int.ofNat stateCount)
  | ⟨6, _⟩ => .signed .i32 (Int.ofNat position)
  | ⟨7, _⟩ => .signed .i32 (Int.ofNat first)
  | ⟨8, _⟩ => .signed .i32 (Int.ofNat count)
  | ⟨9, _⟩ => .signed .i32 (Int.ofNat index)

noncomputable def predictionTermMachine (workspaceLayout : WorkspaceLayout)
    (words : List Int) (grammarCell : CellId) :=
  Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
    (RecognizerCallRegistry.calls workspaceLayout words grammarCell)

noncomputable def predictionStatefulMachine (workspaceLayout : WorkspaceLayout)
    (words : List Int) (grammarCell : CellId) :=
  Lanius.FunctionalView.Core.Stateful.machineWith verifiedParserCore
    (Lanius.FunctionalView.Core.Effectful.evaluateOperation verifiedParserCore
      (RecognizerCallRegistry.calls workspaceLayout words grammarCell))

/-- Persistent state for the extracted prediction loop.  As with initial
    seeding, the loop traverses an interval of the packed `lhsProductions`
    table; the surrounding state-processing proof will identify that interval
    with the expected nonterminal's row. -/
def PredictionPersistentLocal (id : VarId) : Prop :=
  id ∈ verifiedParserRecognizerParameterIds ∨
    id ∈ verifiedParserPredictionLoopSharedFrameIds

def PredictionPreservedLocal (id : VarId) : Prop :=
  id ∈ verifiedParserRecognizerParameterIds ∨
    id ∈ verifiedParserPredictionLoopPreservedFrameIds

theorem PredictionPersistentLocal_source_frame (id : VarId) :
    PredictionPersistentLocal id ↔
      verifiedParserPredictionLoopPersistentBindings.ContainsCoreId id := by
  rw [LocalBindingFrame.ContainsCoreId,
    verifiedParserPredictionLoopPersistentBindings_core_ids]
  simp [PredictionPersistentLocal]

theorem PredictionPreservedLocal_source_frame (id : VarId) :
    PredictionPreservedLocal id ↔
      verifiedParserPredictionLoopPreservedBindings.ContainsCoreId id := by
  rw [LocalBindingFrame.ContainsCoreId,
    verifiedParserPredictionLoopPreservedBindings_core_ids]
  simp [PredictionPreservedLocal]

theorem predictionPersistentLocalFootprint_eq (runtime : State) :
    localCellFootprint runtime PredictionPersistentLocal =
      localBindingFrameFootprint runtime
        verifiedParserPredictionLoopPersistentBindings := by
  unfold localBindingFrameFootprint
  congr 1
  funext id
  exact propext (PredictionPersistentLocal_source_frame id)

theorem predictionPreservedLocalFootprint_eq (runtime : State) :
    localCellFootprint runtime PredictionPreservedLocal =
      localBindingFrameFootprint runtime
        verifiedParserPredictionLoopPreservedBindings := by
  unfold localBindingFrameFootprint
  congr 1
  funext id
  exact propext (PredictionPreservedLocal_source_frame id)

theorem PredictionPreservedLocal_iff (id : VarId) :
    PredictionPreservedLocal id ↔
      PredictionPersistentLocal id ∧ id ≠ 18 := by
  unfold PredictionPreservedLocal PredictionPersistentLocal
  constructor
  · intro preserved
    rcases preserved with parameter | frame
    · refine ⟨Or.inl parameter, ?_⟩
      have bound :=
        (mem_verifiedParserRecognizerParameterIds_iff id).mp parameter
      exact Nat.ne_of_lt (Nat.lt_of_le_of_lt bound (by decide))
    · refine ⟨Or.inr ?_, ?_⟩
      · rw [mem_verifiedParserPredictionLoopPreservedFrameIds_iff] at frame
        rw [mem_verifiedParserPredictionLoopSharedFrameIds_iff]
        rcases frame with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
          simp
      · rw [mem_verifiedParserPredictionLoopPreservedFrameIds_iff] at frame
        rcases frame with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
          decide
  · rintro ⟨persistent, notCount⟩
    rcases persistent with parameter | frame
    · exact Or.inl parameter
    · right
      rw [mem_verifiedParserPredictionLoopSharedFrameIds_iff] at frame
      rw [mem_verifiedParserPredictionLoopPreservedFrameIds_iff]
      rcases frame with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
          rfl <;> simp_all

theorem PredictionPersistentLocal_iff (id : Nat) :
    PredictionPersistentLocal id ↔
      id ∈ verifiedParserRecognizerParameterIds ∨
        id = 8 ∨ id = 9 ∨ id = 15 ∨ id = 18 ∨ id = 23 ∨
          id = 31 ∨ id = 32 := by
  simp only [PredictionPersistentLocal,
    mem_verifiedParserRecognizerParameterIds_iff,
    mem_verifiedParserPredictionLoopSharedFrameIds_iff]
  constructor <;> intro hypothesis <;> omega

theorem PredictionPersistentLocal.lt33
    (id : VarId) (persistent : PredictionPersistentLocal id) : id < 33 := by
  unfold PredictionPersistentLocal at persistent
  rcases persistent with bound | shared
  · exact Nat.lt_of_le_of_lt
      ((mem_verifiedParserRecognizerParameterIds_iff id).mp bound) (by decide)
  · rw [mem_verifiedParserPredictionLoopSharedFrameIds_iff] at shared
    rcases shared with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
      decide

structure RecognizerPredictionLoopInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (runtime : State) (position first count index : Nat) : Prop where
  frame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime position
  workspaceWithinGrammar : WorkspaceWithinGrammar grammar workspace
  positionLocal : runtime.local? 23 =
    some (.signed .i32 (Int.ofNat position))
  lhsProductionsOffsetLocal : runtime.local? 15 =
    some (.signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset))
  firstLocal : runtime.local? 31 =
    some (.signed .i32 (Int.ofNat first))
  countLocal : runtime.local? 32 =
    some (.signed .i32 (Int.ofNat count))
  indexOwned : (Assertion.localPointsTo 33 indexCell
    (some (.signed .i32 (Int.ofNat index)))).holds runtime
  indexLe : index ≤ count
  rowRange : first + count ≤ grammar.lhsProductions.length
  rowProductionBound : ∀ (rowIndex : Nat)
    (rowIndexBound : rowIndex < count),
    grammar.lhsProductions.get ⟨first + rowIndex, by
      have := rowRange
      omega⟩ < grammar.productionCount
  persistentSeparate : CellSet.Disjoint
    (localBindingFrameFootprint runtime
      verifiedParserPredictionLoopPreservedBindings)
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton stateCountCell)
        (CellSet.singleton indexCell)))
  indexBackingDistinct :
    indexCell ≠ grammarCell ∧
    indexCell ≠ tokensCell ∧
    indexCell ≠ workspaceCell ∧
    indexCell ≠ stateCountCell

/-- Project the compatibility-facing pointwise facts from the separation
    invariant.  The mutable state-count local owns its cell separately; every
    other persistent local belongs to the source-derived preserved frame. -/
theorem RecognizerPredictionLoopInvariant.persistentLocalsSeparate
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (id : VarId) (persistent : PredictionPersistentLocal id) :
    runtime.cellId? id ≠ some workspaceCell ∧
      (id ≠ 18 → runtime.cellId? id ≠ some stateCountCell) ∧
      runtime.cellId? id ≠ some indexCell := by
  by_cases notStateCount : id ≠ 18
  · have preserved :=
      (PredictionPreservedLocal_iff id).mpr ⟨persistent, notStateCount⟩
    have framed := (PredictionPreservedLocal_source_frame id).mp preserved
    refine ⟨?_, ?_, ?_⟩
    · intro cellId
      exact invariant.persistentSeparate workspaceCell
        ⟨id, framed, cellId⟩ (Or.inl rfl)
    · intro _ cellId
      exact invariant.persistentSeparate stateCountCell
        ⟨id, framed, cellId⟩ (Or.inr (Or.inl rfl))
    · intro cellId
      exact invariant.persistentSeparate indexCell
        ⟨id, framed, cellId⟩ (Or.inr (Or.inr rfl))
  · have same : id = 18 := Classical.byContradiction notStateCount
    subst id
    have stateCountId := invariant.frame.stateCountOwned.1
    refine ⟨?_, ?_, ?_⟩
    · intro workspaceId
      exact invariant.frame.stateCountBackingDistinct.2.2
        (Option.some.inj (stateCountId.symm.trans workspaceId))
    · intro impossible
      exact False.elim (impossible rfl)
    · intro indexId
      exact invariant.indexBackingDistinct.2.2.2
        (Option.some.inj (stateCountId.symm.trans indexId)).symm

theorem RecognizerPredictionLoopInvariant.indexParameterDistinct
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (id : VarId) (member : id ∈ verifiedParserRecognizerParameterIds) :
    runtime.cellId? id ≠ some indexCell :=
  (invariant.persistentLocalsSeparate id (Or.inl member)).2.2

/-- Every state seeded by the selected prediction row has a grammar-valid
    key.  This semantic fact, rather than packed-range safety alone, is what
    permits later nullable and parent traversals to index production tables. -/
theorem RecognizerPredictionLoopInvariant.seed_within_grammar
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (indexBound : index < count) :
    let production := grammar.lhsProductions.get
      ⟨first + index, by
        have := invariant.rowRange
        omega⟩
    StateKeyWithinGrammar grammar
      (recognizerPredictionSeed production position).key := by
  dsimp only
  exact {
    productionBound := invariant.rowProductionBound index indexBound
    dotBound := by
      change 0 ≤ _
      exact Nat.zero_le _
  }

theorem RecognizerPredictionLoopInvariant.condition_true
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (indexBound : index < count) :
    Evaluates verifiedParserCore runtime
      (.binary .less (.local 33) (.local 32)) (.boolean true) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 33)
      (.signed .i32 (Int.ofNat index)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 33 _
      (Assertion.localPointsTo_local 33 indexCell _ runtime
        invariant.indexOwned)⟩
  have right : Evaluates verifiedParserCore runtime (.local 32)
      (.signed .i32 (Int.ofNat count)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 32 _
      invariant.countLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt, indexBound]

theorem RecognizerPredictionLoopInvariant.condition_false
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (done : count ≤ index) :
    Evaluates verifiedParserCore runtime
      (.binary .less (.local 33) (.local 32)) (.boolean false) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 33)
      (.signed .i32 (Int.ofNat index)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 33 _
      (Assertion.localPointsTo_local 33 indexCell _ runtime
        invariant.indexOwned)⟩
  have right : Evaluates verifiedParserCore runtime (.local 32)
      (.signed .i32 (Int.ofNat count)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 32 _
      invariant.countLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt]
  omega

/-- Exact evaluation of the prediction loop's packed production-table read. -/
theorem RecognizerPredictionLoopInvariant.read_production
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (indexBound : index < count) :
    Evaluates verifiedParserCore runtime
      (.index (.local 0)
        (.binary .add
          (.binary .add (.local 15) (.local 31)) (.local 33)))
      (.signed .i32 (Int.ofNat
        (grammar.lhsProductions.get ⟨first + index, by
          have := invariant.rowRange
          omega⟩))) runtime := by
  have rowBound : first + index < grammar.lhsProductions.length := by
    have := invariant.rowRange
    omega
  have physicalBound :=
    invariant.frame.recognizer.grammarEncoded.lhsProductions.row_in_bounds
      rowBound
  have physicalBound' :
      grammarLayout.lhsProductionsOffset + first + index < words.length := by
    simpa [Nat.add_assoc] using physicalBound
  have grammarResult : Evaluates verifiedParserCore runtime (.local 0)
      (parserGrammarValue words grammarCell) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 0 _
      invariant.frame.recognizer.grammarLocal⟩
  have tableOffset : Evaluates verifiedParserCore runtime (.local 15)
      (.signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 15 _
      invariant.lhsProductionsOffsetLocal⟩
  have firstResult : Evaluates verifiedParserCore runtime (.local 31)
      (.signed .i32 (Int.ofNat first)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 31 _
      invariant.firstLocal⟩
  have indexResult : Evaluates verifiedParserCore runtime (.local 33)
      (.signed .i32 (Int.ofNat index)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 33 _
      (Assertion.localPointsTo_local 33 indexCell _ runtime
        invariant.indexOwned)⟩
  have partialBound : grammarLayout.lhsProductionsOffset + first ≤
      2147483647 := Nat.le_trans
    (Nat.le_of_lt (Nat.lt_of_le_of_lt (Nat.le_add_right _ _) physicalBound'))
    invariant.frame.recognizer.wordsI32
  have partialResult : Evaluates verifiedParserCore runtime
      (.binary .add (.local 15) (.local 31))
      (.signed .i32
        (Int.ofNat (grammarLayout.lhsProductionsOffset + first))) runtime := by
    have castAddress : Int.ofNat grammarLayout.lhsProductionsOffset +
        Int.ofNat first =
        Int.ofNat (grammarLayout.lhsProductionsOffset + first) :=
      (Int.natCast_add _ _).symm
    have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target _
      partialBound
    apply evaluatesEagerBinary (by decide) (by decide) tableOffset firstResult
    simp only [evalBinaryValue, evalSignedBinary]
    rw [castAddress, wrapped]
    simp
  have addressBound : grammarLayout.lhsProductionsOffset + first + index ≤
      2147483647 := Nat.le_trans (Nat.le_of_lt physicalBound')
        invariant.frame.recognizer.wordsI32
  have addressResult : Evaluates verifiedParserCore runtime
      (.binary .add
        (.binary .add (.local 15) (.local 31)) (.local 33))
      (.signed .i32 (Int.ofNat
        (grammarLayout.lhsProductionsOffset + first + index))) runtime := by
    have castAddress :
        Int.ofNat (grammarLayout.lhsProductionsOffset + first) +
          Int.ofNat index =
        Int.ofNat (grammarLayout.lhsProductionsOffset + first + index) :=
      (Int.natCast_add _ _).symm
    have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target _
      addressBound
    apply evaluatesEagerBinary (by decide) (by decide) partialResult indexResult
    simp only [evalBinaryValue, evalSignedBinary]
    rw [castAddress, wrapped]
    simp
  have read := evaluatesSignedI32SliceIndex verifiedParserCore runtime runtime
    runtime words (.local 0)
      (.binary .add
        (.binary .add (.local 15) (.local 31)) (.local 33))
    grammarCell (grammarLayout.lhsProductionsOffset + first + index)
    physicalBound' grammarResult addressResult
    invariant.frame.recognizer.grammarBacking
  have physical :=
    invariant.frame.recognizer.grammarEncoded.lhsProductions.get rowBound
  have physical' : words.get
      ⟨grammarLayout.lhsProductionsOffset + first + index, physicalBound'⟩ =
      Int.ofNat (grammar.lhsProductions.get ⟨first + index, rowBound⟩) := by
    simpa [Nat.add_assoc] using physical
  rw [physical'] at read
  exact read

theorem RecognizerPredictionLoopInvariant.index_succ_i32
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (indexBound : index < count) : index + 1 ≤ 2147483647 := by
  have tableFits : grammar.lhsProductions.length ≤ words.length := by
    rcases (invariant.frame.recognizer.grammarEncoded.validation_facts
      invariant.frame.recognizer.grammarWellFormed).prelude.lhsProductionsRange
      with ⟨_, fits⟩
    omega
  have range := invariant.rowRange
  exact Nat.le_trans (by omega)
    (Nat.le_trans tableFits invariant.frame.recognizer.wordsI32)

theorem RecognizerPredictionLoopInvariant.after_temporary_bind
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (id : VarId) (value : Value) (temporary : 33 < id) :
    RecognizerPredictionLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell (runtime.bindLocal id value)
      position first count index := by
  have different (fixed : Nat) (bound : fixed ≤ 33) : id ≠ fixed := by
    intro equal
    rw [equal] at temporary
    exact (Nat.not_lt_of_ge bound) temporary
  exact {
    frame := {
      recognizer := invariant.frame.recognizer.after_bind_local id value
        (different 0 (by decide)) (different 1 (by decide))
        (different 2 (by decide)) (different 3 (by decide))
        (different 4 (by decide)) (different 5 (by decide))
      positionBound := invariant.frame.positionBound
      stateBaseLocal :=
        (bindLocal_preserves_other_local
          invariant.frame.recognizer.wellFormed
          (different 8 (by decide))).trans invariant.frame.stateBaseLocal
      stateCapacityLocal :=
        (bindLocal_preserves_other_local
          invariant.frame.recognizer.wellFormed
          (different 9 (by decide))).trans invariant.frame.stateCapacityLocal
      stateCountLocal :=
        (bindLocal_preserves_other_local
          invariant.frame.recognizer.wellFormed
          (different 18 (by decide))).trans invariant.frame.stateCountLocal
      stateCountOwned := bindLocal_preserves_localPointsTo_of_ne runtime id 18
        value stateCountCell
        (some (.signed .i32 (Int.ofNat workspace.states.length)))
        invariant.frame.recognizer.wellFormed (different 18 (by decide))
        invariant.frame.stateCountOwned
      stateCountBackingDistinct := invariant.frame.stateCountBackingDistinct
      stateCountParameterSeparate := localCellFootprint_disjoint_singleton (by
        intro queried queriedBound same
        apply invariant.frame.stateCountParameterDistinct queried queriedBound
        have queriedLe :=
          (mem_verifiedParserRecognizerParameterIds_iff queried).mp queriedBound
        have notEqual : id ≠ queried := different queried
          (Nat.le_trans queriedLe (by decide))
        simpa [State.bindLocal, State.bindCell, State.cellId?, notEqual] using
          same
        )
    }
    workspaceWithinGrammar := invariant.workspaceWithinGrammar
    positionLocal :=
      (bindLocal_preserves_other_local invariant.frame.recognizer.wellFormed
        (different 23 (by decide))).trans invariant.positionLocal
    lhsProductionsOffsetLocal :=
      (bindLocal_preserves_other_local invariant.frame.recognizer.wellFormed
        (different 15 (by decide))).trans invariant.lhsProductionsOffsetLocal
    firstLocal :=
      (bindLocal_preserves_other_local invariant.frame.recognizer.wellFormed
        (different 31 (by decide))).trans invariant.firstLocal
    countLocal :=
      (bindLocal_preserves_other_local invariant.frame.recognizer.wellFormed
        (different 32 (by decide))).trans invariant.countLocal
    indexOwned := bindLocal_preserves_localPointsTo_of_ne runtime id 33 value
      indexCell (some (.signed .i32 (Int.ofNat index)))
      invariant.frame.recognizer.wellFormed (different 33 (by decide))
      invariant.indexOwned
    indexLe := invariant.indexLe
    rowRange := invariant.rowRange
    rowProductionBound := invariant.rowProductionBound
    persistentSeparate := by
      intro cell framed written
      obtain ⟨queried, preserved, cellId⟩ := framed
      have persistent := (PredictionPreservedLocal_iff queried).mp
        ((PredictionPreservedLocal_source_frame queried).mpr preserved) |>.1
      have notEqual : id ≠ queried := different queried
        (Nat.le_of_lt persistent.lt33)
      apply invariant.persistentSeparate cell
        ⟨queried, preserved, ?_⟩ written
      simpa [State.bindLocal, State.bindCell, State.cellId?, notEqual] using
        cellId
    indexBackingDistinct := invariant.indexBackingDistinct
  }

theorem RecognizerPredictionLoopInvariant.bind_production
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (indexBound : index < count) :
    let production := grammar.lhsProductions.get
      ⟨first + index, by
        have := invariant.rowRange
        omega⟩
    RecognizerPredictionAppendInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell
      (runtime.bindLocal 34 (.signed .i32 (Int.ofNat production)))
      position production index := by
  dsimp only
  let production := grammar.lhsProductions.get
    ⟨first + index, by
      have := invariant.rowRange
      omega⟩
  let value : Value := .signed .i32 (Int.ofNat production)
  let boundInvariant := invariant.after_temporary_bind 34 value (by decide)
  exact {
    frame := boundInvariant.frame
    seedDerivation := {
      languageSound := by
        have productionBound : production < grammar.productionCount := by
          simpa [production] using
            invariant.rowProductionBound index indexBound
        change EarleyStateSound grammar tokens
          ((recognizerPredictionSeed production position).atPosition position)
        simpa [production, recognizerPredictionSeed, freshSeed] using
          (freshSeed_sound (grammar := grammar) (tokens := tokens)
            (position := position) productionBound)
      backpointer := by
        have productionBound : production < grammar.productionCount := by
          simpa [production] using
            invariant.rowProductionBound index indexBound
        simpa [production, recognizerPredictionSeed, freshSeed] using
          (EarleyBackpointerStep.fresh
            (grammar := grammar) (tokens := tokens) (workspace := workspace)
            (stateId := workspace.states.length) (position := position)
            productionBound)
    }
    positionLocal := boundInvariant.positionLocal
    productionLocal := by
      simpa [production, value] using bindLocal_finds_local runtime 34 value
        invariant.frame.recognizer.wellFormed
    indexOwned := boundInvariant.indexOwned
    indexSuccI32 := invariant.index_succ_i32 indexBound
    indexBackingDistinct := invariant.indexBackingDistinct
    indexParameterSeparate := localCellFootprint_disjoint_singleton
      boundInvariant.indexParameterDistinct
  }

private theorem RecognizerPredictionLoopInvariant.functional_read_production
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (rowBound : first + index < grammar.lhsProductions.length) :
    let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
    let world := predictionWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let environment := predictionEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset position
      first count index workspace.states.length
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      world environment predictionProductionTerm =
      .ok (.signed .i32 (Int.ofNat production), world) := by
  dsimp only
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let world := predictionWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let environment := predictionEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset position
    first count index workspace.states.length
  have physicalBound :=
    invariant.frame.recognizer.grammarEncoded.lhsProductions.row_in_bounds
      rowBound
  have physicalBound' :
      grammarLayout.lhsProductionsOffset + first + index < words.length := by
    simpa [Nat.add_assoc] using physicalBound
  have partialBound : grammarLayout.lhsProductionsOffset + first ≤
      2147483647 := Nat.le_trans
    (Nat.le_of_lt (Nat.lt_of_le_of_lt (Nat.le_add_right _ _) physicalBound'))
    invariant.frame.recognizer.wordsI32
  have addressBound : grammarLayout.lhsProductionsOffset + first + index ≤
      2147483647 := Nat.le_trans (Nat.le_of_lt physicalBound')
        invariant.frame.recognizer.wordsI32
  have offsetResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment (predictionSlot ⟨4, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset), world) :=
    by rfl
  have firstResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment (predictionSlot ⟨7, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat first), world) := by rfl
  have indexResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment (predictionSlot ⟨9, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat index), world) := by rfl
  have partialResult :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_add
      (leftType := parserI32Type) (rightType := parserI32Type)
      (outputType := parserI32Type) offsetResult firstResult partialBound
  have addressResult :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_add
      (leftType := parserI32Type) (rightType := parserI32Type)
      (outputType := parserI32Type) partialResult indexResult addressBound
  have baseResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment (predictionSlot ⟨0, by omega⟩) =
      .ok (parserGrammarValue words grammarCell, world) := by rfl
  have physical :=
    invariant.frame.recognizer.grammarEncoded.lhsProductions.get rowBound
  have physical' : words.get
      ⟨grammarLayout.lhsProductionsOffset + first + index, physicalBound'⟩ =
      Int.ofNat production := by
    simpa [production, Nat.add_assoc] using physical
  have readOnlyResult :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_index_as
      (baseType := .slice parserI32Type) (indexType := parserI32Type)
      (elementType := parserI32Type) baseResult addressResult
      (recognizerWorld_finds_grammar)
      physicalBound' physical'
  have termAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerCallRegistry.calls workspaceLayout words grammarCell)
      (world := world) (environment := environment)
      predictionProductionTerm (by native_decide)
  change Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      world environment predictionProductionTerm =
    .ok (.signed .i32 (Int.ofNat production), world)
  exact termAgreement.trans readOnlyResult

/-- Functional evaluation of the nested `state_seed` constructor used by one
    prediction iteration.  The arithmetic/constants are discharged through
    the generic call-free bridge; only the source helper call reaches the
    recognizer registry. -/
private theorem RecognizerPredictionLoopInvariant.functional_seed
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (rowBound : first + index < grammar.lhsProductions.length) :
    let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
    let seed := recognizerPredictionSeed production position
    let world := predictionWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let environment := (predictionEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset position
      first count index workspace.states.length).push
        (.signed .i32 (Int.ofNat production))
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      world environment predictionSeedTerm =
      .ok (stateSeedValue seed, world) := by
  dsimp only
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let seed := recognizerPredictionSeed production position
  let world := predictionWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let environment := (predictionEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset position
    first count index workspace.states.length).push
      (.signed .i32 (Int.ofNat production))
  let machine := predictionTermMachine workspaceLayout words grammarCell
  have productionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (predictionSlot ⟨10, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat production), world) := by
    rfl
  have zeroResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (predictionLiteral 0) =
      .ok (.signed .i32 0, world) := by
    rfl
  have positionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (predictionSlot ⟨6, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat position), world) := by
    rfl
  have negativeOneReadOnly :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_negate_one
      (program := verifiedParserCore) (world := world)
      (environment := environment) (inputType := parserI32Type)
      (outputType := parserI32Type)
  have negativeOneAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerCallRegistry.calls workspaceLayout words grammarCell)
      (world := world) (environment := environment)
      (predictionNegativeOne : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 11) (by native_decide)
  have negativeOneResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (predictionNegativeOne : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 11) =
      .ok (.signed .i32 (-1), world) := by
    change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerCallRegistry.calls workspaceLayout words grammarCell))
      world environment (predictionNegativeOne : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 11) =
      .ok (.signed .i32 (-1), world)
    exact negativeOneAgreement.trans negativeOneReadOnly
  have childNoneReadOnly :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_constant
      (program := verifiedParserCore) (world := world)
      (environment := environment) (type := parserI32Type)
      verifiedParser_child_none_constant
  have childNoneAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerCallRegistry.calls workspaceLayout words grammarCell)
      (world := world) (environment := environment)
      (predictionConstant 37 : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 11) (by native_decide)
  have childNoneResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (predictionConstant 37 : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 11) =
      .ok (.signed .i32 0, world) := by
    change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerCallRegistry.calls workspaceLayout words grammarCell))
      world environment (predictionConstant 37 : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 11) =
      .ok (.signed .i32 0, world)
    exact childNoneAgreement.trans childNoneReadOnly
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [
        predictionSlot ⟨10, by omega⟩,
        predictionLiteral 0,
        predictionSlot ⟨6, by omega⟩,
        predictionNegativeOne,
        predictionConstant 37,
        predictionNegativeOne,
        predictionNegativeOne] =
      .ok (parserStateSeedArgumentsValues seed, world) := by
    simpa [seed, recognizerPredictionSeed, parserStateSeedArgumentsValues,
      previousValue, encodeStateId, childTag, childPayload, childKind] using
      Lanius.FunctionalView.evaluateTerms_cons productionResult
        (Lanius.FunctionalView.evaluateTerms_cons zeroResult
          (Lanius.FunctionalView.evaluateTerms_cons positionResult
            (Lanius.FunctionalView.evaluateTerms_cons negativeOneResult
              (Lanius.FunctionalView.evaluateTerms_cons childNoneResult
                (Lanius.FunctionalView.evaluateTerms_cons negativeOneResult
                  (Lanius.FunctionalView.evaluateTerms_cons negativeOneResult
                    (Lanius.FunctionalView.evaluateTerms_nil machine world
                      environment)))))))
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerCallRegistry.calls workspaceLayout words grammarCell).evaluate
    world extractedParserStateSeedFunction.id
      (parserStateSeedArgumentsValues seed) = _
  exact RecognizerCallRegistry.calls_at_seed world seed

/-- Left-to-right FunctionalView evaluation of the six `append_state`
    arguments.  In particular, the nested constructor is evaluated in place
    and the abstract world is threaded through the argument list. -/
private theorem RecognizerPredictionLoopInvariant.functional_append_arguments
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (rowBound : first + index < grammar.lhsProductions.length) :
    let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
    let seed := recognizerPredictionSeed production position
    let world := predictionWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let environment := (predictionEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset position
      first count index workspace.states.length).push
        (.signed .i32 (Int.ofNat production))
    Lanius.FunctionalView.evaluateTerms
      (predictionTermMachine workspaceLayout words grammarCell)
      world environment predictionAppendArguments =
      .ok ([
        workspaceValue workspaceValues workspaceCell,
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
        .signed .i32 (Int.ofNat workspaceLayout.capacity),
        .signed .i32 (Int.ofNat position),
        stateSeedValue seed,
      .signed .i32 (Int.ofNat workspace.states.length)], world) := by
  dsimp only
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let seed := recognizerPredictionSeed production position
  let world := predictionWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let environment := (predictionEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset position
    first count index workspace.states.length).push
      (.signed .i32 (Int.ofNat production))
  let machine := predictionTermMachine workspaceLayout words grammarCell
  have workspaceResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (predictionSlot ⟨1, by omega⟩) =
      .ok (workspaceValue workspaceValues workspaceCell, world) := by rfl
  have baseResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (predictionSlot ⟨2, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat
        (stateBase workspaceLayout.tokenCount)), world) := by rfl
  have capacityResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (predictionSlot ⟨3, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat workspaceLayout.capacity), world) := by rfl
  have positionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (predictionSlot ⟨6, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat position), world) := by rfl
  have seedResult : Lanius.FunctionalView.Term.evaluate machine world
      environment predictionSeedTerm = .ok (stateSeedValue seed, world) := by
    change Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell) world
      environment predictionSeedTerm = .ok (stateSeedValue seed, world)
    exact invariant.functional_seed rowBound
  have stateCountResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (predictionSlot ⟨5, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat workspace.states.length), world) := by rfl
  simpa only [predictionAppendArguments] using
    Lanius.FunctionalView.evaluateTerms_cons workspaceResult
      (Lanius.FunctionalView.evaluateTerms_cons baseResult
        (Lanius.FunctionalView.evaluateTerms_cons capacityResult
          (Lanius.FunctionalView.evaluateTerms_cons positionResult
            (Lanius.FunctionalView.evaluateTerms_cons seedResult
              (Lanius.FunctionalView.evaluateTerms_cons stateCountResult
                (Lanius.FunctionalView.evaluateTerms_nil machine world
                  environment))))))

/-- Functional execution of the mutating `append_state` expression.  Its
    result world keeps the grammar slice and replaces only the compact
    workspace slice with the logical append encoding. -/
private theorem RecognizerPredictionLoopInvariant.functional_append
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (indexBound : index < count)
    (rowBound : first + index < grammar.lhsProductions.length) :
    let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
    let seed := recognizerPredictionSeed production position
    let outcome := (appendLogical workspaceLayout.capacity position seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace position seed
      workspaceValues
    let world := predictionWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let environment := (predictionEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset position
      first count index workspace.states.length).push
        (.signed .i32 (Int.ofNat production))
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      world environment predictionAppendTerm =
      .ok (appendOutcomeValue outcome,
        predictionWorld words tokens nextValues grammarCell tokensCell workspaceCell) := by
  dsimp only
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let seed := recognizerPredictionSeed production position
  let outcome := (appendLogical workspaceLayout.capacity position seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace position seed
    workspaceValues
  let world := predictionWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let environment := (predictionEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset position
    first count index workspace.states.length).push
      (.signed .i32 (Int.ofNat production))
  let machine := predictionTermMachine workspaceLayout words grammarCell
  let callValues : List Value := [
    workspaceValue workspaceValues workspaceCell,
    .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
    .signed .i32 (Int.ofNat workspaceLayout.capacity),
    .signed .i32 (Int.ofNat position),
    stateSeedValue seed,
    .signed .i32 (Int.ofNat workspace.states.length)]
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment predictionAppendArguments = .ok (callValues, world) := by
    change Lanius.FunctionalView.evaluateTerms
      (predictionTermMachine workspaceLayout words grammarCell) world
      environment predictionAppendArguments = .ok (callValues, world)
    exact invariant.functional_append_arguments rowBound
  let bound := runtime.bindLocal 34
    (.signed .i32 (Int.ofNat production))
  let appendInvariant := invariant.bind_production indexBound
  let appended := appendInvariant.evaluate_append
  have different : workspaceCell ≠ grammarCell :=
    invariant.frame.recognizer.grammarWorkspaceDistinct.symm
  let input : AppendStateCall.Input workspaceLayout world callValues := {
    workspace := workspace
    values := workspaceValues
    cell := workspaceCell
    position := position
    seed := seed
    valuesLength := invariant.frame.recognizer.workspaceLength
    encoded := invariant.frame.recognizer.workspaceEncoded
    positionBound := invariant.frame.positionBound
    seedOriginBound := by
      simpa [seed, recognizerPredictionSeed] using invariant.frame.positionBound
    found := by
      simpa [world, predictionWorld] using
        (recognizerWorld_finds_workspace
          (tokens := tokens) (tokensCell := tokensCell) different)
    argumentsEq := rfl
  }
  have argumentsExecution : ArgumentsEvaluateTo verifiedParserCore bound
      (Lanius.FunctionalView.Core.toCoreExprs
        (Layout.push predictionLoopLayout 34) predictionAppendArguments)
      callValues appended.argumentsState := by
    rw [predictionAppendArguments_toCore]
    simpa [bound, callValues, seed, production, rowBound, appendInvariant,
      appended] using appended.argumentsEvaluation
  have worldRepresents :
      Lanius.FunctionalView.Core.ReadOnly.World.Represents world
        appended.argumentsState := by
    simpa [world, predictionWorld] using
      recognizerWorld_represents appended.argumentsInvariant
  have worldOwned :
      (Lanius.FunctionalView.Core.ReadOnly.World.owns world).holds
        appended.argumentsState :=
    (Lanius.FunctionalView.Core.ReadOnly.World.owns_iff_represents
      appended.argumentsInvariant.wellFormed).2 worldRepresents
  have registryResult := RecognizerCallRegistry.calls_at_append_input
    (words := words) (grammarCell := grammarCell) input bound
    appended.argumentsState (Layout.push predictionLoopLayout 34)
    predictionAppendArguments appended.argumentsInvariant.wellFormed worldOwned
    argumentsExecution
  have outcomeEq : input.outcome = outcome := by
    rfl
  have afterWorldEq : input.afterWorld =
      predictionWorld words tokens nextValues grammarCell tokensCell workspaceCell := by
    change Lanius.FunctionalView.Core.ReadOnly.World.setI32Slice world
        workspaceCell nextValues =
      predictionWorld words tokens nextValues grammarCell tokensCell workspaceCell
    simpa [world, predictionWorld] using
      (recognizerWorld_set_workspace
        (tokens := tokens) (tokensCell := tokensCell)
        (beforeValues := workspaceValues) (afterValues := nextValues)
        different appended.argumentsInvariant.tokensWorkspaceDistinct.symm)
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerCallRegistry.calls workspaceLayout words grammarCell).evaluate
    world extractedParserAppendStateFunction.id callValues =
      .ok (appendOutcomeValue outcome,
        predictionWorld words tokens nextValues grammarCell tokensCell workspaceCell)
  rw [outcomeEq, afterWorldEq] at registryResult
  exact registryResult

/-- The continuation guard reads only the append-result status.  This fact is
    independent of the workspace contents and is shared by successful and
    capacity-full iterations. -/
private theorem predictionFullCondition_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 11)
    (outcome : AppendOutcome) :
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      world (environment.push (appendOutcomeValue outcome))
      predictionFullCondition =
      .ok (.boolean (decide (outcome.status = .full)), world) := by
  have agreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerCallRegistry.calls workspaceLayout words grammarCell)
      (world := world)
      (environment := environment.push (appendOutcomeValue outcome))
      predictionFullCondition (by native_decide)
  have readOnlyResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world (environment.push (appendOutcomeValue outcome))
      predictionFullCondition =
      .ok (.boolean (decide (outcome.status = .full)), world) := by
    rcases outcome with ⟨status, stateId, stateCount, inserted⟩
    cases status <;> rfl
  change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerCallRegistry.calls workspaceLayout words grammarCell))
      world (environment.push (appendOutcomeValue outcome))
      predictionFullCondition = _
  exact agreement.trans readOnlyResult

/-- Field two of the append result is the next logical state count. -/
private theorem predictionStateCount_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 11)
    (outcome : AppendOutcome) :
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      world (environment.push (appendOutcomeValue outcome))
      (.apply (.field (.structure 2) 2 parserI32Type)
        [predictionSlot ⟨11, by omega⟩]) =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), world) := by
  have agreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerCallRegistry.calls workspaceLayout words grammarCell)
      (world := world)
      (environment := environment.push (appendOutcomeValue outcome))
      (.apply (.field (.structure 2) 2 parserI32Type)
        [predictionSlot ⟨11, by omega⟩]) (by native_decide)
  have readOnlyResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world (environment.push (appendOutcomeValue outcome))
      (.apply (.field (.structure 2) 2 parserI32Type)
        [predictionSlot ⟨11, by omega⟩]) =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), world) := by
    rfl
  change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerCallRegistry.calls workspaceLayout words grammarCell))
      world (environment.push (appendOutcomeValue outcome))
      (.apply (.field (.structure 2) 2 parserI32Type)
        [predictionSlot ⟨11, by omega⟩]) = _
  exact agreement.trans readOnlyResult

/-- Functional evaluation of the early capacity result.  The helper call is
    store-pure, so it preserves the post-append workspace world. -/
private theorem predictionFullResult_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 11)
    (outcome : AppendOutcome) (position : Nat)
    (positionValue : environment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat position)) :
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      world (environment.push (appendOutcomeValue outcome))
      predictionFullResult =
      .ok (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position), world) := by
  let machine := predictionTermMachine workspaceLayout words grammarCell
  let extended := environment.push (appendOutcomeValue outcome)
  have outcomeResult : Lanius.FunctionalView.Term.evaluate machine world
      extended (predictionSlot ⟨11, by omega⟩) =
      .ok (appendOutcomeValue outcome, world) := by rfl
  have positionResult : Lanius.FunctionalView.Term.evaluate machine world
      extended (predictionSlot ⟨6, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat position), world) := by
    apply Lanius.FunctionalView.Term.evaluate_slot
    change environment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat position)
    exact positionValue
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      extended [predictionSlot ⟨11, by omega⟩,
        predictionSlot ⟨6, by omega⟩] =
      .ok ([appendOutcomeValue outcome,
        .signed .i32 (Int.ofNat position)], world) :=
    Lanius.FunctionalView.evaluateTerms_cons outcomeResult
      (Lanius.FunctionalView.evaluateTerms_cons positionResult
        (Lanius.FunctionalView.evaluateTerms_nil machine world extended))
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerCallRegistry.calls workspaceLayout words grammarCell).evaluate
    world extractedParserAppendOrFullFunction.id
      [appendOutcomeValue outcome, .signed .i32 (Int.ofNat position)] = _
  exact RecognizerCallRegistry.calls_at_append_or_full world outcome
    (Int.ofNat position)

private def predictionOkEnvironment
    (environment : Lanius.FunctionalView.Env 11)
    (outcome : AppendOutcome) (index : Nat) :
    Lanius.FunctionalView.Env 10 :=
  Lanius.FunctionalView.Stateful.Env.pop
    (Lanius.FunctionalView.Stateful.Env.pop
      (Lanius.FunctionalView.Stateful.Env.set
        (Lanius.FunctionalView.Stateful.Env.set
          (environment.push (appendOutcomeValue outcome))
          ⟨5, by omega⟩ (.signed .i32 (Int.ofNat outcome.stateCount)))
        ⟨9, by omega⟩ (.signed .i32 (Int.ofNat (index + 1)))))

/-- Canonical FunctionalView execution of one non-full prediction body.  This
    is the first complete recognizer iteration expressed without recursively
    replaying the structural-Core loop. -/
private theorem RecognizerPredictionLoopInvariant.functional_ok_body
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (indexBound : index < count)
    (rowBound : first + index < grammar.lhsProductions.length)
    (statusOk :
      let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
      let seed := recognizerPredictionSeed production position
      (appendLogical workspaceLayout.capacity position seed workspace).1.status =
        .ok) :
    let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
    let seed := recognizerPredictionSeed production position
    let outcome := (appendLogical workspaceLayout.capacity position seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace position seed
      workspaceValues
    let beforeWorld := predictionWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let afterWorld := predictionWorld words tokens nextValues grammarCell tokensCell workspaceCell
    let beforeEnvironment := predictionEnvironment words workspaceValues
      grammarCell workspaceCell workspaceLayout
      grammarLayout.lhsProductionsOffset position first count index
      workspace.states.length
    let productionEnvironment := beforeEnvironment.push
      (.signed .i32 (Int.ofNat production))
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      beforeWorld beforeEnvironment predictionBodyCommand .next afterWorld
      (predictionOkEnvironment productionEnvironment outcome index) := by
  dsimp only
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let seed := recognizerPredictionSeed production position
  let outcome := (appendLogical workspaceLayout.capacity position seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace position seed
    workspaceValues
  let beforeWorld := predictionWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let afterWorld := predictionWorld words tokens nextValues grammarCell tokensCell workspaceCell
  let beforeEnvironment := predictionEnvironment words workspaceValues
    grammarCell workspaceCell workspaceLayout
    grammarLayout.lhsProductionsOffset position first count index
    workspace.states.length
  let productionEnvironment := beforeEnvironment.push
    (.signed .i32 (Int.ofNat production))
  let resultEnvironment := productionEnvironment.push
    (appendOutcomeValue outcome)
  have productionResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      beforeWorld beforeEnvironment predictionProductionTerm =
      .ok (.signed .i32 (Int.ofNat production), beforeWorld) := by
    exact invariant.functional_read_production rowBound
  have appendResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      beforeWorld productionEnvironment predictionAppendTerm =
      .ok (appendOutcomeValue outcome, afterWorld) := by
    exact invariant.functional_append indexBound rowBound
  have fullCondition : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment predictionFullCondition =
      .ok (.boolean false, afterWorld) := by
    have evaluated := predictionFullCondition_evaluates
      (workspaceLayout := workspaceLayout) (words := words)
      (grammarCell := grammarCell) afterWorld productionEnvironment outcome
    have statusOk' : outcome.status = .ok := by
      simpa [outcome, seed, production] using statusOk
    rw [statusOk'] at evaluated
    change Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell) afterWorld
      (productionEnvironment.push (appendOutcomeValue outcome))
      predictionFullCondition = .ok (.boolean false, afterWorld)
    simpa using evaluated
  have countResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment
      (.apply (.field (.structure 2) 2 parserI32Type)
        [predictionSlot ⟨11, by omega⟩]) =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), afterWorld) :=
    predictionStateCount_evaluates
      (workspaceLayout := workspaceLayout) (words := words)
      (grammarCell := grammarCell) afterWorld productionEnvironment outcome
  let afterCount := Lanius.FunctionalView.Stateful.Env.set resultEnvironment
    ⟨5, by omega⟩ (.signed .i32 (Int.ofNat outcome.stateCount))
  have oneResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      afterWorld afterCount (predictionLiteral 1) =
      .ok (.signed .i32 1, afterWorld) := by rfl
  have currentIndex : afterCount ⟨9, by omega⟩ =
      .signed .i32 (Int.ofNat index) := by
    change (Lanius.FunctionalView.Stateful.Env.set resultEnvironment
      ⟨5, by omega⟩ (.signed .i32 (Int.ofNat outcome.stateCount)))
        ⟨9, by omega⟩ = _
    have different : (⟨9, by omega⟩ : Fin 12) ≠ ⟨5, by omega⟩ := by
      intro equal
      have valuesEqual := congrArg Fin.val equal
      change 9 = 5 at valuesEqual
      omega
    rw [Lanius.FunctionalView.Stateful.Env.set_other
      (different := different)]
    let index10 : Fin 10 := ⟨9, by decide⟩
    let index11 : Fin 11 := ⟨9, by decide⟩
    let index12 : Fin 12 := ⟨9, by decide⟩
    have index12Eq : index12 =
        ⟨index11.val, Nat.lt_succ_of_lt index11.isLt⟩ := Fin.ext rfl
    have index11Eq : index11 =
        ⟨index10.val, Nat.lt_succ_of_lt index10.isLt⟩ := Fin.ext rfl
    change resultEnvironment index12 = .signed .i32 (Int.ofNat index)
    calc
      resultEnvironment index12 = productionEnvironment index11 := by
        rw [index12Eq]
        exact Lanius.FunctionalView.Env.push_before productionEnvironment
          (appendOutcomeValue outcome) index11
      _ = beforeEnvironment index10 := by
        rw [index11Eq]
        exact Lanius.FunctionalView.Env.push_before beforeEnvironment
          (.signed .i32 (Int.ofNat production)) index10
      _ = .signed .i32 (Int.ofNat index) := by
        rfl
  have addition : Int.ofNat index + 1 = Int.ofNat (index + 1) := by simp
  have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target (index + 1)
    (invariant.index_succ_i32 indexBound)
  have updated : evalAssignValue verifiedParserCore.target .add
      (some (.signed .i32 (Int.ofNat index))) (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (index + 1))) := by
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
      beq_self_eq_true, if_true, evalSignedBinary]
    rw [addition, wrapped]
  have updateResult :
      (predictionStatefulMachine workspaceLayout words grammarCell).evalLocalUpdate
      .add (afterCount ⟨9, by omega⟩) (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (index + 1))) := by
    rw [currentIndex]
    simpa [predictionStatefulMachine,
      Lanius.FunctionalView.Core.Stateful.machineWith] using updated
  exact .letValue productionResult (.letValue appendResult
    (.sequenceNext (.ifFalse fullCondition .skip)
      (.sequenceNext (.setLocal countResult)
        (.sequenceNext (.updateLocal oneResult updateResult) .skip))))

/-- Canonical FunctionalView execution of a capacity-full prediction body.
    Return propagation prevents both the state-count assignment and the loop
    index increment from executing. -/
private theorem RecognizerPredictionLoopInvariant.functional_full_body
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (indexBound : index < count)
    (rowBound : first + index < grammar.lhsProductions.length)
    (statusFull :
      let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
      let seed := recognizerPredictionSeed production position
      (appendLogical workspaceLayout.capacity position seed workspace).1.status =
        .full) :
    let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
    let seed := recognizerPredictionSeed production position
    let outcome := (appendLogical workspaceLayout.capacity position seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace position seed
      workspaceValues
    let beforeWorld := predictionWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let afterWorld := predictionWorld words tokens nextValues grammarCell tokensCell workspaceCell
    let beforeEnvironment := predictionEnvironment words workspaceValues
      grammarCell workspaceCell workspaceLayout
      grammarLayout.lhsProductionsOffset position first count index
      workspace.states.length
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      beforeWorld beforeEnvironment predictionBodyCommand
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld beforeEnvironment := by
  dsimp only
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let seed := recognizerPredictionSeed production position
  let outcome := (appendLogical workspaceLayout.capacity position seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace position seed
    workspaceValues
  let beforeWorld := predictionWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let afterWorld := predictionWorld words tokens nextValues grammarCell tokensCell workspaceCell
  let beforeEnvironment := predictionEnvironment words workspaceValues
    grammarCell workspaceCell workspaceLayout
    grammarLayout.lhsProductionsOffset position first count index
    workspace.states.length
  let productionEnvironment := beforeEnvironment.push
    (.signed .i32 (Int.ofNat production))
  let resultEnvironment := productionEnvironment.push
    (appendOutcomeValue outcome)
  have productionResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      beforeWorld beforeEnvironment predictionProductionTerm =
      .ok (.signed .i32 (Int.ofNat production), beforeWorld) :=
    invariant.functional_read_production rowBound
  have appendResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      beforeWorld productionEnvironment predictionAppendTerm =
      .ok (appendOutcomeValue outcome, afterWorld) :=
    invariant.functional_append indexBound rowBound
  have statusFull' : outcome.status = .full := by
    simpa [outcome, seed, production] using statusFull
  have fullCondition : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment predictionFullCondition =
      .ok (.boolean true, afterWorld) := by
    have evaluated := predictionFullCondition_evaluates
      (workspaceLayout := workspaceLayout) (words := words)
      (grammarCell := grammarCell) afterWorld productionEnvironment outcome
    rw [statusFull'] at evaluated
    change Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell) afterWorld
      (productionEnvironment.push (appendOutcomeValue outcome))
      predictionFullCondition = .ok (.boolean true, afterWorld)
    simpa using evaluated
  have positionValue : productionEnvironment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat position) := by
    let position10 : Fin 10 := ⟨6, by decide⟩
    let position11 : Fin 11 := ⟨6, by decide⟩
    have position11Eq : position11 =
        ⟨position10.val, Nat.lt_succ_of_lt position10.isLt⟩ := Fin.ext rfl
    change productionEnvironment position11 = _
    unfold productionEnvironment
    rw [position11Eq]
    rw [Lanius.FunctionalView.Env.push_before]
    rfl
  have fullResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment predictionFullResult =
      .ok (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position), afterWorld) :=
    predictionFullResult_evaluates
      (workspaceLayout := workspaceLayout) (words := words)
      (grammarCell := grammarCell) afterWorld productionEnvironment outcome
      position positionValue
  have returned : Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment
      (.returnValue (some predictionFullResult))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment :=
    .returnSome fullResult
  have fullBranch : Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment
      (.sequence (.returnValue (some predictionFullResult)) .skip)
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment :=
    .sequenceStop returned (by intro impossible; cases impossible)
  have selected : Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment
      (.ifThenElse predictionFullCondition
        (.sequence (.returnValue (some predictionFullResult)) .skip) .skip)
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment :=
    .ifTrue fullCondition fullBranch
  have stopped : Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment
      (.sequence
        (.ifThenElse predictionFullCondition
          (.sequence (.returnValue (some predictionFullResult)) .skip) .skip)
        (.sequence
          (.setLocal ⟨5, by omega⟩
            (.apply (.field (.structure 2) 2 parserI32Type)
              [predictionSlot ⟨11, by omega⟩]))
          (.sequence
            (.updateLocal .add ⟨9, by omega⟩ (predictionLiteral 1)) .skip)))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment :=
    .sequenceStop selected (by intro impossible; cases impossible)
  have assembled : Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      beforeWorld beforeEnvironment predictionBodyCommand
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop resultEnvironment)) := by
    simpa only [predictionBodyCommand] using
      (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
        (type := parserI32Type) productionResult
        (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
          (type := .structure 2) appendResult stopped))
  have popped : Lanius.FunctionalView.Stateful.Env.pop
      (Lanius.FunctionalView.Stateful.Env.pop resultEnvironment) =
      beforeEnvironment := by
    simp [resultEnvironment, productionEnvironment]
  rw [popped] at assembled
  exact assembled

structure RecognizerPredictionLoopOkStepResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (beforeWorkspace afterWorkspace : LogicalWorkspace)
    (beforeValues afterValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (position first count index : Nat)
    (beforeInvariant : RecognizerPredictionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace beforeValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell before position first
      count index) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizePredictionLoopBody .next after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton stateCountCell)
        (CellSet.singleton indexCell))) before after
  invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
    tokens workspaceLayout afterWorkspace afterValues grammarCell tokensCell
    workspaceCell stateCountCell indexCell after position first count
    (index + 1)

/-- One successful iteration of the exact prediction loop. -/
noncomputable def RecognizerPredictionLoopInvariant.execute_ok_step
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (indexBound : index < count)
    (statusOk :
      let production := grammar.lhsProductions.get
        ⟨first + index, by
          have := invariant.rowRange
          omega⟩
      (appendLogical workspaceLayout.capacity position
        (recognizerPredictionSeed production position) workspace).1.status =
        .ok) :
    let production := grammar.lhsProductions.get
      ⟨first + index, by
        have := invariant.rowRange
        omega⟩
    let nextWorkspace := (appendLogical workspaceLayout.capacity position
      (recognizerPredictionSeed production position) workspace).2
    let nextValues := appendResultValues workspaceLayout workspace position
      (recognizerPredictionSeed production position) workspaceValues
    RecognizerPredictionLoopOkStepResult grammarLayout grammar words tokens
      workspaceLayout workspace nextWorkspace workspaceValues nextValues
      grammarCell tokensCell workspaceCell stateCountCell indexCell runtime
      position first count index invariant := by
  dsimp only
  let rowBound : first + index < grammar.lhsProductions.length := by
    have := invariant.rowRange
    omega
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let value : Value := .signed .i32 (Int.ofNat production)
  let bound := runtime.bindLocal 34 value
  let appendInvariant := invariant.bind_production indexBound
  have statusOk' : (appendLogical workspaceLayout.capacity position
      (recognizerPredictionSeed production position) workspace).1.status =
      .ok := by
    simpa [production, rowBound] using statusOk
  let appended := appendInvariant.execute_ok statusOk'
  let nextWorkspace := (appendLogical workspaceLayout.capacity position
    (recognizerPredictionSeed production position) workspace).2
  let nextValues := appendResultValues workspaceLayout workspace position
    (recognizerPredictionSeed production position) workspaceValues
  let after := restoreLocals runtime appended.after
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton indexCell))
  have bodyExecution : Executes verifiedParserCore runtime
      parserRecognizePredictionLoopBody .next after := by
    rw [extractedParserRecognize_prediction_loop_body_shape]
    simpa [bound, value, production, rowBound, appendInvariant, after] using
      executesLetLocal (type := parserI32Type)
        (invariant.read_production indexBound) appended.execution
  have entered : StoreEffect CellSet.empty runtime bound := by
    simpa [bound, value] using bindLocal_effect runtime 34 value
  have appendEffect : ModifiesOnly writes bound appended.after := by
    simpa [writes, bound, value, production, rowBound, appendInvariant] using
      appended.effect
  have scopedStore : StoreEffect writes runtime appended.after :=
    (entered.weaken CellSet.empty_subset).trans_same
      appendEffect.toStoreEffect
  have outerEffect : ModifiesOnly writes runtime after := by
    simpa [after] using scopedStore.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    scopedStore.restoreLocals_wellFormed
      invariant.frame.recognizer.wellFormed appended.invariant.wellFormed
  have grammarNotWritten : ¬ writes grammarCell := by
    simpa [writes, CellSet.union, CellSet.singleton, not_or] using
      ⟨invariant.frame.recognizer.grammarWorkspaceDistinct,
        invariant.frame.stateCountBackingDistinct.1.symm,
        invariant.indexBackingDistinct.1.symm⟩
  have tokensNotWritten : ¬ writes tokensCell := by
    simpa [writes, CellSet.union, CellSet.singleton, not_or] using
      ⟨invariant.frame.recognizer.tokensWorkspaceDistinct,
        invariant.frame.stateCountBackingDistinct.2.1.symm,
        invariant.indexBackingDistinct.2.1.symm⟩
  have parameterFrameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint runtime
        verifiedParserRecognizerParameterFrame) writes :=
    CellSet.Disjoint.mono_left
      (localBindingFrameFootprint_mono (fun id idBound =>
        (PredictionPreservedLocal_source_frame id).mp
          ((PredictionPreservedLocal_iff id).mpr ⟨Or.inl idBound, by
            have bound :=
              (mem_verifiedParserRecognizerParameterIds_iff id).mp idBound
            exact Nat.ne_of_lt (Nat.lt_of_le_of_lt bound (by decide))⟩)))
      invariant.persistentSeparate
  have newBacking : after.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values nextValues))
    } := by
    change appended.after.cellEntry? workspaceCell = _
    simpa [nextWorkspace, nextValues, production, rowBound, appendInvariant]
      using appended.invariant.workspaceBacking
  have nextRecognizer :=
    invariant.frame.recognizer.after_workspace_and_scalar_effect writes
      outerEffect afterWellFormed grammarNotWritten tokensNotWritten
      parameterFrameDisjoint nextWorkspace nextValues
      (appendResultValues_length workspaceLayout workspace position
        (recognizerPredictionSeed production position) workspaceValues)
      (by
        simpa [nextWorkspace, nextValues, production, rowBound,
          appendInvariant] using appended.invariant.workspaceEncoded)
      (by
        simpa [nextWorkspace, production, rowBound, appendInvariant] using
          appended.invariant.derivations)
      newBacking
  have nextWithinGrammar : WorkspaceWithinGrammar grammar nextWorkspace := by
    let appendedLogical := appendLogical_refines
      (appendLogical workspaceLayout.capacity position
        (recognizerPredictionSeed production position) workspace) rfl
    exact appendedLogical.preserves_withinGrammar
      invariant.workspaceWithinGrammar (by
        simpa [production, rowBound] using
          invariant.seed_within_grammar indexBound)
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint runtime
        verifiedParserPredictionLoopPreservedBindings) writes := by
    intro cell framed written
    obtain ⟨id, preserved, cellId⟩ := framed
    have ⟨persistent, notStateCount⟩ :=
      (PredictionPreservedLocal_iff id).mp
        ((PredictionPreservedLocal_source_frame id).mpr preserved)
    have separated := invariant.persistentLocalsSeparate id persistent
    change cell = workspaceCell ∨ cell = stateCountCell ∨
      cell = indexCell at written
    rcases written with equal | equal | equal
    · subst cell; exact separated.1 cellId
    · subst cell; exact separated.2.1 notStateCount cellId
    · subst cell; exact separated.2.2 cellId
  have preserveLocal (id : VarId) (persistent : PredictionPersistentLocal id)
      (notStateCount : id ≠ 18) (value : Value)
      (found : runtime.local? id = some value) :
      after.local? id = some value :=
    outerEffect.preserves_local_of_disjoint
      invariant.frame.recognizer.wellFormed frameDisjoint
      ((PredictionPreservedLocal_source_frame id).mp
        ((PredictionPreservedLocal_iff id).mpr
          ⟨persistent, notStateCount⟩)) found
  have afterCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))).holds
      after := by
    constructor
    · change runtime.cellId? 18 = some stateCountCell
      exact invariant.frame.stateCountOwned.1
    · change appended.after.cellEntry? stateCountCell = _
      simpa [nextWorkspace, production, rowBound, appendInvariant] using
        appended.stateCountOwned.2
  have afterIndexOwned : (Assertion.localPointsTo 33 indexCell
      (some (.signed .i32 (Int.ofNat (index + 1))))).holds after := by
    constructor
    · change runtime.cellId? 33 = some indexCell
      exact invariant.indexOwned.1
    · change appended.after.cellEntry? indexCell = _
      simpa [appendInvariant, production, rowBound] using appended.indexOwned.2
  have nextInvariant : RecognizerPredictionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout nextWorkspace nextValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell after position first
      count (index + 1) := {
    frame := {
      recognizer := nextRecognizer
      positionBound := invariant.frame.positionBound
      stateBaseLocal := preserveLocal 8 (by simp [PredictionPersistentLocal])
        (by decide) _
        invariant.frame.stateBaseLocal
      stateCapacityLocal := preserveLocal 9
        (by simp [PredictionPersistentLocal]) (by decide) _
        invariant.frame.stateCapacityLocal
      stateCountLocal := Assertion.localPointsTo_local 18 stateCountCell _ after
        afterCountOwned
      stateCountOwned := afterCountOwned
      stateCountBackingDistinct := invariant.frame.stateCountBackingDistinct
      stateCountParameterSeparate := by
        unfold RecognizerParameterFrameSeparated
        rw [outerEffect.localBindingFrameFootprint_eq
          verifiedParserRecognizerParameterFrame]
        exact invariant.frame.stateCountParameterSeparate
    }
    workspaceWithinGrammar := nextWithinGrammar
    positionLocal := preserveLocal 23 (by simp [PredictionPersistentLocal])
      (by decide) _
      invariant.positionLocal
    lhsProductionsOffsetLocal := preserveLocal 15
      (by simp [PredictionPersistentLocal]) (by decide) _
      invariant.lhsProductionsOffsetLocal
    firstLocal := preserveLocal 31 (by simp [PredictionPersistentLocal])
      (by decide) _
      invariant.firstLocal
    countLocal := preserveLocal 32 (by simp [PredictionPersistentLocal])
      (by decide) _
      invariant.countLocal
    indexOwned := afterIndexOwned
    indexLe := by omega
    rowRange := invariant.rowRange
    rowProductionBound := invariant.rowProductionBound
    persistentSeparate := by
      rw [outerEffect.localBindingFrameFootprint_eq
        verifiedParserPredictionLoopPreservedBindings]
      exact invariant.persistentSeparate
    indexBackingDistinct := invariant.indexBackingDistinct
  }
  exact {
    after := after
    execution := bodyExecution
    effect := by simpa [writes] using outerEffect
    invariant := by
      simpa [nextWorkspace, nextValues, production, rowBound] using
        nextInvariant
  }

structure RecognizerPredictionLoopFullStepResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (position first count index production : Nat)
    (beforeInvariant : RecognizerPredictionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell before position first
      count index) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizePredictionLoopBody
    (.returned (some (parseResultValue 2
      (Int.ofNat (appendLogical workspaceLayout.capacity position
        (recognizerPredictionSeed production position) workspace).1.stateCount)
      (-1) (Int.ofNat position)))) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell after

noncomputable def RecognizerPredictionLoopInvariant.execute_full_step
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index)
    (indexBound : index < count)
    (statusFull :
      let production := grammar.lhsProductions.get
        ⟨first + index, by
          have := invariant.rowRange
          omega⟩
      (appendLogical workspaceLayout.capacity position
        (recognizerPredictionSeed production position) workspace).1.status =
        .full) :
    let production := grammar.lhsProductions.get
      ⟨first + index, by
        have := invariant.rowRange
        omega⟩
    RecognizerPredictionLoopFullStepResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count index
      production invariant := by
  dsimp only
  let rowBound : first + index < grammar.lhsProductions.length := by
    have := invariant.rowRange
    omega
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let value : Value := .signed .i32 (Int.ofNat production)
  let bound := runtime.bindLocal 34 value
  let appendInvariant := invariant.bind_production indexBound
  have statusFull' : (appendLogical workspaceLayout.capacity position
      (recognizerPredictionSeed production position) workspace).1.status =
      .full := by
    simpa [production, rowBound] using statusFull
  let appended := appendInvariant.execute_full statusFull'
  let after := restoreLocals runtime appended.after
  have bodyExecution : Executes verifiedParserCore runtime
      parserRecognizePredictionLoopBody
      (.returned (some (parseResultValue 2
        (Int.ofNat (appendLogical workspaceLayout.capacity position
          (recognizerPredictionSeed production position) workspace).1.stateCount)
        (-1) (Int.ofNat position)))) after := by
    rw [extractedParserRecognize_prediction_loop_body_shape]
    simpa [bound, value, production, rowBound, appendInvariant, after] using
      executesLetLocal (type := parserI32Type)
        (invariant.read_production indexBound) appended.execution
  have entered : StoreEffect CellSet.empty runtime bound := by
    simpa [bound, value] using bindLocal_effect runtime 34 value
  have appendEffect : ModifiesOnly (CellSet.singleton workspaceCell) bound
      appended.after := by
    simpa [bound, value, production, rowBound, appendInvariant] using
      appended.effect
  have scopedStore : StoreEffect (CellSet.singleton workspaceCell) runtime
      appended.after :=
    (entered.weaken CellSet.empty_subset).trans_same
      appendEffect.toStoreEffect
  have outerEffect : ModifiesOnly (CellSet.singleton workspaceCell) runtime
      after := by
    simpa [after] using scopedStore.restoreLocals
  have afterWellFormed := scopedStore.restoreLocals_wellFormed
    invariant.frame.recognizer.wellFormed appended.wellFormed
  have afterInvariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell after := by
    apply invariant.frame.recognizer.after_same_workspace_effect outerEffect
      afterWellFormed appended.invariant
    simp [after, restoreLocals]
  exact {
    after := after
    execution := bodyExecution
    effect := outerEffect
    wellFormed := afterWellFormed
    invariant := afterInvariant
  }

abbrev RecognizerPredictionLoopOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (position first count : Nat) : State → Completion → Prop :=
  WorkspaceLoopOutcome workspaceLayout.capacity beforeWorkspace
    (parserCapacityCompletion position)
    (fun workspace workspaceValues after =>
      RecognizerPredictionLoopInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell indexCell after position first count count)
    (fun workspace workspaceValues after =>
      RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
        workspace workspaceValues grammarCell tokensCell workspaceCell after)

/-- Prediction outcome carried across the FunctionalView loop boundary.

    This combines the physical workspace result with the FunctionalView
    runtime relation.  Keeping them in one inductive value is important:
    indexing a separate relation by a proof of `RecognizerPredictionLoopOutcome`
    would not synchronize their hidden workspace witnesses, because Lean treats
    proofs as irrelevant.

    On normal completion, both executions name the same compact workspace and
    final interval cursor.  Capacity returns do not continue into nullable
    replay, so they require no continuation relation. -/
inductive RecognizerPredictionSynchronizedOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell : CellId)
    (stateCountCell indexCell : CellId)
    (lhsProductionsOffset position first count : Nat)
    (after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (predictionTermMachine workspaceLayout words grammarCell) 10) :
    State → Completion → Prop where
  | completed (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell indexCell physicalAfter position first
        count count)
      (worldEq : after.world = predictionWorld words tokens workspaceValues
        grammarCell tokensCell workspaceCell)
      (environmentEq : after.environment = predictionEnvironment words
        workspaceValues grammarCell workspaceCell workspaceLayout
        lhsProductionsOffset position first count count workspace.states.length) :
      RecognizerPredictionSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell indexCell lhsProductionsOffset position first count after
        physicalAfter .next
  | full (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (terminal : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter) :
      RecognizerPredictionSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell indexCell lhsProductionsOffset position first count after
        physicalAfter (parserCapacityCompletion position stateCount)

theorem RecognizerPredictionSynchronizedOutcome.physical
    (outcome : RecognizerPredictionSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell indexCell lhsProductionsOffset position first
      count after physicalAfter completion) :
    RecognizerPredictionLoopOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell indexCell position first count physicalAfter completion := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter growth invariant _ _ =>
      exact .completed workspace workspaceValues physicalAfter growth invariant
  | full workspace workspaceValues physicalAfter growth terminal stateCount
      wellFormed =>
      exact .full workspace workspaceValues physicalAfter growth terminal
        stateCount wellFormed

/-- Eliminate a synchronized prediction outcome without depending on the
    proof object itself.  The resulting data view is safe under proof
    irrelevance and is the interface used by enclosing FunctionalView code. -/
theorem RecognizerPredictionSynchronizedOutcome.view
    (outcome : RecognizerPredictionSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell indexCell lhsProductionsOffset position first
      count after physicalAfter completion) :
    (completion = .next ∧
      ∃ workspace : LogicalWorkspace,
      ∃ workspaceValues : List Int,
      ∃ growth : WorkspaceAppendClosure workspaceLayout.capacity
          beforeWorkspace workspace,
      ∃ invariant : RecognizerPredictionLoopInvariant grammarLayout grammar
          words tokens workspaceLayout workspace workspaceValues grammarCell
          tokensCell workspaceCell stateCountCell indexCell physicalAfter
          position first count count,
        after.world = predictionWorld words tokens workspaceValues grammarCell
          tokensCell workspaceCell ∧
        after.environment = predictionEnvironment words workspaceValues
          grammarCell workspaceCell workspaceLayout lhsProductionsOffset
          position first count count workspace.states.length) ∨
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
  | completed workspace workspaceValues physicalAfter growth invariant worldEq
      environmentEq =>
      exact .inl ⟨rfl, workspace, workspaceValues, growth, invariant, worldEq,
        environmentEq⟩
  | full workspace workspaceValues physicalAfter growth terminal stateCount
      wellFormed =>
      exact .inr ⟨workspace, workspaceValues, growth, terminal, stateCount,
        wellFormed, rfl⟩

theorem RecognizerPredictionSynchronizedOutcome.prepend_growth
    {grammarLayout : PackedGrammarLayout} {grammar : IndexedGrammar}
    {words : List Int} {tokens : List Nat}
    {workspaceLayout : WorkspaceLayout}
    {grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId}
    {lhsProductionsOffset position first count : Nat}
    {beforeWorkspace middleWorkspace : LogicalWorkspace}
    {after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (predictionTermMachine workspaceLayout words grammarCell) 10}
    {physicalAfter : State}
    {completion : Completion}
    (outcome : RecognizerPredictionSynchronizedOutcome grammarLayout grammar
      words tokens workspaceLayout middleWorkspace grammarCell tokensCell
      workspaceCell stateCountCell indexCell lhsProductionsOffset position first
      count after physicalAfter completion)
    (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
      middleWorkspace) :
    RecognizerPredictionSynchronizedOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell indexCell lhsProductionsOffset position first count after
      physicalAfter completion := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter nextGrowth invariant
      worldEq environmentEq =>
      exact .completed workspace workspaceValues physicalAfter
        (growth.trans nextGrowth) invariant worldEq environmentEq
  | full workspace workspaceValues physicalAfter nextGrowth terminal stateCount
      wellFormed =>
      exact .full workspace workspaceValues
        physicalAfter (growth.trans nextGrowth) terminal stateCount wellFormed

structure RecognizerPredictionLoopExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (position first count index : Nat)
    (beforeInvariant : RecognizerPredictionLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell before position first
      count index) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before parserRecognizePredictionLoop
    completion after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton stateCountCell)
        (CellSet.singleton indexCell))) before after
  outcome : RecognizerPredictionLoopOutcome grammarLayout grammar words tokens
    workspaceLayout workspace grammarCell tokensCell workspaceCell stateCountCell
    indexCell position first count after completion

def recognizerPredictionWrites
    (workspaceCell stateCountCell indexCell : CellId) : CellSet :=
  CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton indexCell))

/-- Algorithmic state for prediction replay. Runtime state and the logical
    workspace move together, preventing a semantic trace from being paired
    with stale workspace evidence. -/
structure RecognizerPredictionConfig
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (position first count : Nat) where
  workspace : LogicalWorkspace
  workspaceValues : List Int
  runtime : State
  index : Nat
  invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell indexCell runtime position first count index

def RecognizerPredictionConfig.measure
    (config : RecognizerPredictionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell position first count) : Nat :=
  count - config.index

/-- Pure FunctionalView state corresponding to one prediction configuration.
    The physical Core runtime remains proof evidence in the configuration; it
    is not used to define the algorithm being executed. -/
def RecognizerPredictionConfig.functionalRuntime
    (config : RecognizerPredictionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell position first count) :
    Lanius.FunctionalView.Stateful.Loop.Runtime
      (predictionTermMachine workspaceLayout words grammarCell) 10 :=
  (predictionWorld words tokens config.workspaceValues grammarCell tokensCell workspaceCell,
    predictionEnvironment words config.workspaceValues grammarCell
      workspaceCell workspaceLayout grammarLayout.lhsProductionsOffset position
      first count config.index config.workspace.states.length)

theorem RecognizerPredictionConfig.functional_condition
    (config : RecognizerPredictionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell position first count) :
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      config.functionalRuntime.world config.functionalRuntime.environment
      predictionLoopCondition =
      .ok (.boolean (decide (config.index < count)),
        config.functionalRuntime.world) := by
  simp [RecognizerPredictionConfig.functionalRuntime,
    Lanius.FunctionalView.Stateful.Loop.Runtime.world,
    Lanius.FunctionalView.Stateful.Loop.Runtime.environment,
    predictionEnvironment, predictionLoopCondition, predictionBinary,
    predictionSlot,
    predictionTermMachine, Lanius.FunctionalView.Term.evaluate,
    Lanius.FunctionalView.Ref.evaluate,
    Lanius.FunctionalView.evaluateTerms,
    Lanius.FunctionalView.Core.Effectful.machine,
    Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
    evalBinaryValue, evalSignedBinary, bind, Except.bind, Int.ofNat_lt]

/-- The environment produced by the successful body is exactly the next
    prediction configuration, rather than merely an extensionally similar
    collection of locals. -/
private theorem predictionOkEnvironment_eq_next
    (beforeValues nextValues : List Int) (beforeWorkspace nextWorkspace :
      LogicalWorkspace) (outcome : AppendOutcome) (index : Nat)
    (valuesLengthEq : beforeValues.length = nextValues.length)
    (stateCountEq : outcome.stateCount = nextWorkspace.states.length) :
    let beforeEnvironment := predictionEnvironment words beforeValues
      grammarCell workspaceCell workspaceLayout lhsProductionsOffset position
      first count index beforeWorkspace.states.length
    let productionEnvironment := beforeEnvironment.push
      (.signed .i32 (Int.ofNat production))
    predictionOkEnvironment productionEnvironment outcome index =
      predictionEnvironment words nextValues grammarCell workspaceCell
        workspaceLayout lhsProductionsOffset position first count (index + 1)
        nextWorkspace.states.length := by
  dsimp only
  funext slot
  have cases : slot.val = 0 ∨ slot.val = 1 ∨ slot.val = 2 ∨
      slot.val = 3 ∨ slot.val = 4 ∨ slot.val = 5 ∨ slot.val = 6 ∨
      slot.val = 7 ∨ slot.val = 8 ∨ slot.val = 9 := by
    omega
  rcases cases with zero | one | two | three | four | five | six | seven |
      eight | nine
  · have same : slot = ⟨0, by omega⟩ := Fin.ext zero
    rw [same]
    simp [predictionOkEnvironment, predictionEnvironment,
      Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push]
  · have same : slot = ⟨1, by omega⟩ := Fin.ext one
    rw [same]
    simp [predictionOkEnvironment, predictionEnvironment, workspaceValue,
      Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push, valuesLengthEq]
  · have same : slot = ⟨2, by omega⟩ := Fin.ext two
    rw [same]
    simp [predictionOkEnvironment, predictionEnvironment,
      Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push]
  · have same : slot = ⟨3, by omega⟩ := Fin.ext three
    rw [same]
    simp [predictionOkEnvironment, predictionEnvironment,
      Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push]
  · have same : slot = ⟨4, by omega⟩ := Fin.ext four
    rw [same]
    simp [predictionOkEnvironment, predictionEnvironment,
      Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push]
  · have same : slot = ⟨5, by omega⟩ := Fin.ext five
    rw [same]
    simp [predictionOkEnvironment, predictionEnvironment,
      Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push, stateCountEq]
  · have same : slot = ⟨6, by omega⟩ := Fin.ext six
    rw [same]
    simp [predictionOkEnvironment, predictionEnvironment,
      Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push]
  · have same : slot = ⟨7, by omega⟩ := Fin.ext seven
    rw [same]
    simp [predictionOkEnvironment, predictionEnvironment,
      Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push]
  · have same : slot = ⟨8, by omega⟩ := Fin.ext eight
    rw [same]
    simp [predictionOkEnvironment, predictionEnvironment,
      Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push]
  · have same : slot = ⟨9, by omega⟩ := Fin.ext nine
    rw [same]
    simp [predictionOkEnvironment, predictionEnvironment,
      Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push]

/-- Result transported by the FunctionalView prediction loop.  The abstract
    trace determines control flow and logical workspace evolution; these
    fields retain the corresponding structural-Core execution required by
    the enclosing recognizer proof. -/
structure RecognizerPredictionFunctionalResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (position first count : Nat)
    (config : RecognizerPredictionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell position first count)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (_after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (predictionTermMachine workspaceLayout words grammarCell) 10) where
  physicalAfter : State
  execution : Executes verifiedParserCore config.runtime
    parserRecognizePredictionLoop
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
    physicalAfter
  effect : ModifiesOnly
    (recognizerPredictionWrites workspaceCell stateCountCell indexCell)
    config.runtime physicalAfter
  outcome : RecognizerPredictionSynchronizedOutcome grammarLayout grammar words
    tokens workspaceLayout config.workspace grammarCell tokensCell workspaceCell
    stateCountCell indexCell grammarLayout.lhsProductionsOffset position first
    count _after physicalAfter
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)

/-- One prediction decision whose semantic edge is the extracted
    FunctionalView command.  Core execution is carried only as refinement
    evidence for the enclosing source proof. -/
noncomputable def RecognizerPredictionConfig.functional_decide
    (config : RecognizerPredictionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell position first count) :
    Lanius.FunctionalView.Stateful.Loop.Decision
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      predictionLoopCondition predictionBodyCommand
      (RecognizerPredictionConfig grammarLayout grammar words tokens
        workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
        indexCell position first count)
      RecognizerPredictionConfig.functionalRuntime
      RecognizerPredictionConfig.measure
      (RecognizerPredictionFunctionalResult grammarLayout grammar words tokens
        workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
        indexCell position first count) config := by
  by_cases done : config.index = count
  · apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
    have functionalCondition := config.functional_condition
    have functionalFalse : Lanius.FunctionalView.Term.evaluate
        (predictionTermMachine workspaceLayout words grammarCell)
        config.functionalRuntime.world config.functionalRuntime.environment
        predictionLoopCondition =
        .ok (.boolean false, config.functionalRuntime.world) := by
      simpa [done] using functionalCondition
    exact {
      completion := .next
      after := config.functionalRuntime
      edge := .conditionFalse functionalFalse
      result := {
        physicalAfter := config.runtime
        execution := config.invariant.condition_false (by omega) |>
          executesWhileFalse
        effect := ModifiesOnly.reflAny
          (recognizerPredictionWrites workspaceCell stateCountCell indexCell)
          config.runtime
        outcome := by
          apply RecognizerPredictionSynchronizedOutcome.completed config.workspace
            config.workspaceValues config.runtime (.refl config.workspace)
            (by simpa [done] using config.invariant)
          · rfl
          · change predictionEnvironment words config.workspaceValues
              grammarCell workspaceCell workspaceLayout
              grammarLayout.lhsProductionsOffset position first count
              config.index config.workspace.states.length = _
            rw [done]
      }
    }
  · have indexBound : config.index < count := by
      have := config.invariant.indexLe
      omega
    let rowBound : first + config.index < grammar.lhsProductions.length := by
      have := config.invariant.rowRange
      omega
    let production := grammar.lhsProductions.get
      ⟨first + config.index, rowBound⟩
    let seed := recognizerPredictionSeed production position
    let logical := appendLogical workspaceLayout.capacity position seed
      config.workspace
    let nextValues := appendResultValues workspaceLayout config.workspace
      position seed config.workspaceValues
    have functionalTrue : Lanius.FunctionalView.Term.evaluate
        (predictionTermMachine workspaceLayout words grammarCell)
        config.functionalRuntime.world config.functionalRuntime.environment
        predictionLoopCondition =
        .ok (.boolean true, config.functionalRuntime.world) := by
      simpa [indexBound] using config.functional_condition
    cases statusEq : logical.1.status with
    | ok =>
        have statusOk : (appendLogical workspaceLayout.capacity position seed
            config.workspace).1.status = .ok := by
          simpa [logical]
        let step := config.invariant.execute_ok_step indexBound (by
          simpa [seed, production, rowBound] using statusOk)
        let next : RecognizerPredictionConfig grammarLayout grammar words tokens
            workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
            indexCell position first count := {
          workspace := logical.2
          workspaceValues := nextValues
          runtime := step.after
          index := config.index + 1
          invariant := by
            simpa [logical, nextValues, seed, production, rowBound] using
              step.invariant
        }
        have bodyResult := config.invariant.functional_ok_body indexBound
          rowBound (by simpa [seed, production, rowBound] using statusOk)
        have environmentEq := predictionOkEnvironment_eq_next
          (words := words) (grammarCell := grammarCell)
          (workspaceCell := workspaceCell) (workspaceLayout := workspaceLayout)
          (lhsProductionsOffset := grammarLayout.lhsProductionsOffset)
          (position := position) (first := first) (count := count)
          (production := production) config.workspaceValues nextValues
          config.workspace logical.2 logical.1 config.index
          (by simpa [nextValues, seed] using
            (appendResultValues_length workspaceLayout config.workspace
              position seed config.workspaceValues).symm)
          (by simpa [logical] using
            (appendLogical_stateCount_eq workspaceLayout.capacity position seed
              config.workspace))
        have functionalBody :
            Lanius.FunctionalView.Stateful.Command.Evaluates
              (predictionTermMachine workspaceLayout words grammarCell)
              (predictionStatefulMachine workspaceLayout words grammarCell)
              config.functionalRuntime.world
              config.functionalRuntime.environment predictionBodyCommand .next
              next.functionalRuntime.world next.functionalRuntime.environment := by
          dsimp only at bodyResult environmentEq
          rw [environmentEq] at bodyResult
          simpa [RecognizerPredictionConfig.functionalRuntime,
            Lanius.FunctionalView.Stateful.Loop.Runtime.world,
            Lanius.FunctionalView.Stateful.Loop.Runtime.environment,
            next, logical, nextValues, seed, production, rowBound] using
              bodyResult
        apply Lanius.FunctionalView.Stateful.Loop.Decision.next next
        · exact .next functionalTrue functionalBody
        · dsimp [RecognizerPredictionConfig.measure, next]
          change count - (config.index + 1) < count - config.index
          omega
        · intro completion after result
          exact {
            physicalAfter := result.physicalAfter
            execution := executesWhileTrueThen
              (config.invariant.condition_true indexBound) step.execution
              result.execution
            effect := by
              simpa [recognizerPredictionWrites] using
                step.effect.trans_same result.effect
            outcome := result.outcome.prepend_growth
              (WorkspaceAppendClosure.single workspaceLayout.capacity position
                seed config.workspace)
          }
    | full =>
        have statusFull : (appendLogical workspaceLayout.capacity position seed
            config.workspace).1.status = .full := by
          simpa [logical]
        let step := config.invariant.execute_full_step indexBound (by
          simpa [seed, production, rowBound] using statusFull)
        let stateCount := logical.2.states.length
        have bodyResult := config.invariant.functional_full_body indexBound
          rowBound (by simpa [seed, production, rowBound] using statusFull)
        have functionalBody :
            Lanius.FunctionalView.Stateful.Command.Evaluates
              (predictionTermMachine workspaceLayout words grammarCell)
              (predictionStatefulMachine workspaceLayout words grammarCell)
              config.functionalRuntime.world
              config.functionalRuntime.environment predictionBodyCommand
              (.returned (some (parseResultValue 2
                (Int.ofNat stateCount) (-1) (Int.ofNat position))))
              config.functionalRuntime.world
              config.functionalRuntime.environment := by
          have valuesEq := appendResultValues_eq_of_full
            (layout := workspaceLayout) (workspace := config.workspace)
            (position := position) (seed := seed)
            (values := config.workspaceValues) statusFull
          dsimp only at bodyResult
          rw [valuesEq] at bodyResult
          simpa [RecognizerPredictionConfig.functionalRuntime, logical,
            Lanius.FunctionalView.Stateful.Loop.Runtime.world,
            Lanius.FunctionalView.Stateful.Loop.Runtime.environment,
            nextValues, valuesEq, stateCount, seed, production, rowBound]
            using bodyResult
        apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
        exact {
          completion := .returned (some (parseResultValue 2
            (Int.ofNat stateCount) (-1) (Int.ofNat position)))
          after := config.functionalRuntime
          edge := .returned functionalTrue functionalBody
          result := {
            physicalAfter := step.after
            execution := by
              rw [extractedParserRecognize_prediction_loop_shape,
                ← extractedParserRecognize_prediction_loop_body_shape]
              simpa [Lanius.FunctionalView.Core.Stateful.toCoreCompletion,
                stateCount, logical, seed, production, rowBound] using
                (executesWhileReturned
                  (config.invariant.condition_true indexBound) step.execution)
            effect := step.effect.weaken (by
              intro cell member
              exact Or.inl member)
            outcome := .full config.workspace config.workspaceValues step.after
              (.refl config.workspace) step.invariant stateCount step.wellFormed
          }
        }

/-- The total compact FunctionalView execution retained separately from its
    structural-Core refinement.  Enclosing recognizer phases reuse this trace
    through an environment embedding. -/
noncomputable def RecognizerPredictionConfig.functional_run
    (config : RecognizerPredictionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell position first count) :=
  Lanius.FunctionalView.Stateful.Loop.run
    (predictionTermMachine workspaceLayout words grammarCell)
    (predictionStatefulMachine workspaceLayout words grammarCell)
    predictionLoopCondition predictionBodyCommand
    (RecognizerPredictionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell position first count)
    RecognizerPredictionConfig.functionalRuntime
    RecognizerPredictionConfig.measure
    (RecognizerPredictionFunctionalResult grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell position first count)
    RecognizerPredictionConfig.functional_decide config

theorem RecognizerPredictionConfig.functional_run_evaluates
    (config : RecognizerPredictionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell position first count) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      config.functionalRuntime.world config.functionalRuntime.environment
      predictionLoopCommand config.functional_run.completion
      config.functional_run.after.world
      config.functional_run.after.environment :=
  config.functional_run.trace.evaluates

/-- Total execution of the exact extracted prediction-row loop. -/
noncomputable def RecognizerPredictionLoopInvariant.execute_loop
    (invariant : RecognizerPredictionLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count
      index) :
    RecognizerPredictionLoopExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position first count index
      invariant := by
  let initial : RecognizerPredictionConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell position first count := {
    workspace := workspace
    workspaceValues := workspaceValues
    runtime := runtime
    index := index
    invariant := invariant
  }
  let assembled := initial.functional_run
  exact {
    after := assembled.result.physicalAfter
    completion :=
      Lanius.FunctionalView.Core.Stateful.toCoreCompletion assembled.completion
    execution := assembled.result.execution
    effect := assembled.result.effect
    outcome := assembled.result.outcome.physical
  }


end Lanius.Extraction.ParserRecognize
