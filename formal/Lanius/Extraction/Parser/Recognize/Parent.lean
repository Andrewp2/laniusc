import Lanius.Extraction.Parser.Recognize.Common
import Lanius.Extraction.Parser.Recognize.ChartCursor

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
/-! ## Parent-completion chart traversal -/

def parserRecognizeParentLoop : Stmt :=
  (recognizerWhileLoops extractedParserRecognizeBody)[6]?.getD .skip

def parserRecognizeParentLoopBody : Stmt :=
  match parserRecognizeParentLoop with
  | .whileLoop _ body => body
  | _ => .skip

def parserRecognizeParentPredicate : Expr :=
  match parserRecognizeParentLoopBody with
  | .letLocal 31 _ _ (.letLocal 32 _ _ (.letLocal 33 _ _
      (.sequence (.ifThenElse condition _ _) _))) => condition
  | _ => .value (.boolean false)

def parserRecognizeParentAfterBindings : Stmt :=
  match parserRecognizeParentLoopBody with
  | .letLocal 31 _ _ (.letLocal 32 _ _ (.letLocal 33 _ _ body)) => body
  | _ => .skip

def parserRecognizeParentMatchedBody : Stmt :=
  match parserRecognizeParentAfterBindings with
  | .sequence (.ifThenElse _ matched _) _ => matched
  | _ => .skip

def verifiedParserParentLoopAccessFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedAccessFrameForCore
    parserRecognizeParentLoop (by native_decide)

def verifiedParserParentLoopLiveFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedLiveFrameBeforeCore
    parserRecognizeParentLoop (by native_decide)

theorem verifiedParser_parent_loop_access_frame :
    verifiedParserParentLoopAccessFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("parent", 30, .readWrite),
      ("workspace", 4, .read),
      ("state_base", 8, .read),
      ("grammar", 0, .read),
      ("kind_count", 11, .read),
      ("completed_lhs", 29, .read),
      ("state_capacity", 9, .read),
      ("position", 23, .read),
      ("state_id", 24, .read),
      ("state_count", 18, .readWrite)] := by
  native_decide

theorem verifiedParser_parent_loop_live_frame :
    verifiedParserParentLoopLiveFrame = verifiedParserParentLoopAccessFrame := by
  native_decide

/-- Parent-loop accesses shared with the enclosing recognizer state.  The
    `parent` cursor is omitted because `chartCursor` owns its cell. -/
def verifiedParserParentLoopSharedFrame :
    LocalAccessFrame :=
  verifiedParserParentLoopAccessFrame.excludingName "parent"

def verifiedParserParentLoopSharedFrameIds : List VarId :=
  verifiedParserParentLoopSharedFrame.ids

theorem verifiedParser_parent_loop_shared_frame_ids :
    verifiedParserParentLoopSharedFrameIds =
      [4, 8, 0, 11, 29, 9, 23, 24, 18] := by
  native_decide

@[simp] theorem mem_verifiedParserParentLoopSharedFrameIds_iff
    (id : Nat) :
    id ∈ verifiedParserParentLoopSharedFrameIds ↔
      id = 4 ∨ id = 8 ∨ id = 0 ∨ id = 11 ∨ id = 29 ∨ id = 9 ∨
        id = 23 ∨ id = 24 ∨ id = 18 := by
  rw [verifiedParser_parent_loop_shared_frame_ids]
  simp only [List.mem_cons, List.not_mem_nil, or_false]

/-- Source-derived parent-loop frame that excludes both cells mutated by a
    successful completion append. -/
def verifiedParserParentLoopPreservedFrame :
    LocalAccessFrame :=
  verifiedParserParentLoopSharedFrame.excludingName "state_count"

def verifiedParserParentLoopPreservedFrameIds : List VarId :=
  verifiedParserParentLoopPreservedFrame.ids

theorem verifiedParser_parent_loop_preserved_frame_ids :
    verifiedParserParentLoopPreservedFrameIds =
      [4, 8, 0, 11, 29, 9, 23, 24] := by
  native_decide

@[simp] theorem mem_verifiedParserParentLoopPreservedFrameIds_iff
    (id : Nat) :
    id ∈ verifiedParserParentLoopPreservedFrameIds ↔
      id = 4 ∨ id = 8 ∨ id = 0 ∨ id = 11 ∨ id = 29 ∨ id = 9 ∨
        id = 23 ∨ id = 24 := by
  rw [verifiedParser_parent_loop_preserved_frame_ids]
  simp only [List.mem_cons, List.not_mem_nil, or_false]

def verifiedParserParentPersistentBindings : LocalBindingFrame :=
  LocalBindingFrame.union verifiedParserRecognizerParameterFrame
    verifiedParserParentLoopSharedFrame.bindings

def verifiedParserParentPreservedBindings : LocalBindingFrame :=
  LocalBindingFrame.union verifiedParserRecognizerParameterFrame
    verifiedParserParentLoopPreservedFrame.bindings

def ParentPersistentLocal (id : VarId) : Prop :=
  id ∈ verifiedParserRecognizerParameterIds ∨
    id ∈ verifiedParserParentLoopSharedFrameIds

def ParentPreservedLocal (id : VarId) : Prop :=
  id ∈ verifiedParserRecognizerParameterIds ∨
    id ∈ verifiedParserParentLoopPreservedFrameIds

theorem verifiedParserParentPersistentBindings_core_ids :
    verifiedParserParentPersistentBindings.coreIds =
      verifiedParserRecognizerParameterIds ++
        verifiedParserParentLoopSharedFrameIds := by
  native_decide

theorem verifiedParserParentPreservedBindings_core_ids :
    verifiedParserParentPreservedBindings.coreIds =
      verifiedParserRecognizerParameterIds ++
        verifiedParserParentLoopPreservedFrameIds := by
  native_decide

/-- The compatibility predicate used by the evaluator proofs is exactly the
    projection of the checked declaration frame, not an independent range. -/
theorem ParentPersistentLocal_source_frame (id : VarId) :
    ParentPersistentLocal id ↔
      verifiedParserParentPersistentBindings.ContainsCoreId id := by
  rw [LocalBindingFrame.ContainsCoreId,
    verifiedParserParentPersistentBindings_core_ids]
  simp [ParentPersistentLocal]

theorem ParentPreservedLocal_source_frame (id : VarId) :
    ParentPreservedLocal id ↔
      verifiedParserParentPreservedBindings.ContainsCoreId id := by
  rw [LocalBindingFrame.ContainsCoreId,
    verifiedParserParentPreservedBindings_core_ids]
  simp [ParentPreservedLocal]

theorem parentPreservedLocalFootprint_eq (runtime : State) :
    localCellFootprint runtime ParentPreservedLocal =
      localBindingFrameFootprint runtime
        verifiedParserParentPreservedBindings := by
  unfold localBindingFrameFootprint
  congr 1
  funext id
  exact propext (ParentPreservedLocal_source_frame id)

theorem ParentPreservedLocal_iff (id : VarId) :
    ParentPreservedLocal id ↔ ParentPersistentLocal id ∧ id ≠ 18 := by
  unfold ParentPreservedLocal ParentPersistentLocal
  constructor
  · intro preserved
    rcases preserved with parameter | frame
    · refine ⟨Or.inl parameter, ?_⟩
      have bound :=
        (mem_verifiedParserRecognizerParameterIds_iff id).mp parameter
      exact Nat.ne_of_lt (Nat.lt_of_le_of_lt bound (by decide))
    · refine ⟨Or.inr ?_, ?_⟩
      · rw [mem_verifiedParserParentLoopPreservedFrameIds_iff] at frame
        rw [mem_verifiedParserParentLoopSharedFrameIds_iff]
        rcases frame with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
          simp
      · rw [mem_verifiedParserParentLoopPreservedFrameIds_iff] at frame
        rcases frame with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
          decide
  · rintro ⟨persistent, notCount⟩
    rcases persistent with parameter | frame
    · exact Or.inl parameter
    · right
      rw [mem_verifiedParserParentLoopSharedFrameIds_iff] at frame
      rw [mem_verifiedParserParentLoopPreservedFrameIds_iff]
      rcases frame with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
          rfl <;> simp_all

def parentFrameMutableCells
    (workspaceCell stateCountCell cursorCell : CellId) : CellSet :=
  CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton cursorCell))

/-- The source-derived parent frame is physically separate from every cell
    the parent loop may mutate. -/
def ParentFrameSeparated (runtime : State)
    (workspaceCell stateCountCell cursorCell : CellId) : Prop :=
  CellSet.Disjoint
    (localBindingFrameFootprint runtime verifiedParserParentPreservedBindings)
    (parentFrameMutableCells workspaceCell stateCountCell cursorCell)

theorem ParentPersistentLocal.le29
    (id : Nat) (persistent : ParentPersistentLocal id) : id ≤ 29 := by
  unfold ParentPersistentLocal at persistent
  rcases persistent with parameter | shared
  · exact Nat.le_trans
      ((mem_verifiedParserRecognizerParameterIds_iff id).mp parameter)
      (by decide)
  · rw [mem_verifiedParserParentLoopSharedFrameIds_iff] at shared
    rcases shared with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
        rfl <;> decide

theorem extractedParserRecognize_parent_loop_shape :
    parserRecognizeParentLoop =
      .whileLoop
        (.binary .greaterEqual (.local 30)
          (.value (.signed .i32 0)))
        parserRecognizeParentLoopBody := by
  rfl

theorem extractedParserRecognize_parent_predicate_shape :
    parserRecognizeParentPredicate =
      .binary .logicalAnd
        (.binary .less (.local 32) (.local 33))
        (.binary .equal
          (.call extractedParserRhsSymbolFunction.id
            [.local 0, .local 31, .local 32])
          (.binary .add (.local 11) (.local 29))) := by
  rfl

theorem extractedParserRecognize_parent_after_bindings_shape :
    parserRecognizeParentAfterBindings =
      .sequence
        (.ifThenElse parserRecognizeParentPredicate
          parserRecognizeParentMatchedBody .skip)
        (parserRecognizeCursorAdvanceStatement 30) := by
  rfl

theorem extractedParserRecognize_parent_matched_body_shape :
    parserRecognizeParentMatchedBody =
      .letLocal 34 parserI32Type (parserRecognizeStateValueCall 30 30)
        parserRecognizeParentAppendStatement := by
  rfl

theorem extractedParserRecognize_parent_body_shape :
    parserRecognizeParentLoopBody =
      .letLocal 31 parserI32Type (parserRecognizeStateValueCall 30 28)
        (.letLocal 32 parserI32Type (parserRecognizeStateValueCall 30 29)
          (.letLocal 33 parserI32Type
            (.call extractedParserRhsLengthFunction.id [.local 0, .local 31])
            parserRecognizeParentAfterBindings)) := by
  rfl

/-! ## Artifact-derived FunctionalView for parent completion -/

def parentLoopLayout : Layout 10 := fun index =>
  [0, 4, 8, 9, 18, 11, 23, 24, 29, 30].get index

private def parentLoopContext : Context :=
  let c0 := Context.empty.bind 0 (.slice parserI32Type)
  let c1 := c0.bind 4 (.slice parserI32Type)
  let c2 := c1.bind 8 parserI32Type
  let c3 := c2.bind 9 parserI32Type
  let c4 := c3.bind 18 parserI32Type
  let c5 := c4.bind 11 parserI32Type
  let c6 := c5.bind 23 parserI32Type
  let c7 := c6.bind 24 parserI32Type
  let c8 := c7.bind 29 parserI32Type
  c8.bind 30 parserI32Type

private def parentLoopReification? :=
  reifyCommand? verifiedParserCore (.structure 0) parentLoopContext true
    parentLoopLayout 31 parserRecognizeParentLoop

private theorem parentLoopReification_exists :
    parentLoopReification?.isSome := by
  native_decide

/-- Complete mutable FunctionalView command recovered from the checked parent
    completion loop. -/
def parserRecognizeParentLoopView :=
  parentLoopReification?.get parentLoopReification_exists

theorem parserRecognizeParentLoopView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      parentLoopLayout 31 parserRecognizeParentLoopView.command =
      parserRecognizeParentLoop :=
  parserRecognizeParentLoopView.toCoreExactly

private def parentBodyReification? :=
  reifyCommand? verifiedParserCore (.structure 0) parentLoopContext true
    parentLoopLayout 31 parserRecognizeParentLoopBody

private theorem parentBodyReification_exists :
    parentBodyReification?.isSome := by
  native_decide

private def parserRecognizeParentBodyView :=
  parentBodyReification?.get parentBodyReification_exists

private theorem parserRecognizeParentBodyView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      parentLoopLayout 31 parserRecognizeParentBodyView.command =
      parserRecognizeParentLoopBody :=
  parserRecognizeParentBodyView.toCoreExactly

private def parentSlot {arity : Nat} (index : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .reference (.slot index)

private def parentLiteral {arity : Nat} (value : Int) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .reference (.literal (.signed .i32 value))

private def parentConstant {arity : Nat} (id : ConstantId) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.constant id parserI32Type) []

private def parentBinary {arity : Nat} (operator : BinaryOp)
    (outputType : Ty)
    (left right : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.binary operator parserI32Type parserI32Type outputType)
    [left, right]

private def parentStateValueTerm {arity : Nat} (enough : 10 ≤ arity)
    (fieldConstant : ConstantId) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.call extractedParserStateValueFunction.id [
      .slice parserI32Type, parserI32Type, parserI32Type, parserI32Type]
      parserI32Type) [
    parentSlot ⟨1, by omega⟩,
    parentSlot ⟨2, by omega⟩,
    parentSlot ⟨9, by omega⟩,
    .apply (.constant fieldConstant parserI32Type) []]

private def parentRhsLengthTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 12 :=
  .apply (.call extractedParserRhsLengthFunction.id
    [.slice parserI32Type, parserI32Type] parserI32Type) [
      parentSlot ⟨0, by omega⟩,
      parentSlot ⟨10, by omega⟩]

private def parentRhsSymbolTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 13 :=
  .apply (.call extractedParserRhsSymbolFunction.id
    [.slice parserI32Type, parserI32Type, parserI32Type] parserI32Type) [
      parentSlot ⟨0, by omega⟩,
      parentSlot ⟨10, by omega⟩,
      parentSlot ⟨11, by omega⟩]

private def parentCandidatePredicate :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 13 :=
  Lanius.FunctionalView.Core.logicalAnd
    (parentBinary .less (.scalar .bool)
      (parentSlot ⟨11, by omega⟩) (parentSlot ⟨12, by omega⟩))
    (parentBinary .equal (.scalar .bool) parentRhsSymbolTerm
      (parentBinary .add parserI32Type
        (parentSlot ⟨5, by omega⟩) (parentSlot ⟨8, by omega⟩)))

private def parentNegativeOne {arity : Nat} :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.unary .negate parserI32Type parserI32Type) [parentLiteral 1]

private def parentSeedTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 14 :=
  .apply (.call extractedParserStateSeedFunction.id
    (List.replicate 7 parserI32Type) (.structure 1)) [
      parentSlot ⟨10, by omega⟩,
      parentBinary .add parserI32Type
        (parentSlot ⟨11, by omega⟩) (parentLiteral 1),
      parentSlot ⟨13, by omega⟩,
      parentSlot ⟨9, by omega⟩,
      parentConstant 39,
      parentSlot ⟨7, by omega⟩,
      parentNegativeOne]

private def parentAppendArguments : List
    (Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 14) := [
  parentSlot ⟨1, by omega⟩,
  parentSlot ⟨2, by omega⟩,
  parentSlot ⟨3, by omega⟩,
  parentSlot ⟨6, by omega⟩,
  parentSeedTerm,
  parentSlot ⟨4, by omega⟩]

private def parentAppendTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 14 :=
  .apply (.call extractedParserAppendStateFunction.id [
    .slice parserI32Type, parserI32Type, parserI32Type, parserI32Type,
    .structure 1, parserI32Type] (.structure 2)) parentAppendArguments

private def parentFullCondition :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 15 :=
  parentBinary .equal (.scalar .bool)
    (.apply (.field (.structure 2) 0 parserI32Type)
      [parentSlot ⟨14, by omega⟩])
    (parentConstant 41)

private def parentFullResult :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 15 :=
  .apply (.call extractedParserAppendOrFullFunction.id
    [.structure 2, parserI32Type] (.structure 0)) [
      parentSlot ⟨14, by omega⟩,
      parentSlot ⟨6, by omega⟩]

private def parentStateCountTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 15 :=
  .apply (.field (.structure 2) 2 parserI32Type)
    [parentSlot ⟨14, by omega⟩]

private def parentCanonicalBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 10 :=
  .letValue parserI32Type
    (parentStateValueTerm (arity := 10) (by omega) 28)
    (.letValue parserI32Type
      (parentStateValueTerm (arity := 11) (by omega) 29)
      (.letValue parserI32Type parentRhsLengthTerm
        (.sequence
          (.ifThenElse parentCandidatePredicate
            (.letValue parserI32Type
              (parentStateValueTerm (arity := 13) (by omega) 30)
              (.letValue (.structure 2) parentAppendTerm
                (.sequence
                  (.ifThenElse parentFullCondition
                    (.sequence (.returnValue (some parentFullResult)) .skip)
                    .skip)
                  (.sequence
                    (.setLocal ⟨4, by omega⟩ parentStateCountTerm)
                    .skip))))
            .skip)
          (.sequence
            (.setLocal ⟨9, by omega⟩
              (parentStateValueTerm (arity := 13) (by omega) 32))
            .skip))))

private theorem parentCanonicalBodyCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      parentLoopLayout 31 parentCanonicalBodyCommand =
      parserRecognizeParentLoopBody := by
  rfl

private def parentLoopCondition :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 10 :=
  parentBinary .greaterEqual (.scalar .bool)
    (parentSlot ⟨9, by omega⟩) (parentLiteral 0)

private def parentBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 10 :=
  parentCanonicalBodyCommand

def parentLoopCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 10 :=
  .whileLoop parentLoopCondition parentBodyCommand

theorem parentLoopCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      parentLoopLayout 31 parentLoopCommand = parserRecognizeParentLoop := by
  rw [parentLoopCommand, Lanius.FunctionalView.Core.Stateful.toCoreStmt,
    parentBodyCommand, parentCanonicalBodyCommand_toCore]
  exact extractedParserRecognize_parent_loop_shape.symm

def parentWorld (words : List Int) (tokens : List Nat)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId) :
    Lanius.FunctionalView.Core.ReadOnly.World :=
  recognizerWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell

def parentEnvironment
    (words workspaceValues : List Int) (grammarCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (stateCount kindCount position
      completed completedLhs : Nat) (parent : Int) :
    Lanius.FunctionalView.Env 10
  | ⟨0, _⟩ => parserGrammarValue words grammarCell
  | ⟨1, _⟩ => workspaceValue workspaceValues workspaceCell
  | ⟨2, _⟩ => .signed .i32
      (Int.ofNat (stateBase workspaceLayout.tokenCount))
  | ⟨3, _⟩ => .signed .i32 (Int.ofNat workspaceLayout.capacity)
  | ⟨4, _⟩ => .signed .i32 (Int.ofNat stateCount)
  | ⟨5, _⟩ => .signed .i32 (Int.ofNat kindCount)
  | ⟨6, _⟩ => .signed .i32 (Int.ofNat position)
  | ⟨7, _⟩ => .signed .i32 (Int.ofNat completed)
  | ⟨8, _⟩ => .signed .i32 (Int.ofNat completedLhs)
  | ⟨9, _⟩ => .signed .i32 parent

noncomputable def parentTermMachine
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId) :=
  Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
    (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
      grammarCell)

noncomputable def parentStatefulMachine
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId) :=
  Lanius.FunctionalView.Core.Stateful.machineWith verifiedParserCore
    (Lanius.FunctionalView.Core.Effectful.evaluateOperation verifiedParserCore
      (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
        grammarCell))

/-- Functional evaluation of a packed parent-traversal state-field read. -/
private theorem parentStateValueTerm_evaluates
    {arity : Nat} (enough : 10 ≤ arity)
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words workspaceValues : List Int) (grammarCell workspaceCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (workspace : LogicalWorkspace) (state : EarleyState)
    (stateId field : Nat) (fieldConstant : ConstantId)
    (different : workspaceCell ≠ grammarCell)
    (worldEq : world = parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    (workspaceValueEq : environment ⟨1, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (stateBaseEq : environment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (stateIdEq : environment ⟨9, by omega⟩ =
      .signed .i32 (Int.ofNat stateId))
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
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world environment (parentStateValueTerm enough fieldConstant) =
      .ok (.signed .i32 (stateFieldValue workspace stateId state field),
        world) := by
  subst world
  let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let machine := parentTermMachine workspaceLayout grammar words grammarCell
  have workspaceResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (parentSlot ⟨1, by omega⟩) =
      .ok (workspaceValue workspaceValues workspaceCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot workspaceValueEq
  have baseResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (parentSlot ⟨2, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat
        (stateBase workspaceLayout.tokenCount)), world) :=
    Lanius.FunctionalView.Term.evaluate_slot stateBaseEq
  have stateResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (parentSlot ⟨9, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat stateId), world) :=
    Lanius.FunctionalView.Term.evaluate_slot stateIdEq
  let constantTerm : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity :=
    .apply (.constant fieldConstant parserI32Type) []
  have constantAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell) (world := world) (environment := environment)
      constantTerm (by rfl)
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
      environment [parentSlot ⟨1, by omega⟩, parentSlot ⟨2, by omega⟩,
        parentSlot ⟨9, by omega⟩, constantTerm] =
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
  have worldFound : world.i32Slice? workspaceCell = some workspaceValues := by
    exact recognizerWorld_finds_workspace different
  have addressValue := workspaceLayout.state_value_eq_address
    (encoded.state_id_lt_capacity foundState) fieldBound
  have valueFound :
      ((workspaceValues.drop 0).take workspaceValues.length)[stateWord
        (stateBase workspaceLayout.tokenCount) stateId field]? =
      some (workspaceValues.get ⟨stateWord
        (stateBase workspaceLayout.tokenCount) stateId field,
        addressBound⟩) := by
    simpa using List.getElem?_eq_getElem addressBound
  have registryResult :=
    RecognizerTraversalCallRegistry.calls_at_state_value
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (grammarCell := grammarCell) world workspaceValues
      workspaceCell 0 workspaceValues.length
      (stateWord (stateBase workspaceLayout.tokenCount) stateId field)
      (Int.ofNat (stateBase workspaceLayout.tokenCount)) (Int.ofNat stateId)
      (Int.ofNat field) (workspaceValues.get ⟨stateWord
        (stateBase workspaceLayout.tokenCount) stateId field, addressBound⟩)
      addressValue addressBound worldFound (by simp) valueFound
  have fieldValue : workspaceValues.get ⟨stateWord
      (stateBase workspaceLayout.tokenCount) stateId field, addressBound⟩ =
      stateFieldValue workspace stateId state field := by
    have concrete := encoded.stateField stateId state foundState field fieldBound
    rw [listWords_get workspaceValues _ addressBound] at concrete
    exact concrete
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
    grammarCell).evaluate world extractedParserStateValueFunction.id [
      workspaceValue workspaceValues workspaceCell,
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
      .signed .i32 (Int.ofNat stateId), .signed .i32 (Int.ofNat field)] = _
  rw [fieldValue] at registryResult
  exact registryResult

/-- Functional evaluation of the parent predicate's RHS-length lookup. -/
private theorem parentRhsLengthTerm_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words workspaceValues : List Int) (grammarCell workspaceCell : CellId)
    (environment : Lanius.FunctionalView.Env 12) (production : Nat)
    (productionBound : production < grammar.productionCount)
    (grammarValueEq : environment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell)
    (productionValueEq : environment ⟨10, by omega⟩ =
      .signed .i32 (Int.ofNat production)) :
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      environment parentRhsLengthTerm =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨production, productionBound⟩).rhs.length),
        parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) := by
  let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let machine := parentTermMachine workspaceLayout grammar words grammarCell
  have grammarResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (parentSlot ⟨0, by omega⟩) =
      .ok (parserGrammarValue words grammarCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot grammarValueEq
  have productionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (parentSlot ⟨10, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat production), world) :=
    Lanius.FunctionalView.Term.evaluate_slot productionValueEq
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [parentSlot ⟨0, by omega⟩, parentSlot ⟨10, by omega⟩] =
      .ok ([parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production)], world) :=
    Lanius.FunctionalView.evaluateTerms_cons grammarResult
      (Lanius.FunctionalView.evaluateTerms_cons productionResult
        (Lanius.FunctionalView.evaluateTerms_nil machine world environment))
  have rowBound : production < grammar.rhsLengths.length := by simpa
  have registryResult := RecognizerTraversalCallRegistry.calls_at_rhs_length
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (grammarCell := grammarCell) world production
    (by simp [world, parentWorld]) rowBound
  have rowValue : grammar.rhsLengths.get ⟨production, rowBound⟩ =
      (grammar.productionAt ⟨production, productionBound⟩).rhs.length := by
    simpa using grammar.rhsLengths_get ⟨production, productionBound⟩
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
    grammarCell).evaluate world extractedParserRhsLengthFunction.id
      [parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production)] = _
  rw [rowValue] at registryResult
  exact registryResult

/-- Functional evaluation of the parent predicate's RHS-symbol lookup. -/
private theorem parentRhsSymbolTerm_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words workspaceValues : List Int) (grammarCell workspaceCell : CellId)
    (environment : Lanius.FunctionalView.Env 13) (production dot : Nat)
    (productionBound : production < grammar.productionCount)
    (dotBound : dot <
      (grammar.productionAt ⟨production, productionBound⟩).rhs.length)
    (grammarValueEq : environment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell)
    (productionValueEq : environment ⟨10, by omega⟩ =
      .signed .i32 (Int.ofNat production))
    (dotValueEq : environment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat dot)) :
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      environment parentRhsSymbolTerm =
      .ok (.signed .i32 (Int.ofNat
        ((grammar.productionAt ⟨production, productionBound⟩).rhs.get
          ⟨dot, dotBound⟩)),
        parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) := by
  let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let machine := parentTermMachine workspaceLayout grammar words grammarCell
  have grammarResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (parentSlot ⟨0, by omega⟩) =
      .ok (parserGrammarValue words grammarCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot grammarValueEq
  have productionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (parentSlot ⟨10, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat production), world) :=
    Lanius.FunctionalView.Term.evaluate_slot productionValueEq
  have dotResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (parentSlot ⟨11, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat dot), world) :=
    Lanius.FunctionalView.Term.evaluate_slot dotValueEq
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [parentSlot ⟨0, by omega⟩, parentSlot ⟨10, by omega⟩,
        parentSlot ⟨11, by omega⟩] =
      .ok ([parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production),
        .signed .i32 (Int.ofNat dot)], world) :=
    Lanius.FunctionalView.evaluateTerms_cons grammarResult
      (Lanius.FunctionalView.evaluateTerms_cons productionResult
        (Lanius.FunctionalView.evaluateTerms_cons dotResult
          (Lanius.FunctionalView.evaluateTerms_nil machine world environment)))
  have registryResult := RecognizerTraversalCallRegistry.calls_at_rhs_symbol
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (grammarCell := grammarCell) world production dot
    (by simp [world, parentWorld]) productionBound dotBound
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  exact registryResult

private theorem parentLess_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (grammarCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (left right : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (leftValue rightValue : Nat)
    (leftResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world environment left =
      .ok (.signed .i32 (Int.ofNat leftValue), world))
    (rightResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world environment right =
      .ok (.signed .i32 (Int.ofNat rightValue), world)) :
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world environment (parentBinary .less (.scalar .bool) left right) =
      .ok (.boolean (decide (leftValue < rightValue)), world) := by
  apply Lanius.FunctionalView.Term.evaluate_apply2 leftResult rightResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedParserCore world
      (.binary .less parserI32Type parserI32Type (.scalar .bool))
      [.signed .i32 (Int.ofNat leftValue),
        .signed .i32 (Int.ofNat rightValue)] = _
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_less
    leftValue rightValue

private theorem parentEqual_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (grammarCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (left right : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (leftValue rightValue : Nat)
    (leftResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world environment left =
      .ok (.signed .i32 (Int.ofNat leftValue), world))
    (rightResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world environment right =
      .ok (.signed .i32 (Int.ofNat rightValue), world)) :
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world environment (parentBinary .equal (.scalar .bool) left right) =
      .ok (.boolean (decide (leftValue = rightValue)), world) := by
  apply Lanius.FunctionalView.Term.evaluate_apply2 leftResult rightResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedParserCore world
      (.binary .equal parserI32Type parserI32Type (.scalar .bool))
      [.signed .i32 (Int.ofNat leftValue),
        .signed .i32 (Int.ofNat rightValue)] = _
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_equal
    leftValue rightValue

private theorem parentAdd_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (grammarCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (left right : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (leftValue rightValue : Nat)
    (sumI32 : leftValue + rightValue ≤ 2147483647)
    (leftResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world environment left =
      .ok (.signed .i32 (Int.ofNat leftValue), world))
    (rightResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world environment right =
      .ok (.signed .i32 (Int.ofNat rightValue), world)) :
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world environment (parentBinary .add parserI32Type left right) =
      .ok (.signed .i32 (Int.ofNat (leftValue + rightValue)), world) := by
  apply Lanius.FunctionalView.Term.evaluate_apply2 leftResult rightResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedParserCore world
      (.binary .add parserI32Type parserI32Type parserI32Type)
      [.signed .i32 (Int.ofNat leftValue),
        .signed .i32 (Int.ofNat rightValue)] = _
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_add
    leftValue rightValue sumI32

private theorem parentLoopCondition_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words workspaceValues : List Int)
    (grammarCell workspaceCell : CellId)
    (stateCount kindCount position completed completedLhs : Nat)
    (parent : Int) :
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      (parentEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout stateCount kindCount position completed completedLhs
        parent)
      parentLoopCondition =
      .ok (.boolean (decide (parent ≥ 0)),
        parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) := by
  simp [parentTermMachine, parentWorld, parentEnvironment,
    parentLoopCondition, parentBinary, parentSlot, parentLiteral,
    Lanius.FunctionalView.Term.evaluate,
    Lanius.FunctionalView.Ref.evaluate,
    Lanius.FunctionalView.evaluateTerms,
    Lanius.FunctionalView.Core.Effectful.machine,
    Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
    evalBinaryValue, evalSignedBinary, bind, Except.bind]

/-- Persistent semantic and ownership state for completion replay over the
    completed state's origin chart. -/
structure RecognizerParentLoopInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (runtime : State)
    (position completed completedLhs origin current : Nat)
    (remaining : List Nat) : Type where
  chartCursor : RecognizerChartCursorInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell cursorCell runtime origin 30 current remaining
  appendFrame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime position
  kindCountLocal : runtime.local? 11 =
    some (.signed .i32 (Int.ofNat grammar.grammar.n_kinds))
  positionLocal : runtime.local? 23 =
    some (.signed .i32 (Int.ofNat position))
  completedLocal : runtime.local? 24 =
    some (.signed .i32 (Int.ofNat completed))
  completedLhsLocal : runtime.local? 29 =
    some (.signed .i32 (Int.ofNat completedLhs))
  completedLhsBound : completedLhs < grammar.grammar.n_nonterminals
  completedStored : StoredCompletion grammar workspace completed completedLhs
    origin position
  completedRecognizes : RecognizesSymbol grammar tokens
    (grammar.grammar.n_kinds + completedLhs) origin position
  persistentSeparate : ParentFrameSeparated runtime workspaceCell
    stateCountCell cursorCell
  cursorStateCountDistinct : cursorCell ≠ stateCountCell

/-- The source parent loop's production, dot, and RHS-length bindings evaluate
    to the current logical state and its indexed grammar row. -/
private theorem RecognizerParentLoopInvariant.functional_candidate_reads
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount) :
    let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let environment := parentEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length
      grammar.grammar.n_kinds position completed completedLhs
      (Int.ofNat current)
    let productionEnvironment := environment.push
      (.signed .i32 (Int.ofNat candidate.production))
    let dotEnvironment := productionEnvironment.push
      (.signed .i32 (Int.ofNat candidate.dot))
    Lanius.FunctionalView.Term.evaluate
        (parentTermMachine workspaceLayout grammar words grammarCell)
        world environment (parentStateValueTerm (arity := 10) (by omega) 28) =
      .ok (.signed .i32 (Int.ofNat candidate.production), world) ∧
    Lanius.FunctionalView.Term.evaluate
        (parentTermMachine workspaceLayout grammar words grammarCell)
        world productionEnvironment
        (parentStateValueTerm (arity := 11) (by omega) 29) =
      .ok (.signed .i32 (Int.ofNat candidate.dot), world) ∧
    Lanius.FunctionalView.Term.evaluate
        (parentTermMachine workspaceLayout grammar words grammarCell)
        world dotEnvironment parentRhsLengthTerm =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production,
          productionBound⟩).rhs.length), world) := by
  dsimp only
  let environment := parentEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length
    grammar.grammar.n_kinds position completed completedLhs
    (Int.ofNat current)
  have different :=
    invariant.chartCursor.recognizer.grammarWorkspaceDistinct.symm
  have productionRead := parentStateValueTerm_evaluates
    (arity := 10) (by omega) workspaceLayout grammar words workspaceValues
    grammarCell workspaceCell
    (parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    environment workspace candidate current 0 28 different rfl rfl rfl rfl
    invariant.chartCursor.recognizer.workspaceLength
    invariant.chartCursor.recognizer.workspaceEncoded found (by decide)
    verifiedParser_find_constants.2.1
  have dotRead := parentStateValueTerm_evaluates
    (arity := 11) (by omega) workspaceLayout grammar words workspaceValues
    grammarCell workspaceCell
    (parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    (environment.push (.signed .i32 (Int.ofNat candidate.production)))
    workspace candidate current 1 29 different rfl (by rfl) (by rfl) (by rfl)
    invariant.chartCursor.recognizer.workspaceLength
    invariant.chartCursor.recognizer.workspaceEncoded found (by decide)
    verifiedParser_find_constants.2.2.1
  have rhsRead := parentRhsLengthTerm_evaluates
    (tokens := tokens) (tokensCell := tokensCell) workspaceLayout grammar words
    workspaceValues grammarCell workspaceCell
    ((environment.push (.signed .i32 (Int.ofNat candidate.production))).push
      (.signed .i32 (Int.ofNat candidate.dot))) candidate.production
    productionBound (by rfl) (by rfl)
  simpa [environment, stateFieldValue] using And.intro productionRead
    (And.intro dotRead rhsRead)

/-- Parent-completion state after the origin-chart cursor contains the
    concrete `-1` sentinel. -/
structure RecognizerParentFinishedInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (runtime : State)
    (position completed completedLhs origin : Nat) : Type where
  chartCursor : RecognizerChartCursorFinished grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell cursorCell runtime origin 30
  appendFrame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime position
  kindCountLocal : runtime.local? 11 =
    some (.signed .i32 (Int.ofNat grammar.grammar.n_kinds))
  positionLocal : runtime.local? 23 =
    some (.signed .i32 (Int.ofNat position))
  completedLocal : runtime.local? 24 =
    some (.signed .i32 (Int.ofNat completed))
  completedLhsLocal : runtime.local? 29 =
    some (.signed .i32 (Int.ofNat completedLhs))
  completedLhsBound : completedLhs < grammar.grammar.n_nonterminals
  completedStored : StoredCompletion grammar workspace completed completedLhs
    origin position
  completedRecognizes : RecognizesSymbol grammar tokens
    (grammar.grammar.n_kinds + completedLhs) origin position
  persistentSeparate : ParentFrameSeparated runtime workspaceCell
    stateCountCell cursorCell
  cursorStateCountDistinct : cursorCell ≠ stateCountCell

theorem parentPersistentLocalsSeparate
    (separate : ParentFrameSeparated runtime workspaceCell stateCountCell
      cursorCell)
    (stateCountId : runtime.cellId? 18 = some stateCountCell)
    (stateCountWorkspaceDistinct : stateCountCell ≠ workspaceCell)
    (cursorStateCountDistinct : cursorCell ≠ stateCountCell)
    (id : VarId) (persistent : ParentPersistentLocal id) :
    runtime.cellId? id ≠ some workspaceCell ∧
      (id ≠ 18 → runtime.cellId? id ≠ some stateCountCell) ∧
      runtime.cellId? id ≠ some cursorCell := by
  by_cases notStateCount : id ≠ 18
  · have preserved :=
      (ParentPreservedLocal_iff id).mpr ⟨persistent, notStateCount⟩
    have framed := (ParentPreservedLocal_source_frame id).mp preserved
    refine ⟨?_, ?_, ?_⟩
    · intro cellId
      exact separate workspaceCell ⟨id, framed, cellId⟩
        (Or.inl rfl)
    · intro _ cellId
      exact separate stateCountCell ⟨id, framed, cellId⟩
        (Or.inr (Or.inl rfl))
    · intro cellId
      exact separate cursorCell ⟨id, framed, cellId⟩
        (Or.inr (Or.inr rfl))
  · have same : id = 18 := Classical.byContradiction notStateCount
    subst id
    refine ⟨?_, ?_, ?_⟩
    · intro workspaceId
      exact stateCountWorkspaceDistinct
        (Option.some.inj (stateCountId.symm.trans workspaceId))
    · intro impossible
      exact False.elim (impossible rfl)
    · intro cursorId
      exact cursorStateCountDistinct
        (Option.some.inj (stateCountId.symm.trans cursorId)).symm

theorem RecognizerParentLoopInvariant.persistentLocalsSeparate
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining) :
    ∀ id, ParentPersistentLocal id →
      runtime.cellId? id ≠ some workspaceCell ∧
      (id ≠ 18 → runtime.cellId? id ≠ some stateCountCell) ∧
      runtime.cellId? id ≠ some cursorCell :=
  parentPersistentLocalsSeparate invariant.persistentSeparate
    invariant.appendFrame.stateCountOwned.1
    invariant.appendFrame.stateCountBackingDistinct.2.2
    invariant.cursorStateCountDistinct

theorem RecognizerParentFinishedInvariant.persistentLocalsSeparate
    (invariant : RecognizerParentFinishedInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin) :
    ∀ id, ParentPersistentLocal id →
      runtime.cellId? id ≠ some workspaceCell ∧
      (id ≠ 18 → runtime.cellId? id ≠ some stateCountCell) ∧
      runtime.cellId? id ≠ some cursorCell :=
  parentPersistentLocalsSeparate invariant.persistentSeparate
    invariant.appendFrame.stateCountOwned.1
    invariant.appendFrame.stateCountBackingDistinct.2.2
    invariant.cursorStateCountDistinct

theorem RecognizerParentFinishedInvariant.condition_negative
    (invariant : RecognizerParentFinishedInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin) :
    Evaluates verifiedParserCore runtime
      (.binary .greaterEqual (.local 30) (.value (.signed .i32 0)))
      (.boolean false) runtime :=
  invariant.chartCursor.condition_negative

theorem RecognizerParentLoopInvariant.expected_symbol_i32
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining) :
    grammar.grammar.n_kinds + completedLhs ≤ 2147483647 := by
  have domain :=
    invariant.chartCursor.recognizer.grammarWellFormed.symbolDomainFitsI32
  have completedBound := invariant.completedLhsBound
  omega

def RecognizerParentLoopInvariant.after_empty_effect
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    RecognizerParentLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell after position completed
      completedLhs origin current remaining := {
  chartCursor := invariant.chartCursor.after_empty_effect effect afterWellFormed
  appendFrame := invariant.appendFrame.after_empty_effect effect afterWellFormed
  kindCountLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.kindCountLocal
  positionLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.positionLocal
  completedLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.completedLocal
  completedLhsLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.completedLhsLocal
  completedLhsBound := invariant.completedLhsBound
  completedRecognizes := invariant.completedRecognizes
  completedStored := invariant.completedStored
  persistentSeparate := by
    unfold ParentFrameSeparated
    rw [effect.localBindingFrameFootprint_eq
      verifiedParserParentPreservedBindings]
    exact invariant.persistentSeparate
  cursorStateCountDistinct := invariant.cursorStateCountDistinct
}

def RecognizerParentLoopInvariant.after_bind_local
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining)
    (id : VarId) (value : Value) (temporary : 30 < id) :
    RecognizerParentLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell (runtime.bindLocal id value)
      position completed completedLhs origin current remaining := by
  have different (fixed : Nat) (bound : fixed ≤ 30) : id ≠ fixed :=
    Nat.ne_of_gt (Nat.lt_of_le_of_lt bound temporary)
  exact {
    chartCursor := invariant.chartCursor.after_bind_local id value
      (Nat.lt_of_le_of_lt (by decide : 8 ≤ 30) temporary) temporary
    appendFrame := invariant.appendFrame.after_bind_local id value
      (different 0 (by decide)) (different 1 (by decide))
      (different 2 (by decide)) (different 3 (by decide))
      (different 4 (by decide)) (different 5 (by decide))
      (Nat.lt_of_le_of_lt (by decide : 5 ≤ 30) temporary)
      (different 8 (by decide)) (different 9 (by decide))
      (different 18 (by decide))
    kindCountLocal :=
      (bindLocal_preserves_other_local
        invariant.chartCursor.recognizer.wellFormed
        (different 11 (by decide))).trans invariant.kindCountLocal
    positionLocal :=
      (bindLocal_preserves_other_local
        invariant.chartCursor.recognizer.wellFormed
        (different 23 (by decide))).trans invariant.positionLocal
    completedLocal :=
      (bindLocal_preserves_other_local
        invariant.chartCursor.recognizer.wellFormed
        (different 24 (by decide))).trans invariant.completedLocal
    completedLhsLocal :=
      (bindLocal_preserves_other_local
        invariant.chartCursor.recognizer.wellFormed
        (different 29 (by decide))).trans invariant.completedLhsLocal
    completedLhsBound := invariant.completedLhsBound
    completedRecognizes := invariant.completedRecognizes
    completedStored := invariant.completedStored
    persistentSeparate := by
      unfold ParentFrameSeparated
      intro cell framed written
      obtain ⟨queried, preserved, cellId⟩ := framed
      have queriedBound := (ParentPreservedLocal_iff queried).mp
        ((ParentPreservedLocal_source_frame queried).mpr preserved) |>.1
      have notEqual : id ≠ queried := different queried
        (Nat.le_trans (ParentPersistentLocal.le29 queried queriedBound)
          (by decide))
      apply invariant.persistentSeparate cell
        ⟨queried, preserved, ?_⟩ written
      simpa [State.bindLocal, State.bindCell, State.cellId?, notEqual] using
        cellId
    cursorStateCountDistinct := invariant.cursorStateCountDistinct
  }

def RecognizerParentLoopInvariant.after_cursor_effect
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (afterCursor : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell after origin 30 next nextRemaining)
    (effect : ModifiesOnly (CellSet.singleton cursorCell) before after) :
    RecognizerParentLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell after position completed
      completedLhs origin next nextRemaining := by
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        verifiedParserParentPersistentBindings)
      (CellSet.singleton cursorCell) :=
    localCellFootprint_disjoint_singleton
      (fun id framed =>
        invariant.persistentLocalsSeparate id
          ((ParentPersistentLocal_source_frame id).mpr framed) |>.2.2)
  have preserveLocal (id : VarId) (persistent : ParentPersistentLocal id)
      (value : Value)
      (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint
      invariant.chartCursor.recognizer.wellFormed frameDisjoint
        ((ParentPersistentLocal_source_frame id).mp persistent) found
  have countOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds after :=
    effect.preserve invariant.chartCursor.recognizer.wellFormed
      (Assertion.localPointsTo 18 stateCountCell
        (some (.signed .i32 (Int.ofNat workspace.states.length))))
      invariant.appendFrame.stateCountOwned (by
        intro cell member written
        change cell = stateCountCell at member
        change cell = cursorCell at written
        subst cell
        exact invariant.cursorStateCountDistinct written.symm)
  exact {
    chartCursor := afterCursor
    appendFrame := {
      recognizer := afterCursor.recognizer
      positionBound := invariant.appendFrame.positionBound
      stateBaseLocal := afterCursor.stateBaseLocal
      stateCapacityLocal := preserveLocal 9 (by
        simp [ParentPersistentLocal]) _
        invariant.appendFrame.stateCapacityLocal
      stateCountLocal := preserveLocal 18 (by
        simp [ParentPersistentLocal]) _
        invariant.appendFrame.stateCountLocal
      stateCountOwned := countOwned
      stateCountBackingDistinct :=
        invariant.appendFrame.stateCountBackingDistinct
      stateCountParameterSeparate := by
        unfold RecognizerParameterFrameSeparated
        rw [effect.localBindingFrameFootprint_eq
          verifiedParserRecognizerParameterFrame]
        exact invariant.appendFrame.stateCountParameterSeparate
    }
    kindCountLocal := preserveLocal 11 (by
      simp [ParentPersistentLocal]) _ invariant.kindCountLocal
    positionLocal := preserveLocal 23 (by
      simp [ParentPersistentLocal]) _ invariant.positionLocal
    completedLocal := preserveLocal 24 (by
      simp [ParentPersistentLocal]) _ invariant.completedLocal
    completedLhsLocal := preserveLocal 29 (by
      simp [ParentPersistentLocal]) _
      invariant.completedLhsLocal
    completedLhsBound := invariant.completedLhsBound
    completedRecognizes := invariant.completedRecognizes
    completedStored := invariant.completedStored
    persistentSeparate := by
      unfold ParentFrameSeparated
      rw [effect.localBindingFrameFootprint_eq
        verifiedParserParentPreservedBindings]
      exact invariant.persistentSeparate
    cursorStateCountDistinct := invariant.cursorStateCountDistinct
  }

def RecognizerParentLoopInvariant.after_cursor_exhaustion
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current [])
    (afterCursor : RecognizerChartCursorFinished grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell after origin 30)
    (effect : ModifiesOnly (CellSet.singleton cursorCell) before after) :
    RecognizerParentFinishedInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell after position completed
      completedLhs origin := by
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        verifiedParserParentPersistentBindings)
      (CellSet.singleton cursorCell) :=
    localCellFootprint_disjoint_singleton
      (fun id framed =>
        invariant.persistentLocalsSeparate id
          ((ParentPersistentLocal_source_frame id).mpr framed) |>.2.2)
  have preserveLocal (id : VarId) (persistent : ParentPersistentLocal id)
      (value : Value)
      (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint
      invariant.chartCursor.recognizer.wellFormed frameDisjoint
        ((ParentPersistentLocal_source_frame id).mp persistent) found
  have countOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds after :=
    effect.preserve invariant.chartCursor.recognizer.wellFormed
      (Assertion.localPointsTo 18 stateCountCell
        (some (.signed .i32 (Int.ofNat workspace.states.length))))
      invariant.appendFrame.stateCountOwned (by
        intro cell member written
        change cell = stateCountCell at member
        change cell = cursorCell at written
        subst cell
        exact invariant.cursorStateCountDistinct written.symm)
  exact {
    chartCursor := afterCursor
    appendFrame := {
      recognizer := afterCursor.recognizer
      positionBound := invariant.appendFrame.positionBound
      stateBaseLocal := afterCursor.stateBaseLocal
      stateCapacityLocal := preserveLocal 9 (by
        simp [ParentPersistentLocal]) _
        invariant.appendFrame.stateCapacityLocal
      stateCountLocal := preserveLocal 18 (by
        simp [ParentPersistentLocal]) _
        invariant.appendFrame.stateCountLocal
      stateCountOwned := countOwned
      stateCountBackingDistinct :=
        invariant.appendFrame.stateCountBackingDistinct
      stateCountParameterSeparate := by
        unfold RecognizerParameterFrameSeparated
        rw [effect.localBindingFrameFootprint_eq
          verifiedParserRecognizerParameterFrame]
        exact invariant.appendFrame.stateCountParameterSeparate
    }
    kindCountLocal := preserveLocal 11 (by
      simp [ParentPersistentLocal]) _ invariant.kindCountLocal
    positionLocal := preserveLocal 23 (by
      simp [ParentPersistentLocal]) _ invariant.positionLocal
    completedLocal := preserveLocal 24 (by
      simp [ParentPersistentLocal]) _ invariant.completedLocal
    completedLhsLocal := preserveLocal 29 (by
      simp [ParentPersistentLocal]) _
      invariant.completedLhsLocal
    completedLhsBound := invariant.completedLhsBound
    completedRecognizes := invariant.completedRecognizes
    completedStored := invariant.completedStored
    persistentSeparate := by
      unfold ParentFrameSeparated
      rw [effect.localBindingFrameFootprint_eq
        verifiedParserParentPreservedBindings]
      exact invariant.persistentSeparate
    cursorStateCountDistinct := invariant.cursorStateCountDistinct
  }

theorem RecognizerParentLoopInvariant.seed_within_grammar
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount)
    (dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length) :
    StateKeyWithinGrammar grammar
      (recognizerParentSeed candidate.production candidate.dot candidate.origin
        current completed).key := {
  productionBound := by
    simpa [recognizerParentSeed, StateSeed.key, EarleyState.key] using
      productionBound
  dotBound := by
    simpa [recognizerParentSeed, StateSeed.key] using
      Nat.succ_le_of_lt dotBeforeEnd
}

theorem RecognizerParentLoopInvariant.candidate_dot_succ_i32
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount)
    (dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length) :
    candidate.dot + 1 ≤ 2147483647 := by
  have productionBound' : candidate.production < grammar.productionCount := by
    simpa [EarleyState.key] using productionBound
  have rowRange :=
    invariant.chartCursor.recognizer.grammarWellFormed.production_validation
      |>.rhsRange ⟨candidate.production, productionBound'⟩
  have tableFits :=
    invariant.chartCursor.recognizer.grammarEncoded.rhsSymbols.2.1
  have wordsFit := invariant.chartCursor.recognizer.wordsI32
  have sameLength :
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length =
      (grammar.productionAt ⟨candidate.production,
        productionBound'⟩).rhs.length := by
    exact congrArg (fun productionId : Fin grammar.productionCount =>
      (grammar.productionAt productionId).rhs.length) (Fin.ext rfl)
  omega

/-- The three temporary bindings at the head of one parent-completion
    iteration, together with the semantic values read from the current chart
    state. -/
structure RecognizerParentCandidateBindings
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position completed completedLhs origin current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount) where
  afterProductionRead : State
  productionEvaluation : Evaluates verifiedParserCore before
    (parserRecognizeStateValueCall 30 28)
    (.signed .i32 (Int.ofNat candidate.production)) afterProductionRead
  productionEffect : ModifiesOnly CellSet.empty before afterProductionRead
  afterProductionWellFormed : StateWellFormed afterProductionRead
  afterDotRead : State
  dotEvaluation : Evaluates verifiedParserCore
    (afterProductionRead.bindLocal 31
      (.signed .i32 (Int.ofNat candidate.production)))
    (parserRecognizeStateValueCall 30 29)
    (.signed .i32 (Int.ofNat candidate.dot)) afterDotRead
  dotEffect : ModifiesOnly CellSet.empty
    (afterProductionRead.bindLocal 31
      (.signed .i32 (Int.ofNat candidate.production))) afterDotRead
  afterDotWellFormed : StateWellFormed afterDotRead
  afterRhsLengthRead : State
  rhsLengthEvaluation : Evaluates verifiedParserCore
    (afterDotRead.bindLocal 32 (.signed .i32 (Int.ofNat candidate.dot)))
    (.call extractedParserRhsLengthFunction.id [.local 0, .local 31])
    (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length))
    afterRhsLengthRead
  rhsLengthEffect : ModifiesOnly CellSet.empty
    (afterDotRead.bindLocal 32 (.signed .i32 (Int.ofNat candidate.dot)))
    afterRhsLengthRead
  afterRhsLengthWellFormed : StateWellFormed afterRhsLengthRead
  invariant : RecognizerParentLoopInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell
    (afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length)))
    position completed completedLhs origin current remaining
  productionLocal :
    (afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length))).local? 31 =
      some (.signed .i32 (Int.ofNat candidate.production))
  dotLocal :
    (afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length))).local? 32 =
      some (.signed .i32 (Int.ofNat candidate.dot))
  rhsLengthLocal :
    (afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length))).local? 33 =
      some (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length))

/-- Execute the production, dot, and RHS-length bindings exactly as emitted
    by the extracted parent-completion loop. -/
noncomputable def RecognizerParentLoopInvariant.bind_candidate_fields
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount) :
    RecognizerParentCandidateBindings grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining invariant candidate found
      productionBound := by
  have candidateProductionBound : candidate.production <
      grammar.productionCount := by
    simpa [EarleyState.key] using productionBound
  let productionRead := invariant.chartCursor.read_production candidate found
  have productionEvaluation : Evaluates verifiedParserCore runtime
      (parserRecognizeStateValueCall 30 28)
      (.signed .i32 (Int.ofNat candidate.production)) productionRead.after := by
    simpa [stateFieldValue] using productionRead.evaluation
  let afterProduction := invariant.after_empty_effect productionRead.effect
    productionRead.invariant.recognizer.wellFormed
  let productionScope := productionRead.after.bindLocal 31
    (.signed .i32 (Int.ofNat candidate.production))
  let productionInvariant := afterProduction.after_bind_local 31
    (.signed .i32 (Int.ofNat candidate.production)) (by decide)
  let dotRead := productionInvariant.chartCursor.read_dot candidate found
  have dotEvaluation : Evaluates verifiedParserCore productionScope
      (parserRecognizeStateValueCall 30 29)
      (.signed .i32 (Int.ofNat candidate.dot)) dotRead.after := by
    simpa [productionScope, productionInvariant, stateFieldValue] using
      dotRead.evaluation
  let afterDot := productionInvariant.after_empty_effect dotRead.effect
    dotRead.invariant.recognizer.wellFormed
  let dotScope := dotRead.after.bindLocal 32
    (.signed .i32 (Int.ofNat candidate.dot))
  let dotInvariant := afterDot.after_bind_local 32
    (.signed .i32 (Int.ofNat candidate.dot)) (by decide)
  have productionAtDotScope : dotScope.local? 31 =
      some (.signed .i32 (Int.ofNat candidate.production)) := by
    have atProductionScope : productionScope.local? 31 =
        some (.signed .i32 (Int.ofNat candidate.production)) := by
      simpa [productionScope] using bindLocal_finds_local productionRead.after
        31 (.signed .i32 (Int.ofNat candidate.production))
        productionRead.invariant.recognizer.wellFormed
    have atDotRead := dotRead.effect.empty_preserves_local
      productionInvariant.chartCursor.recognizer.wellFormed atProductionScope
    exact (bindLocal_preserves_other_local
      dotRead.invariant.recognizer.wellFormed (by decide : 32 ≠ 31)).trans
      atDotRead
  have productionResult : Evaluates verifiedParserCore dotScope (.local 31)
      (.signed .i32 (Int.ofNat candidate.production)) dotScope :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore dotScope 31 _
      productionAtDotScope⟩
  let rhsRead := dotInvariant.chartCursor.read_rhs_length candidate.production
    candidateProductionBound (.local 31) productionResult
  have rhsLengthValue : grammar.rhsLengths.get
      ⟨candidate.production, by simpa using candidateProductionBound⟩ =
      (grammar.productionAt ⟨candidate.production,
        candidateProductionBound⟩).rhs.length := by
    simpa using grammar.rhsLengths_get
      ⟨candidate.production, candidateProductionBound⟩
  have rhsLengthEvaluation : Evaluates verifiedParserCore dotScope
      (.call extractedParserRhsLengthFunction.id [.local 0, .local 31])
      (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production,
          candidateProductionBound⟩).rhs.length)) rhsRead.after := by
    simpa only [rhsLengthValue] using rhsRead.evaluation
  let afterRhs := dotInvariant.after_empty_effect rhsRead.effect
    rhsRead.invariant.recognizer.wellFormed
  let rhsLength :=
    (grammar.productionAt ⟨candidate.production,
      candidateProductionBound⟩).rhs.length
  let rhsScope := rhsRead.after.bindLocal 33
    (.signed .i32 (Int.ofNat rhsLength))
  let rhsInvariant := afterRhs.after_bind_local 33
    (.signed .i32 (Int.ofNat rhsLength)) (by decide)
  have dotAtDotScope : dotScope.local? 32 =
      some (.signed .i32 (Int.ofNat candidate.dot)) := by
    simpa [dotScope] using bindLocal_finds_local dotRead.after 32
      (.signed .i32 (Int.ofNat candidate.dot))
      dotRead.invariant.recognizer.wellFormed
  have productionAtRhsRead : rhsRead.after.local? 31 =
      some (.signed .i32 (Int.ofNat candidate.production)) :=
    rhsRead.effect.empty_preserves_local
      dotInvariant.chartCursor.recognizer.wellFormed productionAtDotScope
  have dotAtRhsRead : rhsRead.after.local? 32 =
      some (.signed .i32 (Int.ofNat candidate.dot)) :=
    rhsRead.effect.empty_preserves_local
      dotInvariant.chartCursor.recognizer.wellFormed dotAtDotScope
  exact {
    afterProductionRead := productionRead.after
    productionEvaluation := productionEvaluation
    productionEffect := productionRead.effect
    afterProductionWellFormed :=
      productionRead.invariant.recognizer.wellFormed
    afterDotRead := dotRead.after
    dotEvaluation := by simpa [productionScope, productionInvariant] using
      dotEvaluation
    dotEffect := by simpa [productionScope, productionInvariant] using
      dotRead.effect
    afterDotWellFormed := dotRead.invariant.recognizer.wellFormed
    afterRhsLengthRead := rhsRead.after
    rhsLengthEvaluation := by
      simpa [dotScope, dotInvariant, rhsLength] using rhsLengthEvaluation
    rhsLengthEffect := by simpa [dotScope, dotInvariant] using rhsRead.effect
    afterRhsLengthWellFormed := rhsRead.invariant.recognizer.wellFormed
    invariant := by simpa [rhsScope, rhsLength] using rhsInvariant
    productionLocal := by
      exact (bindLocal_preserves_other_local
        rhsRead.invariant.recognizer.wellFormed
        (by decide : 33 ≠ 31)).trans productionAtRhsRead
    dotLocal := by
      exact (bindLocal_preserves_other_local
        rhsRead.invariant.recognizer.wellFormed
        (by decide : 33 ≠ 32)).trans dotAtRhsRead
    rhsLengthLocal := by
      simpa [rhsLength] using bindLocal_finds_local rhsRead.after 33
        (.signed .i32 (Int.ofNat rhsLength))
        rhsRead.invariant.recognizer.wellFormed
  }

/-- Semantic condition implemented by the parent-completion predicate: the
    candidate expects the nonterminal completed by the current state. -/
def ParentCandidateMatches
    (grammar : IndexedGrammar) (candidate : EarleyState) (completedLhs : Nat)
    (productionBound : candidate.key.production < grammar.productionCount) :
    Prop :=
  let production := grammar.productionAt ⟨candidate.production, by
    simpa [EarleyState.key] using productionBound⟩
  candidate.dot < production.rhs.length ∧
    production.rhs[candidate.dot]? =
      some (grammar.grammar.n_kinds + completedLhs)

instance parentCandidateMatchesDecidable
    (grammar : IndexedGrammar) (candidate : EarleyState) (completedLhs : Nat)
    (productionBound : candidate.key.production < grammar.productionCount) :
    Decidable (ParentCandidateMatches grammar candidate completedLhs
      productionBound) := by
  unfold ParentCandidateMatches
  infer_instance

/-- The mechanically reified parent predicate evaluates to the logical
    completion relation, including its source short-circuit around
    `rhs_symbol`. -/
private theorem RecognizerParentLoopInvariant.functional_predicate
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount) :
    let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let environment := parentEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length
      grammar.grammar.n_kinds position completed completedLhs
      (Int.ofNat current)
    let predicateEnvironment := ((environment.push
      (.signed .i32 (Int.ofNat candidate.production))).push
      (.signed .i32 (Int.ofNat candidate.dot))).push
      (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length))
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world predicateEnvironment parentCandidatePredicate =
      .ok (.boolean (decide (ParentCandidateMatches grammar candidate
        completedLhs productionBound)), world) := by
  dsimp only
  let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let environment := parentEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length
    grammar.grammar.n_kinds position completed completedLhs
    (Int.ofNat current)
  have productionBound' : candidate.production < grammar.productionCount := by
    simpa [EarleyState.key] using productionBound
  let production := grammar.productionAt
    ⟨candidate.production, productionBound'⟩
  have productionSame :
      grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩ = production := by
    apply congrArg grammar.productionAt
    exact Fin.ext rfl
  let predicateEnvironment := ((environment.push
    (.signed .i32 (Int.ofNat candidate.production))).push
    (.signed .i32 (Int.ofNat candidate.dot))).push
    (.signed .i32 (Int.ofNat production.rhs.length))
  let machine := parentTermMachine workspaceLayout grammar words grammarCell
  have dotResult : Lanius.FunctionalView.Term.evaluate machine world
      predicateEnvironment (parentSlot ⟨11, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat candidate.dot), world) := by rfl
  have lengthResult : Lanius.FunctionalView.Term.evaluate machine world
      predicateEnvironment (parentSlot ⟨12, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat production.rhs.length), world) := by rfl
  have lessResult := parentLess_evaluates workspaceLayout grammar words
    grammarCell world predicateEnvironment _ _ candidate.dot
    production.rhs.length dotResult lengthResult
  by_cases dotBound : candidate.dot < production.rhs.length
  · have symbolResult := parentRhsSymbolTerm_evaluates
      (tokens := tokens) (tokensCell := tokensCell) workspaceLayout grammar
      words workspaceValues grammarCell workspaceCell predicateEnvironment
      candidate.production candidate.dot productionBound' dotBound
      (by rfl) (by rfl) (by rfl)
    have kindResult : Lanius.FunctionalView.Term.evaluate machine world
        predicateEnvironment (parentSlot ⟨5, by omega⟩) =
        .ok (.signed .i32 (Int.ofNat grammar.grammar.n_kinds), world) := by rfl
    have lhsResult : Lanius.FunctionalView.Term.evaluate machine world
        predicateEnvironment (parentSlot ⟨8, by omega⟩) =
        .ok (.signed .i32 (Int.ofNat completedLhs), world) := by rfl
    have expectedResult := parentAdd_evaluates workspaceLayout grammar words
      grammarCell world predicateEnvironment _ _ grammar.grammar.n_kinds
      completedLhs invariant.expected_symbol_i32 kindResult lhsResult
    let symbol := production.rhs.get ⟨candidate.dot, dotBound⟩
    have equalityResult := parentEqual_evaluates workspaceLayout grammar words
      grammarCell world predicateEnvironment _ _ symbol
      (grammar.grammar.n_kinds + completedLhs)
      (by simpa [machine, production, symbol] using symbolResult)
      expectedResult
    have conjunction := evaluatesLogicalAnd machine world
      predicateEnvironment _ _ (decide (candidate.dot < production.rhs.length))
      (decide (symbol = grammar.grammar.n_kinds + completedLhs))
      lessResult equalityResult
    have selected : production.rhs[candidate.dot]? = some symbol := by
      simpa [symbol] using List.getElem?_eq_getElem dotBound
    have resultValue :
        (decide (candidate.dot < production.rhs.length) &&
          decide (symbol = grammar.grammar.n_kinds + completedLhs)) =
        decide (ParentCandidateMatches grammar candidate completedLhs
          productionBound) := by
      have matchesIff :
          ParentCandidateMatches grammar candidate completedLhs
              productionBound ↔
            symbol = grammar.grammar.n_kinds + completedLhs := by
        simp only [ParentCandidateMatches]
        rw [productionSame]
        constructor
        · intro candidateMatches
          have expectedAt : production.rhs[candidate.dot]? = some
              (grammar.grammar.n_kinds + completedLhs) := candidateMatches.2
          exact Option.some.inj (selected.symm.trans expectedAt)
        · intro symbolMatches
          exact ⟨dotBound, by simpa [symbolMatches] using selected⟩
      by_cases symbolMatches :
          symbol = grammar.grammar.n_kinds + completedLhs
      · have logicalMatches := matchesIff.mpr symbolMatches
        simp [dotBound, symbolMatches, logicalMatches]
      · have logicalDoesNotMatch :
            ¬ ParentCandidateMatches grammar candidate completedLhs
              productionBound := fun contrary =>
          symbolMatches (matchesIff.mp contrary)
        simp [dotBound, symbolMatches, logicalDoesNotMatch]
    rw [resultValue] at conjunction
    simpa [parentCandidatePredicate,
      Lanius.FunctionalView.Core.logicalAnd, world, environment,
      predicateEnvironment, machine, productionSame] using conjunction
  · have conjunction :=
      Lanius.FunctionalView.Term.evaluate_logicalAnd_false
        (right := parentBinary .equal (.scalar .bool) parentRhsSymbolTerm
          (parentBinary .add parserI32Type
            (parentSlot ⟨5, by omega⟩) (parentSlot ⟨8, by omega⟩)))
        (by simpa [dotBound] using lessResult)
    have doesNotMatch : ¬ ParentCandidateMatches grammar candidate completedLhs
        productionBound := by
      simp [ParentCandidateMatches, production, productionBound', dotBound]
    simpa [parentCandidatePredicate,
      Lanius.FunctionalView.Core.logicalAnd, doesNotMatch, world, environment,
      predicateEnvironment, machine, productionSame] using conjunction

/-- Functional evaluation of the state seed emitted for a matching parent. -/
private theorem RecognizerParentLoopInvariant.functional_seed
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount)
    (dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length) :
    let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let environment := parentEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length
      grammar.grammar.n_kinds position completed completedLhs
      (Int.ofNat current)
    let originEnvironment := (((environment.push
      (.signed .i32 (Int.ofNat candidate.production))).push
      (.signed .i32 (Int.ofNat candidate.dot))).push
      (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length))).push
      (.signed .i32 (Int.ofNat candidate.origin))
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world originEnvironment parentSeedTerm =
      .ok (stateSeedValue (recognizerParentSeed candidate.production
        candidate.dot candidate.origin current completed), world) := by
  dsimp only
  let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let environment := parentEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length
    grammar.grammar.n_kinds position completed completedLhs
    (Int.ofNat current)
  have productionBound' : candidate.production < grammar.productionCount := by
    simpa [EarleyState.key] using productionBound
  let production := grammar.productionAt
    ⟨candidate.production, productionBound'⟩
  have productionSame :
      grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩ = production := by
    apply congrArg grammar.productionAt
    exact Fin.ext rfl
  have dotBeforeEnd' : candidate.dot < production.rhs.length := by
    simpa [productionSame] using dotBeforeEnd
  let originEnvironment := (((environment.push
    (.signed .i32 (Int.ofNat candidate.production))).push
    (.signed .i32 (Int.ofNat candidate.dot))).push
    (.signed .i32 (Int.ofNat production.rhs.length))).push
    (.signed .i32 (Int.ofNat candidate.origin))
  let machine := parentTermMachine workspaceLayout grammar words grammarCell
  have productionResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (parentSlot ⟨10, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat candidate.production), world) := by rfl
  have dotResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (parentSlot ⟨11, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat candidate.dot), world) := by rfl
  have oneResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (parentLiteral 1) = .ok (.signed .i32 1, world) := by rfl
  have dotSuccResult := parentAdd_evaluates workspaceLayout grammar words
    grammarCell world originEnvironment _ _ candidate.dot 1
    (invariant.candidate_dot_succ_i32 candidate productionBound dotBeforeEnd)
    dotResult oneResult
  have originResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (parentSlot ⟨13, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat candidate.origin), world) := by rfl
  have parentResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (parentSlot ⟨9, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat current), world) := by rfl
  have childStateReadOnly :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_constant
      (program := verifiedParserCore) (world := world)
      (environment := originEnvironment) (type := parserI32Type)
      verifiedParser_child_state_constant
  have childStateAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell) (world := world) (environment := originEnvironment)
      (parentConstant 39 : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 14) (by native_decide)
  have childStateResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (parentConstant 39 : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 14) =
      .ok (.signed .i32 2, world) := by
    change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
          grammarCell)) world originEnvironment _ = _
    exact childStateAgreement.trans childStateReadOnly
  have completedResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (parentSlot ⟨7, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat completed), world) := by rfl
  have negativeOneReadOnly :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_negate_one
      (program := verifiedParserCore) (world := world)
      (environment := originEnvironment) (inputType := parserI32Type)
      (outputType := parserI32Type)
  have negativeOneAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell) (world := world) (environment := originEnvironment)
      (parentNegativeOne : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 14) (by native_decide)
  have negativeOneResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (parentNegativeOne : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 14) =
      .ok (.signed .i32 (-1), world) := by
    change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
          grammarCell)) world originEnvironment _ = _
    exact negativeOneAgreement.trans negativeOneReadOnly
  let seed := recognizerParentSeed candidate.production candidate.dot
    candidate.origin current completed
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      originEnvironment [
        parentSlot ⟨10, by omega⟩,
        parentBinary .add parserI32Type
          (parentSlot ⟨11, by omega⟩) (parentLiteral 1),
        parentSlot ⟨13, by omega⟩,
        parentSlot ⟨9, by omega⟩,
        parentConstant 39,
        parentSlot ⟨7, by omega⟩,
        parentNegativeOne] =
      .ok (parserStateSeedArgumentsValues seed, world) := by
    simpa [seed, recognizerParentSeed, parserStateSeedArgumentsValues,
      previousValue, encodeStateId, childTag, childPayload, childKind] using
      Lanius.FunctionalView.evaluateTerms_cons productionResult
        (Lanius.FunctionalView.evaluateTerms_cons dotSuccResult
          (Lanius.FunctionalView.evaluateTerms_cons originResult
            (Lanius.FunctionalView.evaluateTerms_cons parentResult
              (Lanius.FunctionalView.evaluateTerms_cons childStateResult
                (Lanius.FunctionalView.evaluateTerms_cons completedResult
                  (Lanius.FunctionalView.evaluateTerms_cons negativeOneResult
                    (Lanius.FunctionalView.evaluateTerms_nil machine world
                      originEnvironment)))))))
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
    grammarCell).evaluate world extractedParserStateSeedFunction.id
      (parserStateSeedArgumentsValues seed) = _
  exact RecognizerTraversalCallRegistry.calls_at_seed world seed

/-- Left-to-right evaluation of the parent `append_state` call arguments. -/
private theorem RecognizerParentLoopInvariant.functional_append_arguments
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount)
    (dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length) :
    let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let environment := parentEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length
      grammar.grammar.n_kinds position completed completedLhs
      (Int.ofNat current)
    let originEnvironment := (((environment.push
      (.signed .i32 (Int.ofNat candidate.production))).push
      (.signed .i32 (Int.ofNat candidate.dot))).push
      (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length))).push
      (.signed .i32 (Int.ofNat candidate.origin))
    let seed := recognizerParentSeed candidate.production candidate.dot
      candidate.origin current completed
    Lanius.FunctionalView.evaluateTerms
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world originEnvironment parentAppendArguments =
      .ok ([workspaceValue workspaceValues workspaceCell,
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
        .signed .i32 (Int.ofNat workspaceLayout.capacity),
        .signed .i32 (Int.ofNat position), stateSeedValue seed,
        .signed .i32 (Int.ofNat workspace.states.length)], world) := by
  dsimp only
  let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let environment := parentEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length
    grammar.grammar.n_kinds position completed completedLhs
    (Int.ofNat current)
  have productionBound' : candidate.production < grammar.productionCount := by
    simpa [EarleyState.key] using productionBound
  let production := grammar.productionAt
    ⟨candidate.production, productionBound'⟩
  have productionSame :
      grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩ = production := by
    apply congrArg grammar.productionAt
    exact Fin.ext rfl
  let originEnvironment := (((environment.push
    (.signed .i32 (Int.ofNat candidate.production))).push
    (.signed .i32 (Int.ofNat candidate.dot))).push
    (.signed .i32 (Int.ofNat production.rhs.length))).push
    (.signed .i32 (Int.ofNat candidate.origin))
  let machine := parentTermMachine workspaceLayout grammar words grammarCell
  have workspaceResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (parentSlot ⟨1, by omega⟩) =
      .ok (workspaceValue workspaceValues workspaceCell, world) := by rfl
  have baseResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (parentSlot ⟨2, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat
        (stateBase workspaceLayout.tokenCount)), world) := by rfl
  have capacityResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (parentSlot ⟨3, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat workspaceLayout.capacity), world) := by rfl
  have positionResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (parentSlot ⟨6, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat position), world) := by rfl
  have seedResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment parentSeedTerm =
      .ok (stateSeedValue (recognizerParentSeed candidate.production
        candidate.dot candidate.origin current completed), world) := by
    simpa [world, environment, originEnvironment, productionSame] using
      invariant.functional_seed candidate productionBound dotBeforeEnd
  have countResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (parentSlot ⟨4, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat workspace.states.length), world) := by rfl
  simpa only [parentAppendArguments] using
    Lanius.FunctionalView.evaluateTerms_cons workspaceResult
      (Lanius.FunctionalView.evaluateTerms_cons baseResult
        (Lanius.FunctionalView.evaluateTerms_cons capacityResult
          (Lanius.FunctionalView.evaluateTerms_cons positionResult
            (Lanius.FunctionalView.evaluateTerms_cons seedResult
              (Lanius.FunctionalView.evaluateTerms_cons countResult
                (Lanius.FunctionalView.evaluateTerms_nil machine world
                  originEnvironment))))))

structure RecognizerParentPredicateResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position completed completedLhs origin current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount) where
  after : State
  evaluation : Evaluates verifiedParserCore before parserRecognizeParentPredicate
    (.boolean (decide (ParentCandidateMatches grammar candidate completedLhs
      productionBound))) after
  effect : ModifiesOnly CellSet.empty before after
  invariant : RecognizerParentLoopInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell after position completed
    completedLhs origin current remaining

/-- Evaluate the extracted short-circuit parent predicate.  The RHS-symbol
    accessor is entered only after `dot < rhs_length` has evaluated true. -/
noncomputable def RecognizerParentCandidateBindings.evaluate_predicate
    (bindings : RecognizerParentCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining beforeInvariant candidate found
      productionBound) :
    RecognizerParentPredicateResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current remaining
      bindings.invariant candidate productionBound := by
  have candidateProductionBound : candidate.production <
      grammar.productionCount := by
    simpa [EarleyState.key] using productionBound
  let productionFin : Fin grammar.productionCount :=
    ⟨candidate.production, candidateProductionBound⟩
  let production := grammar.productionAt productionFin
  let rhsLength := production.rhs.length
  have sourceRhsLengthEq :
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length =
        rhsLength := by
    exact congrArg (fun productionId : Fin grammar.productionCount =>
      (grammar.productionAt productionId).rhs.length) (Fin.ext rfl)
  let bound := bindings.afterRhsLengthRead.bindLocal 33
    (.signed .i32 (Int.ofNat rhsLength))
  have dotResult : Evaluates verifiedParserCore bound (.local 32)
      (.signed .i32 (Int.ofNat candidate.dot)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 32 _
      (by simpa [bound, rhsLength, production, productionFin] using
        bindings.dotLocal)⟩
  have lengthResult : Evaluates verifiedParserCore bound (.local 33)
      (.signed .i32 (Int.ofNat rhsLength)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 33 _
      (by simpa [bound, rhsLength, production, productionFin] using
        bindings.rhsLengthLocal)⟩
  have lessEvaluation := evaluatesNatLessThreaded bound bound bound
    (.local 32) (.local 33) candidate.dot rhsLength dotResult lengthResult
  by_cases dotMatches : candidate.dot < rhsLength
  · have lessTrue : Evaluates verifiedParserCore bound
        (.binary .less (.local 32) (.local 33)) (.boolean true) bound := by
      simpa [dotMatches] using lessEvaluation
    have productionResult : Evaluates verifiedParserCore bound (.local 31)
        (.signed .i32 (Int.ofNat candidate.production)) bound :=
      ⟨1, evalLocal_of_local 1 verifiedParserCore bound 31 _
        (by simpa [bound, rhsLength, production, productionFin] using
          bindings.productionLocal)⟩
    let rhsRead := bindings.invariant.chartCursor.read_rhs_symbol
      candidate.production candidateProductionBound candidate.dot
      (by simpa [rhsLength, production, productionFin] using dotMatches)
      (.local 31) (.local 32) productionResult dotResult
    let symbol := production.rhs.get ⟨candidate.dot, dotMatches⟩
    have sourceRhsEq :
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs =
          production.rhs := by
      exact congrArg (fun productionId : Fin grammar.productionCount =>
        (grammar.productionAt productionId).rhs) (Fin.ext rfl)
    have sourceSymbolEq :
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.get
            ⟨candidate.dot, by simpa [rhsLength, production, productionFin]
              using dotMatches⟩ = symbol := by
      simp only [List.get_eq_getElem, symbol]
      exact getElem_congr
        (valid := fun (values : List Nat) index => index < values.length)
        sourceRhsEq rfl (by
          simpa [rhsLength, production, productionFin] using dotMatches)
    have sourceSymbolGetElemEq :
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs[candidate.dot] =
          symbol := by
      simpa only [List.get_eq_getElem] using sourceSymbolEq
    have symbolEvaluation : Evaluates verifiedParserCore bound
        (.call extractedParserRhsSymbolFunction.id
        [.local 0, .local 31, .local 32])
        (.signed .i32 (Int.ofNat symbol)) rhsRead.after := by
      simpa [bound, sourceRhsLengthEq, sourceSymbolEq, symbol, production,
        productionFin] using rhsRead.evaluation
    let afterReadInvariant := bindings.invariant.after_empty_effect
      rhsRead.effect rhsRead.invariant.recognizer.wellFormed
    have kindCountAtRead : rhsRead.after.local? 11 =
        some (.signed .i32 (Int.ofNat grammar.grammar.n_kinds)) :=
      rhsRead.effect.empty_preserves_local
        bindings.invariant.chartCursor.recognizer.wellFormed
        bindings.invariant.kindCountLocal
    have completedLhsAtRead : rhsRead.after.local? 29 =
        some (.signed .i32 (Int.ofNat completedLhs)) :=
      rhsRead.effect.empty_preserves_local
        bindings.invariant.chartCursor.recognizer.wellFormed
        bindings.invariant.completedLhsLocal
    have kindCountResult : Evaluates verifiedParserCore rhsRead.after (.local 11)
        (.signed .i32 (Int.ofNat grammar.grammar.n_kinds)) rhsRead.after :=
      ⟨1, evalLocal_of_local 1 verifiedParserCore rhsRead.after 11 _
        kindCountAtRead⟩
    have completedLhsResult : Evaluates verifiedParserCore rhsRead.after
        (.local 29) (.signed .i32 (Int.ofNat completedLhs)) rhsRead.after :=
      ⟨1, evalLocal_of_local 1 verifiedParserCore rhsRead.after 29 _
        completedLhsAtRead⟩
    have expectedResult : Evaluates verifiedParserCore rhsRead.after
        (.binary .add (.local 11) (.local 29))
        (.signed .i32 (Int.ofNat
          (grammar.grammar.n_kinds + completedLhs))) rhsRead.after := by
      have castSum : Int.ofNat grammar.grammar.n_kinds +
          Int.ofNat completedLhs =
          Int.ofNat (grammar.grammar.n_kinds + completedLhs) :=
        (Int.natCast_add _ _).symm
      have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target _
        bindings.invariant.expected_symbol_i32
      apply evaluatesEagerBinary (by decide) (by decide) kindCountResult
        completedLhsResult
      simp only [evalBinaryValue, evalSignedBinary]
      rw [castSum, wrapped]
      simp
    have equalityEvaluation := evaluatesNatEqualityThreaded bound rhsRead.after
      rhsRead.after
      (.call extractedParserRhsSymbolFunction.id
        [.local 0, .local 31, .local 32])
      (.binary .add (.local 11) (.local 29)) symbol
      (grammar.grammar.n_kinds + completedLhs) symbolEvaluation expectedResult
    have predicateEvaluation := evaluatesLogicalAndTrue lessTrue
      equalityEvaluation
    exact {
      after := rhsRead.after
      evaluation := by
        rw [extractedParserRecognize_parent_predicate_shape]
        have selected : production.rhs[candidate.dot]? = some symbol := by
          simpa [symbol] using List.getElem?_eq_getElem dotMatches
        have resultValue : decide (ParentCandidateMatches grammar candidate
            completedLhs productionBound) =
            decide (symbol = grammar.grammar.n_kinds + completedLhs) := by
          have matchIff : ParentCandidateMatches grammar candidate completedLhs
              productionBound ↔
              symbol = grammar.grammar.n_kinds + completedLhs := by
            simp [ParentCandidateMatches, production, productionFin, rhsLength,
              dotMatches]
            rw [sourceSymbolGetElemEq]
          simpa only [matchIff]
        rw [resultValue]
        exact predicateEvaluation
      effect := rhsRead.effect
      invariant := by
        simpa [bound, rhsLength, production, productionFin] using
          afterReadInvariant
    }
  · have lessFalse : Evaluates verifiedParserCore bound
        (.binary .less (.local 32) (.local 33)) (.boolean false) bound := by
      simpa [dotMatches] using lessEvaluation
    have predicateEvaluation := evaluatesLogicalAndFalse
      (right := .binary .equal
        (.call extractedParserRhsSymbolFunction.id
          [.local 0, .local 31, .local 32])
        (.binary .add (.local 11) (.local 29))) lessFalse
    exact {
      after := bound
      evaluation := by
        rw [extractedParserRecognize_parent_predicate_shape]
        have resultValue : decide (ParentCandidateMatches grammar candidate
            completedLhs productionBound) = false := by
          simp [ParentCandidateMatches, production, productionFin, rhsLength,
            dotMatches]
        rw [resultValue]
        exact predicateEvaluation
      effect := ModifiesOnly.reflAny CellSet.empty bound
      invariant := by
        simpa [bound, rhsLength, production, productionFin] using
          bindings.invariant
    }

structure RecognizerParentNoMatchAdvance
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position completed completedLhs origin current next : Nat)
    (tail : List Nat)
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current (next :: tail))
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current (next :: tail) beforeInvariant candidate
      productionBound)
    (notMatches : ¬ ParentCandidateMatches grammar candidate completedLhs
      productionBound) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeParentAfterBindings .next after
  effect : ModifiesOnly (CellSet.singleton cursorCell) before after
  invariant : RecognizerParentLoopInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell after position completed
    completedLhs origin next tail

structure RecognizerParentNoMatchFinish
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position completed completedLhs origin current : Nat)
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current [])
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current [] beforeInvariant candidate productionBound)
    (notMatches : ¬ ParentCandidateMatches grammar candidate completedLhs
      productionBound) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeParentAfterBindings .next after
  effect : ModifiesOnly (CellSet.singleton cursorCell) before after
  invariant : RecognizerParentFinishedInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell after position completed
    completedLhs origin

noncomputable def RecognizerParentPredicateResult.advance_no_match
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current (next :: tail) beforeInvariant candidate
      productionBound)
    (notMatches : ¬ ParentCandidateMatches grammar candidate completedLhs
      productionBound) :
    RecognizerParentNoMatchAdvance grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current next tail beforeInvariant candidate
      productionBound predicate notMatches := by
  have conditionFalse : Evaluates verifiedParserCore runtime
      parserRecognizeParentPredicate (.boolean false) predicate.after := by
    simpa [notMatches] using predicate.evaluation
  have selected : Executes verifiedParserCore runtime
      (.ifThenElse parserRecognizeParentPredicate
        parserRecognizeParentMatchedBody .skip) .next predicate.after :=
    executesIfFalse conditionFalse (executesSkip verifiedParserCore _)
  let advanced := predicate.invariant.chartCursor.advance
  let nextInvariant := predicate.invariant.after_cursor_effect
    advanced.invariant advanced.effect
  exact {
    after := advanced.after
    execution := by
      rw [extractedParserRecognize_parent_after_bindings_shape]
      exact executesSequence selected advanced.execution
    effect := by
      simpa using (predicate.effect.weaken CellSet.empty_subset).trans_same
        advanced.effect
    invariant := nextInvariant
  }

noncomputable def RecognizerParentPredicateResult.finish_no_match
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current [] beforeInvariant candidate productionBound)
    (notMatches : ¬ ParentCandidateMatches grammar candidate completedLhs
      productionBound) :
    RecognizerParentNoMatchFinish grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current beforeInvariant candidate productionBound
      predicate notMatches := by
  have conditionFalse : Evaluates verifiedParserCore runtime
      parserRecognizeParentPredicate (.boolean false) predicate.after := by
    simpa [notMatches] using predicate.evaluation
  have selected : Executes verifiedParserCore runtime
      (.ifThenElse parserRecognizeParentPredicate
        parserRecognizeParentMatchedBody .skip) .next predicate.after :=
    executesIfFalse conditionFalse (executesSkip verifiedParserCore _)
  let exhausted := predicate.invariant.chartCursor.exhaust
  let finished := predicate.invariant.after_cursor_exhaustion
    exhausted.finished exhausted.effect
  exact {
    after := exhausted.after
    execution := by
      rw [extractedParserRecognize_parent_after_bindings_shape]
      exact executesSequence selected exhausted.execution
    effect := by
      simpa using (predicate.effect.weaken CellSet.empty_subset).trans_same
        exhausted.effect
    invariant := finished
  }

/-- Close the three candidate bindings around one parent-completion action. -/
structure RecognizerParentScopedExecution
    (before innerAfter : State) (completion : Completion) (writes : CellSet)
    (candidate : EarleyState)
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount)
    (bindings : RecognizerParentCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining beforeInvariant candidate found
      productionBound) where
  after : State
  execution : Executes verifiedParserCore before parserRecognizeParentLoopBody
    completion after
  effect : ModifiesOnly writes before after
  wellFormed : StateWellFormed after
  cells : after.cells = innerAfter.cells

noncomputable def RecognizerParentCandidateBindings.close_scopes
    (bindings : RecognizerParentCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining beforeInvariant candidate found
      productionBound)
    (innerAfter : State) (completion : Completion) (writes : CellSet)
    (innerExecution : Executes verifiedParserCore
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      parserRecognizeParentAfterBindings completion innerAfter)
    (innerEffect : ModifiesOnly writes
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      innerAfter)
    (innerWellFormed : StateWellFormed innerAfter) :
    RecognizerParentScopedExecution runtime innerAfter completion writes
      candidate beforeInvariant found productionBound bindings := by
  let rhsLength := (grammar.productionAt ⟨candidate.production, by
    simpa [EarleyState.key] using productionBound⟩).rhs.length
  let productionScope := bindings.afterProductionRead.bindLocal 31
    (.signed .i32 (Int.ofNat candidate.production))
  let dotScope := bindings.afterDotRead.bindLocal 32
    (.signed .i32 (Int.ofNat candidate.dot))
  let rhsScope := bindings.afterRhsLengthRead.bindLocal 33
    (.signed .i32 (Int.ofNat rhsLength))
  let afterRhs := restoreLocals bindings.afterRhsLengthRead innerAfter
  let afterDot := restoreLocals bindings.afterDotRead afterRhs
  let afterProduction := restoreLocals bindings.afterProductionRead afterDot
  have enteredRhs : StoreEffect CellSet.empty bindings.afterRhsLengthRead
      rhsScope := by
    simpa [rhsScope] using bindLocal_effect bindings.afterRhsLengthRead 33
      (.signed .i32 (Int.ofNat rhsLength))
  have rhsScopeEffect : StoreEffect writes bindings.afterRhsLengthRead
      innerAfter :=
    (enteredRhs.weaken CellSet.empty_subset).trans_same
      (by simpa [rhsScope, rhsLength] using innerEffect.toStoreEffect)
  have closedRhs : ModifiesOnly writes bindings.afterRhsLengthRead afterRhs := by
    simpa [afterRhs] using rhsScopeEffect.restoreLocals
  have afterRhsWellFormed : StateWellFormed afterRhs :=
    rhsScopeEffect.restoreLocals_wellFormed
      bindings.afterRhsLengthWellFormed innerWellFormed
  have rhsBodyEffect : ModifiesOnly writes dotScope afterRhs :=
    (bindings.rhsLengthEffect.weaken CellSet.empty_subset).trans_same closedRhs
  have enteredDot : StoreEffect CellSet.empty bindings.afterDotRead dotScope := by
    simpa [dotScope] using bindLocal_effect bindings.afterDotRead 32
      (.signed .i32 (Int.ofNat candidate.dot))
  have dotScopeEffect : StoreEffect writes bindings.afterDotRead afterRhs :=
    (enteredDot.weaken CellSet.empty_subset).trans_same
      rhsBodyEffect.toStoreEffect
  have closedDot : ModifiesOnly writes bindings.afterDotRead afterDot := by
    simpa [afterDot] using dotScopeEffect.restoreLocals
  have afterDotWellFormed : StateWellFormed afterDot :=
    dotScopeEffect.restoreLocals_wellFormed bindings.afterDotWellFormed
      afterRhsWellFormed
  have dotBodyEffect : ModifiesOnly writes productionScope afterDot :=
    (bindings.dotEffect.weaken CellSet.empty_subset).trans_same closedDot
  have enteredProduction : StoreEffect CellSet.empty
      bindings.afterProductionRead productionScope := by
    simpa [productionScope] using bindLocal_effect bindings.afterProductionRead
      31 (.signed .i32 (Int.ofNat candidate.production))
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
  have rhsExecution : Executes verifiedParserCore dotScope
      (.letLocal 33 parserI32Type
        (.call extractedParserRhsLengthFunction.id [.local 0, .local 31])
        parserRecognizeParentAfterBindings) completion afterRhs := by
    simpa [dotScope, rhsScope, rhsLength, afterRhs] using
      executesLetLocal (type := parserI32Type) bindings.rhsLengthEvaluation
        innerExecution
  have dotExecution : Executes verifiedParserCore productionScope
      (.letLocal 32 parserI32Type (parserRecognizeStateValueCall 30 29)
        (.letLocal 33 parserI32Type
          (.call extractedParserRhsLengthFunction.id [.local 0, .local 31])
          parserRecognizeParentAfterBindings)) completion afterDot := by
    simpa [productionScope, dotScope, afterDot] using
      executesLetLocal (type := parserI32Type) bindings.dotEvaluation rhsExecution
  have productionExecution : Executes verifiedParserCore runtime
      (.letLocal 31 parserI32Type (parserRecognizeStateValueCall 30 28)
        (.letLocal 32 parserI32Type (parserRecognizeStateValueCall 30 29)
          (.letLocal 33 parserI32Type
            (.call extractedParserRhsLengthFunction.id [.local 0, .local 31])
            parserRecognizeParentAfterBindings))) completion afterProduction := by
    simpa [productionScope, afterProduction] using
      executesLetLocal (type := parserI32Type) bindings.productionEvaluation
        dotExecution
  exact {
    after := afterProduction
    execution := by
      rw [extractedParserRecognize_parent_body_shape]
      exact productionExecution
    effect := outerEffect
    wellFormed := afterProductionWellFormed
    cells := by
      simp [afterProduction, afterDot, afterRhs, restoreLocals]
  }

def RecognizerParentScopedExecution.restore_invariant
    (closed : RecognizerParentScopedExecution
      (grammarLayout := grammarLayout) (grammar := grammar) (words := words)
      (tokens := tokens) (workspaceLayout := workspaceLayout)
      (workspace := workspace) (workspaceValues := workspaceValues)
      (grammarCell := grammarCell) (tokensCell := tokensCell)
      (workspaceCell := workspaceCell) (stateCountCell := stateCountCell)
      (cursorCell := cursorCell) (position := position)
      (completed := completed) (completedLhs := completedLhs)
      (origin := origin) (current := current) (remaining := remaining)
      runtime innerAfter completion writes candidate beforeInvariant found
      productionBound bindings)
    (innerInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout nextWorkspace nextWorkspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell innerAfter position
      completed completedLhs origin nextCurrent nextRemaining)
    (writesMutable : CellSet.Subset writes
      (CellSet.union (CellSet.singleton workspaceCell)
        (CellSet.union (CellSet.singleton stateCountCell)
          (CellSet.singleton cursorCell)))) :
    RecognizerParentLoopInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextWorkspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell closed.after position completed
      completedLhs origin nextCurrent nextRemaining := by
  have preserveLocal (id : VarId) (persistent : ParentPersistentLocal id)
      (notStateCount : id ≠ 18) (value : Value)
      (foundLocal : runtime.local? id = some value) :
      closed.after.local? id = some value :=
    closed.effect.preserves_local_of_disjoint
      beforeInvariant.chartCursor.recognizer.wellFormed
      (CellSet.Disjoint.mono_right writesMutable
        beforeInvariant.persistentSeparate)
      ((ParentPreservedLocal_source_frame id).mp
        ((ParentPreservedLocal_iff id).mpr
          ⟨persistent, notStateCount⟩)) foundLocal
  have entryTransferred (cell : CellId) (entry : Cell)
      (innerEntry : innerAfter.cellEntry? cell = some entry) :
      closed.after.cellEntry? cell = some entry := by
    unfold State.cellEntry? at innerEntry ⊢
    rw [closed.cells]
    exact innerEntry
  have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))).holds
      closed.after := by
    constructor
    · unfold State.cellId?
      rw [closed.effect.locals]
      exact beforeInvariant.appendFrame.stateCountOwned.1
    · exact entryTransferred stateCountCell _
        innerInvariant.appendFrame.stateCountOwned.2
  have cursorOwned : (Assertion.localPointsTo 30 cursorCell
      (some (.signed .i32 (Int.ofNat nextCurrent)))).holds closed.after := by
    constructor
    · unfold State.cellId?
      rw [closed.effect.locals]
      exact beforeInvariant.chartCursor.cursorOwned.1
    · exact entryTransferred cursorCell _
        innerInvariant.chartCursor.cursorOwned.2
  have recognizer : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextWorkspaceValues grammarCell tokensCell
      workspaceCell closed.after := {
    grammarEncoded := innerInvariant.chartCursor.recognizer.grammarEncoded
    grammarWellFormed := innerInvariant.chartCursor.recognizer.grammarWellFormed
    wordsI32 := innerInvariant.chartCursor.recognizer.wordsI32
    tokensI32 := innerInvariant.chartCursor.recognizer.tokensI32
    workspaceLength := innerInvariant.chartCursor.recognizer.workspaceLength
    workspaceTokenCount :=
      innerInvariant.chartCursor.recognizer.workspaceTokenCount
    workspaceEncoded := innerInvariant.chartCursor.recognizer.workspaceEncoded
    derivations := innerInvariant.chartCursor.recognizer.derivations
    wellFormed := closed.wellFormed
    grammarLocal := preserveLocal 0 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.grammarLocal
    grammarLengthLocal := preserveLocal 1 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.grammarLengthLocal
    tokensLocal := preserveLocal 2 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.tokensLocal
    tokenCountLocal := preserveLocal 3 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.tokenCountLocal
    workspaceLocal := by
      have preserved := preserveLocal 4 (by
        simp [ParentPersistentLocal]) (by decide) _
        beforeInvariant.chartCursor.recognizer.workspaceLocal
      simpa [workspaceValue,
        beforeInvariant.chartCursor.recognizer.workspaceLength,
        innerInvariant.chartCursor.recognizer.workspaceLength] using preserved
    workspaceLengthLocal := by
      have preserved := preserveLocal 5 (by
        simp [ParentPersistentLocal]) (by decide) _
        beforeInvariant.chartCursor.recognizer.workspaceLengthLocal
      simpa [beforeInvariant.chartCursor.recognizer.workspaceLength,
        innerInvariant.chartCursor.recognizer.workspaceLength] using preserved
    grammarBacking := entryTransferred grammarCell _
      innerInvariant.chartCursor.recognizer.grammarBacking
    tokensBacking := entryTransferred tokensCell _
      innerInvariant.chartCursor.recognizer.tokensBacking
    workspaceBacking := entryTransferred workspaceCell _
      innerInvariant.chartCursor.recognizer.workspaceBacking
    grammarWorkspaceDistinct :=
      innerInvariant.chartCursor.recognizer.grammarWorkspaceDistinct
    tokensWorkspaceDistinct :=
      innerInvariant.chartCursor.recognizer.tokensWorkspaceDistinct
  }
  exact {
    chartCursor := {
      recognizer := recognizer
      workspaceWithinGrammar :=
        innerInvariant.chartCursor.workspaceWithinGrammar
      stateBaseLocal := preserveLocal 8 (by
        simp [ParentPersistentLocal]) (by decide) _
        beforeInvariant.chartCursor.stateBaseLocal
      cursorOwned := cursorOwned
      cursorFrameSeparate := by
        unfold ChartCursorFrameSeparated
        rw [closed.effect.localBindingFrameFootprint_eq
          verifiedParserChartCursorBindings]
        exact beforeInvariant.chartCursor.cursorFrameSeparate
      cursorBackingDistinct :=
        beforeInvariant.chartCursor.cursorBackingDistinct
      chartPositionBound := innerInvariant.chartCursor.chartPositionBound
      cursor := innerInvariant.chartCursor.cursor
    }
    appendFrame := {
      recognizer := recognizer
      positionBound := innerInvariant.appendFrame.positionBound
      stateBaseLocal := preserveLocal 8 (by
        simp [ParentPersistentLocal]) (by decide) _
        beforeInvariant.appendFrame.stateBaseLocal
      stateCapacityLocal := preserveLocal 9 (by
        simp [ParentPersistentLocal]) (by decide) _
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
    kindCountLocal := preserveLocal 11 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.kindCountLocal
    positionLocal := preserveLocal 23 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.positionLocal
    completedLocal := preserveLocal 24 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.completedLocal
    completedLhsLocal := preserveLocal 29 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.completedLhsLocal
    completedLhsBound := beforeInvariant.completedLhsBound
    completedRecognizes := beforeInvariant.completedRecognizes
    completedStored := innerInvariant.completedStored
    persistentSeparate := by
      unfold ParentFrameSeparated
      rw [closed.effect.localBindingFrameFootprint_eq
        verifiedParserParentPreservedBindings]
      exact beforeInvariant.persistentSeparate
    cursorStateCountDistinct := beforeInvariant.cursorStateCountDistinct
  }

def RecognizerParentScopedExecution.restore_finished
    (closed : RecognizerParentScopedExecution
      (grammarLayout := grammarLayout) (grammar := grammar) (words := words)
      (tokens := tokens) (workspaceLayout := workspaceLayout)
      (workspace := workspace) (workspaceValues := workspaceValues)
      (grammarCell := grammarCell) (tokensCell := tokensCell)
      (workspaceCell := workspaceCell) (stateCountCell := stateCountCell)
      (cursorCell := cursorCell) (position := position)
      (completed := completed) (completedLhs := completedLhs)
      (origin := origin) (current := current) (remaining := remaining)
      runtime innerAfter completion writes candidate beforeInvariant found
      productionBound bindings)
    (innerInvariant : RecognizerParentFinishedInvariant grammarLayout grammar
      words tokens workspaceLayout nextWorkspace nextWorkspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell innerAfter position
      completed completedLhs origin)
    (writesMutable : CellSet.Subset writes
      (CellSet.union (CellSet.singleton workspaceCell)
        (CellSet.union (CellSet.singleton stateCountCell)
          (CellSet.singleton cursorCell)))) :
    RecognizerParentFinishedInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextWorkspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell closed.after position completed
      completedLhs origin := by
  have preserveLocal (id : VarId) (persistent : ParentPersistentLocal id)
      (notStateCount : id ≠ 18) (value : Value)
      (foundLocal : runtime.local? id = some value) :
      closed.after.local? id = some value :=
    closed.effect.preserves_local_of_disjoint
      beforeInvariant.chartCursor.recognizer.wellFormed
      (CellSet.Disjoint.mono_right writesMutable
        beforeInvariant.persistentSeparate)
      ((ParentPreservedLocal_source_frame id).mp
        ((ParentPreservedLocal_iff id).mpr
          ⟨persistent, notStateCount⟩)) foundLocal
  have entryTransferred (cell : CellId) (entry : Cell)
      (innerEntry : innerAfter.cellEntry? cell = some entry) :
      closed.after.cellEntry? cell = some entry := by
    unfold State.cellEntry? at innerEntry ⊢
    rw [closed.cells]
    exact innerEntry
  have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))).holds
      closed.after := by
    constructor
    · unfold State.cellId?
      rw [closed.effect.locals]
      exact beforeInvariant.appendFrame.stateCountOwned.1
    · exact entryTransferred stateCountCell _
        innerInvariant.appendFrame.stateCountOwned.2
  have cursorOwned : (Assertion.localPointsTo 30 cursorCell
      (some (.signed .i32 (-1)))).holds closed.after := by
    constructor
    · unfold State.cellId?
      rw [closed.effect.locals]
      exact beforeInvariant.chartCursor.cursorOwned.1
    · exact entryTransferred cursorCell _
        innerInvariant.chartCursor.cursorOwned.2
  have recognizer : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextWorkspaceValues grammarCell tokensCell
      workspaceCell closed.after := {
    grammarEncoded := innerInvariant.chartCursor.recognizer.grammarEncoded
    grammarWellFormed := innerInvariant.chartCursor.recognizer.grammarWellFormed
    wordsI32 := innerInvariant.chartCursor.recognizer.wordsI32
    tokensI32 := innerInvariant.chartCursor.recognizer.tokensI32
    workspaceLength := innerInvariant.chartCursor.recognizer.workspaceLength
    workspaceTokenCount :=
      innerInvariant.chartCursor.recognizer.workspaceTokenCount
    workspaceEncoded := innerInvariant.chartCursor.recognizer.workspaceEncoded
    derivations := innerInvariant.chartCursor.recognizer.derivations
    wellFormed := closed.wellFormed
    grammarLocal := preserveLocal 0 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.grammarLocal
    grammarLengthLocal := preserveLocal 1 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.grammarLengthLocal
    tokensLocal := preserveLocal 2 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.tokensLocal
    tokenCountLocal := preserveLocal 3 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.tokenCountLocal
    workspaceLocal := by
      have preserved := preserveLocal 4 (by
        simp [ParentPersistentLocal]) (by decide) _
        beforeInvariant.chartCursor.recognizer.workspaceLocal
      simpa [workspaceValue,
        beforeInvariant.chartCursor.recognizer.workspaceLength,
        innerInvariant.chartCursor.recognizer.workspaceLength] using preserved
    workspaceLengthLocal := by
      have preserved := preserveLocal 5 (by
        simp [ParentPersistentLocal]) (by decide) _
        beforeInvariant.chartCursor.recognizer.workspaceLengthLocal
      simpa [beforeInvariant.chartCursor.recognizer.workspaceLength,
        innerInvariant.chartCursor.recognizer.workspaceLength] using preserved
    grammarBacking := entryTransferred grammarCell _
      innerInvariant.chartCursor.recognizer.grammarBacking
    tokensBacking := entryTransferred tokensCell _
      innerInvariant.chartCursor.recognizer.tokensBacking
    workspaceBacking := entryTransferred workspaceCell _
      innerInvariant.chartCursor.recognizer.workspaceBacking
    grammarWorkspaceDistinct :=
      innerInvariant.chartCursor.recognizer.grammarWorkspaceDistinct
    tokensWorkspaceDistinct :=
      innerInvariant.chartCursor.recognizer.tokensWorkspaceDistinct
  }
  exact {
    chartCursor := {
      recognizer := recognizer
      workspaceWithinGrammar :=
        innerInvariant.chartCursor.workspaceWithinGrammar
      stateBaseLocal := preserveLocal 8 (by
        simp [ParentPersistentLocal]) (by decide) _
        beforeInvariant.chartCursor.stateBaseLocal
      cursorOwned := cursorOwned
      cursorFrameSeparate := by
        unfold ChartCursorFrameSeparated
        rw [closed.effect.localBindingFrameFootprint_eq
          verifiedParserChartCursorBindings]
        exact beforeInvariant.chartCursor.cursorFrameSeparate
      cursorBackingDistinct :=
        beforeInvariant.chartCursor.cursorBackingDistinct
      chartPositionBound := innerInvariant.chartCursor.chartPositionBound
    }
    appendFrame := {
      recognizer := recognizer
      positionBound := innerInvariant.appendFrame.positionBound
      stateBaseLocal := preserveLocal 8 (by
        simp [ParentPersistentLocal]) (by decide) _
        beforeInvariant.appendFrame.stateBaseLocal
      stateCapacityLocal := preserveLocal 9 (by
        simp [ParentPersistentLocal]) (by decide) _
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
    kindCountLocal := preserveLocal 11 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.kindCountLocal
    positionLocal := preserveLocal 23 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.positionLocal
    completedLocal := preserveLocal 24 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.completedLocal
    completedLhsLocal := preserveLocal 29 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeInvariant.completedLhsLocal
    completedLhsBound := beforeInvariant.completedLhsBound
    completedRecognizes := beforeInvariant.completedRecognizes
    completedStored := innerInvariant.completedStored
    persistentSeparate := by
      unfold ParentFrameSeparated
      rw [closed.effect.localBindingFrameFootprint_eq
        verifiedParserParentPreservedBindings]
      exact beforeInvariant.persistentSeparate
    cursorStateCountDistinct := beforeInvariant.cursorStateCountDistinct
  }

noncomputable def RecognizerParentCandidateBindings.close_no_match_advance
    (bindings : RecognizerParentCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current (next :: tail) beforeInvariant candidate found
      productionBound)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current (next :: tail)
      bindings.invariant candidate productionBound)
    (notMatches : ¬ ParentCandidateMatches grammar candidate completedLhs
      productionBound) :
    let advanced := predicate.advance_no_match notMatches
    RecognizerParentScopedExecution runtime advanced.after .next
      (CellSet.singleton cursorCell) candidate beforeInvariant found
      productionBound bindings := by
  dsimp only
  let advanced := predicate.advance_no_match notMatches
  exact bindings.close_scopes advanced.after .next
    (CellSet.singleton cursorCell) advanced.execution advanced.effect
    advanced.invariant.chartCursor.recognizer.wellFormed

noncomputable def RecognizerParentCandidateBindings.after_no_match_advance
    (bindings : RecognizerParentCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current (next :: tail) beforeInvariant candidate found
      productionBound)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current (next :: tail)
      bindings.invariant candidate productionBound)
    (notMatches : ¬ ParentCandidateMatches grammar candidate completedLhs
      productionBound) :
    let closed := bindings.close_no_match_advance predicate notMatches
    RecognizerParentLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell closed.after position completed
      completedLhs origin next tail := by
  dsimp only
  let advanced := predicate.advance_no_match notMatches
  let closed := bindings.close_scopes advanced.after .next
    (CellSet.singleton cursorCell) advanced.execution advanced.effect
    advanced.invariant.chartCursor.recognizer.wellFormed
  exact closed.restore_invariant advanced.invariant (by
    intro cell written
    exact .inr (.inr written))

noncomputable def RecognizerParentCandidateBindings.close_no_match_finish
    (bindings : RecognizerParentCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current [] beforeInvariant candidate found
      productionBound)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current [] bindings.invariant
      candidate productionBound)
    (notMatches : ¬ ParentCandidateMatches grammar candidate completedLhs
      productionBound) :
    let finished := predicate.finish_no_match notMatches
    RecognizerParentScopedExecution runtime finished.after .next
      (CellSet.singleton cursorCell) candidate beforeInvariant found
      productionBound bindings := by
  dsimp only
  let finished := predicate.finish_no_match notMatches
  exact bindings.close_scopes finished.after .next
    (CellSet.singleton cursorCell) finished.execution finished.effect
    finished.invariant.chartCursor.recognizer.wellFormed

noncomputable def RecognizerParentCandidateBindings.after_no_match_finish
    (bindings : RecognizerParentCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current [] beforeInvariant candidate found
      productionBound)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current [] bindings.invariant
      candidate productionBound)
    (notMatches : ¬ ParentCandidateMatches grammar candidate completedLhs
      productionBound) :
    let closed := bindings.close_no_match_finish predicate notMatches
    RecognizerParentFinishedInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell closed.after position completed
      completedLhs origin := by
  dsimp only
  let finished := predicate.finish_no_match notMatches
  let closed := bindings.close_scopes finished.after .next
    (CellSet.singleton cursorCell) finished.execution finished.effect
    finished.invariant.chartCursor.recognizer.wellFormed
  exact closed.restore_finished finished.invariant (by
    intro cell written
    exact .inr (.inr written))

/-- The matched branch's `parent_origin` binding and the append contract it
    establishes in that lexical scope. -/
structure RecognizerParentMatchedOriginBinding
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position completed completedLhs origin current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining beforeInvariant candidate
      productionBound)
    (doesMatch : ParentCandidateMatches grammar candidate completedLhs
      productionBound) where
  afterOriginRead : State
  originEvaluation : Evaluates verifiedParserCore predicate.after
    (parserRecognizeStateValueCall 30 30)
    (.signed .i32 (Int.ofNat candidate.origin)) afterOriginRead
  originEffect : ModifiesOnly CellSet.empty predicate.after afterOriginRead
  afterOriginWellFormed : StateWellFormed afterOriginRead
  invariant : RecognizerParentLoopInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell
    (afterOriginRead.bindLocal 34
      (.signed .i32 (Int.ofNat candidate.origin)))
    position completed completedLhs origin current remaining
  appendInvariant : RecognizerParentAppendInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell
    (afterOriginRead.bindLocal 34
      (.signed .i32 (Int.ofNat candidate.origin)))
    position candidate.production candidate.dot candidate.origin current
    completed

noncomputable def RecognizerParentCandidateBindings.bind_matched_origin
    (bindings : RecognizerParentCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining beforeInvariant candidate found
      productionBound)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current remaining
      bindings.invariant candidate productionBound)
    (doesMatch : ParentCandidateMatches grammar candidate completedLhs
      productionBound) :
    RecognizerParentMatchedOriginBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current remaining
      bindings.invariant candidate found productionBound predicate doesMatch := by
  let originRead := predicate.invariant.chartCursor.read_origin candidate found
  have originEvaluation : Evaluates verifiedParserCore predicate.after
      (parserRecognizeStateValueCall 30 30)
      (.signed .i32 (Int.ofNat candidate.origin)) originRead.after := by
    simpa [stateFieldValue] using originRead.evaluation
  let afterOrigin := predicate.invariant.after_empty_effect originRead.effect
    originRead.invariant.recognizer.wellFormed
  let originScope := originRead.after.bindLocal 34
    (.signed .i32 (Int.ofNat candidate.origin))
  let originInvariant := afterOrigin.after_bind_local 34
    (.signed .i32 (Int.ofNat candidate.origin)) (by decide)
  have productionAtPredicate : predicate.after.local? 31 =
      some (.signed .i32 (Int.ofNat candidate.production)) :=
    predicate.effect.empty_preserves_local
      bindings.invariant.chartCursor.recognizer.wellFormed
      bindings.productionLocal
  have dotAtPredicate : predicate.after.local? 32 =
      some (.signed .i32 (Int.ofNat candidate.dot)) :=
    predicate.effect.empty_preserves_local
      bindings.invariant.chartCursor.recognizer.wellFormed bindings.dotLocal
  have productionAtOriginRead : originRead.after.local? 31 =
      some (.signed .i32 (Int.ofNat candidate.production)) :=
    originRead.effect.empty_preserves_local
      predicate.invariant.chartCursor.recognizer.wellFormed
      productionAtPredicate
  have dotAtOriginRead : originRead.after.local? 32 =
      some (.signed .i32 (Int.ofNat candidate.dot)) :=
    originRead.effect.empty_preserves_local
      predicate.invariant.chartCursor.recognizer.wellFormed dotAtPredicate
  have productionAtOriginScope : originScope.local? 31 =
      some (.signed .i32 (Int.ofNat candidate.production)) :=
    (bindLocal_preserves_other_local
      originRead.invariant.recognizer.wellFormed (by decide : 34 ≠ 31)).trans
      productionAtOriginRead
  have dotAtOriginScope : originScope.local? 32 =
      some (.signed .i32 (Int.ofNat candidate.dot)) :=
    (bindLocal_preserves_other_local
      originRead.invariant.recognizer.wellFormed (by decide : 34 ≠ 32)).trans
      dotAtOriginRead
  have originAtOriginScope : originScope.local? 34 =
      some (.signed .i32 (Int.ofNat candidate.origin)) := by
    simpa [originScope] using bindLocal_finds_local originRead.after 34
      (.signed .i32 (Int.ofNat candidate.origin))
      originRead.invariant.recognizer.wellFormed
  have dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length := by
    exact doesMatch.1
  have appendInvariant : RecognizerParentAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell originScope position
      candidate.production candidate.dot candidate.origin current completed := {
    frame := originInvariant.appendFrame
    seedDerivation := by
      have candidatePosition : candidate.position = origin := by
        obtain ⟨cursorState, cursorFound, cursorPosition⟩ :=
          originInvariant.chartCursor.state_at_cursor
        rw [found] at cursorFound
        injection cursorFound with stateEqual
        subst cursorState
        exact cursorPosition
      refine {
        languageSound := by
          have candidateSound :=
            originInvariant.chartCursor.recognizer.languageSound current candidate
              found
          have recognizedAtCandidate : RecognizesSymbol grammar tokens
              (grammar.grammar.n_kinds + completedLhs) candidate.position
              position := by
            simpa [candidatePosition] using originInvariant.completedRecognizes
          have advanced := candidateSound.advance doesMatch.2
            recognizedAtCandidate current (.state completed)
          simpa [recognizerParentSeed, EarleyState.advanceSeed] using advanced
        backpointer := by
          have previousBefore : current < workspace.states.length :=
            List.getElem?_eq_some_iff.mp found |>.1
          have childBefore : completed < workspace.states.length :=
            List.getElem?_eq_some_iff.mp originInvariant.completedStored.found |>.1
          have previousProductionBound : candidate.production <
              grammar.productionCount := by
            simpa [EarleyState.key] using productionBound
          have childLhsBound :=
            originInvariant.chartCursor.recognizer.grammarWellFormed
              |>.production_validation.lhsInBounds
                ⟨originInvariant.completedStored.state.production,
                  originInvariant.completedStored.productionBound⟩
          have symbolFound :
              (grammar.productionAt
                ⟨candidate.production, previousProductionBound⟩).rhs[
                  candidate.dot]? =
                some (grammar.grammar.n_kinds +
                  (grammar.productionAt
                    ⟨originInvariant.completedStored.state.production,
                      originInvariant.completedStored.productionBound⟩).lhs) := by
            simpa [originInvariant.completedStored.lhs] using doesMatch.2
          have childOrigin : originInvariant.completedStored.state.origin =
              candidate.position := by
            exact originInvariant.completedStored.originEq.trans
              candidatePosition.symm
          have step := EarleyBackpointerStep.nonterminal
            (grammar := grammar) (tokens := tokens) (workspace := workspace)
            (stateId := workspace.states.length) found previousBefore
            originInvariant.completedStored.found childBefore
            previousProductionBound
            originInvariant.completedStored.productionBound symbolFound
            childLhsBound childOrigin originInvariant.completedStored.complete
          simpa [recognizerParentSeed, EarleyState.advanceSeed,
            originInvariant.completedStored.positionEq] using step
      }
    dotSuccI32 := bindings.invariant.candidate_dot_succ_i32 candidate
      productionBound dotBeforeEnd
    originBound :=
      bindings.invariant.chartCursor.recognizer.workspaceEncoded.originsBound
        current candidate found
    positionLocal := originInvariant.positionLocal
    completedLocal := originInvariant.completedLocal
    parentLocal := Assertion.localPointsTo_local 30 cursorCell _ originScope
      originInvariant.chartCursor.cursorOwned
    productionLocal := productionAtOriginScope
    dotLocal := dotAtOriginScope
    originLocal := originAtOriginScope
  }
  exact {
    afterOriginRead := originRead.after
    originEvaluation := originEvaluation
    originEffect := originRead.effect
    afterOriginWellFormed := originRead.invariant.recognizer.wellFormed
    invariant := by simpa [originScope] using originInvariant
    appendInvariant := by simpa [originScope] using appendInvariant
  }

/-- Functional execution of the parent workspace append.  The source call's
    arguments are evaluated by FunctionalView, while the shared append
    contract supplies the mutation and resulting world. -/
private theorem RecognizerParentLoopInvariant.functional_append
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount)
    (doesMatch : ParentCandidateMatches grammar candidate completedLhs
      productionBound) :
    let seed := recognizerParentSeed candidate.production candidate.dot
      candidate.origin current completed
    let outcome := (appendLogical workspaceLayout.capacity position seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace position seed
      workspaceValues
    let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let afterWorld := parentWorld words tokens nextValues grammarCell tokensCell workspaceCell
    let environment := parentEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length
      grammar.grammar.n_kinds position completed completedLhs
      (Int.ofNat current)
    let originEnvironment := (((environment.push
      (.signed .i32 (Int.ofNat candidate.production))).push
      (.signed .i32 (Int.ofNat candidate.dot))).push
      (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length))).push
      (.signed .i32 (Int.ofNat candidate.origin))
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world originEnvironment parentAppendTerm =
      .ok (appendOutcomeValue outcome, afterWorld) := by
  dsimp only
  let seed := recognizerParentSeed candidate.production candidate.dot
    candidate.origin current completed
  let outcome := (appendLogical workspaceLayout.capacity position seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace position seed
    workspaceValues
  let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let afterWorld := parentWorld words tokens nextValues grammarCell tokensCell workspaceCell
  let environment := parentEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length
    grammar.grammar.n_kinds position completed completedLhs
    (Int.ofNat current)
  have productionBound' : candidate.production < grammar.productionCount := by
    simpa [EarleyState.key] using productionBound
  let production := grammar.productionAt
    ⟨candidate.production, productionBound'⟩
  have productionSame :
      grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩ = production := by
    apply congrArg grammar.productionAt
    exact Fin.ext rfl
  let originEnvironment := (((environment.push
    (.signed .i32 (Int.ofNat candidate.production))).push
    (.signed .i32 (Int.ofNat candidate.dot))).push
    (.signed .i32 (Int.ofNat production.rhs.length))).push
    (.signed .i32 (Int.ofNat candidate.origin))
  let machine := parentTermMachine workspaceLayout grammar words grammarCell
  let callValues : List Value := [
    workspaceValue workspaceValues workspaceCell,
    .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
    .signed .i32 (Int.ofNat workspaceLayout.capacity),
    .signed .i32 (Int.ofNat position), stateSeedValue seed,
    .signed .i32 (Int.ofNat workspace.states.length)]
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      originEnvironment parentAppendArguments = .ok (callValues, world) := by
    change Lanius.FunctionalView.evaluateTerms
      (parentTermMachine workspaceLayout grammar words grammarCell) world
      originEnvironment parentAppendArguments = .ok (callValues, world)
    simpa [world, environment, originEnvironment, productionSame, callValues,
      seed] using invariant.functional_append_arguments candidate
        productionBound doesMatch.1
  let bindings := invariant.bind_candidate_fields candidate found
    productionBound
  let predicate := bindings.evaluate_predicate
  let originBinding := bindings.bind_matched_origin predicate doesMatch
  let appended := originBinding.appendInvariant.evaluate_append
  have different : workspaceCell ≠ grammarCell :=
    invariant.chartCursor.recognizer.grammarWorkspaceDistinct.symm
  let input : AppendStateCall.Input workspaceLayout world callValues := {
    workspace := workspace
    values := workspaceValues
    cell := workspaceCell
    position := position
    seed := seed
    valuesLength := invariant.chartCursor.recognizer.workspaceLength
    encoded := invariant.chartCursor.recognizer.workspaceEncoded
    positionBound := invariant.appendFrame.positionBound
    seedOriginBound := by
      simpa [seed, recognizerParentSeed] using
        originBinding.appendInvariant.originBound
    found := by
      simpa [world, parentWorld] using
        (recognizerWorld_finds_workspace
          (tokens := tokens) (tokensCell := tokensCell) different)
    argumentsEq := rfl
  }
  let commandLayout := Layout.push
    (Layout.push (Layout.push (Layout.push parentLoopLayout 31) 32) 33) 34
  have argumentsExecution : ArgumentsEvaluateTo verifiedParserCore
      (originBinding.afterOriginRead.bindLocal 34
        (.signed .i32 (Int.ofNat candidate.origin)))
      (Lanius.FunctionalView.Core.toCoreExprs commandLayout
        parentAppendArguments) callValues appended.argumentsState := by
    change ArgumentsEvaluateTo verifiedParserCore
      (originBinding.afterOriginRead.bindLocal 34
        (.signed .i32 (Int.ofNat candidate.origin)))
      parserRecognizeParentAppendArguments callValues appended.argumentsState
    simpa [callValues, seed, parserRecognizeParentAppendArguments,
      recognizerAppendArguments] using appended.argumentsEvaluation
  have worldRepresents :
      Lanius.FunctionalView.Core.ReadOnly.World.Represents world
        appended.argumentsState := by
    simpa [world, parentWorld] using
      recognizerWorld_represents appended.argumentsInvariant
  have worldOwned :
      (Lanius.FunctionalView.Core.ReadOnly.World.owns world).holds
        appended.argumentsState :=
    (Lanius.FunctionalView.Core.ReadOnly.World.owns_iff_represents
      appended.argumentsInvariant.wellFormed).2 worldRepresents
  have registryResult :=
    RecognizerTraversalCallRegistry.calls_at_append_input
      (grammar := grammar) (words := words) (grammarCell := grammarCell)
      input
      (originBinding.afterOriginRead.bindLocal 34
        (.signed .i32 (Int.ofNat candidate.origin)))
      appended.argumentsState commandLayout parentAppendArguments
      appended.argumentsInvariant.wellFormed worldOwned argumentsExecution
  have outcomeEq : input.outcome = outcome := by rfl
  have afterWorldEq : input.afterWorld = afterWorld := by
    change Lanius.FunctionalView.Core.ReadOnly.World.setI32Slice world
        workspaceCell nextValues = afterWorld
    simpa [world, afterWorld, parentWorld] using
      (recognizerWorld_set_workspace
        (tokens := tokens) (tokensCell := tokensCell)
        (beforeValues := workspaceValues) (afterValues := nextValues)
        different appended.argumentsInvariant.tokensWorkspaceDistinct.symm)
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
    grammarCell).evaluate world extractedParserAppendStateFunction.id
      callValues = .ok (appendOutcomeValue outcome, afterWorld)
  rw [outcomeEq, afterWorldEq] at registryResult
  exact registryResult

private theorem parentFullCondition_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 14)
    (outcome : AppendOutcome) :
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world (environment.push (appendOutcomeValue outcome))
      parentFullCondition =
      .ok (.boolean (decide (outcome.status = .full)), world) := by
  have agreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell) (world := world)
      (environment := environment.push (appendOutcomeValue outcome))
      parentFullCondition (by native_decide)
  have readOnlyResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world (environment.push (appendOutcomeValue outcome))
      parentFullCondition =
      .ok (.boolean (decide (outcome.status = .full)), world) := by
    rcases outcome with ⟨status, stateId, stateCount, inserted⟩
    cases status <;> rfl
  change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
          grammarCell)) world
      (environment.push (appendOutcomeValue outcome)) parentFullCondition = _
  exact agreement.trans readOnlyResult

private theorem parentStateCountTerm_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 14)
    (outcome : AppendOutcome) :
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world (environment.push (appendOutcomeValue outcome))
      parentStateCountTerm =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), world) := by
  have agreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell) (world := world)
      (environment := environment.push (appendOutcomeValue outcome))
      parentStateCountTerm (by native_decide)
  have readOnlyResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world (environment.push (appendOutcomeValue outcome))
      parentStateCountTerm =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), world) := by rfl
  change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
          grammarCell)) world
      (environment.push (appendOutcomeValue outcome)) parentStateCountTerm = _
  exact agreement.trans readOnlyResult

private theorem parentFullResult_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 14)
    (outcome : AppendOutcome) (position : Nat)
    (positionValue : environment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat position)) :
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world (environment.push (appendOutcomeValue outcome))
      parentFullResult =
      .ok (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position), world) := by
  let machine := parentTermMachine workspaceLayout grammar words grammarCell
  let extended := environment.push (appendOutcomeValue outcome)
  have outcomeResult : Lanius.FunctionalView.Term.evaluate machine world
      extended (parentSlot ⟨14, by omega⟩) =
      .ok (appendOutcomeValue outcome, world) := by rfl
  have positionResult : Lanius.FunctionalView.Term.evaluate machine world
      extended (parentSlot ⟨6, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat position), world) := by
    apply Lanius.FunctionalView.Term.evaluate_slot
    change environment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat position)
    exact positionValue
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      extended [parentSlot ⟨14, by omega⟩, parentSlot ⟨6, by omega⟩] =
      .ok ([appendOutcomeValue outcome,
        .signed .i32 (Int.ofNat position)], world) :=
    Lanius.FunctionalView.evaluateTerms_cons outcomeResult
      (Lanius.FunctionalView.evaluateTerms_cons positionResult
        (Lanius.FunctionalView.evaluateTerms_nil machine world extended))
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
    grammarCell).evaluate world extractedParserAppendOrFullFunction.id
      [appendOutcomeValue outcome, .signed .i32 (Int.ofNat position)] = _
  exact RecognizerTraversalCallRegistry.calls_at_append_or_full world outcome
    (Int.ofNat position)

/-- Read the next origin-chart link from a parent-loop invariant. -/
private theorem RecognizerParentLoopInvariant.functional_next
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining)
    (environment : Lanius.FunctionalView.Env 13)
    (workspaceValueEq : environment ⟨1, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (stateBaseEq : environment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (currentEq : environment ⟨9, by omega⟩ =
      .signed .i32 (Int.ofNat current)) :
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      environment (parentStateValueTerm (arity := 13) (by omega) 32) =
      .ok (.signed .i32 (encodeStateId remaining.head?),
        parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) := by
  let candidate := Classical.choose invariant.chartCursor.state_at_cursor
  have candidateFacts :=
    Classical.choose_spec invariant.chartCursor.state_at_cursor
  have found : workspace.state? current = some candidate := candidateFacts.1
  have positionEq : candidate.position = origin := candidateFacts.2
  have evaluated := parentStateValueTerm_evaluates
    (arity := 13) (by omega) workspaceLayout grammar words workspaceValues
    grammarCell workspaceCell
    (parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    environment workspace candidate current 4 32
    invariant.chartCursor.recognizer.grammarWorkspaceDistinct.symm rfl
    workspaceValueEq stateBaseEq currentEq
    invariant.chartCursor.recognizer.workspaceLength
    invariant.chartCursor.recognizer.workspaceEncoded found (by decide)
    verifiedParser_find_constants.2.2.2.2
  have nextValue : stateFieldValue workspace current candidate 4 =
      encodeStateId remaining.head? := by
    simp only [stateFieldValue, stateNextValue]
    rw [positionEq, invariant.chartCursor.cursor.nextAfter]
  rw [nextValue] at evaluated
  exact evaluated

/-- A nonmatching parent candidate executes the real body without an append
    and advances the origin-chart cursor. -/
private theorem RecognizerParentLoopInvariant.functional_no_match_body
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount)
    (notMatches : ¬ ParentCandidateMatches grammar candidate completedLhs
      productionBound) :
    let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let beforeEnvironment := parentEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length
      grammar.grammar.n_kinds position completed completedLhs
      (Int.ofNat current)
    let afterEnvironment := parentEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length
      grammar.grammar.n_kinds position completed completedLhs
      (encodeStateId remaining.head?)
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      world beforeEnvironment parentBodyCommand .next world
      afterEnvironment := by
  dsimp only
  let world := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let beforeEnvironment := parentEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length
    grammar.grammar.n_kinds position completed completedLhs
    (Int.ofNat current)
  have productionBound' : candidate.production < grammar.productionCount := by
    simpa [EarleyState.key] using productionBound
  let productionEnvironment := beforeEnvironment.push
    (.signed .i32 (Int.ofNat candidate.production))
  let dotEnvironment := productionEnvironment.push
    (.signed .i32 (Int.ofNat candidate.dot))
  let rhsEnvironment := dotEnvironment.push
    (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound'⟩).rhs.length))
  have reads := invariant.functional_candidate_reads candidate found
    productionBound'
  have productionResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world beforeEnvironment
      (parentStateValueTerm (arity := 10) (by omega) 28) =
      .ok (.signed .i32 (Int.ofNat candidate.production), world) := reads.1
  have dotResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world productionEnvironment
      (parentStateValueTerm (arity := 11) (by omega) 29) =
      .ok (.signed .i32 (Int.ofNat candidate.dot), world) := reads.2.1
  have rhsResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world dotEnvironment parentRhsLengthTerm =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production,
          productionBound'⟩).rhs.length), world) := reads.2.2
  have predicateResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world rhsEnvironment parentCandidatePredicate =
      .ok (.boolean false, world) := by
    have evaluated := invariant.functional_predicate candidate productionBound
    simpa [world, rhsEnvironment, dotEnvironment, productionEnvironment,
      beforeEnvironment, notMatches] using evaluated
  have nextResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      world rhsEnvironment
      (parentStateValueTerm (arity := 13) (by omega) 32) =
      .ok (.signed .i32 (encodeStateId remaining.head?), world) :=
    invariant.functional_next rhsEnvironment (by rfl) (by rfl) (by rfl)
  let afterCursor := Lanius.FunctionalView.Stateful.Env.set rhsEnvironment
    ⟨9, by omega⟩ (.signed .i32 (encodeStateId remaining.head?))
  have body : Lanius.FunctionalView.Stateful.Command.Evaluates
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      world rhsEnvironment
      (.sequence
        (.ifThenElse parentCandidatePredicate
          (.letValue parserI32Type
            (parentStateValueTerm (arity := 13) (by omega) 30)
            (.letValue (.structure 2) parentAppendTerm
              (.sequence
                (.ifThenElse parentFullCondition
                  (.sequence (.returnValue (some parentFullResult)) .skip)
                  .skip)
                (.sequence
                  (.setLocal ⟨4, by omega⟩ parentStateCountTerm) .skip))))
          .skip)
        (.sequence
          (.setLocal ⟨9, by omega⟩
            (parentStateValueTerm (arity := 13) (by omega) 32)) .skip))
      .next world afterCursor :=
    .sequenceNext (.ifFalse predicateResult .skip)
      (.sequenceNext (.setLocal nextResult) .skip)
  have assembled :=
    Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
      (type := parserI32Type) productionResult
      (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
        (type := parserI32Type) dotResult
        (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
          (type := parserI32Type) rhsResult body))
  have environmentEq :
      Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop afterCursor)) =
      parentEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout workspace.states.length grammar.grammar.n_kinds
        position completed completedLhs (encodeStateId remaining.head?) := by
    funext index
    rcases index with ⟨index, indexBound⟩
    have indexCases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨
        index = 4 ∨ index = 5 ∨ index = 6 ∨ index = 7 ∨ index = 8 ∨
        index = 9 := by omega
    rcases indexCases with h | h | h | h | h | h | h | h | h | h <;>
      subst index <;> rfl
  rw [environmentEq] at assembled
  simpa [parentBodyCommand, parentCanonicalBodyCommand, world,
    beforeEnvironment] using assembled

/-- A matching, non-full parent candidate appends its advanced state, installs
    the returned state count, and follows the post-append chart link. -/
private theorem RecognizerParentLoopInvariant.functional_ok_body
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount)
    (doesMatch : ParentCandidateMatches grammar candidate completedLhs
      productionBound)
    (statusOk :
      let seed := recognizerParentSeed candidate.production candidate.dot
        candidate.origin current completed
      (appendLogical workspaceLayout.capacity position seed workspace).1.status =
        .ok)
    (nextRemaining : List Nat) (afterRuntime : State)
    (afterInvariant :
      let seed := recognizerParentSeed candidate.production candidate.dot
        candidate.origin current completed
      RecognizerParentLoopInvariant grammarLayout grammar words tokens
        workspaceLayout
        (appendLogical workspaceLayout.capacity position seed workspace).2
        (appendResultValues workspaceLayout workspace position seed
          workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell
        afterRuntime position completed completedLhs origin current
        nextRemaining) :
    let seed := recognizerParentSeed candidate.production candidate.dot
      candidate.origin current completed
    let outcome := (appendLogical workspaceLayout.capacity position seed
      workspace).1
    let nextWorkspace := (appendLogical workspaceLayout.capacity position seed
      workspace).2
    let nextValues := appendResultValues workspaceLayout workspace position seed
      workspaceValues
    let beforeWorld := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let afterWorld := parentWorld words tokens nextValues grammarCell tokensCell workspaceCell
    let beforeEnvironment := parentEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length
      grammar.grammar.n_kinds position completed completedLhs
      (Int.ofNat current)
    let afterEnvironment := parentEnvironment words nextValues grammarCell
      workspaceCell workspaceLayout nextWorkspace.states.length
      grammar.grammar.n_kinds position completed completedLhs
      (encodeStateId nextRemaining.head?)
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld beforeEnvironment parentBodyCommand .next afterWorld
      afterEnvironment := by
  dsimp only
  let seed := recognizerParentSeed candidate.production candidate.dot
    candidate.origin current completed
  let outcome := (appendLogical workspaceLayout.capacity position seed
    workspace).1
  let nextWorkspace := (appendLogical workspaceLayout.capacity position seed
    workspace).2
  let nextValues := appendResultValues workspaceLayout workspace position seed
    workspaceValues
  let beforeWorld := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let afterWorld := parentWorld words tokens nextValues grammarCell tokensCell workspaceCell
  let beforeEnvironment := parentEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length
    grammar.grammar.n_kinds position completed completedLhs
    (Int.ofNat current)
  have productionBound' : candidate.production < grammar.productionCount := by
    simpa [EarleyState.key] using productionBound
  let productionEnvironment := beforeEnvironment.push
    (.signed .i32 (Int.ofNat candidate.production))
  let dotEnvironment := productionEnvironment.push
    (.signed .i32 (Int.ofNat candidate.dot))
  let rhsEnvironment := dotEnvironment.push
    (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound'⟩).rhs.length))
  let originEnvironment := rhsEnvironment.push
    (.signed .i32 (Int.ofNat candidate.origin))
  let resultEnvironment := originEnvironment.push (appendOutcomeValue outcome)
  have reads := invariant.functional_candidate_reads candidate found
    productionBound'
  have productionResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld beforeEnvironment
      (parentStateValueTerm (arity := 10) (by omega) 28) =
      .ok (.signed .i32 (Int.ofNat candidate.production), beforeWorld) :=
    reads.1
  have dotResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld productionEnvironment
      (parentStateValueTerm (arity := 11) (by omega) 29) =
      .ok (.signed .i32 (Int.ofNat candidate.dot), beforeWorld) := reads.2.1
  have rhsResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld dotEnvironment parentRhsLengthTerm =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production,
          productionBound'⟩).rhs.length), beforeWorld) := reads.2.2
  have predicateResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld rhsEnvironment parentCandidatePredicate =
      .ok (.boolean true, beforeWorld) := by
    have evaluated := invariant.functional_predicate candidate productionBound
    simpa [beforeWorld, rhsEnvironment, dotEnvironment, productionEnvironment,
      beforeEnvironment, doesMatch] using evaluated
  have originResult := parentStateValueTerm_evaluates
    (arity := 13) (by omega) workspaceLayout grammar words workspaceValues
    grammarCell workspaceCell beforeWorld rhsEnvironment workspace candidate
    current 2 30
    invariant.chartCursor.recognizer.grammarWorkspaceDistinct.symm rfl
    (by rfl) (by rfl) (by rfl)
    invariant.chartCursor.recognizer.workspaceLength
    invariant.chartCursor.recognizer.workspaceEncoded found (by decide)
    verifiedParser_find_constants.2.2.2.1
  have originResult' : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld rhsEnvironment
      (parentStateValueTerm (arity := 13) (by omega) 30) =
      .ok (.signed .i32 (Int.ofNat candidate.origin), beforeWorld) := by
    simpa [stateFieldValue] using originResult
  have appendResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld originEnvironment parentAppendTerm =
      .ok (appendOutcomeValue outcome, afterWorld) := by
    exact invariant.functional_append candidate found productionBound doesMatch
  have statusOk' : outcome.status = .ok := by
    simpa [outcome, seed] using statusOk
  have fullCondition : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment parentFullCondition =
      .ok (.boolean false, afterWorld) := by
    have evaluated := parentFullCondition_evaluates
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (grammarCell := grammarCell) afterWorld
      originEnvironment outcome
    rw [statusOk'] at evaluated
    simpa [resultEnvironment] using evaluated
  have countResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment parentStateCountTerm =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), afterWorld) := by
    simpa [resultEnvironment] using parentStateCountTerm_evaluates
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (grammarCell := grammarCell) afterWorld
      originEnvironment outcome
  let afterCount := Lanius.FunctionalView.Stateful.Env.set resultEnvironment
    ⟨4, by omega⟩ (.signed .i32 (Int.ofNat outcome.stateCount))
  have appendContinuation :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (parentTermMachine workspaceLayout grammar words grammarCell)
        (parentStatefulMachine workspaceLayout grammar words grammarCell)
        afterWorld resultEnvironment
        (.sequence
          (.ifThenElse parentFullCondition
            (.sequence (.returnValue (some parentFullResult)) .skip) .skip)
          (.sequence (.setLocal ⟨4, by omega⟩ parentStateCountTerm) .skip))
        .next afterWorld afterCount :=
    .sequenceNext (.ifFalse fullCondition .skip)
      (.sequenceNext (.setLocal countResult) .skip)
  have appendScope :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (parentTermMachine workspaceLayout grammar words grammarCell)
        (parentStatefulMachine workspaceLayout grammar words grammarCell)
        beforeWorld originEnvironment
        (.letValue (.structure 2) parentAppendTerm
          (.sequence
            (.ifThenElse parentFullCondition
              (.sequence (.returnValue (some parentFullResult)) .skip) .skip)
            (.sequence
              (.setLocal ⟨4, by omega⟩ parentStateCountTerm) .skip)))
        .next afterWorld
        (Lanius.FunctionalView.Stateful.Env.pop afterCount) :=
    .letValue appendResult appendContinuation
  have originScope :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (parentTermMachine workspaceLayout grammar words grammarCell)
        (parentStatefulMachine workspaceLayout grammar words grammarCell)
        beforeWorld rhsEnvironment
        (.letValue parserI32Type
          (parentStateValueTerm (arity := 13) (by omega) 30)
          (.letValue (.structure 2) parentAppendTerm
            (.sequence
              (.ifThenElse parentFullCondition
                (.sequence (.returnValue (some parentFullResult)) .skip) .skip)
              (.sequence
                (.setLocal ⟨4, by omega⟩ parentStateCountTerm) .skip))))
        .next afterWorld
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop afterCount)) :=
    .letValue originResult' appendScope
  have selected :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (parentTermMachine workspaceLayout grammar words grammarCell)
        (parentStatefulMachine workspaceLayout grammar words grammarCell)
        beforeWorld rhsEnvironment
        (.ifThenElse parentCandidatePredicate
          (.letValue parserI32Type
            (parentStateValueTerm (arity := 13) (by omega) 30)
            (.letValue (.structure 2) parentAppendTerm
              (.sequence
                (.ifThenElse parentFullCondition
                  (.sequence (.returnValue (some parentFullResult)) .skip)
                  .skip)
                (.sequence
                  (.setLocal ⟨4, by omega⟩ parentStateCountTerm) .skip))))
          .skip)
        .next afterWorld
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop afterCount)) :=
    .ifTrue predicateResult originScope
  let afterAppendEnvironment := Lanius.FunctionalView.Stateful.Env.pop
    (Lanius.FunctionalView.Stateful.Env.pop afterCount)
  have workspaceValueEq : afterAppendEnvironment ⟨1, by omega⟩ =
      workspaceValue nextValues workspaceCell := by
    simp [afterAppendEnvironment, afterCount, resultEnvironment,
      originEnvironment, rhsEnvironment, dotEnvironment, productionEnvironment,
      beforeEnvironment, Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push, parentEnvironment, workspaceValue,
      nextValues, appendResultValues_length]
  have stateBaseEq : afterAppendEnvironment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)) := by rfl
  have currentEq : afterAppendEnvironment ⟨9, by omega⟩ =
      .signed .i32 (Int.ofNat current) := by rfl
  have nextResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      afterWorld afterAppendEnvironment
      (parentStateValueTerm (arity := 13) (by omega) 32) =
      .ok (.signed .i32 (encodeStateId nextRemaining.head?), afterWorld) := by
    simpa [afterWorld, nextValues, nextWorkspace, seed] using
      afterInvariant.functional_next afterAppendEnvironment workspaceValueEq
        stateBaseEq currentEq
  let afterCursor := Lanius.FunctionalView.Stateful.Env.set
    afterAppendEnvironment ⟨9, by omega⟩
      (.signed .i32 (encodeStateId nextRemaining.head?))
  have body : Lanius.FunctionalView.Stateful.Command.Evaluates
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld rhsEnvironment
      (.sequence
        (.ifThenElse parentCandidatePredicate
          (.letValue parserI32Type
            (parentStateValueTerm (arity := 13) (by omega) 30)
            (.letValue (.structure 2) parentAppendTerm
              (.sequence
                (.ifThenElse parentFullCondition
                  (.sequence (.returnValue (some parentFullResult)) .skip)
                  .skip)
                (.sequence
                  (.setLocal ⟨4, by omega⟩ parentStateCountTerm) .skip))))
          .skip)
        (.sequence
          (.setLocal ⟨9, by omega⟩
            (parentStateValueTerm (arity := 13) (by omega) 32)) .skip))
      .next afterWorld afterCursor :=
    .sequenceNext selected (.sequenceNext (.setLocal nextResult) .skip)
  have assembled :=
    Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
      (type := parserI32Type) productionResult
      (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
        (type := parserI32Type) dotResult
        (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
          (type := parserI32Type) rhsResult body))
  have collapsedEnvironment :
      Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop afterCursor)) =
      Lanius.FunctionalView.Stateful.Env.set
        (Lanius.FunctionalView.Stateful.Env.set beforeEnvironment
          ⟨4, by omega⟩ (.signed .i32 (Int.ofNat outcome.stateCount)))
        ⟨9, by omega⟩
        (.signed .i32 (encodeStateId nextRemaining.head?)) := by
    dsimp [afterCursor, afterAppendEnvironment, afterCount,
      resultEnvironment, originEnvironment, rhsEnvironment, dotEnvironment,
      productionEnvironment]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 12) (before := by native_decide)]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 11) (before := by native_decide)]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 10) (before := by native_decide)]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 14) (before := by native_decide)]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 13) (before := by native_decide)]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 12) (before := by native_decide)]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 11) (before := by native_decide)]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 10) (before := by native_decide)]
    congr
    simp
  have environmentEq :
      Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop afterCursor)) =
      parentEnvironment words nextValues grammarCell workspaceCell
        workspaceLayout nextWorkspace.states.length grammar.grammar.n_kinds
        position completed completedLhs (encodeStateId nextRemaining.head?) := by
    rw [collapsedEnvironment]
    funext index
    rcases index with ⟨index, indexBound⟩
    have indexCases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨
        index = 4 ∨ index = 5 ∨ index = 6 ∨ index = 7 ∨ index = 8 ∨
        index = 9 := by omega
    rcases indexCases with zero | one | two | three | four | five | six |
      seven | eight | nine
    all_goals subst index
    all_goals simp [Lanius.FunctionalView.Stateful.Env.set,
      beforeEnvironment, parentEnvironment, workspaceValue, nextValues,
      appendResultValues_length, nextWorkspace, outcome, seed,
      appendLogical_stateCount_eq, Fin.ext_iff]
    all_goals try (split <;> simp_all <;> try omega)
    all_goals try omega
    all_goals try (split <;> simp_all <;> try omega)
  rw [environmentEq] at assembled
  simpa [parentBodyCommand, parentCanonicalBodyCommand, beforeWorld,
    beforeEnvironment] using assembled

/-- A matching parent candidate whose append reports full returns the source
    capacity diagnostic before the count and cursor updates. -/
private theorem RecognizerParentLoopInvariant.functional_full_body
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount)
    (doesMatch : ParentCandidateMatches grammar candidate completedLhs
      productionBound)
    (statusFull :
      let seed := recognizerParentSeed candidate.production candidate.dot
        candidate.origin current completed
      (appendLogical workspaceLayout.capacity position seed workspace).1.status =
        .full) :
    let seed := recognizerParentSeed candidate.production candidate.dot
      candidate.origin current completed
    let outcome := (appendLogical workspaceLayout.capacity position seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace position seed
      workspaceValues
    let beforeWorld := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let afterWorld := parentWorld words tokens nextValues grammarCell tokensCell workspaceCell
    let beforeEnvironment := parentEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length
      grammar.grammar.n_kinds position completed completedLhs
      (Int.ofNat current)
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld beforeEnvironment parentBodyCommand
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld beforeEnvironment := by
  dsimp only
  let seed := recognizerParentSeed candidate.production candidate.dot
    candidate.origin current completed
  let outcome := (appendLogical workspaceLayout.capacity position seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace position seed
    workspaceValues
  let beforeWorld := parentWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let afterWorld := parentWorld words tokens nextValues grammarCell tokensCell workspaceCell
  let beforeEnvironment := parentEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length
    grammar.grammar.n_kinds position completed completedLhs
    (Int.ofNat current)
  have productionBound' : candidate.production < grammar.productionCount := by
    simpa [EarleyState.key] using productionBound
  let productionEnvironment := beforeEnvironment.push
    (.signed .i32 (Int.ofNat candidate.production))
  let dotEnvironment := productionEnvironment.push
    (.signed .i32 (Int.ofNat candidate.dot))
  let rhsEnvironment := dotEnvironment.push
    (.signed .i32 (Int.ofNat
      (grammar.productionAt ⟨candidate.production,
        productionBound'⟩).rhs.length))
  let originEnvironment := rhsEnvironment.push
    (.signed .i32 (Int.ofNat candidate.origin))
  let resultEnvironment := originEnvironment.push (appendOutcomeValue outcome)
  have reads := invariant.functional_candidate_reads candidate found
    productionBound'
  have productionResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld beforeEnvironment
      (parentStateValueTerm (arity := 10) (by omega) 28) =
      .ok (.signed .i32 (Int.ofNat candidate.production), beforeWorld) :=
    reads.1
  have dotResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld productionEnvironment
      (parentStateValueTerm (arity := 11) (by omega) 29) =
      .ok (.signed .i32 (Int.ofNat candidate.dot), beforeWorld) := reads.2.1
  have rhsResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld dotEnvironment parentRhsLengthTerm =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production,
          productionBound'⟩).rhs.length), beforeWorld) := reads.2.2
  have predicateResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld rhsEnvironment parentCandidatePredicate =
      .ok (.boolean true, beforeWorld) := by
    have evaluated := invariant.functional_predicate candidate productionBound
    simpa [beforeWorld, rhsEnvironment, dotEnvironment, productionEnvironment,
      beforeEnvironment, doesMatch] using evaluated
  have originResult := parentStateValueTerm_evaluates
    (arity := 13) (by omega) workspaceLayout grammar words workspaceValues
    grammarCell workspaceCell beforeWorld rhsEnvironment workspace candidate
    current 2 30
    invariant.chartCursor.recognizer.grammarWorkspaceDistinct.symm rfl
    (by rfl) (by rfl) (by rfl)
    invariant.chartCursor.recognizer.workspaceLength
    invariant.chartCursor.recognizer.workspaceEncoded found (by decide)
    verifiedParser_find_constants.2.2.2.1
  have originResult' : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld rhsEnvironment
      (parentStateValueTerm (arity := 13) (by omega) 30) =
      .ok (.signed .i32 (Int.ofNat candidate.origin), beforeWorld) := by
    simpa [stateFieldValue] using originResult
  have appendResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld originEnvironment parentAppendTerm =
      .ok (appendOutcomeValue outcome, afterWorld) :=
    invariant.functional_append candidate found productionBound doesMatch
  have statusFull' : outcome.status = .full := by
    simpa [outcome, seed] using statusFull
  have fullCondition : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment parentFullCondition =
      .ok (.boolean true, afterWorld) := by
    have evaluated := parentFullCondition_evaluates
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (grammarCell := grammarCell) afterWorld
      originEnvironment outcome
    rw [statusFull'] at evaluated
    simpa [resultEnvironment] using evaluated
  have positionValue : originEnvironment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat position) := by rfl
  have fullResult : Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment parentFullResult =
      .ok (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position), afterWorld) := by
    simpa [resultEnvironment] using parentFullResult_evaluates
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (grammarCell := grammarCell) afterWorld
      originEnvironment outcome position positionValue
  have returned : Lanius.FunctionalView.Stateful.Command.Evaluates
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment (.returnValue (some parentFullResult))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment :=
    .returnSome fullResult
  have fullBranch : Lanius.FunctionalView.Stateful.Command.Evaluates
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment
      (.sequence (.returnValue (some parentFullResult)) .skip)
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment :=
    .sequenceStop returned (by intro impossible; cases impossible)
  have selectedFull : Lanius.FunctionalView.Stateful.Command.Evaluates
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment
      (.ifThenElse parentFullCondition
        (.sequence (.returnValue (some parentFullResult)) .skip) .skip)
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment :=
    .ifTrue fullCondition fullBranch
  have appendContinuation :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (parentTermMachine workspaceLayout grammar words grammarCell)
        (parentStatefulMachine workspaceLayout grammar words grammarCell)
        afterWorld resultEnvironment
        (.sequence
          (.ifThenElse parentFullCondition
            (.sequence (.returnValue (some parentFullResult)) .skip) .skip)
          (.sequence (.setLocal ⟨4, by omega⟩ parentStateCountTerm) .skip))
        (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
          (Int.ofNat position)))) afterWorld resultEnvironment :=
    .sequenceStop selectedFull (by intro impossible; cases impossible)
  have appendScope : Lanius.FunctionalView.Stateful.Command.Evaluates
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld originEnvironment
      (.letValue (.structure 2) parentAppendTerm
        (.sequence
          (.ifThenElse parentFullCondition
            (.sequence (.returnValue (some parentFullResult)) .skip) .skip)
          (.sequence (.setLocal ⟨4, by omega⟩ parentStateCountTerm) .skip)))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop resultEnvironment) :=
    .letValue appendResult appendContinuation
  have originScope : Lanius.FunctionalView.Stateful.Command.Evaluates
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld rhsEnvironment
      (.letValue parserI32Type
        (parentStateValueTerm (arity := 13) (by omega) 30)
        (.letValue (.structure 2) parentAppendTerm
          (.sequence
            (.ifThenElse parentFullCondition
              (.sequence (.returnValue (some parentFullResult)) .skip) .skip)
            (.sequence
              (.setLocal ⟨4, by omega⟩ parentStateCountTerm) .skip))))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop resultEnvironment)) :=
    .letValue originResult' appendScope
  have selected : Lanius.FunctionalView.Stateful.Command.Evaluates
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld rhsEnvironment
      (.ifThenElse parentCandidatePredicate
        (.letValue parserI32Type
          (parentStateValueTerm (arity := 13) (by omega) 30)
          (.letValue (.structure 2) parentAppendTerm
            (.sequence
              (.ifThenElse parentFullCondition
                (.sequence (.returnValue (some parentFullResult)) .skip) .skip)
              (.sequence
                (.setLocal ⟨4, by omega⟩ parentStateCountTerm) .skip))))
        .skip)
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop resultEnvironment)) :=
    .ifTrue predicateResult originScope
  have body : Lanius.FunctionalView.Stateful.Command.Evaluates
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld rhsEnvironment
      (.sequence
        (.ifThenElse parentCandidatePredicate
          (.letValue parserI32Type
            (parentStateValueTerm (arity := 13) (by omega) 30)
            (.letValue (.structure 2) parentAppendTerm
              (.sequence
                (.ifThenElse parentFullCondition
                  (.sequence (.returnValue (some parentFullResult)) .skip)
                  .skip)
                (.sequence
                  (.setLocal ⟨4, by omega⟩ parentStateCountTerm) .skip))))
          .skip)
        (.sequence
          (.setLocal ⟨9, by omega⟩
            (parentStateValueTerm (arity := 13) (by omega) 32)) .skip))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop resultEnvironment)) :=
    .sequenceStop selected (by intro impossible; cases impossible)
  have assembled :=
    Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
      (type := parserI32Type) productionResult
      (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
        (type := parserI32Type) dotResult
        (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
          (type := parserI32Type) rhsResult body))
  have popped :
      Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.pop
              (Lanius.FunctionalView.Stateful.Env.pop resultEnvironment)))) =
      beforeEnvironment := by
    simp [resultEnvironment, originEnvironment, rhsEnvironment, dotEnvironment,
      productionEnvironment]
  rw [popped] at assembled
  have outcomeCountEq : outcome.stateCount =
      (appendLogical workspaceLayout.capacity position seed workspace).2.states.length := by
    simpa [outcome] using appendLogical_stateCount_eq
      workspaceLayout.capacity position seed workspace
  rw [outcomeCountEq] at assembled
  simpa [parentBodyCommand, parentCanonicalBodyCommand, beforeWorld,
    beforeEnvironment] using assembled

/-- Reframe a successful parent append as the next logical workspace while
    retaining a supplied cursor over the completed state's origin chart. -/
def RecognizerParentLoopInvariant.after_ok_append
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (appendInvariant : RecognizerParentAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell before position
      candidate.production candidate.dot candidate.origin current completed)
    (appended : RecognizerParentOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell before position candidate.production
      candidate.dot candidate.origin current completed appendInvariant)
    (newRemaining : List Nat)
    (cursor : ChartCursor
      ((appendLogical workspaceLayout.capacity position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspace).2.chart origin)
      current newRemaining)
    (within : WorkspaceWithinGrammar grammar
      (appendLogical workspaceLayout.capacity position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspace).2) :
    RecognizerParentLoopInvariant grammarLayout grammar words tokens
      workspaceLayout
      (appendLogical workspaceLayout.capacity position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspace).2
      (appendResultValues workspaceLayout workspace position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspaceValues)
      grammarCell tokensCell workspaceCell stateCountCell cursorCell
      appended.after position completed completedLhs origin current
      newRemaining := by
  let nextWorkspace := (appendLogical workspaceLayout.capacity position
    (recognizerParentSeed candidate.production candidate.dot candidate.origin
      current completed) workspace).2
  let nextValues := appendResultValues workspaceLayout workspace position
    (recognizerParentSeed candidate.production candidate.dot candidate.origin
      current completed) workspaceValues
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton stateCountCell)
  have writesMutable : CellSet.Subset writes
      (parentFrameMutableCells workspaceCell stateCountCell cursorCell) := by
    intro cell written
    exact written.elim Or.inl (fun count => Or.inr (Or.inl count))
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        verifiedParserParentPreservedBindings) writes :=
    CellSet.Disjoint.mono_right writesMutable invariant.persistentSeparate
  have preserveLocal (id : VarId) (persistent : ParentPersistentLocal id)
      (notStateCount : id ≠ 18) (value : Value)
      (found : before.local? id = some value) :
      appended.after.local? id = some value :=
    appended.effect.preserves_local_of_disjoint
      invariant.chartCursor.recognizer.wellFormed frameDisjoint
      ((ParentPreservedLocal_source_frame id).mp
        ((ParentPreservedLocal_iff id).mpr
          ⟨persistent, notStateCount⟩)) found
  have cursorOwned : (Assertion.localPointsTo 30 cursorCell
      (some (.signed .i32 (Int.ofNat current)))).holds appended.after :=
    appended.effect.preserve invariant.chartCursor.recognizer.wellFormed
      (Assertion.localPointsTo 30 cursorCell
        (some (.signed .i32 (Int.ofNat current))))
      invariant.chartCursor.cursorOwned (by
        intro cell member written
        change cell = cursorCell at member
        subst cell
        change cursorCell = workspaceCell ∨ cursorCell = stateCountCell
          at written
        exact written.elim invariant.chartCursor.cursorBackingDistinct.2.2
          invariant.cursorStateCountDistinct)
  have chartInvariant : RecognizerChartCursorInvariant grammarLayout grammar
      words tokens workspaceLayout nextWorkspace nextValues grammarCell
      tokensCell workspaceCell cursorCell appended.after origin 30 current
      newRemaining := {
    recognizer := by simpa [nextWorkspace, nextValues] using appended.invariant
    workspaceWithinGrammar := by simpa [nextWorkspace] using within
    stateBaseLocal := preserveLocal 8 (by
      simp [ParentPersistentLocal]) (by decide) _
      invariant.chartCursor.stateBaseLocal
    cursorOwned := cursorOwned
    cursorFrameSeparate := by
      unfold ChartCursorFrameSeparated
      rw [appended.effect.localBindingFrameFootprint_eq
        verifiedParserChartCursorBindings]
      exact invariant.chartCursor.cursorFrameSeparate
    cursorBackingDistinct := invariant.chartCursor.cursorBackingDistinct
    chartPositionBound := invariant.chartCursor.chartPositionBound
    cursor := by simpa [nextWorkspace] using cursor
  }
  exact {
    chartCursor := chartInvariant
    appendFrame := {
      recognizer := chartInvariant.recognizer
      positionBound := invariant.appendFrame.positionBound
      stateBaseLocal := chartInvariant.stateBaseLocal
      stateCapacityLocal := preserveLocal 9 (by
        simp [ParentPersistentLocal]) (by decide) _
        invariant.appendFrame.stateCapacityLocal
      stateCountLocal := Assertion.localPointsTo_local 18 stateCountCell _
        appended.after appended.stateCountOwned
      stateCountOwned := by simpa [nextWorkspace] using appended.stateCountOwned
      stateCountBackingDistinct :=
        invariant.appendFrame.stateCountBackingDistinct
      stateCountParameterSeparate := by
        unfold RecognizerParameterFrameSeparated
        rw [appended.effect.localBindingFrameFootprint_eq
          verifiedParserRecognizerParameterFrame]
        exact invariant.appendFrame.stateCountParameterSeparate
    }
    kindCountLocal := preserveLocal 11 (by
      simp [ParentPersistentLocal]) (by decide) _
      invariant.kindCountLocal
    positionLocal := preserveLocal 23 (by
      simp [ParentPersistentLocal]) (by decide) _
      invariant.positionLocal
    completedLocal := preserveLocal 24 (by
      simp [ParentPersistentLocal]) (by decide) _
      invariant.completedLocal
    completedLhsLocal := preserveLocal 29 (by
      simp [ParentPersistentLocal]) (by decide) _
      invariant.completedLhsLocal
    completedLhsBound := invariant.completedLhsBound
    completedRecognizes := invariant.completedRecognizes
    completedStored := invariant.completedStored.transfer (by
      let appendRefinement := appendLogical_refines
        (appendLogical workspaceLayout.capacity position
          (recognizerParentSeed candidate.production candidate.dot
            candidate.origin current completed) workspace) rfl
      exact (appendRefinement.preserves_existing_states
        (List.getElem?_eq_some_iff.mp invariant.completedStored.found |>.1)).trans
          invariant.completedStored.found)
    persistentSeparate := by
      unfold ParentFrameSeparated
      rw [appended.effect.localBindingFrameFootprint_eq
        verifiedParserParentPreservedBindings]
      exact invariant.persistentSeparate
    cursorStateCountDistinct := invariant.cursorStateCountDistinct
  }

inductive RecognizerParentOkAppendCursor
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position completed completedLhs origin current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (appendInvariant : RecognizerParentAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell before position
      candidate.production candidate.dot candidate.origin current completed)
    (appended : RecognizerParentOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell before position candidate.production
      candidate.dot candidate.origin current completed appendInvariant) : Type
  | unchanged
      (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
        tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position
          (recognizerParentSeed candidate.production candidate.dot
            candidate.origin current completed) workspace).2
        (appendResultValues workspaceLayout workspace position
          (recognizerParentSeed candidate.production candidate.dot
            candidate.origin current completed) workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell
        appended.after position completed completedLhs origin current remaining)
      (countUnchanged :
        (appendLogical workspaceLayout.capacity position
          (recognizerParentSeed candidate.production candidate.dot
            candidate.origin current completed) workspace).2.states.length =
          workspace.states.length) :
      RecognizerParentOkAppendCursor grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position completed
        completedLhs origin current remaining beforeInvariant candidate
        appendInvariant appended
  | inserted (nextRemaining : List Nat)
      (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
        tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position
          (recognizerParentSeed candidate.production candidate.dot
            candidate.origin current completed) workspace).2
        (appendResultValues workspaceLayout workspace position
          (recognizerParentSeed candidate.production candidate.dot
            candidate.origin current completed) workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell
        appended.after position completed completedLhs origin current
        nextRemaining)
      (countIncreased :
        (appendLogical workspaceLayout.capacity position
          (recognizerParentSeed candidate.production candidate.dot
            candidate.origin current completed) workspace).2.states.length =
          workspace.states.length + 1) :
      RecognizerParentOkAppendCursor grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position completed
        completedLhs origin current remaining beforeInvariant candidate
        appendInvariant appended

/-- Classify the parent append while respecting that the loop may observe a
    different origin chart from the append's current-position chart. -/
noncomputable def RecognizerParentMatchedOriginBinding.classify_ok_append
    (originBinding : RecognizerParentMatchedOriginBinding grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      completed completedLhs origin current remaining beforeInvariant candidate
      found productionBound predicate doesMatch)
    (appended : RecognizerParentOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell
      (originBinding.afterOriginRead.bindLocal 34
        (.signed .i32 (Int.ofNat candidate.origin)))
      position candidate.production candidate.dot candidate.origin current
      completed originBinding.appendInvariant) :
    RecognizerParentOkAppendCursor grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (originBinding.afterOriginRead.bindLocal 34
        (.signed .i32 (Int.ofNat candidate.origin)))
      position completed completedLhs origin current remaining
      originBinding.invariant candidate originBinding.appendInvariant appended := by
  let seed := recognizerParentSeed candidate.production candidate.dot
    candidate.origin current completed
  let logical := appendLogical workspaceLayout.capacity position seed workspace
  have relation : Append workspaceLayout.capacity position seed workspace
      logical.1 logical.2 := appendLogical_refines logical rfl
  have dotBeforeEnd : candidate.dot <
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length :=
    doesMatch.1
  have seedWithin := originBinding.invariant.seed_within_grammar candidate
    productionBound dotBeforeEnd
  have within : WorkspaceWithinGrammar grammar logical.2 :=
    relation.preserves_withinGrammar
      originBinding.invariant.chartCursor.workspaceWithinGrammar
      (by simpa [seed] using seedWithin)
  by_cases sameChart : origin = position
  · subst origin
    cases transportAppendLogicalCursor workspaceLayout.capacity position seed
        workspace originBinding.invariant.chartCursor.cursor with
    | inl unchanged =>
        exact .unchanged
          (originBinding.invariant.after_ok_append candidate
            originBinding.appendInvariant appended remaining (by
              simpa [logical, seed] using unchanged.cursor) (by
              simpa [logical] using within)) (by
                simpa [logical, seed] using unchanged.countUnchanged)
    | inr extended =>
        exact .inserted (remaining ++ [workspace.states.length])
          (originBinding.invariant.after_ok_append candidate
            originBinding.appendInvariant appended
            (remaining ++ [workspace.states.length]) (by
              simpa [logical, seed] using extended.cursor) (by
              simpa [logical] using within)) (by
                simpa [logical, seed] using extended.countIncreased)
  · cases transportAppendLogicalOtherCursor workspaceLayout.capacity position
        origin sameChart seed workspace
        originBinding.invariant.chartCursor.cursor with
    | inl unchanged =>
        exact .unchanged
          (originBinding.invariant.after_ok_append candidate
            originBinding.appendInvariant appended remaining (by
              simpa [logical, seed] using unchanged.cursor) (by
              simpa [logical] using within)) (by
                simpa [logical, seed] using unchanged.countUnchanged)
    | inr inserted =>
        exact .inserted remaining
          (originBinding.invariant.after_ok_append candidate
            originBinding.appendInvariant appended remaining (by
              simpa [logical, seed] using inserted.cursor) (by
              simpa [logical] using within)) (by
                simpa [logical, seed] using inserted.countIncreased)

structure RecognizerParentClosedOkAppend
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position completed completedLhs origin current : Nat)
    (remaining nextRemaining : List Nat)
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining beforeInvariant candidate
      productionBound)
    (doesMatch : ParentCandidateMatches grammar candidate completedLhs
      productionBound)
    (originBinding : RecognizerParentMatchedOriginBinding grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      completed completedLhs origin current remaining beforeInvariant candidate
      found productionBound predicate doesMatch)
    (appended : RecognizerParentOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell
      (originBinding.afterOriginRead.bindLocal 34
        (.signed .i32 (Int.ofNat candidate.origin)))
      position candidate.production candidate.dot candidate.origin current
      completed originBinding.appendInvariant)
    (innerInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout
      (appendLogical workspaceLayout.capacity position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspace).2
      (appendResultValues workspaceLayout workspace position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspaceValues)
      grammarCell tokensCell workspaceCell stateCountCell cursorCell
      appended.after position completed completedLhs origin current
      nextRemaining) where
  after : State
  execution : Executes verifiedParserCore predicate.after
    parserRecognizeParentMatchedBody .next after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell)) predicate.after after
  invariant : RecognizerParentLoopInvariant grammarLayout grammar words tokens
    workspaceLayout
    (appendLogical workspaceLayout.capacity position
      (recognizerParentSeed candidate.production candidate.dot
        candidate.origin current completed) workspace).2
    (appendResultValues workspaceLayout workspace position
      (recognizerParentSeed candidate.production candidate.dot
        candidate.origin current completed) workspaceValues)
    grammarCell tokensCell workspaceCell stateCountCell cursorCell after position
    completed completedLhs origin current nextRemaining

noncomputable def RecognizerParentMatchedOriginBinding.close_ok_append
    (originBinding : RecognizerParentMatchedOriginBinding grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      completed completedLhs origin current remaining beforeInvariant candidate
      found productionBound predicate doesMatch)
    (appended : RecognizerParentOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell
      (originBinding.afterOriginRead.bindLocal 34
        (.signed .i32 (Int.ofNat candidate.origin)))
      position candidate.production candidate.dot candidate.origin current
      completed originBinding.appendInvariant)
    (innerInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout
      (appendLogical workspaceLayout.capacity position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspace).2
      (appendResultValues workspaceLayout workspace position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspaceValues)
      grammarCell tokensCell workspaceCell stateCountCell cursorCell
      appended.after position completed completedLhs origin current
      nextRemaining) :
    RecognizerParentClosedOkAppend grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining nextRemaining beforeInvariant
      candidate found productionBound predicate doesMatch originBinding appended
      innerInvariant := by
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton stateCountCell)
  let originScope := originBinding.afterOriginRead.bindLocal 34
    (.signed .i32 (Int.ofNat candidate.origin))
  let after := restoreLocals originBinding.afterOriginRead appended.after
  have enteredOrigin : StoreEffect CellSet.empty
      originBinding.afterOriginRead originScope := by
    simpa [originScope] using bindLocal_effect originBinding.afterOriginRead 34
      (.signed .i32 (Int.ofNat candidate.origin))
  have scopeEffect : StoreEffect writes originBinding.afterOriginRead
      appended.after :=
    (enteredOrigin.weaken CellSet.empty_subset).trans_same
      (by simpa [writes, originScope] using appended.effect.toStoreEffect)
  have effect : ModifiesOnly writes originBinding.afterOriginRead after := by
    simpa [after] using scopeEffect.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    scopeEffect.restoreLocals_wellFormed originBinding.afterOriginWellFormed
      innerInvariant.chartCursor.recognizer.wellFormed
  have cells : after.cells = appended.after.cells := by
    simp [after, restoreLocals]
  have entryTransferred (cell : CellId) (entry : Cell)
      (innerEntry : appended.after.cellEntry? cell = some entry) :
      after.cellEntry? cell = some entry := by
    unfold State.cellEntry? at innerEntry ⊢
    rw [cells]
    exact innerEntry
  let beforeScopeInvariant := predicate.invariant.after_empty_effect
    originBinding.originEffect originBinding.afterOriginWellFormed
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint originBinding.afterOriginRead
        verifiedParserParentPreservedBindings) writes := by
    intro cell framed written
    obtain ⟨id, preserved, cellId⟩ := framed
    have ⟨persistent, notStateCount⟩ :=
      (ParentPreservedLocal_iff id).mp
        ((ParentPreservedLocal_source_frame id).mpr preserved)
    change cell = workspaceCell ∨ cell = stateCountCell at written
    rcases written with workspaceWritten | countWritten
    · subst cell
      exact beforeScopeInvariant.persistentLocalsSeparate id persistent |>.1 cellId
    · subst cell
      exact beforeScopeInvariant.persistentLocalsSeparate id persistent |>.2.1
        notStateCount cellId
  have preserveLocal (id : VarId) (persistent : ParentPersistentLocal id)
      (notStateCount : id ≠ 18) (value : Value)
      (foundLocal : originBinding.afterOriginRead.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint
      originBinding.afterOriginWellFormed frameDisjoint
      ((ParentPreservedLocal_source_frame id).mp
        ((ParentPreservedLocal_iff id).mpr
          ⟨persistent, notStateCount⟩)) foundLocal
  have sameLength :
      (appendResultValues workspaceLayout workspace position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspaceValues).length =
        workspaceValues.length := by
    rw [innerInvariant.chartCursor.recognizer.workspaceLength,
      beforeScopeInvariant.chartCursor.recognizer.workspaceLength]
  have writesMutable : CellSet.Subset writes
      (parentFrameMutableCells workspaceCell stateCountCell cursorCell) := by
    intro cell written
    exact written.elim Or.inl (fun count => Or.inr (Or.inl count))
  have parameterFrameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint originBinding.afterOriginRead
        verifiedParserRecognizerParameterFrame) writes :=
    CellSet.Disjoint.mono_right writesMutable
      (CellSet.Disjoint.mono_left
        (localBindingFrameFootprint_mono (fun id idBound =>
          (ParentPreservedLocal_source_frame id).mp
            ((ParentPreservedLocal_iff id).mpr ⟨Or.inl idBound, by
              have bound :=
                (mem_verifiedParserRecognizerParameterIds_iff id).mp idBound
              exact Nat.ne_of_lt (Nat.lt_of_le_of_lt bound (by decide))⟩)))
        beforeScopeInvariant.persistentSeparate)
  have recognizer : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout
      (appendLogical workspaceLayout.capacity position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspace).2
      (appendResultValues workspaceLayout workspace position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspaceValues)
      grammarCell tokensCell workspaceCell after :=
    beforeScopeInvariant.chartCursor.recognizer.after_workspace_and_scalar_effect
      writes effect afterWellFormed (by
        intro written
        change grammarCell = workspaceCell ∨ grammarCell = stateCountCell
          at written
        exact written.elim
          beforeScopeInvariant.chartCursor.recognizer.grammarWorkspaceDistinct
          (fun equal => beforeScopeInvariant.appendFrame
            |>.stateCountBackingDistinct.1 equal.symm)) (by
        intro written
        change tokensCell = workspaceCell ∨ tokensCell = stateCountCell
          at written
        exact written.elim
          beforeScopeInvariant.chartCursor.recognizer.tokensWorkspaceDistinct
          (fun equal => beforeScopeInvariant.appendFrame
            |>.stateCountBackingDistinct.2.1 equal.symm))
      parameterFrameDisjoint _ _ sameLength
      innerInvariant.chartCursor.recognizer.workspaceEncoded
      innerInvariant.chartCursor.recognizer.derivations
      (entryTransferred workspaceCell _
        innerInvariant.chartCursor.recognizer.workspaceBacking)
  have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat
        (appendLogical workspaceLayout.capacity position
          (recognizerParentSeed candidate.production candidate.dot
            candidate.origin current completed) workspace).2.states.length)))).holds
      after := by
    constructor
    · unfold State.cellId?
      rw [effect.locals]
      exact beforeScopeInvariant.appendFrame.stateCountOwned.1
    · exact entryTransferred stateCountCell _
        innerInvariant.appendFrame.stateCountOwned.2
  have cursorOwned : (Assertion.localPointsTo 30 cursorCell
      (some (.signed .i32 (Int.ofNat current)))).holds after := by
    constructor
    · unfold State.cellId?
      rw [effect.locals]
      exact beforeScopeInvariant.chartCursor.cursorOwned.1
    · exact entryTransferred cursorCell _
        innerInvariant.chartCursor.cursorOwned.2
  have restoredInvariant : RecognizerParentLoopInvariant grammarLayout grammar
      words tokens workspaceLayout
      (appendLogical workspaceLayout.capacity position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspace).2
      (appendResultValues workspaceLayout workspace position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspaceValues)
      grammarCell tokensCell workspaceCell stateCountCell cursorCell after position
      completed completedLhs origin current nextRemaining := {
    chartCursor := {
      recognizer := recognizer
      workspaceWithinGrammar := innerInvariant.chartCursor.workspaceWithinGrammar
      stateBaseLocal := preserveLocal 8 (by
        simp [ParentPersistentLocal]) (by decide) _
        beforeScopeInvariant.chartCursor.stateBaseLocal
      cursorOwned := cursorOwned
      cursorFrameSeparate := by
        unfold ChartCursorFrameSeparated
        rw [effect.localBindingFrameFootprint_eq
          verifiedParserChartCursorBindings]
        exact beforeScopeInvariant.chartCursor.cursorFrameSeparate
      cursorBackingDistinct :=
        beforeScopeInvariant.chartCursor.cursorBackingDistinct
      chartPositionBound := innerInvariant.chartCursor.chartPositionBound
      cursor := innerInvariant.chartCursor.cursor
    }
    appendFrame := {
      recognizer := recognizer
      positionBound := innerInvariant.appendFrame.positionBound
      stateBaseLocal := preserveLocal 8 (by
        simp [ParentPersistentLocal]) (by decide) _
        beforeScopeInvariant.appendFrame.stateBaseLocal
      stateCapacityLocal := preserveLocal 9 (by
        simp [ParentPersistentLocal]) (by decide) _
        beforeScopeInvariant.appendFrame.stateCapacityLocal
      stateCountLocal := Assertion.localPointsTo_local 18 stateCountCell _ after
        stateCountOwned
      stateCountOwned := stateCountOwned
      stateCountBackingDistinct :=
        beforeScopeInvariant.appendFrame.stateCountBackingDistinct
      stateCountParameterSeparate := by
        unfold RecognizerParameterFrameSeparated
        rw [effect.localBindingFrameFootprint_eq
          verifiedParserRecognizerParameterFrame]
        exact beforeScopeInvariant.appendFrame.stateCountParameterSeparate
    }
    kindCountLocal := preserveLocal 11 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeScopeInvariant.kindCountLocal
    positionLocal := preserveLocal 23 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeScopeInvariant.positionLocal
    completedLocal := preserveLocal 24 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeScopeInvariant.completedLocal
    completedLhsLocal := preserveLocal 29 (by
      simp [ParentPersistentLocal]) (by decide) _
      beforeScopeInvariant.completedLhsLocal
    completedLhsBound := beforeScopeInvariant.completedLhsBound
    completedRecognizes := beforeScopeInvariant.completedRecognizes
    completedStored := innerInvariant.completedStored
    persistentSeparate := by
      unfold ParentFrameSeparated
      rw [effect.localBindingFrameFootprint_eq
        verifiedParserParentPreservedBindings]
      exact beforeScopeInvariant.persistentSeparate
    cursorStateCountDistinct := beforeScopeInvariant.cursorStateCountDistinct
  }
  exact {
    after := after
    execution := by
      rw [extractedParserRecognize_parent_matched_body_shape]
      simpa [originScope, after] using
        executesLetLocal (type := parserI32Type) originBinding.originEvaluation
          appended.execution
    effect := by
      exact (originBinding.originEffect.weaken CellSet.empty_subset).trans_same
        effect
    invariant := restoredInvariant
  }

/-- Close the matched branch's `parent_origin` scope when the append reports
    capacity exhaustion.  The returned parse result bypasses cursor advance,
    but the lexical scope still has to be restored before the three outer
    candidate bindings can be closed. -/
structure RecognizerParentClosedFull
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position completed completedLhs origin current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining beforeInvariant candidate
      productionBound)
    (doesMatch : ParentCandidateMatches grammar candidate completedLhs
      productionBound)
    (originBinding : RecognizerParentMatchedOriginBinding grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      completed completedLhs origin current remaining beforeInvariant candidate
      found productionBound predicate doesMatch)
    (statusFull : (appendLogical workspaceLayout.capacity position
      (recognizerParentSeed candidate.production candidate.dot candidate.origin
        current completed) workspace).1.status = .full) where
  after : State
  execution : Executes verifiedParserCore predicate.after
    parserRecognizeParentMatchedBody
    (.returned (some (parseResultValue 2
      (Int.ofNat (appendLogical workspaceLayout.capacity position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspace).1.stateCount)
      (-1) (Int.ofNat position)))) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) predicate.after after
  wellFormed : StateWellFormed after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell after

noncomputable def RecognizerParentMatchedOriginBinding.close_full
    (originBinding : RecognizerParentMatchedOriginBinding grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      completed completedLhs origin current remaining beforeInvariant candidate
      found productionBound predicate doesMatch)
    (statusFull : (appendLogical workspaceLayout.capacity position
      (recognizerParentSeed candidate.production candidate.dot candidate.origin
        current completed) workspace).1.status = .full) :
    RecognizerParentClosedFull grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      stateCountCell cursorCell before position completed completedLhs origin
      current remaining beforeInvariant candidate found productionBound
      predicate doesMatch originBinding statusFull := by
  let originScope := originBinding.afterOriginRead.bindLocal 34
    (.signed .i32 (Int.ofNat candidate.origin))
  let full := originBinding.appendInvariant.execute_full statusFull
  let after := restoreLocals originBinding.afterOriginRead full.after
  have enteredOrigin : StoreEffect CellSet.empty
      originBinding.afterOriginRead originScope := by
    simpa [originScope] using bindLocal_effect originBinding.afterOriginRead 34
      (.signed .i32 (Int.ofNat candidate.origin))
  have scopeEffect : StoreEffect (CellSet.singleton workspaceCell)
      originBinding.afterOriginRead full.after :=
    (enteredOrigin.weaken CellSet.empty_subset).trans_same
      (by simpa [originScope] using full.effect.toStoreEffect)
  have closedEffect : ModifiesOnly (CellSet.singleton workspaceCell)
      originBinding.afterOriginRead after := by
    simpa [after] using scopeEffect.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    scopeEffect.restoreLocals_wellFormed originBinding.afterOriginWellFormed
      full.wellFormed
  have afterInvariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell after := by
    apply predicate.invariant.chartCursor.recognizer.after_same_workspace_effect
      ((originBinding.originEffect.weaken CellSet.empty_subset).trans_same
        closedEffect) afterWellFormed full.invariant
    simp [after, restoreLocals]
  exact {
    after := after
    execution := by
      rw [extractedParserRecognize_parent_matched_body_shape]
      simpa [originScope, after] using
        executesLetLocal (type := parserI32Type) originBinding.originEvaluation
          full.execution
    effect := (originBinding.originEffect.weaken CellSet.empty_subset).trans_same
      closedEffect
    wellFormed := afterWellFormed
    invariant := afterInvariant
  }

/-- One successful parent-completion iteration whose updated origin-chart
    cursor has a successor.  This packages the true branch, the mandatory
    cursor advance, and restoration of all candidate-local scopes. -/
structure RecognizerParentClosedAdvance
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position completed completedLhs origin current next : Nat)
    (remaining tail : List Nat)
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount)
    (bindings : RecognizerParentCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining beforeInvariant candidate found
      productionBound)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current remaining
      bindings.invariant candidate productionBound)
    (doesMatch : ParentCandidateMatches grammar candidate completedLhs
      productionBound)
    (originBinding : RecognizerParentMatchedOriginBinding grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current remaining
      bindings.invariant candidate found productionBound predicate doesMatch)
    (appended : RecognizerParentOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell
      (originBinding.afterOriginRead.bindLocal 34
        (.signed .i32 (Int.ofNat candidate.origin)))
      position candidate.production candidate.dot candidate.origin current
      completed originBinding.appendInvariant)
    (innerInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout
      (appendLogical workspaceLayout.capacity position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspace).2
      (appendResultValues workspaceLayout workspace position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspaceValues)
      grammarCell tokensCell workspaceCell stateCountCell cursorCell
      appended.after position completed completedLhs origin current
      (next :: tail)) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeParentLoopBody .next after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton stateCountCell)
        (CellSet.singleton cursorCell))) before after
  invariant : RecognizerParentLoopInvariant grammarLayout grammar words tokens
    workspaceLayout
    (appendLogical workspaceLayout.capacity position
      (recognizerParentSeed candidate.production candidate.dot
        candidate.origin current completed) workspace).2
    (appendResultValues workspaceLayout workspace position
      (recognizerParentSeed candidate.production candidate.dot
        candidate.origin current completed) workspaceValues)
    grammarCell tokensCell workspaceCell stateCountCell cursorCell after position
    completed completedLhs origin next tail

noncomputable def RecognizerParentClosedOkAppend.advance_and_close
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount)
    (bindings : RecognizerParentCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining beforeInvariant candidate found
      productionBound)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current remaining
      bindings.invariant candidate productionBound)
    (doesMatch : ParentCandidateMatches grammar candidate completedLhs
      productionBound)
    (originBinding : RecognizerParentMatchedOriginBinding grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current remaining
      bindings.invariant candidate found productionBound predicate doesMatch)
    (appended : RecognizerParentOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell
      (originBinding.afterOriginRead.bindLocal 34
        (.signed .i32 (Int.ofNat candidate.origin)))
      position candidate.production candidate.dot candidate.origin current
      completed originBinding.appendInvariant)
    (innerInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout
      (appendLogical workspaceLayout.capacity position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspace).2
      (appendResultValues workspaceLayout workspace position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspaceValues)
      grammarCell tokensCell workspaceCell stateCountCell cursorCell
      appended.after position completed completedLhs origin current
      (next :: tail))
    (closedAppend : RecognizerParentClosedOkAppend grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current remaining (next :: tail)
      bindings.invariant candidate found productionBound predicate doesMatch
      originBinding appended innerInvariant) :
    RecognizerParentClosedAdvance grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current next remaining tail beforeInvariant candidate
      found productionBound bindings predicate doesMatch originBinding appended
      innerInvariant := by
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton cursorCell))
  have conditionTrue : Evaluates verifiedParserCore
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      parserRecognizeParentPredicate (.boolean true) predicate.after := by
    simpa [doesMatch] using predicate.evaluation
  let advanced := closedAppend.invariant.chartCursor.advance
  let nextInner := closedAppend.invariant.after_cursor_effect
    advanced.invariant advanced.effect
  have selected : Executes verifiedParserCore
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      (.ifThenElse parserRecognizeParentPredicate
        parserRecognizeParentMatchedBody .skip) .next closedAppend.after :=
    executesIfTrue conditionTrue closedAppend.execution
  have innerExecution : Executes verifiedParserCore
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      parserRecognizeParentAfterBindings .next advanced.after := by
    rw [extractedParserRecognize_parent_after_bindings_shape]
    exact executesSequence selected advanced.execution
  have beforeAdvanceEffect : ModifiesOnly writes
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      closedAppend.after := by
    have predicateEffect : ModifiesOnly writes
        (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
          (grammar.productionAt ⟨candidate.production, by
            simpa [EarleyState.key] using productionBound⟩).rhs.length)))
        predicate.after :=
      predicate.effect.weaken CellSet.empty_subset
    have appendEffect : ModifiesOnly writes predicate.after
        closedAppend.after := closedAppend.effect.weaken (by
      intro cell listed
      exact match listed with
      | Or.inl workspace => Or.inl workspace
      | Or.inr count => Or.inr (Or.inl count))
    exact predicateEffect.trans_same appendEffect
  have innerEffect : ModifiesOnly writes
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      advanced.after :=
    beforeAdvanceEffect.trans_same (advanced.effect.weaken (by
      intro cell listed
      exact Or.inr (Or.inr listed)))
  let closed := bindings.close_scopes advanced.after .next writes innerExecution
    innerEffect nextInner.chartCursor.recognizer.wellFormed
  exact {
    after := closed.after
    execution := closed.execution
    effect := by simpa [writes] using closed.effect
    invariant := closed.restore_invariant nextInner (by
      intro cell written
      exact written)
  }

/-- Terminal successful parent-completion iteration.  When the updated chart
    suffix is empty, the exact `STATE_NEXT` load installs `-1`, after which the
    loop condition is false. -/
structure RecognizerParentClosedFinish
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position completed completedLhs origin current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount)
    (bindings : RecognizerParentCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining beforeInvariant candidate found
      productionBound)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current remaining
      bindings.invariant candidate productionBound)
    (doesMatch : ParentCandidateMatches grammar candidate completedLhs
      productionBound)
    (originBinding : RecognizerParentMatchedOriginBinding grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current remaining
      bindings.invariant candidate found productionBound predicate doesMatch)
    (appended : RecognizerParentOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell
      (originBinding.afterOriginRead.bindLocal 34
        (.signed .i32 (Int.ofNat candidate.origin)))
      position candidate.production candidate.dot candidate.origin current
      completed originBinding.appendInvariant)
    (innerInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout
      (appendLogical workspaceLayout.capacity position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspace).2
      (appendResultValues workspaceLayout workspace position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspaceValues)
      grammarCell tokensCell workspaceCell stateCountCell cursorCell
      appended.after position completed completedLhs origin current []) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeParentLoopBody .next after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton stateCountCell)
        (CellSet.singleton cursorCell))) before after
  invariant : RecognizerParentFinishedInvariant grammarLayout grammar words
    tokens workspaceLayout
    (appendLogical workspaceLayout.capacity position
      (recognizerParentSeed candidate.production candidate.dot
        candidate.origin current completed) workspace).2
    (appendResultValues workspaceLayout workspace position
      (recognizerParentSeed candidate.production candidate.dot
        candidate.origin current completed) workspaceValues)
    grammarCell tokensCell workspaceCell stateCountCell cursorCell after position
    completed completedLhs origin

noncomputable def RecognizerParentClosedOkAppend.finish_and_close
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.key.production < grammar.productionCount)
    (bindings : RecognizerParentCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining beforeInvariant candidate found
      productionBound)
    (predicate : RecognizerParentPredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current remaining
      bindings.invariant candidate productionBound)
    (doesMatch : ParentCandidateMatches grammar candidate completedLhs
      productionBound)
    (originBinding : RecognizerParentMatchedOriginBinding grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current remaining
      bindings.invariant candidate found productionBound predicate doesMatch)
    (appended : RecognizerParentOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell
      (originBinding.afterOriginRead.bindLocal 34
        (.signed .i32 (Int.ofNat candidate.origin)))
      position candidate.production candidate.dot candidate.origin current
      completed originBinding.appendInvariant)
    (innerInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout
      (appendLogical workspaceLayout.capacity position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspace).2
      (appendResultValues workspaceLayout workspace position
        (recognizerParentSeed candidate.production candidate.dot
          candidate.origin current completed) workspaceValues)
      grammarCell tokensCell workspaceCell stateCountCell cursorCell
      appended.after position completed completedLhs origin current [])
    (closedAppend : RecognizerParentClosedOkAppend grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      position completed completedLhs origin current remaining []
      bindings.invariant candidate found productionBound predicate doesMatch
      originBinding appended innerInvariant) :
    RecognizerParentClosedFinish grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining beforeInvariant candidate found
      productionBound bindings predicate doesMatch originBinding appended
      innerInvariant := by
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton cursorCell))
  have conditionTrue : Evaluates verifiedParserCore
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      parserRecognizeParentPredicate (.boolean true) predicate.after := by
    simpa [doesMatch] using predicate.evaluation
  let exhausted := closedAppend.invariant.chartCursor.exhaust
  let finishedInner := closedAppend.invariant.after_cursor_exhaustion
    exhausted.finished exhausted.effect
  have selected : Executes verifiedParserCore
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      (.ifThenElse parserRecognizeParentPredicate
        parserRecognizeParentMatchedBody .skip) .next closedAppend.after :=
    executesIfTrue conditionTrue closedAppend.execution
  have innerExecution : Executes verifiedParserCore
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      parserRecognizeParentAfterBindings .next exhausted.after := by
    rw [extractedParserRecognize_parent_after_bindings_shape]
    exact executesSequence selected exhausted.execution
  have beforeExhaustEffect : ModifiesOnly writes
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      closedAppend.after := by
    have predicateEffect : ModifiesOnly writes
        (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
          (grammar.productionAt ⟨candidate.production, by
            simpa [EarleyState.key] using productionBound⟩).rhs.length)))
        predicate.after := predicate.effect.weaken CellSet.empty_subset
    have appendEffect : ModifiesOnly writes predicate.after
        closedAppend.after := closedAppend.effect.weaken (by
      intro cell listed
      exact match listed with
      | Or.inl workspace => Or.inl workspace
      | Or.inr count => Or.inr (Or.inl count))
    exact predicateEffect.trans_same appendEffect
  have innerEffect : ModifiesOnly writes
      (bindings.afterRhsLengthRead.bindLocal 33 (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩).rhs.length)))
      exhausted.after := beforeExhaustEffect.trans_same
    (exhausted.effect.weaken (by
      intro cell listed
      exact Or.inr (Or.inr listed)))
  let closed := bindings.close_scopes exhausted.after .next writes
    innerExecution innerEffect finishedInner.chartCursor.recognizer.wellFormed
  exact {
    after := closed.after
    execution := closed.execution
    effect := by simpa [writes] using closed.effect
    invariant := closed.restore_finished finishedInner (by
      intro cell written
      exact written)
  }

/-- One live origin-chart position in the parent-completion traversal. -/
structure RecognizerParentActiveConfig
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position completed completedLhs origin : Nat) where
  workspace : LogicalWorkspace
  workspaceValues : List Int
  runtime : State
  current : Nat
  remaining : List Nat
  invariant : RecognizerParentLoopInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell runtime position completed
    completedLhs origin current remaining

/-- Explicit false-condition state after the origin chart has been consumed. -/
structure RecognizerParentSentinelConfig
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position completed completedLhs origin : Nat) where
  workspace : LogicalWorkspace
  workspaceValues : List Int
  runtime : State
  invariant : RecognizerParentFinishedInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell runtime position completed
    completedLhs origin

inductive RecognizerParentConfig
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position completed completedLhs origin : Nat) where
  | active (config : RecognizerParentActiveConfig grammarLayout grammar words
      tokens workspaceLayout grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position completed completedLhs origin)
  | sentinel (config : RecognizerParentSentinelConfig grammarLayout grammar
      words tokens workspaceLayout grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position completed completedLhs origin)

@[simp] def RecognizerParentConfig.workspace
    (config : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin) : LogicalWorkspace :=
  match config with
  | .active activeConfig => activeConfig.workspace
  | .sentinel sentinelConfig => sentinelConfig.workspace

@[simp] def RecognizerParentConfig.workspaceValues
    (config : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin) : List Int :=
  match config with
  | .active activeConfig => activeConfig.workspaceValues
  | .sentinel sentinelConfig => sentinelConfig.workspaceValues

@[simp] def RecognizerParentConfig.runtime
    (config : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin) : State :=
  match config with
  | .active activeConfig => activeConfig.runtime
  | .sentinel sentinelConfig => sentinelConfig.runtime

@[simp] def RecognizerParentConfig.candidate
    (config : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin) : Int :=
  match config with
  | .active activeConfig => Int.ofNat activeConfig.current
  | .sentinel _ => -1

def RecognizerParentConfig.functionalRuntime
    (config : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin) :
    Lanius.FunctionalView.Stateful.Loop.Runtime
      (parentTermMachine workspaceLayout grammar words grammarCell) 10 :=
  (parentWorld words tokens config.workspaceValues grammarCell tokensCell workspaceCell,
    parentEnvironment words config.workspaceValues grammarCell workspaceCell
      workspaceLayout config.workspace.states.length grammar.grammar.n_kinds
      position completed completedLhs config.candidate)

/-- Insertion consumes capacity; otherwise consuming the chart suffix makes
    progress. The extra suffix step makes the sentinel strictly smaller. -/
def RecognizerParentConfig.measure
    (config : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin) : Nat × Nat :=
  match config with
  | .active activeConfig =>
      (workspaceLayout.capacity - activeConfig.workspace.states.length,
        activeConfig.remaining.length + 1)
  | .sentinel sentinelConfig =>
      (workspaceLayout.capacity - sentinelConfig.workspace.states.length, 0)

theorem RecognizerParentConfig.functional_condition
    (config : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin) :
    Lanius.FunctionalView.Term.evaluate
      (parentTermMachine workspaceLayout grammar words grammarCell)
      config.functionalRuntime.world config.functionalRuntime.environment
      parentLoopCondition =
      .ok (.boolean (decide (config.candidate ≥ 0)),
        config.functionalRuntime.world) := by
  cases config with
  | active activeConfig =>
      simpa [RecognizerParentConfig.functionalRuntime,
        RecognizerParentConfig.workspace,
        RecognizerParentConfig.workspaceValues,
        RecognizerParentConfig.candidate,
        Lanius.FunctionalView.Stateful.Loop.Runtime.world,
        Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
        parentLoopCondition_evaluates workspaceLayout grammar words
          activeConfig.workspaceValues grammarCell workspaceCell
          activeConfig.workspace.states.length grammar.grammar.n_kinds
          position completed completedLhs (Int.ofNat activeConfig.current)
  | sentinel sentinelConfig =>
      simpa [RecognizerParentConfig.functionalRuntime,
        RecognizerParentConfig.workspace,
        RecognizerParentConfig.workspaceValues,
        RecognizerParentConfig.candidate,
        Lanius.FunctionalView.Stateful.Loop.Runtime.world,
        Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
        parentLoopCondition_evaluates workspaceLayout grammar words
          sentinelConfig.workspaceValues grammarCell workspaceCell
          sentinelConfig.workspace.states.length grammar.grammar.n_kinds
          position completed completedLhs (-1)

abbrev RecognizerParentLoopOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position completed completedLhs origin : Nat) :
    State → Completion → Prop :=
  WorkspaceLoopOutcome workspaceLayout.capacity beforeWorkspace
    (parserCapacityCompletion position)
    (fun workspace workspaceValues after =>
      RecognizerParentFinishedInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell after position completed
        completedLhs origin)
    (fun workspace workspaceValues after =>
      RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
        workspace workspaceValues grammarCell tokensCell workspaceCell after)

/-- Parent replay's physical and FunctionalView results are one value.  On
    normal completion this records the exact compact world and sentinel
    environment reached by the FunctionalView loop, preventing an enclosing
    proof from pairing that runtime with a different hidden workspace witness. -/
inductive RecognizerParentSynchronizedOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position completed completedLhs origin : Nat)
    (after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (parentTermMachine workspaceLayout grammar words grammarCell) 10) :
    State → Completion → Prop where
  | completed (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (invariant : RecognizerParentFinishedInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell physicalAfter position completed
        completedLhs origin)
      (worldEq : after.world = parentWorld words tokens workspaceValues
        grammarCell tokensCell workspaceCell)
      (environmentEq : after.environment = parentEnvironment words
        workspaceValues grammarCell workspaceCell workspaceLayout
        workspace.states.length grammar.grammar.n_kinds position completed
        completedLhs (-1)) :
      RecognizerParentSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell cursorCell position completed completedLhs origin after
        physicalAfter .next
  | full (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (terminal : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter) :
      RecognizerParentSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell cursorCell position completed completedLhs origin after
        physicalAfter (parserCapacityCompletion position stateCount)

theorem RecognizerParentSynchronizedOutcome.physical
    {completed : Nat}
    (outcome : RecognizerParentSynchronizedOutcome grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position completed completedLhs
      origin after physicalAfter completion) :
    RecognizerParentLoopOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position completed completedLhs origin
      physicalAfter completion := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter growth invariant _ _ =>
      exact .completed workspace workspaceValues physicalAfter growth invariant
  | full workspace workspaceValues physicalAfter growth terminal stateCount
      wellFormed =>
      exact .full workspace workspaceValues physicalAfter growth terminal
        stateCount wellFormed

theorem RecognizerParentSynchronizedOutcome.view
    {completed : Nat}
    (outcome : RecognizerParentSynchronizedOutcome grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position completed completedLhs
      origin after physicalAfter completion) :
    (completion = .next ∧
      ∃ workspace : LogicalWorkspace,
      ∃ workspaceValues : List Int,
      ∃ growth : WorkspaceAppendClosure workspaceLayout.capacity
          beforeWorkspace workspace,
      ∃ invariant : RecognizerParentFinishedInvariant grammarLayout grammar
          words tokens workspaceLayout workspace workspaceValues grammarCell
          tokensCell workspaceCell stateCountCell cursorCell physicalAfter
          position completed completedLhs origin,
        after.world = parentWorld words tokens workspaceValues grammarCell
          tokensCell workspaceCell ∧
        after.environment = parentEnvironment words workspaceValues grammarCell
          workspaceCell workspaceLayout workspace.states.length
          grammar.grammar.n_kinds position completed completedLhs (-1)) ∨
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

theorem RecognizerParentSynchronizedOutcome.prepend_growth
    {grammarLayout : PackedGrammarLayout} {grammar : IndexedGrammar}
    {words : List Int} {tokens : List Nat}
    {workspaceLayout : WorkspaceLayout}
    {grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId}
    {position completed completedLhs origin : Nat}
    {beforeWorkspace middleWorkspace : LogicalWorkspace}
    {after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (parentTermMachine workspaceLayout grammar words grammarCell) 10}
    {physicalAfter : State} {completion : Completion}
    (outcome : RecognizerParentSynchronizedOutcome grammarLayout grammar words
      tokens workspaceLayout middleWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position completed completedLhs
      origin after physicalAfter completion)
    (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
      middleWorkspace) :
    RecognizerParentSynchronizedOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position completed completedLhs origin after
      physicalAfter completion := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter nextGrowth invariant
      worldEq environmentEq =>
      exact .completed workspace workspaceValues physicalAfter
        (growth.trans nextGrowth) invariant worldEq environmentEq
  | full workspace workspaceValues physicalAfter nextGrowth terminal stateCount
      wellFormed =>
      exact .full workspace workspaceValues physicalAfter
        (growth.trans nextGrowth) terminal stateCount wellFormed

structure RecognizerParentLoopExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position completed completedLhs origin current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position completed
      completedLhs origin current remaining) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before parserRecognizeParentLoop
    completion after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton stateCountCell)
        (CellSet.singleton cursorCell))) before after
  outcome : RecognizerParentLoopOutcome grammarLayout grammar words tokens
    workspaceLayout workspace grammarCell tokensCell workspaceCell stateCountCell
    cursorCell position completed completedLhs origin after completion

/-- Semantic result transported by the generic FunctionalView loop. -/
structure RecognizerParentFunctionalResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position completed completedLhs origin : Nat)
    (config : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (_after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (parentTermMachine workspaceLayout grammar words grammarCell) 10) where
  physicalAfter : State
  execution : Executes verifiedParserCore config.runtime
    parserRecognizeParentLoop
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
    physicalAfter
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton stateCountCell)
        (CellSet.singleton cursorCell))) config.runtime physicalAfter
  outcome : RecognizerParentSynchronizedOutcome grammarLayout grammar words
    tokens workspaceLayout config.workspace grammarCell tokensCell workspaceCell
    stateCountCell cursorCell position completed completedLhs origin _after physicalAfter
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)

/-- One exact FunctionalView transition of the parent-completion traversal. -/
noncomputable def RecognizerParentConfig.functional_decide
    (config : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin) :
    Lanius.FunctionalView.Stateful.Loop.Decision
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      parentLoopCondition parentBodyCommand
      (RecognizerParentConfig grammarLayout grammar words tokens
        workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
        cursorCell position completed completedLhs origin)
      RecognizerParentConfig.functionalRuntime
      RecognizerParentConfig.measure
      (RecognizerParentFunctionalResult grammarLayout grammar words tokens
        workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
        cursorCell position completed completedLhs origin) config := by
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton cursorCell))
  cases config with
  | sentinel sentinelConfig =>
      have functionalFalse : Lanius.FunctionalView.Term.evaluate
          (parentTermMachine workspaceLayout grammar words grammarCell)
          (RecognizerParentConfig.functionalRuntime
            (.sentinel sentinelConfig)).world
          (RecognizerParentConfig.functionalRuntime
            (.sentinel sentinelConfig)).environment
          parentLoopCondition =
          .ok (.boolean false,
            (RecognizerParentConfig.functionalRuntime
              (.sentinel sentinelConfig)).world) := by
        simpa [RecognizerParentConfig.candidate] using
          (RecognizerParentConfig.functional_condition
            (.sentinel sentinelConfig))
      apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
      exact {
        completion := .next
        after := RecognizerParentConfig.functionalRuntime
          (.sentinel sentinelConfig)
        edge := .conditionFalse functionalFalse
        result := {
          physicalAfter := sentinelConfig.runtime
          execution := sentinelConfig.invariant.condition_negative |>
            executesWhileFalse
          effect := ModifiesOnly.reflAny writes sentinelConfig.runtime
          outcome := .completed sentinelConfig.workspace
            sentinelConfig.workspaceValues sentinelConfig.runtime
            (.refl sentinelConfig.workspace) sentinelConfig.invariant rfl rfl
        }
      }
  | active activeConfig =>
      let invariant := activeConfig.invariant
      let candidate := Classical.choose invariant.chartCursor.state_at_cursor
      have candidateFacts :=
        Classical.choose_spec invariant.chartCursor.state_at_cursor
      have found : activeConfig.workspace.state? activeConfig.current =
          some candidate := candidateFacts.1
      have candidateWithin := invariant.chartCursor.state_within_grammar
        candidate found
      let bindings := invariant.bind_candidate_fields candidate found
        candidateWithin.productionBound
      let predicate := bindings.evaluate_predicate
      have conditionTrue := invariant.chartCursor.condition_nonnegative
      have functionalTrue : Lanius.FunctionalView.Term.evaluate
          (parentTermMachine workspaceLayout grammar words grammarCell)
          (RecognizerParentConfig.functionalRuntime
            (.active activeConfig)).world
          (RecognizerParentConfig.functionalRuntime
            (.active activeConfig)).environment
          parentLoopCondition =
          .ok (.boolean true,
            (RecognizerParentConfig.functionalRuntime
              (.active activeConfig)).world) := by
        simpa [RecognizerParentConfig.candidate] using
          (RecognizerParentConfig.functional_condition
            (.active activeConfig))
      by_cases doesMatch : ParentCandidateMatches grammar candidate
          completedLhs candidateWithin.productionBound
      · let originBinding := bindings.bind_matched_origin predicate doesMatch
        let seed := recognizerParentSeed candidate.production candidate.dot
          candidate.origin activeConfig.current completed
        let logical := appendLogical workspaceLayout.capacity position seed
          activeConfig.workspace
        let nextValues := appendResultValues workspaceLayout
          activeConfig.workspace position seed activeConfig.workspaceValues
        cases statusEq : logical.1.status with
        | full =>
            have statusFull : (appendLogical workspaceLayout.capacity position
                seed activeConfig.workspace).1.status = .full := by
              simpa [logical]
            let full := originBinding.close_full (by
              simpa [seed] using statusFull)
            have conditionTrue' : Evaluates verifiedParserCore
                (bindings.afterRhsLengthRead.bindLocal 33
                  (.signed .i32 (Int.ofNat
                    (grammar.productionAt ⟨candidate.production, by
                      simpa [EarleyState.key] using
                        candidateWithin.productionBound⟩).rhs.length)))
                parserRecognizeParentPredicate (.boolean true)
                predicate.after := by
              simpa [doesMatch] using predicate.evaluation
            have selected : Executes verifiedParserCore
                (bindings.afterRhsLengthRead.bindLocal 33
                  (.signed .i32 (Int.ofNat
                    (grammar.productionAt ⟨candidate.production, by
                      simpa [EarleyState.key] using
                        candidateWithin.productionBound⟩).rhs.length)))
                (.ifThenElse parserRecognizeParentPredicate
                  parserRecognizeParentMatchedBody .skip)
                (.returned (some (parseResultValue 2
                  (Int.ofNat logical.1.stateCount) (-1)
                  (Int.ofNat position)))) full.after := by
              simpa [logical] using executesIfTrue conditionTrue'
                full.execution
            have innerExecution : Executes verifiedParserCore
                (bindings.afterRhsLengthRead.bindLocal 33
                  (.signed .i32 (Int.ofNat
                    (grammar.productionAt ⟨candidate.production, by
                      simpa [EarleyState.key] using
                        candidateWithin.productionBound⟩).rhs.length)))
                parserRecognizeParentAfterBindings
                (.returned (some (parseResultValue 2
                  (Int.ofNat logical.1.stateCount) (-1)
                  (Int.ofNat position)))) full.after := by
              rw [extractedParserRecognize_parent_after_bindings_shape]
              exact executesSequenceReturned selected
            have innerEffect : ModifiesOnly
                (CellSet.singleton workspaceCell)
                (bindings.afterRhsLengthRead.bindLocal 33
                  (.signed .i32 (Int.ofNat
                    (grammar.productionAt ⟨candidate.production, by
                      simpa [EarleyState.key] using
                        candidateWithin.productionBound⟩).rhs.length)))
                full.after :=
              (predicate.effect.weaken CellSet.empty_subset).trans_same
                full.effect
            let closed := bindings.close_scopes full.after
              (.returned (some (parseResultValue 2
                (Int.ofNat logical.1.stateCount) (-1) (Int.ofNat position))))
              (CellSet.singleton workspaceCell) innerExecution innerEffect
              full.wellFormed
            have closedInvariant : RecognizerInvariant grammarLayout grammar
                words tokens workspaceLayout activeConfig.workspace
                activeConfig.workspaceValues grammarCell tokensCell
                workspaceCell closed.after := by
              apply invariant.chartCursor.recognizer
                |>.after_same_workspace_effect closed.effect
                  closed.wellFormed full.invariant closed.cells
            have bodyResult := invariant.functional_full_body candidate found
              candidateWithin.productionBound doesMatch (by
                simpa [seed] using statusFull)
            let returnedRuntime :
                Lanius.FunctionalView.Stateful.Loop.Runtime
                  (parentTermMachine workspaceLayout grammar words
                    grammarCell) 10 :=
              (parentWorld words tokens nextValues grammarCell tokensCell workspaceCell,
                (RecognizerParentConfig.functionalRuntime
                  (.active activeConfig)).environment)
            have functionalBody :
                Lanius.FunctionalView.Stateful.Command.Evaluates
                  (parentTermMachine workspaceLayout grammar words grammarCell)
                  (parentStatefulMachine workspaceLayout grammar words
                    grammarCell)
                  (RecognizerParentConfig.functionalRuntime
                    (.active activeConfig)).world
                  (RecognizerParentConfig.functionalRuntime
                    (.active activeConfig)).environment parentBodyCommand
                  (.returned (some (parseResultValue 2
                    (Int.ofNat logical.1.stateCount) (-1)
                    (Int.ofNat position))))
                  returnedRuntime.world returnedRuntime.environment := by
              simpa [RecognizerParentConfig.functionalRuntime,
                RecognizerParentConfig.candidate, logical, returnedRuntime,
                nextValues, seed,
                Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                  bodyResult
            apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
            exact {
              completion := .returned (some (parseResultValue 2
                (Int.ofNat logical.1.stateCount) (-1) (Int.ofNat position)))
              after := returnedRuntime
              edge := .returned functionalTrue functionalBody
              result := {
                physicalAfter := closed.after
                execution := by
                  rw [extractedParserRecognize_parent_loop_shape]
                  exact executesWhileReturned conditionTrue closed.execution
                effect := closed.effect.weaken (by
                  intro cell written
                  exact Or.inl written)
                outcome := .full activeConfig.workspace
                  activeConfig.workspaceValues closed.after
                  (.refl activeConfig.workspace) closedInvariant
                  logical.1.stateCount closed.wellFormed
              }
            }
        | ok =>
            have statusOk : (appendLogical workspaceLayout.capacity position
                seed activeConfig.workspace).1.status = .ok := by
              simpa [logical]
            let appended := originBinding.appendInvariant.execute_ok (by
              simpa [seed] using statusOk)
            let cursorResult := originBinding.classify_ok_append appended
            cases cursorResult with
            | unchanged innerInvariant countUnchanged =>
                cases remainingEq : activeConfig.remaining with
                | nil =>
                    have caseInnerInvariant : RecognizerParentLoopInvariant
                        grammarLayout grammar words tokens workspaceLayout
                        logical.2 nextValues grammarCell tokensCell
                        workspaceCell stateCountCell cursorCell appended.after
                        position completed completedLhs origin
                        activeConfig.current [] := by
                      simpa [logical, nextValues, seed, remainingEq] using
                        innerInvariant
                    let closedAppend := originBinding.close_ok_append appended
                      caseInnerInvariant
                    let step := RecognizerParentClosedOkAppend.finish_and_close
                      invariant candidate found candidateWithin.productionBound
                      bindings predicate doesMatch originBinding appended
                      caseInnerInvariant closedAppend
                    let nextConfig : RecognizerParentConfig grammarLayout
                        grammar words tokens workspaceLayout grammarCell
                        tokensCell workspaceCell stateCountCell cursorCell
                        position completed completedLhs origin := .sentinel {
                      workspace := logical.2
                      workspaceValues := nextValues
                      runtime := step.after
                      invariant := step.invariant
                    }
                    have bodyResult := invariant.functional_ok_body candidate
                      found candidateWithin.productionBound doesMatch (by
                        simpa [seed] using statusOk) [] appended.after (by
                        simpa [logical, nextValues, seed] using
                          caseInnerInvariant)
                    have functionalBody :
                        Lanius.FunctionalView.Stateful.Command.Evaluates
                          (parentTermMachine workspaceLayout grammar words
                            grammarCell)
                          (parentStatefulMachine workspaceLayout grammar words
                            grammarCell)
                          (RecognizerParentConfig.functionalRuntime
                            (.active activeConfig)).world
                          (RecognizerParentConfig.functionalRuntime
                            (.active activeConfig)).environment
                          parentBodyCommand .next
                          nextConfig.functionalRuntime.world
                          nextConfig.functionalRuntime.environment := by
                      simpa [nextConfig,
                        RecognizerParentConfig.functionalRuntime, logical,
                        nextValues, seed, encodeStateId,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
                        using bodyResult
                    apply Lanius.FunctionalView.Stateful.Loop.Decision.next
                      nextConfig
                    · exact .next functionalTrue functionalBody
                    · simp only [WellFoundedRelation.rel,
                        RecognizerParentConfig.measure, nextConfig]
                      rw [countUnchanged]
                      apply Prod.Lex.right
                      show sizeOf 0 < sizeOf
                        (activeConfig.remaining.length + 1)
                      simpa [remainingEq] using Nat.zero_lt_one
                    · intro completion after result
                      exact {
                        physicalAfter := result.physicalAfter
                        execution := by
                          rw [extractedParserRecognize_parent_loop_shape]
                          exact executesWhileTrueThen conditionTrue
                            step.execution result.execution
                        effect := by
                          simpa [writes] using
                            step.effect.trans_same result.effect
                        outcome := result.outcome.prepend_growth
                          (WorkspaceAppendClosure.single
                            workspaceLayout.capacity position seed
                            activeConfig.workspace)
                      }
                | cons next tail =>
                    have caseInnerInvariant : RecognizerParentLoopInvariant
                        grammarLayout grammar words tokens workspaceLayout
                        logical.2 nextValues grammarCell tokensCell
                        workspaceCell stateCountCell cursorCell appended.after
                        position completed completedLhs origin
                        activeConfig.current (next :: tail) := by
                      simpa [logical, nextValues, seed, remainingEq] using
                        innerInvariant
                    let closedAppend := originBinding.close_ok_append appended
                      caseInnerInvariant
                    let step := RecognizerParentClosedOkAppend.advance_and_close
                      invariant candidate found candidateWithin.productionBound
                      bindings predicate doesMatch originBinding appended
                      caseInnerInvariant closedAppend
                    let nextConfig : RecognizerParentConfig grammarLayout
                        grammar words tokens workspaceLayout grammarCell
                        tokensCell workspaceCell stateCountCell cursorCell
                        position completed completedLhs origin := .active {
                      workspace := logical.2
                      workspaceValues := nextValues
                      runtime := step.after
                      current := next
                      remaining := tail
                      invariant := step.invariant
                    }
                    have bodyResult := invariant.functional_ok_body candidate
                      found candidateWithin.productionBound doesMatch (by
                        simpa [seed] using statusOk) (next :: tail)
                      appended.after (by
                        simpa [logical, nextValues, seed] using
                          caseInnerInvariant)
                    have functionalBody :
                        Lanius.FunctionalView.Stateful.Command.Evaluates
                          (parentTermMachine workspaceLayout grammar words
                            grammarCell)
                          (parentStatefulMachine workspaceLayout grammar words
                            grammarCell)
                          (RecognizerParentConfig.functionalRuntime
                            (.active activeConfig)).world
                          (RecognizerParentConfig.functionalRuntime
                            (.active activeConfig)).environment
                          parentBodyCommand .next
                          nextConfig.functionalRuntime.world
                          nextConfig.functionalRuntime.environment := by
                      simpa [nextConfig,
                        RecognizerParentConfig.functionalRuntime, logical,
                        nextValues, seed, encodeStateId,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
                        using bodyResult
                    apply Lanius.FunctionalView.Stateful.Loop.Decision.next
                      nextConfig
                    · exact .next functionalTrue functionalBody
                    · simp only [WellFoundedRelation.rel,
                        RecognizerParentConfig.measure, nextConfig]
                      rw [countUnchanged]
                      apply Prod.Lex.right
                      have suffixDecrease : tail.length + 1 <
                          activeConfig.remaining.length + 1 := by
                        rw [remainingEq]
                        simp
                      show sizeOf (tail.length + 1) < sizeOf
                        (activeConfig.remaining.length + 1)
                      simpa using suffixDecrease
                    · intro completion after result
                      exact {
                        physicalAfter := result.physicalAfter
                        execution := by
                          rw [extractedParserRecognize_parent_loop_shape]
                          exact executesWhileTrueThen conditionTrue
                            step.execution result.execution
                        effect := by
                          simpa [writes] using
                            step.effect.trans_same result.effect
                        outcome := result.outcome.prepend_growth
                          (WorkspaceAppendClosure.single
                            workspaceLayout.capacity position seed
                            activeConfig.workspace)
                      }
            | inserted nextRemaining innerInvariant countIncreased =>
                cases nextEq : nextRemaining with
                | nil =>
                    have caseInnerInvariant : RecognizerParentLoopInvariant
                        grammarLayout grammar words tokens workspaceLayout
                        logical.2 nextValues grammarCell tokensCell
                        workspaceCell stateCountCell cursorCell appended.after
                        position completed completedLhs origin
                        activeConfig.current [] := by
                      simpa [logical, nextValues, seed, nextEq] using
                        innerInvariant
                    let closedAppend := originBinding.close_ok_append appended
                      caseInnerInvariant
                    let step := RecognizerParentClosedOkAppend.finish_and_close
                      invariant candidate found candidateWithin.productionBound
                      bindings predicate doesMatch originBinding appended
                      caseInnerInvariant closedAppend
                    let nextConfig : RecognizerParentConfig grammarLayout
                        grammar words tokens workspaceLayout grammarCell
                        tokensCell workspaceCell stateCountCell cursorCell
                        position completed completedLhs origin := .sentinel {
                      workspace := logical.2
                      workspaceValues := nextValues
                      runtime := step.after
                      invariant := step.invariant
                    }
                    have bodyResult := invariant.functional_ok_body candidate
                      found candidateWithin.productionBound doesMatch (by
                        simpa [seed] using statusOk) [] appended.after (by
                        simpa [logical, nextValues, seed] using
                          caseInnerInvariant)
                    have functionalBody :
                        Lanius.FunctionalView.Stateful.Command.Evaluates
                          (parentTermMachine workspaceLayout grammar words
                            grammarCell)
                          (parentStatefulMachine workspaceLayout grammar words
                            grammarCell)
                          (RecognizerParentConfig.functionalRuntime
                            (.active activeConfig)).world
                          (RecognizerParentConfig.functionalRuntime
                            (.active activeConfig)).environment
                          parentBodyCommand .next
                          nextConfig.functionalRuntime.world
                          nextConfig.functionalRuntime.environment := by
                      simpa [nextConfig,
                        RecognizerParentConfig.functionalRuntime, logical,
                        nextValues, seed, encodeStateId,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
                        using bodyResult
                    apply Lanius.FunctionalView.Stateful.Loop.Decision.next
                      nextConfig
                    · exact .next functionalTrue functionalBody
                    · simp only [WellFoundedRelation.rel,
                        RecognizerParentConfig.measure, nextConfig]
                      have afterFits := caseInnerInvariant.chartCursor
                        |>.recognizer.workspaceEncoded.stateCountFits
                      have grew : activeConfig.workspace.states.length <
                          logical.2.states.length := by
                        change activeConfig.workspace.states.length <
                          (appendLogical workspaceLayout.capacity position seed
                            activeConfig.workspace).2.states.length
                        rw [countIncreased]
                        omega
                      exact Prod.Lex.left _ _
                        (Nat.sub_lt_sub_left
                          (Nat.lt_of_lt_of_le grew afterFits) grew)
                    · intro completion after result
                      exact {
                        physicalAfter := result.physicalAfter
                        execution := by
                          rw [extractedParserRecognize_parent_loop_shape]
                          exact executesWhileTrueThen conditionTrue
                            step.execution result.execution
                        effect := by
                          simpa [writes] using
                            step.effect.trans_same result.effect
                        outcome := result.outcome.prepend_growth
                          (WorkspaceAppendClosure.single
                            workspaceLayout.capacity position seed
                            activeConfig.workspace)
                      }
                | cons next tail =>
                    have caseInnerInvariant : RecognizerParentLoopInvariant
                        grammarLayout grammar words tokens workspaceLayout
                        logical.2 nextValues grammarCell tokensCell
                        workspaceCell stateCountCell cursorCell appended.after
                        position completed completedLhs origin
                        activeConfig.current (next :: tail) := by
                      simpa [logical, nextValues, seed, nextEq] using
                        innerInvariant
                    let closedAppend := originBinding.close_ok_append appended
                      caseInnerInvariant
                    let step := RecognizerParentClosedOkAppend.advance_and_close
                      invariant candidate found candidateWithin.productionBound
                      bindings predicate doesMatch originBinding appended
                      caseInnerInvariant closedAppend
                    let nextConfig : RecognizerParentConfig grammarLayout
                        grammar words tokens workspaceLayout grammarCell
                        tokensCell workspaceCell stateCountCell cursorCell
                        position completed completedLhs origin := .active {
                      workspace := logical.2
                      workspaceValues := nextValues
                      runtime := step.after
                      current := next
                      remaining := tail
                      invariant := step.invariant
                    }
                    have bodyResult := invariant.functional_ok_body candidate
                      found candidateWithin.productionBound doesMatch (by
                        simpa [seed] using statusOk) (next :: tail)
                      appended.after (by
                        simpa [logical, nextValues, seed] using
                          caseInnerInvariant)
                    have functionalBody :
                        Lanius.FunctionalView.Stateful.Command.Evaluates
                          (parentTermMachine workspaceLayout grammar words
                            grammarCell)
                          (parentStatefulMachine workspaceLayout grammar words
                            grammarCell)
                          (RecognizerParentConfig.functionalRuntime
                            (.active activeConfig)).world
                          (RecognizerParentConfig.functionalRuntime
                            (.active activeConfig)).environment
                          parentBodyCommand .next
                          nextConfig.functionalRuntime.world
                          nextConfig.functionalRuntime.environment := by
                      simpa [nextConfig,
                        RecognizerParentConfig.functionalRuntime, logical,
                        nextValues, seed, encodeStateId,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
                        using bodyResult
                    apply Lanius.FunctionalView.Stateful.Loop.Decision.next
                      nextConfig
                    · exact .next functionalTrue functionalBody
                    · simp only [WellFoundedRelation.rel,
                        RecognizerParentConfig.measure, nextConfig]
                      have afterFits := caseInnerInvariant.chartCursor
                        |>.recognizer.workspaceEncoded.stateCountFits
                      have grew : activeConfig.workspace.states.length <
                          logical.2.states.length := by
                        change activeConfig.workspace.states.length <
                          (appendLogical workspaceLayout.capacity position seed
                            activeConfig.workspace).2.states.length
                        rw [countIncreased]
                        omega
                      exact Prod.Lex.left _ _
                        (Nat.sub_lt_sub_left
                          (Nat.lt_of_lt_of_le grew afterFits) grew)
                    · intro completion after result
                      exact {
                        physicalAfter := result.physicalAfter
                        execution := by
                          rw [extractedParserRecognize_parent_loop_shape]
                          exact executesWhileTrueThen conditionTrue
                            step.execution result.execution
                        effect := by
                          simpa [writes] using
                            step.effect.trans_same result.effect
                        outcome := result.outcome.prepend_growth
                          (WorkspaceAppendClosure.single
                            workspaceLayout.capacity position seed
                            activeConfig.workspace)
                      }
      · cases remainingEq : activeConfig.remaining with
        | nil =>
            have caseInvariant : RecognizerParentLoopInvariant grammarLayout
                grammar words tokens workspaceLayout activeConfig.workspace
                activeConfig.workspaceValues grammarCell tokensCell
                workspaceCell stateCountCell cursorCell activeConfig.runtime
                position completed completedLhs origin activeConfig.current
                [] := by
              simpa [remainingEq] using invariant
            let caseBindings := caseInvariant.bind_candidate_fields candidate
              found candidateWithin.productionBound
            let casePredicate := caseBindings.evaluate_predicate
            let closed := caseBindings.close_no_match_finish casePredicate
              doesMatch
            let finished := caseBindings.after_no_match_finish casePredicate
              doesMatch
            let nextConfig : RecognizerParentConfig grammarLayout grammar words
                tokens workspaceLayout grammarCell tokensCell workspaceCell
                stateCountCell cursorCell position completed completedLhs
                origin := .sentinel {
              workspace := activeConfig.workspace
              workspaceValues := activeConfig.workspaceValues
              runtime := closed.after
              invariant := finished
            }
            have bodyResult := caseInvariant.functional_no_match_body candidate
              found candidateWithin.productionBound doesMatch
            have functionalBody :
                Lanius.FunctionalView.Stateful.Command.Evaluates
                  (parentTermMachine workspaceLayout grammar words grammarCell)
                  (parentStatefulMachine workspaceLayout grammar words
                    grammarCell)
                  (RecognizerParentConfig.functionalRuntime
                    (.active activeConfig)).world
                  (RecognizerParentConfig.functionalRuntime
                    (.active activeConfig)).environment parentBodyCommand
                  .next nextConfig.functionalRuntime.world
                  nextConfig.functionalRuntime.environment := by
              simpa [nextConfig, RecognizerParentConfig.functionalRuntime,
                encodeStateId,
                Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                  bodyResult
            apply Lanius.FunctionalView.Stateful.Loop.Decision.next nextConfig
            · exact .next functionalTrue functionalBody
            · simp only [WellFoundedRelation.rel,
                RecognizerParentConfig.measure, nextConfig]
              apply Prod.Lex.right
              show sizeOf 0 < sizeOf
                (activeConfig.remaining.length + 1)
              simpa [remainingEq] using Nat.zero_lt_one
            · intro completion after result
              exact {
                physicalAfter := result.physicalAfter
                execution := by
                  rw [extractedParserRecognize_parent_loop_shape]
                  exact executesWhileTrueThen conditionTrue closed.execution
                    result.execution
                effect := by
                  have first : ModifiesOnly writes activeConfig.runtime
                      closed.after := closed.effect.weaken (by
                    intro cell written
                    exact Or.inr (Or.inr written))
                  simpa [writes] using first.trans_same result.effect
                outcome := result.outcome
              }
        | cons next tail =>
            have caseInvariant : RecognizerParentLoopInvariant grammarLayout
                grammar words tokens workspaceLayout activeConfig.workspace
                activeConfig.workspaceValues grammarCell tokensCell
                workspaceCell stateCountCell cursorCell activeConfig.runtime
                position completed completedLhs origin activeConfig.current
                (next :: tail) := by
              simpa [remainingEq] using invariant
            let caseBindings := caseInvariant.bind_candidate_fields candidate
              found candidateWithin.productionBound
            let casePredicate := caseBindings.evaluate_predicate
            let closed := caseBindings.close_no_match_advance casePredicate
              doesMatch
            let nextInvariant := caseBindings.after_no_match_advance
              casePredicate doesMatch
            let nextConfig : RecognizerParentConfig grammarLayout grammar words
                tokens workspaceLayout grammarCell tokensCell workspaceCell
                stateCountCell cursorCell position completed completedLhs
                origin := .active {
              workspace := activeConfig.workspace
              workspaceValues := activeConfig.workspaceValues
              runtime := closed.after
              current := next
              remaining := tail
              invariant := nextInvariant
            }
            have bodyResult := caseInvariant.functional_no_match_body candidate
              found candidateWithin.productionBound doesMatch
            have functionalBody :
                Lanius.FunctionalView.Stateful.Command.Evaluates
                  (parentTermMachine workspaceLayout grammar words grammarCell)
                  (parentStatefulMachine workspaceLayout grammar words
                    grammarCell)
                  (RecognizerParentConfig.functionalRuntime
                    (.active activeConfig)).world
                  (RecognizerParentConfig.functionalRuntime
                    (.active activeConfig)).environment parentBodyCommand
                  .next nextConfig.functionalRuntime.world
                  nextConfig.functionalRuntime.environment := by
              simpa [nextConfig, RecognizerParentConfig.functionalRuntime,
                encodeStateId,
                Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                  bodyResult
            apply Lanius.FunctionalView.Stateful.Loop.Decision.next nextConfig
            · exact .next functionalTrue functionalBody
            · simp only [WellFoundedRelation.rel,
                RecognizerParentConfig.measure, nextConfig]
              apply Prod.Lex.right
              have suffixDecrease : tail.length + 1 <
                  activeConfig.remaining.length + 1 := by
                rw [remainingEq]
                simp
              show sizeOf (tail.length + 1) < sizeOf
                (activeConfig.remaining.length + 1)
              simpa using suffixDecrease
            · intro completion after result
              exact {
                physicalAfter := result.physicalAfter
                execution := by
                  rw [extractedParserRecognize_parent_loop_shape]
                  exact executesWhileTrueThen conditionTrue closed.execution
                    result.execution
                effect := by
                  have first : ModifiesOnly writes activeConfig.runtime
                      closed.after := closed.effect.weaken (by
                    intro cell written
                    exact Or.inr (Or.inr written))
                  simpa [writes] using first.trans_same result.effect
                outcome := result.outcome
              }

/-- The total compact FunctionalView execution retained independently of its
    structural-Core refinement so an enclosing recognizer command can embed
    the same semantic trace. -/
noncomputable def RecognizerParentConfig.functional_run
    (config : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin) :=
  Lanius.FunctionalView.Stateful.Loop.run
    (parentTermMachine workspaceLayout grammar words grammarCell)
    (parentStatefulMachine workspaceLayout grammar words grammarCell)
    parentLoopCondition parentBodyCommand
    (RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin)
    RecognizerParentConfig.functionalRuntime
    RecognizerParentConfig.measure
    (RecognizerParentFunctionalResult grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin)
    RecognizerParentConfig.functional_decide config

theorem RecognizerParentConfig.functional_run_evaluates
    (config : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (parentTermMachine workspaceLayout grammar words grammarCell)
      (parentStatefulMachine workspaceLayout grammar words grammarCell)
      config.functionalRuntime.world config.functionalRuntime.environment
      parentLoopCommand config.functional_run.completion
      config.functional_run.after.world
      config.functional_run.after.environment :=
  config.functional_run.trace.evaluates

/-- Total execution of the exact artifact-derived parent-completion loop,
    assembled from its FunctionalView condition and body semantics. -/
noncomputable def RecognizerParentLoopInvariant.execute_loop
    (invariant : RecognizerParentLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining) :
    RecognizerParentLoopExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position completed
      completedLhs origin current remaining invariant := by
  let initial : RecognizerParentConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position completed completedLhs origin := .active {
    workspace := workspace
    workspaceValues := workspaceValues
    runtime := runtime
    current := current
    remaining := remaining
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
