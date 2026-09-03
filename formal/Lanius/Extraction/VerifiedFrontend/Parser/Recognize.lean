import Lanius.Extraction.VerifiedFrontend.Parser.ScanFunctionalView
import Lanius.Extraction.VerifiedFrontend.Parser.Validation
import Lanius.Extraction.VerifiedFrontend.Parser.Append
import Lanius.Extraction.VerifiedFrontend.Parser.Result
import Lanius.LoopVerification
import Lanius.Compiler.WorkspaceLoop
import Lanius.Compiler.ParserTree

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
open Lanius.Extraction.ParserAccessors
open Lanius.Extraction.ParserValidation
open Lanius.Extraction.ParserFind
open Lanius.Extraction.ParserAppend
open Lanius.Extraction.ParserResult
open Lanius.Compiler.Parser

def extractedParserRecognizeBody : Stmt :=
  extractedParserRecognizeFunction.body.getD .skip

def parserRecognizeGrammarValidArguments : List Expr := [
  .local 0, .local 1]

def parserRecognizeGrammarValidCall : Expr :=
  .call extractedParserGrammarValidFunction.id
    parserRecognizeGrammarValidArguments

def parserRecognizeGrammarGuard : Stmt :=
  match extractedParserRecognizeBody with
  | .sequence guard _ => guard
  | _ => .skip

def parserRecognizeAfterGrammarGuard : Stmt :=
  match extractedParserRecognizeBody with
  | .sequence _ continuation => continuation
  | _ => .skip

def parserRecognizeBadGrammarBranch : Stmt :=
  match parserRecognizeGrammarGuard with
  | .ifThenElse _ badGrammar _ => badGrammar
  | _ => .skip

/-- The first recognizer branch is selected from the checked artifact and is
    exactly the negation of the extracted validator call. -/
theorem extractedParserRecognize_initial_grammar_guard_shape :
    extractedParserRecognizeBody =
      .sequence
        (.ifThenElse (.unary .logicalNot parserRecognizeGrammarValidCall)
          parserRecognizeBadGrammarBranch .skip)
        parserRecognizeAfterGrammarGuard := by
  rfl

theorem extractedParserRecognize_grammar_guard_shape :
    parserRecognizeGrammarGuard =
      .ifThenElse (.unary .logicalNot parserRecognizeGrammarValidCall)
        parserRecognizeBadGrammarBranch .skip := by
  rfl

/-- A compact artifact-derived description of a direct call whose result is
    bound by a local declaration.  This is deliberately a structural query
    over extracted Core, not a source-name or handwritten-AST assertion. -/
structure DirectCallBinding where
  localId : VarId
  functionId : FunctionId
  arguments : List Expr
  resultGuardedNonnegative : Bool
deriving BEq, Repr

def resultGuardedNonnegative (id : VarId) : Stmt → Bool
  | .sequence
      (.ifThenElse
        (.binary .greaterEqual (.local found)
          (.value (.signed .i32 0))) _ _) _ => found == id
  | _ => false

/-- Collect direct call initializers throughout statement control flow.  The
    continuation bit records the recognizer convention that a nonnegative
    scanner result enters the successful transition branch. -/
def directCallBindings : Stmt → List DirectCallBinding
  | .skip | .expression _ | .returnValue _ | .breakLoop | .continueLoop => []
  | .sequence first second =>
      directCallBindings first ++ directCallBindings second
  | .letLocal id _ initializer body =>
      let tail := directCallBindings body
      match initializer with
      | .call functionId arguments =>
          { localId := id
            functionId := functionId
            arguments := arguments
            resultGuardedNonnegative := resultGuardedNonnegative id body } ::
            tail
      | _ => tail
  | .letUninitialized _ _ body => directCallBindings body
  | .ifThenElse _ thenBranch elseBranch =>
      directCallBindings thenBranch ++ directCallBindings elseBranch
  | .whileLoop _ body | .forValues _ _ body | .forRange _ _ _ _ body =>
      directCallBindings body

def findLetLocalStatement (wanted : Nat) : Stmt → Option Stmt
  | statement@(.letLocal id _ _ body) =>
      if id == wanted then some statement
      else findLetLocalStatement wanted body
  | .letUninitialized _ _ body => findLetLocalStatement wanted body
  | .sequence first second =>
      (findLetLocalStatement wanted first).orElse fun _ =>
        findLetLocalStatement wanted second
  | .ifThenElse _ thenBranch elseBranch =>
      (findLetLocalStatement wanted thenBranch).orElse fun _ =>
        findLetLocalStatement wanted elseBranch
  | .whileLoop _ body | .forValues _ _ body | .forRange _ _ _ _ body =>
      findLetLocalStatement wanted body
  | _ => none

def findLetLocalStatements (wanted : VarId) : Stmt → List Stmt
  | statement@(.letLocal id _ _ body) =>
      (if id == wanted then [statement] else []) ++
        findLetLocalStatements wanted body
  | .letUninitialized _ _ body => findLetLocalStatements wanted body
  | .sequence first second =>
      findLetLocalStatements wanted first ++
        findLetLocalStatements wanted second
  | .ifThenElse _ thenBranch elseBranch =>
      findLetLocalStatements wanted thenBranch ++
        findLetLocalStatements wanted elseBranch
  | .whileLoop _ body | .forValues _ _ body | .forRange _ _ _ _ body =>
      findLetLocalStatements wanted body
  | _ => []

/-- Extract the generated recognizer's loops in source/control-flow order.
    Loop proofs use this artifact-derived view rather than maintaining a
    second handwritten copy of the recognizer body. -/
def recognizerWhileLoops : Stmt → List Stmt
  | loop@(.whileLoop _ body) => loop :: recognizerWhileLoops body
  | .letLocal _ _ _ body | .letUninitialized _ _ body =>
      recognizerWhileLoops body
  | .sequence first second =>
      recognizerWhileLoops first ++ recognizerWhileLoops second
  | .ifThenElse _ thenBranch elseBranch =>
      recognizerWhileLoops thenBranch ++ recognizerWhileLoops elseBranch
  | .forValues _ _ body | .forRange _ _ _ _ body =>
      recognizerWhileLoops body
  | _ => []

def parserRecognizeScanTerminalArguments : List Expr := [
  .local 0, .local 2, .local 3, .local 23, .local 29]

def parserRecognizeScanTerminalCall : Expr :=
  .call extractedParserScanTerminalFunction.id
    parserRecognizeScanTerminalArguments

/-- The checked recognizer artifact has exactly one direct `scan_terminal`
    binding. It feeds grammar, tokens, token count, current lattice position,
    and current terminal kind to the proved scanner, then guards its result as
    a nonnegative next position. -/
theorem extractedParserRecognize_scan_terminal_binding :
    ((directCallBindings
      (extractedParserRecognizeFunction.body.getD .skip)).filter
        (fun binding =>
          binding.functionId == extractedParserScanTerminalFunction.id) == [{
            localId := 30
            functionId := extractedParserScanTerminalFunction.id
            arguments := parserRecognizeScanTerminalArguments
            resultGuardedNonnegative := true
          }]) = true := by
  native_decide

def parserRecognizeTerminalSeedArguments : List Expr := [
  .local 25,
  .binary .add (.local 26) (.value (.signed .i32 1)),
  .local 27,
  .local 24,
  .constant 38,
  .binary .divide (.local 23) (.value (.signed .i32 2)),
  .local 29]

def parserRecognizeTerminalSeedCall : Expr :=
  .call extractedParserStateSeedFunction.id
    parserRecognizeTerminalSeedArguments

def parserRecognizeTerminalAppendArguments : List Expr := [
  .local 4, .local 8, .local 9, .local 30,
  parserRecognizeTerminalSeedCall, .local 18]

def parserRecognizeTerminalAppendCall : Expr :=
  .call extractedParserAppendStateFunction.id
    parserRecognizeTerminalAppendArguments

def parserRecognizeTerminalStatement : Stmt :=
  (findLetLocalStatement 30 extractedParserRecognizeBody).getD .skip

def parserRecognizeTerminalSuccessStatement : Stmt :=
  match parserRecognizeTerminalStatement with
  | .letLocal _ _ _
      (.sequence (.ifThenElse _ successBranch _) _) => successBranch
  | _ => .skip

def parserRecognizeTerminalFullBranch : Stmt :=
  match parserRecognizeTerminalSuccessStatement with
  | .letLocal _ _ _
      (.sequence (.ifThenElse _ fullBranch _) _) => fullBranch
  | _ => .skip

def parserRecognizeTerminalFullCall : Expr :=
  .call extractedParserAppendOrFullFunction.id [.local 31, .local 23]

theorem extractedParserRecognize_terminal_statement_shape :
    parserRecognizeTerminalStatement =
      .letLocal 30 parserI32Type parserRecognizeScanTerminalCall
        (.sequence
          (.ifThenElse
            (.binary .greaterEqual (.local 30)
              (.value (.signed .i32 0)))
            parserRecognizeTerminalSuccessStatement .skip)
          .skip) := by
  rfl

theorem extractedParserRecognize_terminal_success_shape :
    parserRecognizeTerminalSuccessStatement =
      .letLocal 31 (.structure 2) parserRecognizeTerminalAppendCall
        (.sequence
          (.ifThenElse
            (.binary .equal (.field (.local 31) 0) (.constant 41))
            parserRecognizeTerminalFullBranch .skip)
          (.sequence
            (.expression
              (.assign .set (.local 18) (.field (.local 31) 2)))
            .skip)) := by
  rfl

theorem extractedParserRecognize_terminal_full_shape :
    parserRecognizeTerminalFullBranch =
      .sequence
        (.returnValue (some parserRecognizeTerminalFullCall)) .skip := by
  rfl

theorem extractedParserRecognize_terminal_append_control_shape :
    parserRecognizeTerminalSuccessStatement =
      .letLocal 31 (.structure 2) parserRecognizeTerminalAppendCall
        (parserAppendOutcomeContinuation 31 18 (.local 23)) := by
  rfl

/-- The terminal scanner's successful branch has exactly one extracted
    `append_state` binding, with the advanced dot, token child evidence, and
    scanner result wired into the six append parameters. -/
theorem extractedParserRecognize_terminal_append_binding :
    ((directCallBindings
      (extractedParserRecognizeFunction.body.getD .skip)).filter
        (fun binding =>
          binding.functionId == extractedParserAppendStateFunction.id &&
          binding.localId == 31) == [{
            localId := 31
            functionId := extractedParserAppendStateFunction.id
            arguments := parserRecognizeTerminalAppendArguments
            resultGuardedNonnegative := false
          }]) = true := by
  native_decide

def parserRecognizeNullableSeedArguments : List Expr := [
  .local 25,
  .binary .add (.local 26) (.value (.signed .i32 1)),
  .local 27,
  .local 24,
  .constant 39,
  .local 36,
  .unary .negate (.value (.signed .i32 1))]

def parserRecognizeNullableSeedCall : Expr :=
  .call extractedParserStateSeedFunction.id
    parserRecognizeNullableSeedArguments

def parserRecognizeNullableAppendArguments : List Expr := [
  .local 4, .local 8, .local 9, .local 23,
  parserRecognizeNullableSeedCall, .local 18]

def parserRecognizeNullableAppendCall : Expr :=
  .call extractedParserAppendStateFunction.id
    parserRecognizeNullableAppendArguments

def parserRecognizeNullableAppendStatement : Stmt :=
  (findLetLocalStatement 40 extractedParserRecognizeBody).getD .skip

/-- The nullable-replay transition is one application of the same append
    operation, with a completed state as child evidence. -/
theorem extractedParserRecognize_nullable_append_shape :
    parserRecognizeNullableAppendStatement =
      .letLocal 40 (.structure 2) parserRecognizeNullableAppendCall
        (parserAppendOutcomeContinuation 40 18 (.local 23)) := by
  rfl

theorem extractedParserRecognize_nullable_append_binding :
    ((directCallBindings extractedParserRecognizeBody).filter
      (fun binding =>
        binding.functionId == extractedParserAppendStateFunction.id &&
        binding.localId == 40) == [{
          localId := 40
          functionId := extractedParserAppendStateFunction.id
          arguments := parserRecognizeNullableAppendArguments
          resultGuardedNonnegative := false
        }]) = true := by
  native_decide

def parserRecognizeIncrementLocal (id : VarId) : Stmt :=
  .sequence
    (.expression
      (.assign .add (.local id) (.value (.signed .i32 1)))) .skip

def parserRecognizePredictionSeedArguments : List Expr := [
  .local 34,
  .value (.signed .i32 0),
  .local 23,
  .unary .negate (.value (.signed .i32 1)),
  .constant 37,
  .unary .negate (.value (.signed .i32 1)),
  .unary .negate (.value (.signed .i32 1))]

def parserRecognizePredictionSeedCall : Expr :=
  .call extractedParserStateSeedFunction.id
    parserRecognizePredictionSeedArguments

def parserRecognizePredictionAppendArguments : List Expr := [
  .local 4, .local 8, .local 9, .local 23,
  parserRecognizePredictionSeedCall, .local 18]

def parserRecognizePredictionAppendCall : Expr :=
  .call extractedParserAppendStateFunction.id
    parserRecognizePredictionAppendArguments

def parserRecognizePredictionAppendStatement : Stmt :=
  (findLetLocalStatement 35 extractedParserRecognizeBody).getD .skip

theorem extractedParserRecognize_prediction_append_shape :
    parserRecognizePredictionAppendStatement =
      .letLocal 35 (.structure 2) parserRecognizePredictionAppendCall
        (parserAppendOutcomeContinuationThen 35 18 (.local 23)
          (parserRecognizeIncrementLocal 33)) := by
  rfl

theorem extractedParserRecognize_prediction_append_binding :
    ((directCallBindings extractedParserRecognizeBody).filter
      (fun binding =>
        binding.functionId == extractedParserAppendStateFunction.id &&
        binding.localId == 35 &&
        binding.arguments == parserRecognizePredictionAppendArguments) == [{
          localId := 35
          functionId := extractedParserAppendStateFunction.id
          arguments := parserRecognizePredictionAppendArguments
          resultGuardedNonnegative := false
        }]) = true := by
  native_decide

def parserRecognizeParentSeedArguments : List Expr := [
  .local 31,
  .binary .add (.local 32) (.value (.signed .i32 1)),
  .local 34,
  .local 30,
  .constant 39,
  .local 24,
  .unary .negate (.value (.signed .i32 1))]

def parserRecognizeParentSeedCall : Expr :=
  .call extractedParserStateSeedFunction.id
    parserRecognizeParentSeedArguments

def parserRecognizeParentAppendArguments : List Expr := [
  .local 4, .local 8, .local 9, .local 23,
  parserRecognizeParentSeedCall, .local 18]

def parserRecognizeParentAppendCall : Expr :=
  .call extractedParserAppendStateFunction.id
    parserRecognizeParentAppendArguments

def parserRecognizeParentAppendStatement : Stmt :=
  (findLetLocalStatements 35 extractedParserRecognizeBody)[1]?.getD .skip

theorem extractedParserRecognize_parent_append_shape :
    parserRecognizeParentAppendStatement =
      .letLocal 35 (.structure 2) parserRecognizeParentAppendCall
        (parserAppendOutcomeContinuation 35 18 (.local 23)) := by
  rfl

theorem extractedParserRecognize_parent_append_binding :
    ((directCallBindings extractedParserRecognizeBody).filter
      (fun binding =>
        binding.functionId == extractedParserAppendStateFunction.id &&
        binding.localId == 35 &&
        binding.arguments == parserRecognizeParentAppendArguments) == [{
          localId := 35
          functionId := extractedParserAppendStateFunction.id
          arguments := parserRecognizeParentAppendArguments
          resultGuardedNonnegative := false
        }]) = true := by
  native_decide

def parserRecognizeInitialSeedArguments : List Expr := [
  .local 20,
  .value (.signed .i32 0),
  .value (.signed .i32 0),
  .unary .negate (.value (.signed .i32 1)),
  .constant 37,
  .unary .negate (.value (.signed .i32 1)),
  .unary .negate (.value (.signed .i32 1))]

def parserRecognizeInitialSeedCall : Expr :=
  .call extractedParserStateSeedFunction.id parserRecognizeInitialSeedArguments

def parserRecognizeInitialAppendArguments : List Expr := [
  .local 4, .local 8, .local 9, .value (.signed .i32 0),
  parserRecognizeInitialSeedCall, .local 18]

def parserRecognizeInitialAppendCall : Expr :=
  .call extractedParserAppendStateFunction.id
    parserRecognizeInitialAppendArguments

def parserRecognizeInitialAppendStatement : Stmt :=
  (findLetLocalStatement 21 extractedParserRecognizeBody).getD .skip

theorem extractedParserRecognize_initial_append_shape :
    parserRecognizeInitialAppendStatement =
      .letLocal 21 (.structure 2) parserRecognizeInitialAppendCall
        (parserAppendOutcomeContinuationThen 21 18
          (.value (.signed .i32 0))
          (parserRecognizeIncrementLocal 19)) := by
  rfl

theorem extractedParserRecognize_initial_append_binding :
    ((directCallBindings extractedParserRecognizeBody).filter
      (fun binding =>
        binding.functionId == extractedParserAppendStateFunction.id &&
        binding.localId == 21) == [{
          localId := 21
          functionId := extractedParserAppendStateFunction.id
          arguments := parserRecognizeInitialAppendArguments
          resultGuardedNonnegative := false
        }]) = true := by
  native_decide

def parserRecognizeInitialLoop : Stmt :=
  (recognizerWhileLoops extractedParserRecognizeBody)[1]?.getD .skip

def parserRecognizeInitialLoopBody : Stmt :=
  match parserRecognizeInitialLoop with
  | .whileLoop _ body => body
  | _ => .skip

def verifiedParserInitialLoopAccessFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedAccessFrameForCore
    parserRecognizeInitialLoop (by native_decide)

def verifiedParserInitialLoopLiveFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedLiveFrameBeforeCore
    parserRecognizeInitialLoop (by native_decide)

theorem verifiedParser_initial_loop_access_frame :
    verifiedParserInitialLoopAccessFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("start_index", 19, .readWrite),
      ("start_count", 17, .read),
      ("grammar", 0, .read),
      ("lhs_productions_offset", 15, .read),
      ("start_first", 16, .read),
      ("workspace", 4, .read),
      ("state_base", 8, .read),
      ("state_capacity", 9, .read),
      ("state_count", 18, .readWrite)] := by
  native_decide

theorem verifiedParser_initial_loop_live_frame :
    verifiedParserInitialLoopLiveFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("start_index", 19, .readWrite),
      ("start_count", 17, .read),
      ("grammar", 0, .read),
      ("lhs_productions_offset", 15, .read),
      ("start_first", 16, .read),
      ("workspace", 4, .read),
      ("state_base", 8, .read),
      ("state_capacity", 9, .read),
      ("state_count", 18, .readWrite),
      ("final_position", 6, .read),
      ("kind_count", 11, .read),
      ("tokens", 2, .read),
      ("token_count", 3, .read),
      ("lhs_offsets_offset", 13, .read),
      ("lhs_counts_offset", 14, .read),
      ("start_nonterminal", 12, .read)] := by
  native_decide

/-- Locals live across the initial loop whose cells remain owned by the
    surrounding frame.  This is derived from liveness, not merely from reads
    performed inside the loop: later phases still need the final position,
    grammar metadata, tokens, and start symbol.  The two loop-owned mutable
    scalars have dedicated ownership fields instead. -/
def verifiedParserInitialLoopSharedFrame :
    LocalAccessFrame :=
  (verifiedParserInitialLoopLiveFrame.excludingName "start_index")
    |>.excludingName "state_count"

def verifiedParserInitialLoopSharedFrameIds : List VarId :=
  verifiedParserInitialLoopSharedFrame.ids

def verifiedParserInitialLoopPersistentBindings : LocalBindingFrame :=
  LocalBindingFrame.union verifiedParserRecognizerParameterFrame
    verifiedParserInitialLoopSharedFrame.bindings

theorem verifiedParser_initial_loop_shared_frame_ids :
    verifiedParserInitialLoopSharedFrameIds =
      [17, 0, 15, 16, 4, 8, 9, 6, 11, 2, 3, 13, 14, 12] := by
  native_decide

theorem verifiedParserInitialLoopPersistentBindings_core_ids :
    verifiedParserInitialLoopPersistentBindings.coreIds =
      verifiedParserRecognizerParameterIds ++
        verifiedParserInitialLoopSharedFrameIds := by
  native_decide

@[simp] theorem mem_verifiedParserInitialLoopSharedFrameIds_iff
    (id : Nat) :
    id ∈ verifiedParserInitialLoopSharedFrameIds ↔
      id = 17 ∨ id = 0 ∨ id = 15 ∨ id = 16 ∨ id = 4 ∨ id = 8 ∨
        id = 9 ∨ id = 6 ∨ id = 11 ∨ id = 2 ∨ id = 3 ∨ id = 13 ∨
        id = 14 ∨ id = 12 := by
  rw [verifiedParser_initial_loop_shared_frame_ids]
  simp only [List.mem_cons, List.not_mem_nil, or_false]

def InitialLoopPersistentLocal (id : VarId) : Prop :=
  id ∈ verifiedParserRecognizerParameterIds ∨
    id ∈ verifiedParserInitialLoopSharedFrameIds

theorem InitialLoopPersistentLocal_source_frame (id : VarId) :
    InitialLoopPersistentLocal id ↔
      verifiedParserInitialLoopPersistentBindings.ContainsCoreId id := by
  rw [LocalBindingFrame.ContainsCoreId,
    verifiedParserInitialLoopPersistentBindings_core_ids]
  simp [InitialLoopPersistentLocal]

def initialLoopMutableCells
    (workspaceCell stateCountCell indexCell : CellId) : CellSet :=
  CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton indexCell))

def InitialLoopFrameSeparated (runtime : State)
    (workspaceCell stateCountCell indexCell : CellId) : Prop :=
  CellSet.Disjoint
    (localBindingFrameFootprint runtime
      verifiedParserInitialLoopPersistentBindings)
    (initialLoopMutableCells workspaceCell stateCountCell indexCell)

theorem InitialLoopPersistentLocal.lt18
    (id : Nat) (persistent : InitialLoopPersistentLocal id) : id < 18 := by
  unfold InitialLoopPersistentLocal at persistent
  rcases persistent with parameter | shared
  · exact Nat.lt_of_le_of_lt
      ((mem_verifiedParserRecognizerParameterIds_iff id).mp parameter)
      (by decide)
  · rw [mem_verifiedParserInitialLoopSharedFrameIds_iff] at shared
    rcases shared with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
      rfl | rfl | rfl | rfl | rfl | rfl <;> decide

/-- The second generated loop seeds chart position zero from the complete
    packed row of productions for the start nonterminal. -/
theorem extractedParserRecognize_initial_loop_shape :
    parserRecognizeInitialLoop =
      .whileLoop (.binary .less (.local 19) (.local 17))
        (.letLocal 20 parserI32Type
          (.index (.local 0)
            (.binary .add
              (.binary .add (.local 15) (.local 16)) (.local 19)))
          parserRecognizeInitialAppendStatement) := by
  rfl

theorem extractedParserRecognize_initial_loop_body_shape :
    parserRecognizeInitialLoopBody =
      .letLocal 20 parserI32Type
        (.index (.local 0)
          (.binary .add
            (.binary .add (.local 15) (.local 16)) (.local 19)))
        parserRecognizeInitialAppendStatement := by
  rfl

/-- Semantic bridge for the exact call expression found above.  A future
    whole-recognizer loop invariant only has to establish the five call-site
    locals and the scanner's framed ownership invariant; the call itself then
    computes the mathematical terminal transition already proved in
    `VerifiedParserScan`. -/
theorem parserRecognizeScanTerminalCall_implements_model
    (state : State)
    (stateWellFormed : StateWellFormed state)
    (grammarLocal : state.local? 0 =
      some (parserGrammarValue words grammarCell))
    (tokensLocal : state.local? 2 =
      some (parserTokensValue tokens tokensCell))
    (tokenCountLocal : state.local? 3 =
      some (.signed .i32 (Int.ofNat tokens.length)))
    (positionLocal : state.local? 23 =
      some (.signed .i32 (Int.ofNat position)))
    (semanticKindLocal : state.local? 29 =
      some (.signed .i32 (Int.ofNat semanticKind)))
    (grammarBacking : state.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values words))
    })
    (tokensBacking : state.cellEntry? tokensCell = some {
      id := tokensCell
      value := some (.array
        (signedI32Values (tokens.map Int.ofNat)))
    })
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind
      (parserScanTerminalCallee state words tokens grammarCell tokensCell
        position semanticKind)) :
    ∃ after,
      Evaluates verifiedParserCore state parserRecognizeScanTerminalCall
        (scanTerminalValue
          (scanTerminal grammar tokens position semanticKind)) after ∧
      ModifiesOnly CellSet.empty state after ∧
      StateWellFormed after ∧
      after.cellEntry? grammarCell = some {
        id := grammarCell
        value := some (.array (signedI32Values words))
      } ∧
      after.cellEntry? tokensCell = some {
        id := tokensCell
        value := some (.array
          (signedI32Values (tokens.map Int.ofNat)))
      } := by
  have grammarResult : Evaluates verifiedParserCore state (.local 0)
      (parserGrammarValue words grammarCell) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 0 _ grammarLocal⟩
  have tokensResult : Evaluates verifiedParserCore state (.local 2)
      (parserTokensValue tokens tokensCell) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 2 _ tokensLocal⟩
  have countResult : Evaluates verifiedParserCore state (.local 3)
      (.signed .i32 (Int.ofNat tokens.length)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 3 _ tokenCountLocal⟩
  have positionResult : Evaluates verifiedParserCore state (.local 23)
      (.signed .i32 (Int.ofNat position)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 23 _ positionLocal⟩
  have kindResult : Evaluates verifiedParserCore state (.local 29)
      (.signed .i32 (Int.ofNat semanticKind)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 29 _ semanticKindLocal⟩
  have arguments : ArgumentsEvaluateTo verifiedParserCore state
      parserRecognizeScanTerminalArguments [
        parserGrammarValue words grammarCell,
        parserTokensValue tokens tokensCell,
        .signed .i32 (Int.ofNat tokens.length),
        .signed .i32 (Int.ofNat position),
        .signed .i32 (Int.ofNat semanticKind)] state :=
    ArgumentsEvaluateTo.cons grammarResult
      (ArgumentsEvaluateTo.cons tokensResult
        (ArgumentsEvaluateTo.cons countResult
          (ArgumentsEvaluateTo.cons positionResult
            (ArgumentsEvaluateTo.singleton kindResult))))
  simpa [parserRecognizeScanTerminalCall] using
    extractedParserScanTerminalCall_implements_model state state
      parserRecognizeScanTerminalArguments stateWellFormed arguments
      grammarBacking tokensBacking invariant

/-- Persistent physical resources available before and throughout
    recognition. Chart initialization starts from this representation-only
    frame because the caller's workspace does not encode a logical chart
    until its prefix has been cleared. -/
structure RecognizerResources
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (runtime : State) : Prop where
  grammarEncoded : EncodesGrammar grammarLayout grammar words
  grammarWellFormed : grammar.WellFormed
  wordsI32 : words.length ≤ 2147483647
  tokensI32 : tokens.length ≤ 2147483647
  workspaceLength : workspaceValues.length = workspaceLayout.workspaceLength
  workspaceTokenCount : workspaceLayout.tokenCount = tokens.length
  wellFormed : StateWellFormed runtime
  grammarLocal : runtime.local? 0 =
    some (parserGrammarValue words grammarCell)
  grammarLengthLocal : runtime.local? 1 =
    some (.signed .i32 (Int.ofNat words.length))
  tokensLocal : runtime.local? 2 =
    some (parserTokensValue tokens tokensCell)
  tokenCountLocal : runtime.local? 3 =
    some (.signed .i32 (Int.ofNat tokens.length))
  workspaceLocal : runtime.local? 4 =
    some (workspaceValue workspaceValues workspaceCell)
  workspaceLengthLocal : runtime.local? 5 =
    some (.signed .i32 (Int.ofNat workspaceValues.length))
  grammarBacking : runtime.cellEntry? grammarCell = some {
    id := grammarCell
    value := some (.array (signedI32Values words))
  }
  tokensBacking : runtime.cellEntry? tokensCell = some {
    id := tokensCell
    value := some (.array
      (signedI32Values (tokens.map Int.ofNat)))
  }
  workspaceBacking : runtime.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values workspaceValues))
  }
  grammarWorkspaceDistinct : grammarCell ≠ workspaceCell
  tokensWorkspaceDistinct : tokensCell ≠ workspaceCell

/-- Persistent recognizer state shared by the nested Earley loops.  Logical
    grammar/workspace models, physical backing cells, and the six source
    parameters travel together, so read-only calls and workspace mutations
    cannot silently drop one side of the representation relation. -/
structure RecognizerInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (runtime : State) : Prop where
  grammarEncoded : EncodesGrammar grammarLayout grammar words
  grammarWellFormed : grammar.WellFormed
  wordsI32 : words.length ≤ 2147483647
  tokensI32 : tokens.length ≤ 2147483647
  workspaceLength : workspaceValues.length = workspaceLayout.workspaceLength
  workspaceTokenCount : workspaceLayout.tokenCount = tokens.length
  workspaceEncoded : EncodesWorkspace workspaceLayout workspace
    (listWords workspaceValues)
  derivations : WorkspaceDerivations grammar tokens workspace
  wellFormed : StateWellFormed runtime
  grammarLocal : runtime.local? 0 =
    some (parserGrammarValue words grammarCell)
  grammarLengthLocal : runtime.local? 1 =
    some (.signed .i32 (Int.ofNat words.length))
  tokensLocal : runtime.local? 2 =
    some (parserTokensValue tokens tokensCell)
  tokenCountLocal : runtime.local? 3 =
    some (.signed .i32 (Int.ofNat tokens.length))
  workspaceLocal : runtime.local? 4 =
    some (workspaceValue workspaceValues workspaceCell)
  workspaceLengthLocal : runtime.local? 5 =
    some (.signed .i32 (Int.ofNat workspaceValues.length))
  grammarBacking : runtime.cellEntry? grammarCell = some {
    id := grammarCell
    value := some (.array (signedI32Values words))
  }
  tokensBacking : runtime.cellEntry? tokensCell = some {
    id := tokensCell
    value := some (.array
      (signedI32Values (tokens.map Int.ofNat)))
  }
  workspaceBacking : runtime.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values workspaceValues))
  }
  grammarWorkspaceDistinct : grammarCell ≠ workspaceCell
  tokensWorkspaceDistinct : tokensCell ≠ workspaceCell

theorem RecognizerInvariant.languageSound
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime) :
    WorkspaceLanguageSound grammar tokens workspace :=
  invariant.derivations.languageSound

theorem RecognizerInvariant.backpointersSound
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime) :
    WorkspaceBackpointersSound grammar tokens workspace :=
  invariant.derivations.backpointersSound

/-- Caller-visible semantic artifact produced by recognition.  Unlike
    `RecognizerInvariant`, this representation does not mention callee-local
    parameter bindings, so it remains meaningful after the function scope is
    closed. -/
structure RecognizerWorkspaceArtifact
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int) (workspaceCell : CellId)
    (runtime : State) : Prop where
  workspaceLength : workspaceValues.length = workspaceLayout.workspaceLength
  workspaceEncoded : EncodesWorkspace workspaceLayout workspace
    (listWords workspaceValues)
  workspaceBacking : runtime.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values workspaceValues))
  }

theorem RecognizerInvariant.workspaceArtifact
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime) :
    RecognizerWorkspaceArtifact workspaceLayout workspace workspaceValues
      workspaceCell runtime := {
  workspaceLength := invariant.workspaceLength
  workspaceEncoded := invariant.workspaceEncoded
  workspaceBacking := invariant.workspaceBacking
}

theorem RecognizerWorkspaceArtifact.transfer_cells
    (artifact : RecognizerWorkspaceArtifact workspaceLayout workspace
      workspaceValues workspaceCell before)
    (cells : after.cells = before.cells) :
    RecognizerWorkspaceArtifact workspaceLayout workspace workspaceValues
      workspaceCell after := {
  workspaceLength := artifact.workspaceLength
  workspaceEncoded := artifact.workspaceEncoded
  workspaceBacking := by
    simpa [State.cellEntry?, cells] using artifact.workspaceBacking
}

theorem RecognizerInvariant.resources
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime) :
    RecognizerResources grammarLayout grammar words tokens workspaceLayout
      workspaceValues grammarCell tokensCell workspaceCell runtime := {
  grammarEncoded := invariant.grammarEncoded
  grammarWellFormed := invariant.grammarWellFormed
  wordsI32 := invariant.wordsI32
  tokensI32 := invariant.tokensI32
  workspaceLength := invariant.workspaceLength
  workspaceTokenCount := invariant.workspaceTokenCount
  wellFormed := invariant.wellFormed
  grammarLocal := invariant.grammarLocal
  grammarLengthLocal := invariant.grammarLengthLocal
  tokensLocal := invariant.tokensLocal
  tokenCountLocal := invariant.tokenCountLocal
  workspaceLocal := invariant.workspaceLocal
  workspaceLengthLocal := invariant.workspaceLengthLocal
  grammarBacking := invariant.grammarBacking
  tokensBacking := invariant.tokensBacking
  workspaceBacking := invariant.workspaceBacking
  grammarWorkspaceDistinct := invariant.grammarWorkspaceDistinct
  tokensWorkspaceDistinct := invariant.tokensWorkspaceDistinct
}

theorem RecognizerResources.with_workspace_encoding
    (resources : RecognizerResources grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      runtime)
    (workspace : LogicalWorkspace)
    (encoded : EncodesWorkspace workspaceLayout workspace
      (listWords workspaceValues))
    (derivations : WorkspaceDerivations grammar tokens workspace) :
    RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell runtime := {
  grammarEncoded := resources.grammarEncoded
  grammarWellFormed := resources.grammarWellFormed
  wordsI32 := resources.wordsI32
  tokensI32 := resources.tokensI32
  workspaceLength := resources.workspaceLength
  workspaceTokenCount := resources.workspaceTokenCount
  workspaceEncoded := encoded
  derivations := derivations
  wellFormed := resources.wellFormed
  grammarLocal := resources.grammarLocal
  grammarLengthLocal := resources.grammarLengthLocal
  tokensLocal := resources.tokensLocal
  tokenCountLocal := resources.tokenCountLocal
  workspaceLocal := resources.workspaceLocal
  workspaceLengthLocal := resources.workspaceLengthLocal
  grammarBacking := resources.grammarBacking
  tokensBacking := resources.tokensBacking
  workspaceBacking := resources.workspaceBacking
  grammarWorkspaceDistinct := resources.grammarWorkspaceDistinct
  tokensWorkspaceDistinct := resources.tokensWorkspaceDistinct
}

theorem RecognizerInvariant.after_empty_effect
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell before)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell after := {
  grammarEncoded := invariant.grammarEncoded
  grammarWellFormed := invariant.grammarWellFormed
  wordsI32 := invariant.wordsI32
  tokensI32 := invariant.tokensI32
  workspaceLength := invariant.workspaceLength
  workspaceTokenCount := invariant.workspaceTokenCount
  workspaceEncoded := invariant.workspaceEncoded
  derivations := invariant.derivations
  wellFormed := afterWellFormed
  grammarLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.grammarLocal
  grammarLengthLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.grammarLengthLocal
  tokensLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.tokensLocal
  tokenCountLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.tokenCountLocal
  workspaceLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.workspaceLocal
  workspaceLengthLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.workspaceLengthLocal
  grammarBacking := effect.empty_preserves_entry invariant.wellFormed
    invariant.grammarBacking
  tokensBacking := effect.empty_preserves_entry invariant.wellFormed
    invariant.tokensBacking
  workspaceBacking := effect.empty_preserves_entry invariant.wellFormed
    invariant.workspaceBacking
  grammarWorkspaceDistinct := invariant.grammarWorkspaceDistinct
  tokensWorkspaceDistinct := invariant.tokensWorkspaceDistinct
}

theorem RecognizerInvariant.after_bind_local
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime)
    (id : VarId) (value : Value)
    (not0 : id ≠ 0) (not1 : id ≠ 1) (not2 : id ≠ 2)
    (not3 : id ≠ 3) (not4 : id ≠ 4) (not5 : id ≠ 5) :
    RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      (runtime.bindLocal id value) := by
  have effect := bindLocal_effect runtime id value
  exact {
    grammarEncoded := invariant.grammarEncoded
    grammarWellFormed := invariant.grammarWellFormed
    wordsI32 := invariant.wordsI32
    tokensI32 := invariant.tokensI32
    workspaceLength := invariant.workspaceLength
    workspaceTokenCount := invariant.workspaceTokenCount
    workspaceEncoded := invariant.workspaceEncoded
    derivations := invariant.derivations
    wellFormed := bindLocal_preserves_well_formed runtime id value
      invariant.wellFormed
    grammarLocal :=
      (bindLocal_preserves_other_local invariant.wellFormed not0).trans
        invariant.grammarLocal
    grammarLengthLocal :=
      (bindLocal_preserves_other_local invariant.wellFormed not1).trans
        invariant.grammarLengthLocal
    tokensLocal :=
      (bindLocal_preserves_other_local invariant.wellFormed not2).trans
        invariant.tokensLocal
    tokenCountLocal :=
      (bindLocal_preserves_other_local invariant.wellFormed not3).trans
        invariant.tokenCountLocal
    workspaceLocal :=
      (bindLocal_preserves_other_local invariant.wellFormed not4).trans
        invariant.workspaceLocal
    workspaceLengthLocal :=
      (bindLocal_preserves_other_local invariant.wellFormed not5).trans
        invariant.workspaceLengthLocal
    grammarBacking := by
      have old := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
        invariant.wellFormed invariant.grammarBacking
      exact (effect.oldCells grammarCell old (by simp [CellSet.empty])).trans
        invariant.grammarBacking
    tokensBacking := by
      have old := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
        invariant.wellFormed invariant.tokensBacking
      exact (effect.oldCells tokensCell old (by simp [CellSet.empty])).trans
        invariant.tokensBacking
    workspaceBacking := by
      have old := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
        invariant.wellFormed invariant.workspaceBacking
      exact (effect.oldCells workspaceCell old (by simp [CellSet.empty])).trans
        invariant.workspaceBacking
    grammarWorkspaceDistinct := invariant.grammarWorkspaceDistinct
    tokensWorkspaceDistinct := invariant.tokensWorkspaceDistinct
  }

/-- Introduce a source-derived list of locals above the six recognizer
    parameters while retaining the complete grammar/token/workspace frame. -/
theorem RecognizerInvariant.after_bind_locals
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime)
    (bindings : List (VarId × Value))
    (afterParameters : ∀ binding, binding ∈ bindings → 5 < binding.1) :
    RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      (runtime.bindLocals bindings) := by
  induction bindings generalizing runtime with
  | nil => simpa [State.bindLocals] using invariant
  | cons binding rest inductionHypothesis =>
      simp only [State.bindLocals, List.foldl_cons]
      have bound := afterParameters binding (by simp)
      have next := invariant.after_bind_local binding.1 binding.2
        (Nat.ne_of_gt (Nat.lt_trans (by decide : 0 < 5) bound))
        (Nat.ne_of_gt (Nat.lt_trans (by decide : 1 < 5) bound))
        (Nat.ne_of_gt (Nat.lt_trans (by decide : 2 < 5) bound))
        (Nat.ne_of_gt (Nat.lt_trans (by decide : 3 < 5) bound))
        (Nat.ne_of_gt (Nat.lt_trans (by decide : 4 < 5) bound))
        (Nat.ne_of_gt bound)
      exact inductionHypothesis next (fun later member =>
        afterParameters later (List.mem_cons_of_mem binding member))

/-- Reframe one proved workspace mutation as a complete recognizer state.
    The append operation may alter the workspace backing and no other
    pre-existing cell; the immutable grammar and token resources therefore
    survive, while the workspace's logical and physical views advance
    together. -/
theorem RecognizerInvariant.after_workspace_effect
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell before)
    (effect : ModifiesOnly (CellSet.singleton workspaceCell) before after)
    (afterWellFormed : StateWellFormed after)
    (newWorkspace : LogicalWorkspace) (newValues : List Int)
    (sameLength : newValues.length = workspaceValues.length)
    (newEncoded : EncodesWorkspace workspaceLayout newWorkspace
      (listWords newValues))
    (newDerivations : WorkspaceDerivations grammar tokens newWorkspace)
    (newBacking : after.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values newValues))
    }) :
    RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
      newWorkspace newValues grammarCell tokensCell workspaceCell after := by
  have grammarLocal := effect.singleton_preserves_local_of_ne
    invariant.wellFormed invariant.grammarLocal invariant.workspaceBacking
    (by simp [parserGrammarValue])
  have grammarLengthLocal := effect.singleton_preserves_local_of_ne
    invariant.wellFormed invariant.grammarLengthLocal
    invariant.workspaceBacking (by simp)
  have tokensLocal := effect.singleton_preserves_local_of_ne
    invariant.wellFormed invariant.tokensLocal invariant.workspaceBacking
    (by simp [parserTokensValue, parserGrammarValue])
  have tokenCountLocal := effect.singleton_preserves_local_of_ne
    invariant.wellFormed invariant.tokenCountLocal invariant.workspaceBacking
    (by simp)
  have workspaceLocal := effect.singleton_preserves_local_of_ne
    invariant.wellFormed invariant.workspaceLocal invariant.workspaceBacking
    (by simp [workspaceValue])
  have workspaceLengthLocal := effect.singleton_preserves_local_of_ne
    invariant.wellFormed invariant.workspaceLengthLocal
    invariant.workspaceBacking (by simp)
  exact {
    grammarEncoded := invariant.grammarEncoded
    grammarWellFormed := invariant.grammarWellFormed
    wordsI32 := invariant.wordsI32
    tokensI32 := invariant.tokensI32
    workspaceLength := by
      rw [sameLength]
      exact invariant.workspaceLength
    workspaceTokenCount := invariant.workspaceTokenCount
    workspaceEncoded := newEncoded
    derivations := newDerivations
    wellFormed := afterWellFormed
    grammarLocal := grammarLocal
    grammarLengthLocal := grammarLengthLocal
    tokensLocal := tokensLocal
    tokenCountLocal := tokenCountLocal
    workspaceLocal := by
      simpa [workspaceValue, sameLength] using workspaceLocal
    workspaceLengthLocal := by
      rw [sameLength]
      exact workspaceLengthLocal
    grammarBacking := effect.preserves_entry invariant.wellFormed
      invariant.grammarBacking (by
        simpa [CellSet.singleton] using invariant.grammarWorkspaceDistinct)
    tokensBacking := effect.preserves_entry invariant.wellFormed
      invariant.tokensBacking (by
        simpa [CellSet.singleton] using invariant.tokensWorkspaceDistinct)
    workspaceBacking := newBacking
    grammarWorkspaceDistinct := invariant.grammarWorkspaceDistinct
    tokensWorkspaceDistinct := invariant.tokensWorkspaceDistinct
  }

/-- Preserve an unchanged logical workspace across a scoped workspace effect.
    The outer effect supplies the caller's lexical behavior, while `cells`
    transfers the already-proved physical workspace representation from the
    inner result. -/
theorem RecognizerInvariant.after_same_workspace_effect
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell before)
    (effect : ModifiesOnly (CellSet.singleton workspaceCell) before after)
    (afterWellFormed : StateWellFormed after)
    (completed : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell innerAfter)
    (cells : after.cells = innerAfter.cells) :
    RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell after := by
  apply invariant.after_workspace_effect effect afterWellFormed workspace
    workspaceValues rfl completed.workspaceEncoded invariant.derivations
  unfold State.cellEntry?
  rw [cells]
  exact completed.workspaceBacking

/-- Re-establish the recognizer after a workspace mutation accompanied by
    owned scalar updates (for example state-count and loop-index cells).
    The caller supplies the new logical/physical workspace view; every other
    persistent resource follows from the declared write footprint. -/
theorem RecognizerInvariant.after_workspace_and_scalar_effect
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell before)
    (writes : CellSet)
    (effect : ModifiesOnly writes before after)
    (afterWellFormed : StateWellFormed after)
    (grammarNotWritten : ¬ writes grammarCell)
    (tokensNotWritten : ¬ writes tokensCell)
    (parameterFrameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        verifiedParserRecognizerParameterFrame) writes)
    (newWorkspace : LogicalWorkspace) (newValues : List Int)
    (sameLength : newValues.length = workspaceValues.length)
    (newEncoded : EncodesWorkspace workspaceLayout newWorkspace
      (listWords newValues))
    (newDerivations : WorkspaceDerivations grammar tokens newWorkspace)
    (newBacking : after.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values newValues))
    }) :
    RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
      newWorkspace newValues grammarCell tokensCell workspaceCell after := by
  have preserveLocal (id : VarId)
      (idBound : id ∈ verifiedParserRecognizerParameterIds)
      (value : Value) (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint invariant.wellFormed
      parameterFrameDisjoint idBound found
  exact {
    grammarEncoded := invariant.grammarEncoded
    grammarWellFormed := invariant.grammarWellFormed
    wordsI32 := invariant.wordsI32
    tokensI32 := invariant.tokensI32
    workspaceLength := by
      rw [sameLength]
      exact invariant.workspaceLength
    workspaceTokenCount := invariant.workspaceTokenCount
    workspaceEncoded := newEncoded
    derivations := newDerivations
    wellFormed := afterWellFormed
    grammarLocal := preserveLocal 0 (by simp) _ invariant.grammarLocal
    grammarLengthLocal := preserveLocal 1 (by simp) _
      invariant.grammarLengthLocal
    tokensLocal := preserveLocal 2 (by simp) _ invariant.tokensLocal
    tokenCountLocal := preserveLocal 3 (by simp) _
      invariant.tokenCountLocal
    workspaceLocal := by
      have preserved := preserveLocal 4 (by simp) _ invariant.workspaceLocal
      simpa [workspaceValue, sameLength] using preserved
    workspaceLengthLocal := by
      have preserved := preserveLocal 5 (by simp) _
        invariant.workspaceLengthLocal
      rw [sameLength]
      exact preserved
    grammarBacking := effect.preserves_entry invariant.wellFormed
      invariant.grammarBacking grammarNotWritten
    tokensBacking := effect.preserves_entry invariant.wellFormed
      invariant.tokensBacking tokensNotWritten
    workspaceBacking := newBacking
    grammarWorkspaceDistinct := invariant.grammarWorkspaceDistinct
    tokensWorkspaceDistinct := invariant.tokensWorkspaceDistinct
  }

/-- Preserve the recognizer frame across arbitrary writes disjoint from its
    three array backings and six source-parameter cells. This is the general
    frame rule used when one loop iteration mutates several owned scalars. -/
theorem RecognizerInvariant.after_disjoint_effect
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell before)
    (writes : CellSet)
    (effect : ModifiesOnly writes before after)
    (afterWellFormed : StateWellFormed after)
    (grammarNotWritten : ¬ writes grammarCell)
    (tokensNotWritten : ¬ writes tokensCell)
    (workspaceNotWritten : ¬ writes workspaceCell)
    (parameterFrameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        verifiedParserRecognizerParameterFrame) writes) :
    RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell after := by
  have preserveLocal (id : VarId)
      (idBound : id ∈ verifiedParserRecognizerParameterIds)
      (value : Value) (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint invariant.wellFormed
      parameterFrameDisjoint idBound found
  exact {
    grammarEncoded := invariant.grammarEncoded
    grammarWellFormed := invariant.grammarWellFormed
    wordsI32 := invariant.wordsI32
    tokensI32 := invariant.tokensI32
    workspaceLength := invariant.workspaceLength
    workspaceTokenCount := invariant.workspaceTokenCount
    workspaceEncoded := invariant.workspaceEncoded
    derivations := invariant.derivations
    wellFormed := afterWellFormed
    grammarLocal := preserveLocal 0 (by simp) _ invariant.grammarLocal
    grammarLengthLocal := preserveLocal 1 (by simp) _
      invariant.grammarLengthLocal
    tokensLocal := preserveLocal 2 (by simp) _ invariant.tokensLocal
    tokenCountLocal := preserveLocal 3 (by simp) _
      invariant.tokenCountLocal
    workspaceLocal := preserveLocal 4 (by simp) _ invariant.workspaceLocal
    workspaceLengthLocal := preserveLocal 5 (by simp) _
      invariant.workspaceLengthLocal
    grammarBacking := effect.preserves_entry invariant.wellFormed
      invariant.grammarBacking grammarNotWritten
    tokensBacking := effect.preserves_entry invariant.wellFormed
      invariant.tokensBacking tokensNotWritten
    workspaceBacking := effect.preserves_entry invariant.wellFormed
      invariant.workspaceBacking workspaceNotWritten
    grammarWorkspaceDistinct := invariant.grammarWorkspaceDistinct
    tokensWorkspaceDistinct := invariant.tokensWorkspaceDistinct
  }

/-- Singleton specialization for one scalar-local assignment. -/
theorem RecognizerInvariant.after_disjoint_scalar_effect
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell before)
    (written : CellId)
    (effect : ModifiesOnly (CellSet.singleton written) before after)
    (afterWellFormed : StateWellFormed after)
    (grammarDistinct : grammarCell ≠ written)
    (tokensDistinct : tokensCell ≠ written)
    (workspaceDistinct : workspaceCell ≠ written)
    (parameterFrameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        verifiedParserRecognizerParameterFrame)
      (CellSet.singleton written)) :
    RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell after := by
  apply invariant.after_disjoint_effect (CellSet.singleton written) effect
    afterWellFormed
  · simpa [CellSet.singleton] using grammarDistinct
  · simpa [CellSet.singleton] using tokensDistinct
  · simpa [CellSet.singleton] using workspaceDistinct
  · exact parameterFrameDisjoint

structure RecognizerAppendCallResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (before afterArguments : State) (arguments : List Expr)
    (position : Nat) (seed : StateSeed)
    (argumentsInvariant : RecognizerInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell afterArguments) where
  after : State
  evaluation : Evaluates verifiedParserCore before
    (.call extractedParserAppendStateFunction.id arguments)
    (appendOutcomeValue
      (appendLogical workspaceLayout.capacity position seed workspace).1)
    after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) afterArguments after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout
    (appendLogical workspaceLayout.capacity position seed workspace).2
    (appendResultValues workspaceLayout workspace position seed
      workspaceValues)
    grammarCell tokensCell workspaceCell after

/-- Apply the extracted `append_state` contract inside the persistent
    recognizer frame. Argument evaluation may contain pure nested constructor
    calls, so its post-state and invariant are explicit; only the subsequent
    append call receives permission to mutate the workspace cell. -/
noncomputable def RecognizerInvariant.evaluate_append
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell afterArguments)
    (before : State) (arguments : List Expr)
    (position : Nat) (seed : StateSeed)
    (positionBound : position ≤ finalPosition workspaceLayout.tokenCount)
    (seedOriginBound : seed.origin ≤
      finalPosition workspaceLayout.tokenCount)
    (seedDerivation :
      EarleySeedDerivation grammar tokens workspace position seed)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      workspaceValue workspaceValues workspaceCell,
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
      .signed .i32 (Int.ofNat workspaceLayout.capacity),
      .signed .i32 (Int.ofNat position), stateSeedValue seed,
      .signed .i32 (Int.ofNat workspace.states.length)] afterArguments) :
    RecognizerAppendCallResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell before afterArguments arguments position seed invariant := by
  let result := extractedParserAppendStateCall_evaluates workspaceLayout
    workspace workspaceValues workspaceCell position seed before afterArguments
    arguments invariant.workspaceLength invariant.workspaceEncoded positionBound
    seedOriginBound invariant.wellFormed argumentsResult invariant.workspaceBacking
  let after := Classical.choose result
  have facts := Classical.choose_spec result
  have appended : Append workspaceLayout.capacity position seed workspace
      (appendLogical workspaceLayout.capacity position seed workspace).1
      (appendLogical workspaceLayout.capacity position seed workspace).2 :=
    appendLogical_refines _ rfl
  have newDerivations := appended.preserves_derivations
    invariant.derivations seedDerivation
  exact {
    after := after
    evaluation := facts.1
    effect := facts.2.1
    invariant := invariant.after_workspace_effect facts.2.1 facts.2.2.1
      (appendLogical workspaceLayout.capacity position seed workspace).2
      (appendResultValues workspaceLayout workspace position seed
        workspaceValues)
      (appendResultValues_length workspaceLayout workspace position seed
        workspaceValues)
      facts.2.2.2.2
      newDerivations
      facts.2.2.2.1
  }

def recognizerAppendArguments
    (position seed : Expr) : List Expr := [
  .local 4, .local 8, .local 9, position, seed, .local 18]

def recognizerAppendCall (position seed : Expr) : Expr :=
  .call extractedParserAppendStateFunction.id
    (recognizerAppendArguments position seed)

/-- Physical separation between the recognizer's source-parameter frame and
    one loop-owned scalar cell. -/
def RecognizerParameterFrameSeparated
    (runtime : State) (ownedCell : CellId) : Prop :=
  CellSet.Disjoint
    (localBindingFrameFootprint runtime verifiedParserRecognizerParameterFrame)
    (CellSet.singleton ownedCell)

/-- State shared by every recognizer `append_state` site. Site-specific
    invariants add only the locals needed to construct their `StateSeed`. -/
structure RecognizerAppendFrame
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (runtime : State) (position : Nat) : Prop where
  recognizer : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell runtime
  positionBound : position ≤ finalPosition workspaceLayout.tokenCount
  stateBaseLocal : runtime.local? 8 = some
    (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
  stateCapacityLocal : runtime.local? 9 = some
    (.signed .i32 (Int.ofNat workspaceLayout.capacity))
  stateCountLocal : runtime.local? 18 = some
    (.signed .i32 (Int.ofNat workspace.states.length))
  stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
    (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds runtime
  stateCountBackingDistinct :
    stateCountCell ≠ grammarCell ∧
    stateCountCell ≠ tokensCell ∧
    stateCountCell ≠ workspaceCell
  stateCountParameterSeparate :
    RecognizerParameterFrameSeparated runtime stateCountCell

/-- Re-index the shared append resources at another valid chart position.
    No physical state changes; only the semantic position carried by the
    caller changes. -/
def RecognizerAppendFrame.at_position
    (frame : RecognizerAppendFrame grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position)
    (nextPosition : Nat)
    (nextPositionBound : nextPosition ≤
      finalPosition workspaceLayout.tokenCount) :
    RecognizerAppendFrame grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      stateCountCell runtime nextPosition := {
  recognizer := frame.recognizer
  positionBound := nextPositionBound
  stateBaseLocal := frame.stateBaseLocal
  stateCapacityLocal := frame.stateCapacityLocal
  stateCountLocal := frame.stateCountLocal
  stateCountOwned := frame.stateCountOwned
  stateCountBackingDistinct := frame.stateCountBackingDistinct
  stateCountParameterSeparate := frame.stateCountParameterSeparate
}

theorem RecognizerAppendFrame.stateCountParameterDistinct
    (frame : RecognizerAppendFrame grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position)
    (id : VarId) (member : id ∈ verifiedParserRecognizerParameterIds) :
    runtime.cellId? id ≠ some stateCountCell :=
  frame.stateCountParameterSeparate.localCell_ne_of_singleton member

/-- Store-pure helper calls preserve the complete append frame. -/
theorem RecognizerAppendFrame.after_empty_effect
    (frame : RecognizerAppendFrame grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell before position)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    RecognizerAppendFrame grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      stateCountCell after position := {
  recognizer := frame.recognizer.after_empty_effect effect afterWellFormed
  positionBound := frame.positionBound
  stateBaseLocal := effect.empty_preserves_local frame.recognizer.wellFormed
    frame.stateBaseLocal
  stateCapacityLocal := effect.empty_preserves_local
    frame.recognizer.wellFormed frame.stateCapacityLocal
  stateCountLocal := effect.empty_preserves_local frame.recognizer.wellFormed
    frame.stateCountLocal
  stateCountOwned := effect.empty_preserves_assertion frame.recognizer.wellFormed
    (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length))))
    frame.stateCountOwned
  stateCountBackingDistinct := frame.stateCountBackingDistinct
  stateCountParameterSeparate := by
    unfold RecognizerParameterFrameSeparated
    rw [effect.localBindingFrameFootprint_eq
      verifiedParserRecognizerParameterFrame]
    exact frame.stateCountParameterSeparate
}

/-- A write to one loop-owned scalar preserves the shared append frame when
    that scalar is physically separate from `state_base`, `state_capacity`,
    and `state_count`.  Cursor-bearing recognizer loops use this rule after
    advancing their cursor, instead of rebuilding the same ownership proof
    independently. -/
theorem RecognizerAppendFrame.after_scalar_effect
    (frame : RecognizerAppendFrame grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell before position)
    (scalarCell : CellId)
    (effect : ModifiesOnly (CellSet.singleton scalarCell) before after)
    (recognizer : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell after)
    (stateBaseDistinct : before.cellId? 8 ≠ some scalarCell)
    (stateCapacityDistinct : before.cellId? 9 ≠ some scalarCell)
    (stateCountDistinct : stateCountCell ≠ scalarCell) :
    RecognizerAppendFrame grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      stateCountCell after position := by
  have preserveLocal (id : VarId) (value : Value)
      (found : before.local? id = some value)
      (distinct : before.cellId? id ≠ some scalarCell) :
      after.local? id = some value := by
    apply effect.preserves_local frame.recognizer.wellFormed found
    intro cell cellId written
    change cell = scalarCell at written
    subst cell
    exact distinct cellId
  have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds after :=
    effect.preserves_localPointsTo frame.recognizer.wellFormed
      frame.stateCountOwned (by
        intro written
        change stateCountCell = scalarCell at written
        exact stateCountDistinct written)
  exact {
    recognizer := recognizer
    positionBound := frame.positionBound
    stateBaseLocal := preserveLocal 8 _ frame.stateBaseLocal stateBaseDistinct
    stateCapacityLocal := preserveLocal 9 _ frame.stateCapacityLocal
      stateCapacityDistinct
    stateCountLocal := Assertion.localPointsTo_local 18 stateCountCell _ after
      stateCountOwned
    stateCountOwned := stateCountOwned
    stateCountBackingDistinct := frame.stateCountBackingDistinct
    stateCountParameterSeparate := by
      unfold RecognizerParameterFrameSeparated
      rw [effect.localBindingFrameFootprint_eq
        verifiedParserRecognizerParameterFrame]
      exact frame.stateCountParameterSeparate
  }

/-- Binding a temporary local preserves the complete append frame.  Keeping
    this operation at the shared frame level prevents each recognizer loop
    from reproving ownership of the state-count cell and the immutable parser
    resources for every artifact-derived `let`. -/
theorem RecognizerAppendFrame.after_bind_local
    (frame : RecognizerAppendFrame grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position)
    (id : VarId) (value : Value)
    (not0 : id ≠ 0) (not1 : id ≠ 1) (not2 : id ≠ 2)
    (not3 : id ≠ 3) (not4 : id ≠ 4) (not5 : id ≠ 5)
    (parametersBefore : 5 < id)
    (not8 : id ≠ 8) (not9 : id ≠ 9) (not18 : id ≠ 18) :
    RecognizerAppendFrame grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      stateCountCell (runtime.bindLocal id value) position := by
  exact {
    recognizer := frame.recognizer.after_bind_local id value not0 not1 not2
      not3 not4 not5
    positionBound := frame.positionBound
    stateBaseLocal :=
      (bindLocal_preserves_other_local frame.recognizer.wellFormed not8).trans
        frame.stateBaseLocal
    stateCapacityLocal :=
      (bindLocal_preserves_other_local frame.recognizer.wellFormed not9).trans
        frame.stateCapacityLocal
    stateCountLocal :=
      (bindLocal_preserves_other_local frame.recognizer.wellFormed not18).trans
        frame.stateCountLocal
    stateCountOwned := bindLocal_preserves_localPointsTo_of_ne runtime id 18
      value stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))
      frame.recognizer.wellFormed not18 frame.stateCountOwned
    stateCountBackingDistinct := frame.stateCountBackingDistinct
    stateCountParameterSeparate := by
      unfold RecognizerParameterFrameSeparated
      intro cell framed written
      obtain ⟨queried, queriedBound, cellId⟩ := framed
      have queriedLe :=
        (mem_verifiedParserRecognizerParameterIds_iff queried).mp queriedBound
      have different : id ≠ queried :=
        Nat.ne_of_gt (Nat.lt_of_le_of_lt queriedLe parametersBefore)
      apply frame.stateCountParameterSeparate cell
      · exact ⟨queried, queriedBound, by
          simpa [State.bindLocal, State.bindCell, State.cellId?, different]
            using cellId⟩
      · exact written
  }

structure RecognizerSeededAppendResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (before : State) (position : Nat) (positionExpr seedExpr : Expr)
    (seed : StateSeed)
    (beforeFrame : RecognizerAppendFrame grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell before position) where
  argumentsState : State
  argumentsEvaluation : ArgumentsEvaluateTo verifiedParserCore before
    (recognizerAppendArguments positionExpr seedExpr) [
      workspaceValue workspaceValues workspaceCell,
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
      .signed .i32 (Int.ofNat workspaceLayout.capacity),
      .signed .i32 (Int.ofNat position), stateSeedValue seed,
      .signed .i32 (Int.ofNat workspace.states.length)] argumentsState
  argumentsInvariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell argumentsState
  after : State
  evaluation : Evaluates verifiedParserCore before
    (recognizerAppendCall positionExpr seedExpr)
    (appendOutcomeValue
      (appendLogical workspaceLayout.capacity position seed workspace).1) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
    (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout
    (appendLogical workspaceLayout.capacity position seed workspace).2
    (appendResultValues workspaceLayout workspace position seed
      workspaceValues)
    grammarCell tokensCell workspaceCell after

/-- Shared semantic operation behind all five extracted recognizer appends.
    The nested state constructor is required to be store-pure; only the
    workspace backing may be written by the append itself. -/
noncomputable def RecognizerAppendFrame.evaluate_seeded_append
    (frame : RecognizerAppendFrame grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position)
    (positionExpr seedExpr : Expr) (seed : StateSeed) (afterSeed : State)
    (seedDerivation :
      EarleySeedDerivation grammar tokens workspace position seed)
    (seedOriginBound : seed.origin ≤
      finalPosition workspaceLayout.tokenCount)
    (positionResult : Evaluates verifiedParserCore runtime positionExpr
      (.signed .i32 (Int.ofNat position)) runtime)
    (seedEvaluation : Evaluates verifiedParserCore runtime seedExpr
      (stateSeedValue seed) afterSeed)
    (seedEffect : ModifiesOnly CellSet.empty runtime afterSeed)
    (afterSeedWellFormed : StateWellFormed afterSeed) :
    RecognizerSeededAppendResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position positionExpr seedExpr seed
      frame := by
  have afterSeedInvariant := frame.recognizer.after_empty_effect seedEffect
    afterSeedWellFormed
  have workspaceResult : Evaluates verifiedParserCore runtime (.local 4)
      (workspaceValue workspaceValues workspaceCell) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 4 _
      frame.recognizer.workspaceLocal⟩
  have baseResult : Evaluates verifiedParserCore runtime (.local 8)
      (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
      runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 8 _
      frame.stateBaseLocal⟩
  have capacityResult : Evaluates verifiedParserCore runtime (.local 9)
      (.signed .i32 (Int.ofNat workspaceLayout.capacity)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 9 _
      frame.stateCapacityLocal⟩
  have stateCountResult : Evaluates verifiedParserCore afterSeed (.local 18)
      (.signed .i32 (Int.ofNat workspace.states.length)) afterSeed :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore afterSeed 18 _
      (seedEffect.empty_preserves_local frame.recognizer.wellFormed
        frame.stateCountLocal)⟩
  have argumentsResult : ArgumentsEvaluateTo verifiedParserCore runtime
      (recognizerAppendArguments positionExpr seedExpr) [
        workspaceValue workspaceValues workspaceCell,
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
        .signed .i32 (Int.ofNat workspaceLayout.capacity),
        .signed .i32 (Int.ofNat position), stateSeedValue seed,
        .signed .i32 (Int.ofNat workspace.states.length)] afterSeed := by
    simpa [recognizerAppendArguments] using
      ArgumentsEvaluateTo.cons workspaceResult
        (ArgumentsEvaluateTo.cons baseResult
          (ArgumentsEvaluateTo.cons capacityResult
            (ArgumentsEvaluateTo.cons positionResult
              (ArgumentsEvaluateTo.cons seedEvaluation
                (ArgumentsEvaluateTo.singleton stateCountResult)))))
  let appended := afterSeedInvariant.evaluate_append runtime
    (recognizerAppendArguments positionExpr seedExpr) position seed
    frame.positionBound seedOriginBound seedDerivation argumentsResult
  have ownedAfterSeed := seedEffect.empty_preserves_assertion
    frame.recognizer.wellFormed
    (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length))))
    frame.stateCountOwned
  have ownedAfterAppend := appended.effect.preserve
    afterSeedInvariant.wellFormed
    (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length))))
    ownedAfterSeed (by
      intro cell member written
      exact frame.stateCountBackingDistinct.2.2
        (member.symm.trans written))
  exact {
    argumentsState := afterSeed
    argumentsEvaluation := argumentsResult
    argumentsInvariant := afterSeedInvariant
    after := appended.after
    evaluation := by
      simpa [recognizerAppendCall] using appended.evaluation
    effect := (seedEffect.weaken CellSet.empty_subset).trans_same
      appended.effect
    stateCountOwned := ownedAfterAppend
    invariant := appended.invariant
  }

/-- Close a no-tail append-result scope on its successful path. This is the
    common operation used by terminal, nullable, and parent-completion sites;
    prediction and initial seeding add an explicit loop-index tail. -/
theorem RecognizerSeededAppendResult.execute_ok
    (appended : RecognizerSeededAppendResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position positionExpr seedExpr seed
      frame)
    (resultLocal : VarId) (errorPosition : Expr)
    (resultNotCount : resultLocal ≠ 18)
    (statusOk : (appendLogical workspaceLayout.capacity position seed
      workspace).1.status = .ok) :
    ∃ after,
      Executes verifiedParserCore runtime
        (.letLocal resultLocal (.structure 2)
          (recognizerAppendCall positionExpr seedExpr)
          (parserAppendOutcomeContinuation resultLocal 18 errorPosition))
        .next after ∧
      ModifiesOnly
        (CellSet.union (CellSet.singleton workspaceCell)
          (CellSet.singleton stateCountCell)) runtime after ∧
      RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position seed workspace).2
        (appendResultValues workspaceLayout workspace position seed
          workspaceValues)
        grammarCell tokensCell workspaceCell after ∧
      (Assertion.localPointsTo 18 stateCountCell
        (some (.signed .i32 (Int.ofNat
          (appendLogical workspaceLayout.capacity position seed
            workspace).2.states.length)))).holds after := by
  let logical := appendLogical workspaceLayout.capacity position seed workspace
  let outcome := logical.1
  let bound := appended.after.bindLocal resultLocal (appendOutcomeValue outcome)
  have boundWellFormed : StateWellFormed bound :=
    bindLocal_preserves_well_formed appended.after resultLocal
      (appendOutcomeValue outcome) appended.invariant.wellFormed
  have resultFound : bound.local? resultLocal =
      some (appendOutcomeValue outcome) :=
    bindLocal_finds_local appended.after resultLocal
      (appendOutcomeValue outcome) appended.invariant.wellFormed
  have countOwnedBound : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds bound :=
    bindLocal_preserves_localPointsTo_of_ne appended.after resultLocal 18
      (appendOutcomeValue outcome) stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))
      appended.invariant.wellFormed resultNotCount appended.stateCountOwned
  have outcomeStatus : outcome.status = .ok := by
    simpa [outcome, logical] using statusOk
  let controlled := executeAppendOutcomeOk bound resultLocal 18 stateCountCell
    errorPosition outcome workspace.states.length boundWellFormed resultFound
    countOwnedBound outcomeStatus
  let after := restoreLocals appended.after controlled.after
  have execution : Executes verifiedParserCore runtime
      (.letLocal resultLocal (.structure 2)
        (recognizerAppendCall positionExpr seedExpr)
        (parserAppendOutcomeContinuation resultLocal 18 errorPosition))
      .next after := by
    simpa [bound, after] using
      (executesLetLocal (type := .structure 2) appended.evaluation
        controlled.execution)
  have entered : StoreEffect CellSet.empty appended.after bound := by
    simpa [bound] using
      bindLocal_effect appended.after resultLocal (appendOutcomeValue outcome)
  have scopedStore : StoreEffect (CellSet.singleton stateCountCell)
      appended.after controlled.after :=
    (entered.weaken CellSet.empty_subset).trans_same
      controlled.effect.toStoreEffect
  have closed : ModifiesOnly (CellSet.singleton stateCountCell)
      appended.after after := by
    simpa [after] using scopedStore.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    scopedStore.restoreLocals_wellFormed appended.invariant.wellFormed
      controlled.wellFormed
  have parameterFrameAfterAppend : RecognizerParameterFrameSeparated
      appended.after stateCountCell := by
    unfold RecognizerParameterFrameSeparated
    rw [appended.effect.localBindingFrameFootprint_eq
      verifiedParserRecognizerParameterFrame]
    exact frame.stateCountParameterSeparate
  have afterInvariant := appended.invariant.after_disjoint_scalar_effect
    stateCountCell closed afterWellFormed
    frame.stateCountBackingDistinct.1.symm
    frame.stateCountBackingDistinct.2.1.symm
    frame.stateCountBackingDistinct.2.2.symm
    parameterFrameAfterAppend
  have afterCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat logical.2.states.length)))).holds
      after := by
    constructor
    · change appended.after.cellId? 18 = some stateCountCell
      exact appended.stateCountOwned.1
    · change controlled.after.cellEntry? stateCountCell = some {
        id := stateCountCell
        value := some (.signed .i32 (Int.ofNat logical.2.states.length))
      }
      simpa [logical, outcome] using controlled.stateCountOwned.2
  exact ⟨after, execution, appended.effect.trans closed,
    by simpa [logical] using afterInvariant,
    by simpa [logical] using afterCountOwned⟩

/-- Close a no-tail append-result scope on its capacity-full path. The error
    position is read from an existing local, and return propagation skips the
    successful state-count assignment. -/
theorem RecognizerSeededAppendResult.execute_full_at_local
    (appended : RecognizerSeededAppendResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position positionExpr seedExpr seed
      frame)
    (resultLocal errorLocal : VarId)
    (resultNotError : resultLocal ≠ errorLocal)
    (errorAfterAppend : appended.after.local? errorLocal =
      some (.signed .i32 (Int.ofNat errorValue)))
    (statusFull : (appendLogical workspaceLayout.capacity position seed
      workspace).1.status = .full) :
    ∃ after,
      Executes verifiedParserCore runtime
        (.letLocal resultLocal (.structure 2)
          (recognizerAppendCall positionExpr seedExpr)
          (parserAppendOutcomeContinuation resultLocal 18
            (.local errorLocal)))
        (.returned (some (parseResultValue 2
          (Int.ofNat
            (appendLogical workspaceLayout.capacity position seed
              workspace).1.stateCount)
          (-1) (Int.ofNat errorValue)))) after ∧
      ModifiesOnly (CellSet.singleton workspaceCell) runtime after ∧
      StateWellFormed after ∧
      RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
        workspace workspaceValues grammarCell tokensCell workspaceCell after := by
  let logical := appendLogical workspaceLayout.capacity position seed workspace
  let outcome := logical.1
  let bound := appended.after.bindLocal resultLocal (appendOutcomeValue outcome)
  have boundWellFormed : StateWellFormed bound :=
    bindLocal_preserves_well_formed appended.after resultLocal
      (appendOutcomeValue outcome) appended.invariant.wellFormed
  have resultFound : bound.local? resultLocal =
      some (appendOutcomeValue outcome) :=
    bindLocal_finds_local appended.after resultLocal
      (appendOutcomeValue outcome) appended.invariant.wellFormed
  have errorBound : bound.local? errorLocal =
      some (.signed .i32 (Int.ofNat errorValue)) :=
    (bindLocal_preserves_other_local appended.invariant.wellFormed
      resultNotError).trans errorAfterAppend
  have errorResult : Evaluates verifiedParserCore bound (.local errorLocal)
      (.signed .i32 (Int.ofNat errorValue)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound errorLocal _ errorBound⟩
  have outcomeStatus : outcome.status = .full := by
    simpa [outcome, logical] using statusFull
  let controlled := executeAppendOutcomeFull bound resultLocal 18
    (.local errorLocal) outcome (Int.ofNat errorValue) boundWellFormed
    resultFound errorResult outcomeStatus
  let after := restoreLocals appended.after controlled.after
  have execution : Executes verifiedParserCore runtime
      (.letLocal resultLocal (.structure 2)
        (recognizerAppendCall positionExpr seedExpr)
        (parserAppendOutcomeContinuation resultLocal 18
          (.local errorLocal)))
      (.returned (some (parseResultValue 2
        (Int.ofNat outcome.stateCount) (-1) (Int.ofNat errorValue))))
      after := by
    simpa [bound, after] using
      (executesLetLocal (type := .structure 2) appended.evaluation
        controlled.execution)
  have entered : StoreEffect CellSet.empty appended.after bound := by
    simpa [bound] using
      bindLocal_effect appended.after resultLocal (appendOutcomeValue outcome)
  have scopedStore : StoreEffect CellSet.empty appended.after
      controlled.after := entered.trans_same controlled.effect.toStoreEffect
  have closed : ModifiesOnly CellSet.empty appended.after after := by
    simpa [after] using scopedStore.restoreLocals
  have effect : ModifiesOnly (CellSet.singleton workspaceCell) runtime after :=
    appended.effect.trans_same (closed.weaken CellSet.empty_subset)
  have afterWellFormed : StateWellFormed after :=
    scopedStore.restoreLocals_wellFormed appended.invariant.wellFormed
      controlled.wellFormed
  have workspaceEq : logical.2 = workspace :=
    appendLogical_workspace_eq_of_full statusFull
  have valuesEq : appendResultValues workspaceLayout workspace position seed
      workspaceValues = workspaceValues :=
    appendResultValues_eq_of_full statusFull
  have afterInvariant :=
    appended.invariant.after_empty_effect closed afterWellFormed
  rw [workspaceEq, valuesEq] at afterInvariant
  exact ⟨after, by simpa [logical, outcome] using execution, effect,
    afterWellFormed, afterInvariant⟩

/-- Successful append followed by an owned `i32` loop-index increment. This
    is shared by initial grammar seeding and nonterminal prediction. -/
theorem RecognizerSeededAppendResult.execute_ok_then_increment
    (appended : RecognizerSeededAppendResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position positionExpr seedExpr seed
      frame)
    (resultLocal indexLocal : VarId) (indexCell : CellId)
    (errorPosition : Expr) (index : Nat)
    (resultNotCount : resultLocal ≠ 18)
    (resultNotIndex : resultLocal ≠ indexLocal)
    (indexOwned : (Assertion.localPointsTo indexLocal indexCell
      (some (.signed .i32 (Int.ofNat index)))).holds runtime)
    (indexSuccI32 : index + 1 ≤ 2147483647)
    (indexBackingDistinct :
      indexCell ≠ grammarCell ∧
      indexCell ≠ tokensCell ∧
      indexCell ≠ workspaceCell ∧
      indexCell ≠ stateCountCell)
    (indexParameterDistinct : ∀ id,
      id ∈ verifiedParserRecognizerParameterIds →
      runtime.cellId? id ≠ some indexCell)
    (statusOk : (appendLogical workspaceLayout.capacity position seed
      workspace).1.status = .ok) :
    ∃ after,
      Executes verifiedParserCore runtime
        (.letLocal resultLocal (.structure 2)
          (recognizerAppendCall positionExpr seedExpr)
          (parserAppendOutcomeContinuationThen resultLocal 18 errorPosition
            (parserRecognizeIncrementLocal indexLocal))) .next after ∧
      ModifiesOnly
        (CellSet.union (CellSet.singleton workspaceCell)
          (CellSet.union (CellSet.singleton stateCountCell)
            (CellSet.singleton indexCell))) runtime after ∧
      RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position seed workspace).2
        (appendResultValues workspaceLayout workspace position seed
          workspaceValues)
        grammarCell tokensCell workspaceCell after ∧
      (Assertion.localPointsTo 18 stateCountCell
        (some (.signed .i32 (Int.ofNat
          (appendLogical workspaceLayout.capacity position seed
            workspace).2.states.length)))).holds after ∧
      (Assertion.localPointsTo indexLocal indexCell
        (some (.signed .i32 (Int.ofNat (index + 1))))).holds after := by
  let logical := appendLogical workspaceLayout.capacity position seed workspace
  let outcome := logical.1
  have indexOwnedAfterAppend : (Assertion.localPointsTo indexLocal indexCell
      (some (.signed .i32 (Int.ofNat index)))).holds appended.after :=
    appended.effect.preserve frame.recognizer.wellFormed
      (Assertion.localPointsTo indexLocal indexCell
        (some (.signed .i32 (Int.ofNat index)))) indexOwned (by
          intro cell member written
          exact indexBackingDistinct.2.2.1 (member.symm.trans written))
  let bound := appended.after.bindLocal resultLocal (appendOutcomeValue outcome)
  have boundWellFormed : StateWellFormed bound :=
    bindLocal_preserves_well_formed appended.after resultLocal
      (appendOutcomeValue outcome) appended.invariant.wellFormed
  have resultFound : bound.local? resultLocal =
      some (appendOutcomeValue outcome) :=
    bindLocal_finds_local appended.after resultLocal
      (appendOutcomeValue outcome) appended.invariant.wellFormed
  have countOwnedBound : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds bound :=
    bindLocal_preserves_localPointsTo_of_ne appended.after resultLocal 18
      (appendOutcomeValue outcome) stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))
      appended.invariant.wellFormed resultNotCount appended.stateCountOwned
  have indexOwnedBound : (Assertion.localPointsTo indexLocal indexCell
      (some (.signed .i32 (Int.ofNat index)))).holds bound :=
    bindLocal_preserves_localPointsTo_of_ne appended.after resultLocal
      indexLocal (appendOutcomeValue outcome) indexCell
      (some (.signed .i32 (Int.ofNat index))) appended.invariant.wellFormed
      resultNotIndex indexOwnedAfterAppend
  have outcomeStatus : outcome.status = .ok := by
    simpa [outcome, logical] using statusOk
  let controlled := executeAppendOutcomeOk bound resultLocal 18 stateCountCell
    errorPosition outcome workspace.states.length boundWellFormed resultFound
    countOwnedBound outcomeStatus
  have indexOwnedAfterControl : (Assertion.localPointsTo indexLocal indexCell
      (some (.signed .i32 (Int.ofNat index)))).holds controlled.after :=
    controlled.effect.preserve boundWellFormed
      (Assertion.localPointsTo indexLocal indexCell
        (some (.signed .i32 (Int.ofNat index)))) indexOwnedBound (by
          intro cell member written
          exact indexBackingDistinct.2.2.2 (member.symm.trans written))
  let incrementResult := executesIncrementOwnedI32Local verifiedParserCore
    controlled.after indexLocal indexCell index controlled.wellFormed
    indexOwnedAfterControl indexSuccI32
  let incrementAfter := Classical.choose incrementResult
  have incrementFacts := Classical.choose_spec incrementResult
  have controlThen : Executes verifiedParserCore bound
      (parserAppendOutcomeContinuationThen resultLocal 18 errorPosition
        (parserRecognizeIncrementLocal indexLocal)) .next incrementAfter := by
    apply executesSequence controlled.guardExecution
    apply executesSequence
      (executesExpression controlled.assignmentEvaluation)
    simpa [parserRecognizeIncrementLocal] using incrementFacts.1
  let after := restoreLocals appended.after incrementAfter
  have execution : Executes verifiedParserCore runtime
      (.letLocal resultLocal (.structure 2)
        (recognizerAppendCall positionExpr seedExpr)
        (parserAppendOutcomeContinuationThen resultLocal 18 errorPosition
          (parserRecognizeIncrementLocal indexLocal))) .next after := by
    simpa [bound, after] using
      (executesLetLocal (type := .structure 2) appended.evaluation controlThen)
  let scalarWrites := CellSet.union (CellSet.singleton stateCountCell)
    (CellSet.singleton indexCell)
  have bodyEffect : ModifiesOnly scalarWrites bound incrementAfter := by
    simpa [scalarWrites] using controlled.effect.trans incrementFacts.2.2.2
  have entered : StoreEffect CellSet.empty appended.after bound := by
    simpa [bound] using bindLocal_effect appended.after resultLocal
      (appendOutcomeValue outcome)
  have scopedStore : StoreEffect scalarWrites appended.after incrementAfter :=
    (entered.weaken CellSet.empty_subset).trans_same bodyEffect.toStoreEffect
  have closed : ModifiesOnly scalarWrites appended.after after := by
    simpa [after] using scopedStore.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    scopedStore.restoreLocals_wellFormed appended.invariant.wellFormed
      incrementFacts.2.1
  have parameterFrameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint appended.after
        verifiedParserRecognizerParameterFrame)
      scalarWrites := by
    intro cell framed written
    obtain ⟨id, idBound, found⟩ := framed
    have runtimeFound : runtime.cellId? id = some cell := by
      unfold State.cellId? at found ⊢
      rw [appended.effect.locals] at found
      exact found
    change cell = stateCountCell ∨ cell = indexCell at written
    rcases written with equal | equal
    · subst cell
      exact frame.stateCountParameterDistinct id idBound runtimeFound
    · subst cell
      exact indexParameterDistinct id idBound runtimeFound
  have afterInvariant := appended.invariant.after_disjoint_effect scalarWrites
    closed afterWellFormed
    (by
      simpa [scalarWrites, CellSet.union, CellSet.singleton, not_or] using
        ⟨frame.stateCountBackingDistinct.1.symm,
          indexBackingDistinct.1.symm⟩)
    (by
      simpa [scalarWrites, CellSet.union, CellSet.singleton, not_or] using
        ⟨frame.stateCountBackingDistinct.2.1.symm,
          indexBackingDistinct.2.1.symm⟩)
    (by
      simpa [scalarWrites, CellSet.union, CellSet.singleton, not_or] using
        ⟨frame.stateCountBackingDistinct.2.2.symm,
          indexBackingDistinct.2.2.1.symm⟩)
    parameterFrameDisjoint
  have countOwnedAfterIncrement : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat outcome.stateCount)))).holds
      incrementAfter :=
    incrementFacts.2.2.2.preserve controlled.wellFormed
      (Assertion.localPointsTo 18 stateCountCell
        (some (.signed .i32 (Int.ofNat outcome.stateCount))))
      controlled.stateCountOwned (by
        intro cell member written
        exact indexBackingDistinct.2.2.2.symm (member.symm.trans written))
  have afterCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat logical.2.states.length)))).holds after := by
    constructor
    · change appended.after.cellId? 18 = some stateCountCell
      exact appended.stateCountOwned.1
    · change incrementAfter.cellEntry? stateCountCell = some {
        id := stateCountCell
        value := some (.signed .i32 (Int.ofNat logical.2.states.length))
      }
      simpa [logical, outcome] using countOwnedAfterIncrement.2
  have afterIndexOwned : (Assertion.localPointsTo indexLocal indexCell
      (some (.signed .i32 (Int.ofNat (index + 1))))).holds after := by
    constructor
    · change appended.after.cellId? indexLocal = some indexCell
      unfold State.cellId?
      rw [appended.effect.locals]
      exact indexOwned.1
    · exact incrementFacts.2.2.1.2
  exact ⟨after, execution,
    by simpa [scalarWrites] using appended.effect.trans closed,
    by simpa [logical] using afterInvariant,
    by simpa [logical] using afterCountOwned, afterIndexOwned⟩

/-- The local state at the terminal branch of the recognizer's state loop. -/
structure RecognizerTerminalInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (runtime : State) (position semanticKind : Nat) : Prop where
  recognizer : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell runtime
  positionAdvanceI32 : position + 2 ≤ 2147483647
  semanticKindBound : semanticKind < grammar.grammar.canonical_kinds.length
  positionLocal : runtime.local? 23 =
    some (.signed .i32 (Int.ofNat position))
  semanticKindLocal : runtime.local? 29 =
    some (.signed .i32 (Int.ofNat semanticKind))

theorem verifiedParser_child_token_constant :
    verifiedParserCore.constant? 38 = some {
      id := 38
      type := parserI32Type
      value := .signed .i32 1
    } := by
  rfl

theorem verifiedParser_child_none_constant :
    verifiedParserCore.constant? 37 = some {
      id := 37
      type := parserI32Type
      value := .signed .i32 0
    } := by
  rfl

theorem verifiedParser_child_state_constant :
    verifiedParserCore.constant? 39 = some {
      id := 39
      type := parserI32Type
      value := .signed .i32 2
    } := by
  rfl

private theorem evaluatesNatSuccAtLocal
    (state : State) (id : VarId) (value : Nat)
    (localValue : state.local? id = some (.signed .i32 (Int.ofNat value)))
    (bound : value + 1 ≤ 2147483647) :
    Evaluates verifiedParserCore state
      (.binary .add (.local id) (.value (.signed .i32 1)))
      (.signed .i32 (Int.ofNat (value + 1))) state := by
  have left : Evaluates verifiedParserCore state (.local id)
      (.signed .i32 (Int.ofNat value)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state id _ localValue⟩
  have right : Evaluates verifiedParserCore state
      (.value (.signed .i32 1)) (.signed .i32 1) state := ⟨1, rfl⟩
  have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target
    (value + 1) bound
  have cast : Int.ofNat value + 1 = Int.ofNat (value + 1) := by simp
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp only [evalBinaryValue, evalSignedBinary]
  rw [cast, wrapped]
  rfl

private theorem evaluatesNatHalfAtLocal
    (state : State) (id : VarId) (value : Nat)
    (localValue : state.local? id = some (.signed .i32 (Int.ofNat value)))
    (bound : value ≤ 2147483647) :
    Evaluates verifiedParserCore state
      (.binary .divide (.local id) (.value (.signed .i32 2)))
      (.signed .i32 (Int.ofNat (value / 2))) state := by
  have left : Evaluates verifiedParserCore state (.local id)
      (.signed .i32 (Int.ofNat value)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state id _ localValue⟩
  have right : Evaluates verifiedParserCore state
      (.value (.signed .i32 2)) (.signed .i32 2) state := ⟨1, rfl⟩
  have quotient : truncDiv (Int.ofNat value) 2 =
      Int.ofNat (value / 2) := by simp [truncDiv]
  have quotientBound : value / 2 ≤ 2147483647 := by omega
  have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target
    (value / 2) quotientBound
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp only [evalBinaryValue, evalSignedBinary]
  simp only [show (SignedIntTy.i32 == SignedIntTy.i32) = true by decide,
    if_true]
  rw [quotient, wrapped]
  simp

def recognizerTerminalSeed
    (production dot origin stateId position semanticKind : Nat) : StateSeed := {
  production := production
  dot := dot + 1
  origin := origin
  previous := some stateId
  child := .token (position / 2) semanticKind
}

/-- Facts present after the scanner result has been bound to local 30 and its
    nonnegative branch has been selected. The logical scanner equation makes
    the subsequent append position part of the parser model rather than an
    arbitrary local value. -/
structure RecognizerTerminalAppendInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (runtime : State)
    (position semanticKind nextPosition production dot origin stateId : Nat) :
    Prop where
  terminal : RecognizerTerminalInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell runtime position semanticKind
  scanResult : scanTerminal grammar tokens position semanticKind =
    some nextPosition
  seedDerivation : EarleySeedDerivation grammar tokens workspace nextPosition
    (recognizerTerminalSeed production dot origin stateId position semanticKind)
  nextPositionBound : nextPosition ≤
    finalPosition workspaceLayout.tokenCount
  originBound : origin ≤ finalPosition workspaceLayout.tokenCount
  dotSuccI32 : dot + 1 ≤ 2147483647
  stateBaseLocal : runtime.local? 8 = some
    (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
  stateCapacityLocal : runtime.local? 9 = some
    (.signed .i32 (Int.ofNat workspaceLayout.capacity))
  stateCountLocal : runtime.local? 18 = some
    (.signed .i32 (Int.ofNat workspace.states.length))
  stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
    (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds runtime
  stateCountBackingDistinct :
    stateCountCell ≠ grammarCell ∧
    stateCountCell ≠ tokensCell ∧
    stateCountCell ≠ workspaceCell
  stateCountParameterSeparate :
    RecognizerParameterFrameSeparated runtime stateCountCell
  stateIdLocal : runtime.local? 24 = some
    (.signed .i32 (Int.ofNat stateId))
  productionLocal : runtime.local? 25 = some
    (.signed .i32 (Int.ofNat production))
  dotLocal : runtime.local? 26 = some
    (.signed .i32 (Int.ofNat dot))
  originLocal : runtime.local? 27 = some
    (.signed .i32 (Int.ofNat origin))
  nextPositionLocal : runtime.local? 30 = some
    (.signed .i32 (Int.ofNat nextPosition))

theorem RecognizerTerminalAppendInvariant.stateCountParameterDistinct
    (invariant : RecognizerTerminalAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId)
    (id : VarId) (member : id ∈ verifiedParserRecognizerParameterIds) :
    runtime.cellId? id ≠ some stateCountCell :=
  invariant.stateCountParameterSeparate.localCell_ne_of_singleton member

/-- Pre-scan state for one terminal Earley transition. The scanner result is
    not yet bound, but the current state fields and mutable state-count cell
    are owned and ready to be carried across the store-pure scanner call. -/
structure RecognizerTerminalReadyInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (runtime : State)
    (position semanticKind production dot origin stateId : Nat) : Prop where
  terminal : RecognizerTerminalInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell runtime position semanticKind
  seedDerivation : ∀ nextPosition,
    scanTerminal grammar tokens position semanticKind = some nextPosition →
    EarleySeedDerivation grammar tokens workspace nextPosition
      (recognizerTerminalSeed production dot origin stateId position semanticKind)
  dotSuccI32 : dot + 1 ≤ 2147483647
  originBound : origin ≤ finalPosition workspaceLayout.tokenCount
  stateBaseLocal : runtime.local? 8 = some
    (.signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
  stateCapacityLocal : runtime.local? 9 = some
    (.signed .i32 (Int.ofNat workspaceLayout.capacity))
  stateCountLocal : runtime.local? 18 = some
    (.signed .i32 (Int.ofNat workspace.states.length))
  stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
    (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds runtime
  stateCountBackingDistinct :
    stateCountCell ≠ grammarCell ∧
    stateCountCell ≠ tokensCell ∧
    stateCountCell ≠ workspaceCell
  stateCountParameterSeparate :
    RecognizerParameterFrameSeparated runtime stateCountCell
  stateIdLocal : runtime.local? 24 = some
    (.signed .i32 (Int.ofNat stateId))
  productionLocal : runtime.local? 25 = some
    (.signed .i32 (Int.ofNat production))
  dotLocal : runtime.local? 26 = some
    (.signed .i32 (Int.ofNat dot))
  originLocal : runtime.local? 27 = some
    (.signed .i32 (Int.ofNat origin))

theorem RecognizerTerminalReadyInvariant.stateCountParameterDistinct
    (invariant : RecognizerTerminalReadyInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind production dot
      origin stateId)
    (id : VarId) (member : id ∈ verifiedParserRecognizerParameterIds) :
    runtime.cellId? id ≠ some stateCountCell :=
  invariant.stateCountParameterSeparate.localCell_ne_of_singleton member

structure RecognizerTerminalScanMatchResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (before : State)
    (position semanticKind nextPosition production dot origin stateId : Nat)
    (beforeInvariant : RecognizerTerminalReadyInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell before position semanticKind
      production dot origin stateId) where
  afterScan : State
  bound : State
  scanEvaluation : Evaluates verifiedParserCore before
    parserRecognizeScanTerminalCall (.signed .i32 (Int.ofNat nextPosition))
    afterScan
  scanEffect : ModifiesOnly CellSet.empty before afterScan
  afterScanInvariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell afterScan
  entered : StoreEffect CellSet.empty afterScan bound
  parameterCellId : ∀ id, id ∈ verifiedParserRecognizerParameterIds →
    bound.cellId? id = afterScan.cellId? id
  invariant : RecognizerTerminalAppendInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell bound position semanticKind nextPosition
    production dot origin stateId

/-- Evaluate the exact scanner call, bind its successful result to local 30,
    and transfer every owned fact needed by the append arm. -/
noncomputable def RecognizerTerminalReadyInvariant.bind_scan_match
    (invariant : RecognizerTerminalReadyInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind production dot
      origin stateId)
    (nextPosition : Nat)
    (scanResult : scanTerminal grammar tokens position semanticKind =
      some nextPosition)
    (nextPositionBound : nextPosition ≤
      finalPosition workspaceLayout.tokenCount) :
    RecognizerTerminalScanMatchResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId invariant := by
  have scanEntry : ScanTerminalInvariant grammarLayout grammar words tokens
      grammarCell tokensCell position semanticKind
      (parserScanTerminalCallee runtime words tokens grammarCell tokensCell
        position semanticKind) :=
    parserScanTerminalCallee_entry grammarLayout grammar words tokens
      grammarCell tokensCell position semanticKind runtime
      invariant.terminal.recognizer.grammarEncoded
      invariant.terminal.recognizer.wordsI32
      invariant.terminal.recognizer.tokensI32
      invariant.terminal.positionAdvanceI32
      invariant.terminal.semanticKindBound
      invariant.terminal.recognizer.wellFormed
      invariant.terminal.recognizer.grammarBacking
      invariant.terminal.recognizer.tokensBacking
  let scanResultProof := parserRecognizeScanTerminalCall_implements_model
    runtime invariant.terminal.recognizer.wellFormed
    invariant.terminal.recognizer.grammarLocal
    invariant.terminal.recognizer.tokensLocal
    invariant.terminal.recognizer.tokenCountLocal
    invariant.terminal.positionLocal invariant.terminal.semanticKindLocal
    invariant.terminal.recognizer.grammarBacking
    invariant.terminal.recognizer.tokensBacking scanEntry
  let afterScan := Classical.choose scanResultProof
  have scanFacts := Classical.choose_spec scanResultProof
  have afterScanInvariant :=
    invariant.terminal.recognizer.after_empty_effect scanFacts.2.1
      scanFacts.2.2.1
  let bound := afterScan.bindLocal 30
    (.signed .i32 (Int.ofNat nextPosition))
  have scanEvaluation : Evaluates verifiedParserCore runtime
      parserRecognizeScanTerminalCall
      (.signed .i32 (Int.ofNat nextPosition)) afterScan := by
    simpa [afterScan, scanResult, scanTerminalValue] using scanFacts.1
  have entered : StoreEffect CellSet.empty afterScan bound := by
    simpa [bound] using bindLocal_effect afterScan 30
      (.signed .i32 (Int.ofNat nextPosition))
  have preserveLocal (id : VarId) (different : 30 ≠ id)
      (value : Value) (found : runtime.local? id = some value) :
      bound.local? id = some value := by
    have afterScanFound := scanFacts.2.1.empty_preserves_local
      invariant.terminal.recognizer.wellFormed found
    exact (bindLocal_preserves_other_local afterScanInvariant.wellFormed
      different).trans afterScanFound
  have countOwnedAfterScan := scanFacts.2.1.empty_preserves_assertion
    invariant.terminal.recognizer.wellFormed
    (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length))))
    invariant.stateCountOwned
  have countOwnedBound := bindLocal_preserves_localPointsTo_of_ne afterScan
    30 18 (.signed .i32 (Int.ofNat nextPosition)) stateCountCell
    (some (.signed .i32 (Int.ofNat workspace.states.length)))
    afterScanInvariant.wellFormed (by decide) countOwnedAfterScan
  have parameterDistinctBound : ∀ id,
      id ∈ verifiedParserRecognizerParameterIds →
      bound.cellId? id ≠ some stateCountCell := by
    intro id idBound
    have idLe := (mem_verifiedParserRecognizerParameterIds_iff id).mp idBound
    have different : 30 ≠ id :=
      Nat.ne_of_gt (Nat.lt_of_le_of_lt idLe (by decide))
    have afterBind : bound.cellId? id = afterScan.cellId? id := by
      simp [bound, State.bindLocal, State.bindCell, State.cellId?, different]
    have afterScanCell : afterScan.cellId? id = runtime.cellId? id := by
      unfold State.cellId?
      rw [scanFacts.2.1.locals]
    rw [afterBind, afterScanCell]
    exact invariant.stateCountParameterDistinct id idBound
  exact {
    afterScan := afterScan
    bound := bound
    scanEvaluation := scanEvaluation
    scanEffect := scanFacts.2.1
    afterScanInvariant := afterScanInvariant
    entered := entered
    parameterCellId := by
      intro id idBound
      have idLe := (mem_verifiedParserRecognizerParameterIds_iff id).mp idBound
      have different : 30 ≠ id :=
        Nat.ne_of_gt (Nat.lt_of_le_of_lt idLe (by decide))
      simp [bound, State.bindLocal, State.bindCell, State.cellId?, different]
    invariant := {
      terminal := {
        recognizer := afterScanInvariant.after_bind_local 30
          (.signed .i32 (Int.ofNat nextPosition))
          (by decide) (by decide) (by decide) (by decide) (by decide)
          (by decide)
        positionAdvanceI32 := invariant.terminal.positionAdvanceI32
        semanticKindBound := invariant.terminal.semanticKindBound
        positionLocal := preserveLocal 23 (by decide) _
          invariant.terminal.positionLocal
        semanticKindLocal := preserveLocal 29 (by decide) _
          invariant.terminal.semanticKindLocal
      }
      scanResult := scanResult
      seedDerivation := invariant.seedDerivation nextPosition scanResult
      nextPositionBound := nextPositionBound
      dotSuccI32 := invariant.dotSuccI32
      originBound := invariant.originBound
      stateBaseLocal := preserveLocal 8 (by decide) _ invariant.stateBaseLocal
      stateCapacityLocal := preserveLocal 9 (by decide) _
        invariant.stateCapacityLocal
      stateCountLocal := preserveLocal 18 (by decide) _
        invariant.stateCountLocal
      stateCountOwned := countOwnedBound
      stateCountBackingDistinct := invariant.stateCountBackingDistinct
      stateCountParameterSeparate :=
        localBindingFrameFootprint_disjoint_singleton parameterDistinctBound
      stateIdLocal := preserveLocal 24 (by decide) _ invariant.stateIdLocal
      productionLocal := preserveLocal 25 (by decide) _
        invariant.productionLocal
      dotLocal := preserveLocal 26 (by decide) _ invariant.dotLocal
      originLocal := preserveLocal 27 (by decide) _ invariant.originLocal
      nextPositionLocal := bindLocal_finds_local afterScan 30
        (.signed .i32 (Int.ofNat nextPosition)) afterScanInvariant.wellFormed
    }
  }

theorem RecognizerTerminalAppendInvariant.seed_arguments
    (invariant : RecognizerTerminalAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId) :
    ArgumentsEvaluateTo verifiedParserCore runtime
      parserRecognizeTerminalSeedArguments
      (parserStateSeedArgumentsValues
        (recognizerTerminalSeed production dot origin stateId position
          semanticKind)) runtime := by
  have productionResult : Evaluates verifiedParserCore runtime (.local 25)
      (.signed .i32 (Int.ofNat production)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 25 _
      invariant.productionLocal⟩
  have dotResult := evaluatesNatSuccAtLocal runtime 26 dot
    invariant.dotLocal invariant.dotSuccI32
  have originResult : Evaluates verifiedParserCore runtime (.local 27)
      (.signed .i32 (Int.ofNat origin)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 27 _
      invariant.originLocal⟩
  have stateIdResult : Evaluates verifiedParserCore runtime (.local 24)
      (.signed .i32 (Int.ofNat stateId)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 24 _
      invariant.stateIdLocal⟩
  have childTagResult : Evaluates verifiedParserCore runtime (.constant 38)
      (.signed .i32 1) runtime := by
    refine ⟨2, ?_⟩
    simp [evalExpr, verifiedParser_child_token_constant]
  have positionI32 : position ≤ 2147483647 := by
    exact Nat.le_trans (Nat.le_add_right position 2)
      invariant.terminal.positionAdvanceI32
  have tokenIndexResult := evaluatesNatHalfAtLocal runtime 23 position
    invariant.terminal.positionLocal positionI32
  have kindResult : Evaluates verifiedParserCore runtime (.local 29)
      (.signed .i32 (Int.ofNat semanticKind)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 29 _
      invariant.terminal.semanticKindLocal⟩
  simpa [parserRecognizeTerminalSeedArguments,
      parserStateSeedArgumentsValues, recognizerTerminalSeed,
      previousValue, encodeStateId, childTag, childPayload, childKind] using
    ArgumentsEvaluateTo.cons productionResult
      (ArgumentsEvaluateTo.cons dotResult
        (ArgumentsEvaluateTo.cons originResult
          (ArgumentsEvaluateTo.cons stateIdResult
            (ArgumentsEvaluateTo.cons childTagResult
              (ArgumentsEvaluateTo.cons tokenIndexResult
                (ArgumentsEvaluateTo.singleton kindResult))))))

structure RecognizerTerminalAppendResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (before : State)
    (position semanticKind nextPosition production dot origin stateId : Nat)
    (beforeInvariant : RecognizerTerminalAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell before position semanticKind
      nextPosition production dot origin stateId) where
  argumentsState : State
  argumentsEvaluation : ArgumentsEvaluateTo verifiedParserCore before
    parserRecognizeTerminalAppendArguments [
      workspaceValue workspaceValues workspaceCell,
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
      .signed .i32 (Int.ofNat workspaceLayout.capacity),
      .signed .i32 (Int.ofNat nextPosition),
      stateSeedValue
        (recognizerTerminalSeed production dot origin stateId position
          semanticKind),
      .signed .i32 (Int.ofNat workspace.states.length)] argumentsState
  argumentsInvariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell argumentsState
  after : State
  evaluation : Evaluates verifiedParserCore before
    parserRecognizeTerminalAppendCall
    (appendOutcomeValue
      (appendLogical workspaceLayout.capacity nextPosition
        (recognizerTerminalSeed production dot origin stateId position
          semanticKind) workspace).1) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  stateCountOwned : (Assertion.localPointsTo 18
    stateCountCell
    (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout
    (appendLogical workspaceLayout.capacity nextPosition
      (recognizerTerminalSeed production dot origin stateId position
        semanticKind) workspace).2
    (appendResultValues workspaceLayout workspace nextPosition
      (recognizerTerminalSeed production dot origin stateId position
        semanticKind) workspaceValues)
    grammarCell tokensCell workspaceCell after

/-- Execute the exact successful terminal append found in the extracted
    recognizer. The nested seed constructor has an empty footprint; composing
    it with `append_state` leaves precisely the workspace singleton as the
    whole transition's write footprint. -/
noncomputable def RecognizerTerminalAppendInvariant.evaluate_append
    (invariant : RecognizerTerminalAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId) :
    RecognizerTerminalAppendResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId invariant := by
  let seed := recognizerTerminalSeed production dot origin stateId position
    semanticKind
  let afterSeed := restoreLocals runtime
    (parserStateSeedCallee runtime seed)
  have seedContract := extractedParserStateSeedCall_contract runtime runtime
    parserRecognizeTerminalSeedArguments seed
    invariant.terminal.recognizer.wellFormed invariant.seed_arguments
  have seedEvaluation : Evaluates verifiedParserCore runtime
      parserRecognizeTerminalSeedCall (stateSeedValue seed) afterSeed := by
    simpa [parserRecognizeTerminalSeedCall, afterSeed] using seedContract.1
  have seedEffect : ModifiesOnly CellSet.empty runtime afterSeed := by
    simpa [afterSeed] using seedContract.2.1
  have nextPositionResult : Evaluates verifiedParserCore runtime (.local 30)
      (.signed .i32 (Int.ofNat nextPosition)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 30 _
      invariant.nextPositionLocal⟩
  have frame : RecognizerAppendFrame grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime nextPosition := {
    recognizer := invariant.terminal.recognizer
    positionBound := invariant.nextPositionBound
    stateBaseLocal := invariant.stateBaseLocal
    stateCapacityLocal := invariant.stateCapacityLocal
    stateCountLocal := invariant.stateCountLocal
    stateCountOwned := invariant.stateCountOwned
    stateCountBackingDistinct := invariant.stateCountBackingDistinct
    stateCountParameterSeparate := invariant.stateCountParameterSeparate
  }
  let appended := frame.evaluate_seeded_append (.local 30)
    parserRecognizeTerminalSeedCall seed afterSeed invariant.seedDerivation
    invariant.originBound
    nextPositionResult
    seedEvaluation seedEffect (by simpa [afterSeed] using seedContract.2.2)
  exact {
    argumentsState := appended.argumentsState
    argumentsEvaluation := by
      simpa [parserRecognizeTerminalAppendArguments, recognizerAppendArguments,
        seed] using appended.argumentsEvaluation
    argumentsInvariant := appended.argumentsInvariant
    after := appended.after
    evaluation := by
      simpa [parserRecognizeTerminalAppendCall,
        parserRecognizeTerminalAppendArguments, recognizerAppendCall,
        recognizerAppendArguments, seed] using appended.evaluation
    effect := appended.effect
    stateCountOwned := appended.stateCountOwned
    invariant := by
      simpa [seed] using appended.invariant
  }

structure RecognizerTerminalFullResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (before : State)
    (position semanticKind nextPosition production dot origin stateId : Nat)
    (beforeInvariant : RecognizerTerminalAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell before position semanticKind
      nextPosition production dot origin stateId) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeTerminalSuccessStatement
    (.returned (some (parseResultValue 2
      (Int.ofNat
        (appendLogical workspaceLayout.capacity nextPosition
          (recognizerTerminalSeed production dot origin stateId position
            semanticKind) workspace).1.stateCount)
      (-1) (Int.ofNat position)))) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell after

/-- Execute the exact capacity-exhaustion arm after a terminal match. The
    append result is converted by the extracted `append_or_full` helper, the
    state-count assignment is skipped by return propagation, and both helper
    calls plus the temporary result local are framed as store-pure. -/
noncomputable def RecognizerTerminalAppendInvariant.execute_full
    (invariant : RecognizerTerminalAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId)
    (statusFull : (appendLogical workspaceLayout.capacity nextPosition
      (recognizerTerminalSeed production dot origin stateId position
        semanticKind) workspace).1.status = .full) :
    RecognizerTerminalFullResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId invariant := by
  let seed := recognizerTerminalSeed production dot origin stateId position
    semanticKind
  let logical := appendLogical workspaceLayout.capacity nextPosition seed
    workspace
  let outcome := logical.1
  let appended := invariant.evaluate_append
  let bound := appended.after.bindLocal 31 (appendOutcomeValue outcome)
  have boundWellFormed : StateWellFormed bound :=
    bindLocal_preserves_well_formed appended.after 31
      (appendOutcomeValue outcome) appended.invariant.wellFormed
  have resultLocal : bound.local? 31 = some (appendOutcomeValue outcome) :=
    bindLocal_finds_local appended.after 31 (appendOutcomeValue outcome)
      appended.invariant.wellFormed
  have positionAfterAppend : appended.after.local? 23 =
      some (.signed .i32 (Int.ofNat position)) :=
    appended.effect.singleton_preserves_local_of_ne
      invariant.terminal.recognizer.wellFormed
      invariant.terminal.positionLocal
      invariant.terminal.recognizer.workspaceBacking (by
        simp [workspaceValue])
  have positionBound : bound.local? 23 =
      some (.signed .i32 (Int.ofNat position)) := by
    exact (bindLocal_preserves_other_local appended.invariant.wellFormed
      (by decide)).trans positionAfterAppend
  have outcomeStatus : outcome.status = .full := by
    simpa [outcome, logical, seed] using statusFull
  have positionArgument : Evaluates verifiedParserCore bound (.local 23)
      (.signed .i32 (Int.ofNat position)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 23 _ positionBound⟩
  let controlled := executeAppendOutcomeFull bound 31 18 (.local 23)
    outcome (Int.ofNat position) boundWellFormed resultLocal positionArgument
    outcomeStatus
  let after := restoreLocals appended.after controlled.after
  have execution : Executes verifiedParserCore runtime
      parserRecognizeTerminalSuccessStatement
      (.returned (some (parseResultValue 2
        (Int.ofNat outcome.stateCount) (-1) (Int.ofNat position))))
      after := by
    rw [extractedParserRecognize_terminal_append_control_shape]
    simpa [bound, after] using
      (executesLetLocal (type := .structure 2) appended.evaluation
        controlled.execution)
  have entered : StoreEffect CellSet.empty appended.after bound := by
    simpa [bound] using
      bindLocal_effect appended.after 31 (appendOutcomeValue outcome)
  have scopedStore : StoreEffect CellSet.empty appended.after
      controlled.after := entered.trans_same controlled.effect.toStoreEffect
  have closed : ModifiesOnly CellSet.empty appended.after after := by
    simpa [after] using scopedStore.restoreLocals
  have effect : ModifiesOnly (CellSet.singleton workspaceCell) runtime after :=
    appended.effect.trans_same (closed.weaken CellSet.empty_subset)
  have afterWellFormed : StateWellFormed after :=
    scopedStore.restoreLocals_wellFormed appended.invariant.wellFormed
      controlled.wellFormed
  have workspaceEq : logical.2 = workspace := by
    simpa [logical, seed] using appendLogical_workspace_eq_of_full statusFull
  have valuesEq : appendResultValues workspaceLayout workspace nextPosition seed
      workspaceValues = workspaceValues := by
    exact appendResultValues_eq_of_full (by
      simpa [seed] using statusFull)
  have afterInvariant :=
    appended.invariant.after_empty_effect closed afterWellFormed
  rw [workspaceEq, valuesEq] at afterInvariant
  exact {
    after := after
    execution := by simpa [seed, logical, outcome] using execution
    effect := effect
    wellFormed := afterWellFormed
    invariant := afterInvariant
  }

structure RecognizerTerminalSuccessResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (before : State)
    (position semanticKind nextPosition production dot origin stateId : Nat)
    (beforeInvariant : RecognizerTerminalAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell before position semanticKind
      nextPosition production dot origin stateId) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeTerminalSuccessStatement .next after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell)) before after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout
    (appendLogical workspaceLayout.capacity nextPosition
      (recognizerTerminalSeed production dot origin stateId position
        semanticKind) workspace).2
    (appendResultValues workspaceLayout workspace nextPosition
      (recognizerTerminalSeed production dot origin stateId position
        semanticKind) workspaceValues)
    grammarCell tokensCell workspaceCell after
  stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
    (some (.signed .i32 (Int.ofNat
      (appendLogical workspaceLayout.capacity nextPosition
        (recognizerTerminalSeed production dot origin stateId position
          semanticKind) workspace).2.states.length)))).holds after

/-- Execute the non-full result arm around the proved append transition,
    including the extracted status test, assignment of `state_count`, and
    closure of the temporary append-result local. -/
noncomputable def RecognizerTerminalAppendInvariant.execute_success
    (invariant : RecognizerTerminalAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId)
    (statusOk : (appendLogical workspaceLayout.capacity nextPosition
      (recognizerTerminalSeed production dot origin stateId position
        semanticKind) workspace).1.status = .ok) :
    RecognizerTerminalSuccessResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId invariant := by
  let seed := recognizerTerminalSeed production dot origin stateId position
    semanticKind
  let logical := appendLogical workspaceLayout.capacity nextPosition seed
    workspace
  let outcome := logical.1
  let appended := invariant.evaluate_append
  let bound := appended.after.bindLocal 31 (appendOutcomeValue outcome)
  have boundWellFormed : StateWellFormed bound :=
    bindLocal_preserves_well_formed appended.after 31
      (appendOutcomeValue outcome) appended.invariant.wellFormed
  have resultLocal : bound.local? 31 = some (appendOutcomeValue outcome) :=
    bindLocal_finds_local appended.after 31 (appendOutcomeValue outcome)
      appended.invariant.wellFormed
  have countOwnedBound : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds bound :=
    bindLocal_preserves_localPointsTo_of_ne appended.after 31 18
      (appendOutcomeValue outcome) stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))
      appended.invariant.wellFormed (by decide) appended.stateCountOwned
  have outcomeStatus : outcome.status = .ok := by
    simpa [outcome, logical, seed] using statusOk
  let controlled := executeAppendOutcomeOk bound 31 18 stateCountCell
    (.local 23) outcome workspace.states.length boundWellFormed resultLocal
    countOwnedBound outcomeStatus
  let after := restoreLocals appended.after controlled.after
  have execution : Executes verifiedParserCore runtime
      parserRecognizeTerminalSuccessStatement .next after := by
    rw [extractedParserRecognize_terminal_append_control_shape]
    simpa [bound, after] using
      (executesLetLocal (type := .structure 2) appended.evaluation
        controlled.execution)
  have entered : StoreEffect CellSet.empty appended.after bound := by
    simpa [bound] using
      bindLocal_effect appended.after 31 (appendOutcomeValue outcome)
  have scopedStore : StoreEffect (CellSet.singleton stateCountCell)
      appended.after controlled.after :=
    (entered.weaken CellSet.empty_subset).trans_same
      controlled.effect.toStoreEffect
  have closed : ModifiesOnly (CellSet.singleton stateCountCell)
      appended.after after := by
    simpa [after] using scopedStore.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    scopedStore.restoreLocals_wellFormed appended.invariant.wellFormed
      controlled.wellFormed
  have parameterFrameAfterAppend : RecognizerParameterFrameSeparated
      appended.after stateCountCell := by
    unfold RecognizerParameterFrameSeparated
    rw [appended.effect.localBindingFrameFootprint_eq
      verifiedParserRecognizerParameterFrame]
    exact invariant.stateCountParameterSeparate
  have afterInvariant := appended.invariant.after_disjoint_scalar_effect
    stateCountCell closed afterWellFormed
    invariant.stateCountBackingDistinct.1.symm
    invariant.stateCountBackingDistinct.2.1.symm
    invariant.stateCountBackingDistinct.2.2.symm
    parameterFrameAfterAppend
  have afterCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat logical.2.states.length)))).holds
      after := by
    constructor
    · change appended.after.cellId? 18 = some stateCountCell
      exact appended.stateCountOwned.1
    · change controlled.after.cellEntry? stateCountCell = some {
        id := stateCountCell
        value := some (.signed .i32 (Int.ofNat logical.2.states.length))
      }
      simpa [logical, outcome] using controlled.stateCountOwned.2
  exact {
    after := after
    execution := execution
    effect := appended.effect.trans closed
    invariant := by simpa [seed, logical] using afterInvariant
    stateCountOwned := by simpa [seed, logical] using afterCountOwned
  }

structure RecognizerTerminalMatchedResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (before : State)
    (position semanticKind nextPosition production dot origin stateId : Nat)
    (beforeInvariant : RecognizerTerminalReadyInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell before position semanticKind
      production dot origin stateId) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeTerminalStatement .next after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell)) before after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout
    (appendLogical workspaceLayout.capacity nextPosition
      (recognizerTerminalSeed production dot origin stateId position
        semanticKind) workspace).2
    (appendResultValues workspaceLayout workspace nextPosition
      (recognizerTerminalSeed production dot origin stateId position
        semanticKind) workspaceValues)
    grammarCell tokensCell workspaceCell after
  stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
    (some (.signed .i32 (Int.ofNat
      (appendLogical workspaceLayout.capacity nextPosition
        (recognizerTerminalSeed production dot origin stateId position
          semanticKind) workspace).2.states.length)))).holds after

/-- Complete successful terminal transition, from the scanner call through
    both nested temporary scopes. This is the first whole extracted Earley
    transition whose result is a new logical workspace and matching encoded
    GPU/CPU-independent backing state. -/
noncomputable def RecognizerTerminalReadyInvariant.execute_match
    (invariant : RecognizerTerminalReadyInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind production dot
      origin stateId)
    (nextPosition : Nat)
    (scanResult : scanTerminal grammar tokens position semanticKind =
      some nextPosition)
    (nextPositionBound : nextPosition ≤
      finalPosition workspaceLayout.tokenCount)
    (statusOk : (appendLogical workspaceLayout.capacity nextPosition
      (recognizerTerminalSeed production dot origin stateId position
        semanticKind) workspace).1.status = .ok) :
    RecognizerTerminalMatchedResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId invariant := by
  let matched := invariant.bind_scan_match nextPosition scanResult
    nextPositionBound
  let success := matched.invariant.execute_success statusOk
  have nextLocal : matched.bound.local? 30 =
      some (.signed .i32 (Int.ofNat nextPosition)) :=
    matched.invariant.nextPositionLocal
  have left : Evaluates verifiedParserCore matched.bound (.local 30)
      (.signed .i32 (Int.ofNat nextPosition)) matched.bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore matched.bound 30 _ nextLocal⟩
  have right : Evaluates verifiedParserCore matched.bound
      (.value (.signed .i32 0)) (.signed .i32 0) matched.bound := ⟨1, rfl⟩
  have nonnegative : Evaluates verifiedParserCore matched.bound
      (.binary .greaterEqual (.local 30) (.value (.signed .i32 0)))
      (.boolean true) matched.bound := by
    apply evaluatesEagerBinary (by decide) (by decide) left right
    simp [evalBinaryValue, evalSignedBinary]
  have selected : Executes verifiedParserCore matched.bound
      (.ifThenElse
        (.binary .greaterEqual (.local 30) (.value (.signed .i32 0)))
        parserRecognizeTerminalSuccessStatement .skip) .next success.after :=
    executesIfTrue nonnegative success.execution
  have body : Executes verifiedParserCore matched.bound
      (.sequence
        (.ifThenElse
          (.binary .greaterEqual (.local 30) (.value (.signed .i32 0)))
          parserRecognizeTerminalSuccessStatement .skip)
        .skip) .next success.after :=
    executesSequence selected (executesSkip verifiedParserCore success.after)
  let after := restoreLocals matched.afterScan success.after
  have execution : Executes verifiedParserCore runtime
      parserRecognizeTerminalStatement .next after := by
    rw [extractedParserRecognize_terminal_statement_shape]
    simpa [after] using
      (executesLetLocal (type := parserI32Type) matched.scanEvaluation body)
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton stateCountCell)
  have scopedStore : StoreEffect writes matched.afterScan success.after :=
    (matched.entered.weaken CellSet.empty_subset).trans_same
      success.effect.toStoreEffect
  have closed : ModifiesOnly writes matched.afterScan after := by
    simpa [after] using scopedStore.restoreLocals
  have effect : ModifiesOnly writes runtime after :=
    (matched.scanEffect.weaken CellSet.empty_subset).trans_same closed
  have afterWellFormed : StateWellFormed after :=
    scopedStore.restoreLocals_wellFormed matched.afterScanInvariant.wellFormed
      success.invariant.wellFormed
  have afterParameterLocal (id : VarId)
      (idBound : id ∈ verifiedParserRecognizerParameterIds) :
      after.local? id = success.after.local? id := by
    have successCellId : success.after.cellId? id =
        matched.bound.cellId? id := by
      unfold State.cellId?
      rw [success.effect.locals]
    have afterCellId : after.cellId? id = matched.afterScan.cellId? id := by
      unfold State.cellId?
      rfl
    have cellIdEqual : after.cellId? id = success.after.cellId? id := by
      rw [afterCellId, successCellId]
      exact (matched.parameterCellId id idBound).symm
    unfold State.local?
    rw [cellIdEqual]
    cases found : success.after.cellId? id with
    | none => rfl
    | some cell =>
        simp only [Option.bind_some]
        rfl
  have afterInvariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout
      (appendLogical workspaceLayout.capacity nextPosition
        (recognizerTerminalSeed production dot origin stateId position
          semanticKind) workspace).2
      (appendResultValues workspaceLayout workspace nextPosition
        (recognizerTerminalSeed production dot origin stateId position
          semanticKind) workspaceValues)
      grammarCell tokensCell workspaceCell after := {
    grammarEncoded := success.invariant.grammarEncoded
    grammarWellFormed := success.invariant.grammarWellFormed
    wordsI32 := success.invariant.wordsI32
    tokensI32 := success.invariant.tokensI32
    workspaceLength := success.invariant.workspaceLength
    workspaceTokenCount := success.invariant.workspaceTokenCount
    workspaceEncoded := success.invariant.workspaceEncoded
    derivations := success.invariant.derivations
    wellFormed := afterWellFormed
    grammarLocal := by
      rw [afterParameterLocal 0 (by simp)]
      exact success.invariant.grammarLocal
    grammarLengthLocal := by
      rw [afterParameterLocal 1 (by simp)]
      exact success.invariant.grammarLengthLocal
    tokensLocal := by
      rw [afterParameterLocal 2 (by simp)]
      exact success.invariant.tokensLocal
    tokenCountLocal := by
      rw [afterParameterLocal 3 (by simp)]
      exact success.invariant.tokenCountLocal
    workspaceLocal := by
      rw [afterParameterLocal 4 (by simp)]
      exact success.invariant.workspaceLocal
    workspaceLengthLocal := by
      rw [afterParameterLocal 5 (by simp)]
      exact success.invariant.workspaceLengthLocal
    grammarBacking := success.invariant.grammarBacking
    tokensBacking := success.invariant.tokensBacking
    workspaceBacking := success.invariant.workspaceBacking
    grammarWorkspaceDistinct := success.invariant.grammarWorkspaceDistinct
    tokensWorkspaceDistinct := success.invariant.tokensWorkspaceDistinct
  }
  have afterCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat
        (appendLogical workspaceLayout.capacity nextPosition
          (recognizerTerminalSeed production dot origin stateId position
            semanticKind) workspace).2.states.length)))).holds after := by
    constructor
    · change matched.afterScan.cellId? 18 = some stateCountCell
      unfold State.cellId?
      rw [matched.scanEffect.locals]
      exact invariant.stateCountOwned.1
    · change success.after.cellEntry? stateCountCell = _
      exact success.stateCountOwned.2
  exact {
    after := after
    execution := execution
    effect := by simpa [writes] using effect
    invariant := afterInvariant
    stateCountOwned := afterCountOwned
  }

structure RecognizerTerminalMatchedFullResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (before : State)
    (position semanticKind nextPosition production dot origin stateId : Nat)
    (beforeInvariant : RecognizerTerminalReadyInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell before position semanticKind
      production dot origin stateId) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeTerminalStatement
    (.returned (some (parseResultValue 2
      (Int.ofNat
        (appendLogical workspaceLayout.capacity nextPosition
          (recognizerTerminalSeed production dot origin stateId position
            semanticKind) workspace).1.stateCount)
      (-1) (Int.ofNat position)))) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell after

/-- Complete the terminal scanner's capacity-exhaustion path, including both
    extracted temporary scopes. This is the whole terminal statement's exact
    early-return behavior, rather than merely the inner append helper. -/
noncomputable def RecognizerTerminalReadyInvariant.execute_match_full
    (invariant : RecognizerTerminalReadyInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind production dot
      origin stateId)
    (nextPosition : Nat)
    (scanResult : scanTerminal grammar tokens position semanticKind =
      some nextPosition)
    (nextPositionBound : nextPosition ≤
      finalPosition workspaceLayout.tokenCount)
    (statusFull : (appendLogical workspaceLayout.capacity nextPosition
      (recognizerTerminalSeed production dot origin stateId position
        semanticKind) workspace).1.status = .full) :
    RecognizerTerminalMatchedFullResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position semanticKind nextPosition
      production dot origin stateId invariant := by
  let matched := invariant.bind_scan_match nextPosition scanResult
    nextPositionBound
  let full := matched.invariant.execute_full statusFull
  have nextLocal : matched.bound.local? 30 =
      some (.signed .i32 (Int.ofNat nextPosition)) :=
    matched.invariant.nextPositionLocal
  have left : Evaluates verifiedParserCore matched.bound (.local 30)
      (.signed .i32 (Int.ofNat nextPosition)) matched.bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore matched.bound 30 _ nextLocal⟩
  have right : Evaluates verifiedParserCore matched.bound
      (.value (.signed .i32 0)) (.signed .i32 0) matched.bound := ⟨1, rfl⟩
  have nonnegative : Evaluates verifiedParserCore matched.bound
      (.binary .greaterEqual (.local 30) (.value (.signed .i32 0)))
      (.boolean true) matched.bound := by
    apply evaluatesEagerBinary (by decide) (by decide) left right
    simp [evalBinaryValue, evalSignedBinary]
  have selected : Executes verifiedParserCore matched.bound
      (.ifThenElse
        (.binary .greaterEqual (.local 30) (.value (.signed .i32 0)))
        parserRecognizeTerminalSuccessStatement .skip)
      (.returned (some (parseResultValue 2
        (Int.ofNat
          (appendLogical workspaceLayout.capacity nextPosition
            (recognizerTerminalSeed production dot origin stateId position
              semanticKind) workspace).1.stateCount)
        (-1) (Int.ofNat position)))) full.after :=
    executesIfTrue nonnegative full.execution
  have body : Executes verifiedParserCore matched.bound
      (.sequence
        (.ifThenElse
          (.binary .greaterEqual (.local 30) (.value (.signed .i32 0)))
          parserRecognizeTerminalSuccessStatement .skip)
        .skip)
      (.returned (some (parseResultValue 2
        (Int.ofNat
          (appendLogical workspaceLayout.capacity nextPosition
            (recognizerTerminalSeed production dot origin stateId position
              semanticKind) workspace).1.stateCount)
        (-1) (Int.ofNat position)))) full.after :=
    executesSequenceReturned selected
  let after := restoreLocals matched.afterScan full.after
  have execution : Executes verifiedParserCore runtime
      parserRecognizeTerminalStatement
      (.returned (some (parseResultValue 2
        (Int.ofNat
          (appendLogical workspaceLayout.capacity nextPosition
            (recognizerTerminalSeed production dot origin stateId position
              semanticKind) workspace).1.stateCount)
        (-1) (Int.ofNat position)))) after := by
    rw [extractedParserRecognize_terminal_statement_shape]
    simpa [after] using
      (executesLetLocal (type := parserI32Type) matched.scanEvaluation body)
  have scopedStore : StoreEffect (CellSet.singleton workspaceCell)
      matched.afterScan full.after :=
    (matched.entered.weaken CellSet.empty_subset).trans_same
      full.effect.toStoreEffect
  have closed : ModifiesOnly (CellSet.singleton workspaceCell)
      matched.afterScan after := by
    simpa [after] using scopedStore.restoreLocals
  have effect : ModifiesOnly (CellSet.singleton workspaceCell) runtime after :=
    (matched.scanEffect.weaken CellSet.empty_subset).trans_same closed
  have afterWellFormed : StateWellFormed after :=
    scopedStore.restoreLocals_wellFormed
      matched.afterScanInvariant.wellFormed full.wellFormed
  have afterInvariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell after := by
    apply invariant.terminal.recognizer.after_same_workspace_effect effect
      afterWellFormed full.invariant
    simp [after, restoreLocals]
  exact {
    after := after
    execution := execution
    effect := effect
    wellFormed := afterWellFormed
    invariant := afterInvariant
  }

def recognizerNullableSeed
    (production dot origin stateId candidate : Nat) : StateSeed := {
  production := production
  dot := dot + 1
  origin := origin
  previous := some stateId
  child := .state candidate
}

/-- Local facts at the nullable-replay append. The candidate is an already
    completed zero-width state; the surrounding loop is responsible for the
    semantic predicate that selected it. -/
structure RecognizerNullableAppendInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (runtime : State)
    (position production dot origin stateId candidate : Nat) : Prop where
  frame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime position
  productionBound : production < grammar.productionCount
  advanceSound : ∀ child symbol finish,
    (grammar.productionAt ⟨production, productionBound⟩).rhs[dot]? =
      some symbol →
    RecognizesSymbol grammar tokens symbol position finish →
    EarleyStateSound grammar tokens
      ((recognizerNullableSeed production dot origin stateId child).atPosition
        finish)
  dotSuccI32 : dot + 1 ≤ 2147483647
  originBound : origin ≤ finalPosition workspaceLayout.tokenCount
  positionLocal : runtime.local? 23 =
    some (.signed .i32 (Int.ofNat position))
  stateIdLocal : runtime.local? 24 =
    some (.signed .i32 (Int.ofNat stateId))
  productionLocal : runtime.local? 25 =
    some (.signed .i32 (Int.ofNat production))
  dotLocal : runtime.local? 26 =
    some (.signed .i32 (Int.ofNat dot))
  originLocal : runtime.local? 27 =
    some (.signed .i32 (Int.ofNat origin))
  candidateLocal : runtime.local? 36 =
    some (.signed .i32 (Int.ofNat candidate))

theorem RecognizerNullableAppendInvariant.seed_arguments
    (invariant : RecognizerNullableAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position production dot origin
      stateId candidate) :
    ArgumentsEvaluateTo verifiedParserCore runtime
      parserRecognizeNullableSeedArguments
      (parserStateSeedArgumentsValues
        (recognizerNullableSeed production dot origin stateId candidate))
      runtime := by
  have productionResult : Evaluates verifiedParserCore runtime (.local 25)
      (.signed .i32 (Int.ofNat production)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 25 _
      invariant.productionLocal⟩
  have dotResult := evaluatesNatSuccAtLocal runtime 26 dot
    invariant.dotLocal invariant.dotSuccI32
  have originResult : Evaluates verifiedParserCore runtime (.local 27)
      (.signed .i32 (Int.ofNat origin)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 27 _
      invariant.originLocal⟩
  have stateIdResult : Evaluates verifiedParserCore runtime (.local 24)
      (.signed .i32 (Int.ofNat stateId)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 24 _
      invariant.stateIdLocal⟩
  have childTagResult : Evaluates verifiedParserCore runtime (.constant 39)
      (.signed .i32 2) runtime :=
    evaluatesConstant verifiedParser_child_state_constant
  have candidateResult : Evaluates verifiedParserCore runtime (.local 36)
      (.signed .i32 (Int.ofNat candidate)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 36 _
      invariant.candidateLocal⟩
  have missingKind := evaluatesParserAppendNegativeOne runtime
  simpa [parserRecognizeNullableSeedArguments,
      parserStateSeedArgumentsValues, recognizerNullableSeed,
      previousValue, encodeStateId, childTag, childPayload, childKind] using
    ArgumentsEvaluateTo.cons productionResult
      (ArgumentsEvaluateTo.cons dotResult
        (ArgumentsEvaluateTo.cons originResult
          (ArgumentsEvaluateTo.cons stateIdResult
            (ArgumentsEvaluateTo.cons childTagResult
              (ArgumentsEvaluateTo.cons candidateResult
                (ArgumentsEvaluateTo.singleton missingKind))))))

noncomputable def RecognizerNullableAppendInvariant.evaluate_append
    (invariant : RecognizerNullableAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position production dot origin
      stateId candidate)
    (seedDerivation : EarleySeedDerivation grammar tokens workspace position
      (recognizerNullableSeed production dot origin stateId candidate)) :
    RecognizerSeededAppendResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position (.local 23)
      parserRecognizeNullableSeedCall
      (recognizerNullableSeed production dot origin stateId candidate)
      invariant.frame := by
  let seed := recognizerNullableSeed production dot origin stateId candidate
  let afterSeed := restoreLocals runtime
    (parserStateSeedCallee runtime seed)
  have seedContract := extractedParserStateSeedCall_contract runtime runtime
    parserRecognizeNullableSeedArguments seed
    invariant.frame.recognizer.wellFormed invariant.seed_arguments
  have seedEvaluation : Evaluates verifiedParserCore runtime
      parserRecognizeNullableSeedCall (stateSeedValue seed) afterSeed := by
    simpa [parserRecognizeNullableSeedCall, afterSeed] using seedContract.1
  have seedEffect : ModifiesOnly CellSet.empty runtime afterSeed := by
    simpa [afterSeed] using seedContract.2.1
  have positionResult : Evaluates verifiedParserCore runtime (.local 23)
      (.signed .i32 (Int.ofNat position)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 23 _
      invariant.positionLocal⟩
  exact invariant.frame.evaluate_seeded_append (.local 23)
    parserRecognizeNullableSeedCall seed afterSeed seedDerivation
    invariant.originBound
    positionResult
    seedEvaluation seedEffect (by simpa [afterSeed] using seedContract.2.2)

structure RecognizerNullableOkResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (before : State)
    (position production dot origin stateId candidate : Nat)
    (beforeInvariant : RecognizerNullableAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell before position production dot
      origin stateId candidate) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeNullableAppendStatement .next after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell)) before after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout
    (appendLogical workspaceLayout.capacity position
      (recognizerNullableSeed production dot origin stateId candidate)
      workspace).2
    (appendResultValues workspaceLayout workspace position
      (recognizerNullableSeed production dot origin stateId candidate)
      workspaceValues)
    grammarCell tokensCell workspaceCell after
  stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
    (some (.signed .i32 (Int.ofNat
      (appendLogical workspaceLayout.capacity position
        (recognizerNullableSeed production dot origin stateId candidate)
        workspace).2.states.length)))).holds after

noncomputable def RecognizerNullableAppendInvariant.execute_ok
    (invariant : RecognizerNullableAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position production dot origin
      stateId candidate)
    (seedDerivation : EarleySeedDerivation grammar tokens workspace position
      (recognizerNullableSeed production dot origin stateId candidate))
    (statusOk : (appendLogical workspaceLayout.capacity position
      (recognizerNullableSeed production dot origin stateId candidate)
      workspace).1.status = .ok) :
    RecognizerNullableOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position production dot origin
      stateId candidate invariant := by
  let appended := invariant.evaluate_append seedDerivation
  let result := appended.execute_ok 40 (.local 23) (by decide) statusOk
  let after := Classical.choose result
  have facts := Classical.choose_spec result
  exact {
    after := after
    execution := by
      rw [extractedParserRecognize_nullable_append_shape]
      simpa [parserRecognizeNullableAppendCall,
        parserRecognizeNullableAppendArguments, recognizerAppendCall,
        recognizerAppendArguments, after] using facts.1
    effect := facts.2.1
    invariant := facts.2.2.1
    stateCountOwned := facts.2.2.2
  }
structure RecognizerNullableFullResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (before : State)
    (position production dot origin stateId candidate : Nat)
    (beforeInvariant : RecognizerNullableAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell before position production dot
      origin stateId candidate) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeNullableAppendStatement
    (.returned (some (parseResultValue 2
      (Int.ofNat
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed production dot origin stateId candidate)
          workspace).1.stateCount)
      (-1) (Int.ofNat position)))) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell after

noncomputable def RecognizerNullableAppendInvariant.execute_full
    (invariant : RecognizerNullableAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position production dot origin
      stateId candidate)
    (seedDerivation : EarleySeedDerivation grammar tokens workspace position
      (recognizerNullableSeed production dot origin stateId candidate))
    (statusFull : (appendLogical workspaceLayout.capacity position
      (recognizerNullableSeed production dot origin stateId candidate)
      workspace).1.status = .full) :
    RecognizerNullableFullResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position production dot origin
      stateId candidate invariant := by
  let appended := invariant.evaluate_append seedDerivation
  have positionAfterAppend : appended.after.local? 23 =
      some (.signed .i32 (Int.ofNat position)) :=
    appended.effect.singleton_preserves_local_of_ne
      invariant.frame.recognizer.wellFormed invariant.positionLocal
      invariant.frame.recognizer.workspaceBacking (by simp [workspaceValue])
  let result := appended.execute_full_at_local 40 23 (by decide)
    positionAfterAppend statusFull
  let after := Classical.choose result
  have facts := Classical.choose_spec result
  exact {
    after := after
    execution := by
      rw [extractedParserRecognize_nullable_append_shape]
      simpa [parserRecognizeNullableAppendCall,
        parserRecognizeNullableAppendArguments, recognizerAppendCall,
        recognizerAppendArguments, after] using facts.1
    effect := facts.2.1
    wellFormed := facts.2.2.1
    invariant := facts.2.2.2
  }
def recognizerPredictionSeed
    (production position : Nat) : StateSeed := {
  production := production
  dot := 0
  origin := position
  previous := none
  child := .none
}

structure RecognizerPredictionAppendInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (runtime : State) (position production index : Nat) : Prop where
  frame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime position
  seedDerivation : EarleySeedDerivation grammar tokens workspace position
    (recognizerPredictionSeed production position)
  positionLocal : runtime.local? 23 =
    some (.signed .i32 (Int.ofNat position))
  productionLocal : runtime.local? 34 =
    some (.signed .i32 (Int.ofNat production))
  indexOwned : (Assertion.localPointsTo 33 indexCell
    (some (.signed .i32 (Int.ofNat index)))).holds runtime
  indexSuccI32 : index + 1 ≤ 2147483647
  indexBackingDistinct :
    indexCell ≠ grammarCell ∧
    indexCell ≠ tokensCell ∧
    indexCell ≠ workspaceCell ∧
    indexCell ≠ stateCountCell
  indexParameterSeparate :
    RecognizerParameterFrameSeparated runtime indexCell

theorem RecognizerPredictionAppendInvariant.indexParameterDistinct
    (invariant : RecognizerPredictionAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell runtime position
      production index)
    (id : VarId) (member : id ∈ verifiedParserRecognizerParameterIds) :
    runtime.cellId? id ≠ some indexCell :=
  invariant.indexParameterSeparate.localCell_ne_of_singleton member

theorem RecognizerPredictionAppendInvariant.seed_arguments
    (invariant : RecognizerPredictionAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell runtime position
      production index) :
    ArgumentsEvaluateTo verifiedParserCore runtime
      parserRecognizePredictionSeedArguments
      (parserStateSeedArgumentsValues
        (recognizerPredictionSeed production position)) runtime := by
  have productionResult : Evaluates verifiedParserCore runtime (.local 34)
      (.signed .i32 (Int.ofNat production)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 34 _
      invariant.productionLocal⟩
  have zero : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 0)) (.signed .i32 0) runtime := ⟨1, rfl⟩
  have positionResult : Evaluates verifiedParserCore runtime (.local 23)
      (.signed .i32 (Int.ofNat position)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 23 _
      invariant.positionLocal⟩
  have negativeOne := evaluatesParserAppendNegativeOne runtime
  have childNone : Evaluates verifiedParserCore runtime (.constant 37)
      (.signed .i32 0) runtime :=
    evaluatesConstant verifiedParser_child_none_constant
  simpa [parserRecognizePredictionSeedArguments,
      parserStateSeedArgumentsValues, recognizerPredictionSeed,
      previousValue, encodeStateId, childTag, childPayload, childKind] using
    ArgumentsEvaluateTo.cons productionResult
      (ArgumentsEvaluateTo.cons zero
        (ArgumentsEvaluateTo.cons positionResult
          (ArgumentsEvaluateTo.cons negativeOne
            (ArgumentsEvaluateTo.cons childNone
              (ArgumentsEvaluateTo.cons negativeOne
                (ArgumentsEvaluateTo.singleton negativeOne))))))

noncomputable def RecognizerPredictionAppendInvariant.evaluate_append
    (invariant : RecognizerPredictionAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell runtime position
      production index) :
    RecognizerSeededAppendResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position (.local 23)
      parserRecognizePredictionSeedCall
      (recognizerPredictionSeed production position) invariant.frame := by
  let seed := recognizerPredictionSeed production position
  let afterSeed := restoreLocals runtime
    (parserStateSeedCallee runtime seed)
  have seedContract := extractedParserStateSeedCall_contract runtime runtime
    parserRecognizePredictionSeedArguments seed
    invariant.frame.recognizer.wellFormed invariant.seed_arguments
  have seedEvaluation : Evaluates verifiedParserCore runtime
      parserRecognizePredictionSeedCall (stateSeedValue seed) afterSeed := by
    simpa [parserRecognizePredictionSeedCall, afterSeed] using seedContract.1
  have seedEffect : ModifiesOnly CellSet.empty runtime afterSeed := by
    simpa [afterSeed] using seedContract.2.1
  have positionResult : Evaluates verifiedParserCore runtime (.local 23)
      (.signed .i32 (Int.ofNat position)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 23 _
      invariant.positionLocal⟩
  exact invariant.frame.evaluate_seeded_append (.local 23)
    parserRecognizePredictionSeedCall seed afterSeed
    invariant.seedDerivation
    (by simpa [seed, recognizerPredictionSeed] using invariant.frame.positionBound)
    positionResult
    seedEvaluation seedEffect (by simpa [afterSeed] using seedContract.2.2)

structure RecognizerPredictionFullResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (position production index : Nat)
    (beforeInvariant : RecognizerPredictionAppendInvariant grammarLayout
      grammar words tokens workspaceLayout workspace workspaceValues
      grammarCell tokensCell workspaceCell stateCountCell indexCell before
      position production index) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizePredictionAppendStatement
    (.returned (some (parseResultValue 2
      (Int.ofNat
        (appendLogical workspaceLayout.capacity position
          (recognizerPredictionSeed production position) workspace).1.stateCount)
      (-1) (Int.ofNat position)))) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell after

noncomputable def RecognizerPredictionAppendInvariant.execute_full
    (invariant : RecognizerPredictionAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell runtime position
      production index)
    (statusFull : (appendLogical workspaceLayout.capacity position
      (recognizerPredictionSeed production position) workspace).1.status =
      .full) :
    RecognizerPredictionFullResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position production index
      invariant := by
  let seed := recognizerPredictionSeed production position
  let logical := appendLogical workspaceLayout.capacity position seed workspace
  let outcome := logical.1
  let appended := invariant.evaluate_append
  let bound := appended.after.bindLocal 35 (appendOutcomeValue outcome)
  have boundWellFormed : StateWellFormed bound :=
    bindLocal_preserves_well_formed appended.after 35
      (appendOutcomeValue outcome) appended.invariant.wellFormed
  have resultLocal : bound.local? 35 = some (appendOutcomeValue outcome) :=
    bindLocal_finds_local appended.after 35 (appendOutcomeValue outcome)
      appended.invariant.wellFormed
  have positionAfterAppend : appended.after.local? 23 =
      some (.signed .i32 (Int.ofNat position)) :=
    appended.effect.singleton_preserves_local_of_ne
      invariant.frame.recognizer.wellFormed invariant.positionLocal
      invariant.frame.recognizer.workspaceBacking (by simp [workspaceValue])
  have positionBound : bound.local? 23 =
      some (.signed .i32 (Int.ofNat position)) :=
    (bindLocal_preserves_other_local appended.invariant.wellFormed
      (by decide)).trans positionAfterAppend
  have positionResult : Evaluates verifiedParserCore bound (.local 23)
      (.signed .i32 (Int.ofNat position)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 23 _ positionBound⟩
  have outcomeStatus : outcome.status = .full := by
    simpa [outcome, logical, seed] using statusFull
  let controlled := executeAppendOutcomeFullThen bound 35 18 (.local 23)
    (parserRecognizeIncrementLocal 33) outcome (Int.ofNat position)
    boundWellFormed resultLocal positionResult outcomeStatus
  let after := restoreLocals appended.after controlled.after
  have execution : Executes verifiedParserCore runtime
      parserRecognizePredictionAppendStatement
      (.returned (some (parseResultValue 2
        (Int.ofNat outcome.stateCount) (-1) (Int.ofNat position)))) after := by
    rw [extractedParserRecognize_prediction_append_shape]
    simpa [parserRecognizePredictionAppendCall,
      parserRecognizePredictionAppendArguments, recognizerAppendCall,
      recognizerAppendArguments, bound, after] using
      (executesLetLocal (type := .structure 2) appended.evaluation
        controlled.execution)
  have entered : StoreEffect CellSet.empty appended.after bound := by
    simpa [bound] using
      bindLocal_effect appended.after 35 (appendOutcomeValue outcome)
  have scopedStore : StoreEffect CellSet.empty appended.after
      controlled.after := entered.trans_same controlled.effect.toStoreEffect
  have closed : ModifiesOnly CellSet.empty appended.after after := by
    simpa [after] using scopedStore.restoreLocals
  have effect : ModifiesOnly (CellSet.singleton workspaceCell) runtime after :=
    appended.effect.trans_same (closed.weaken CellSet.empty_subset)
  have afterWellFormed : StateWellFormed after :=
    scopedStore.restoreLocals_wellFormed appended.invariant.wellFormed
      controlled.wellFormed
  have workspaceEq : logical.2 = workspace := by
    simpa [logical, seed] using appendLogical_workspace_eq_of_full statusFull
  have valuesEq : appendResultValues workspaceLayout workspace position seed
      workspaceValues = workspaceValues :=
    appendResultValues_eq_of_full (by simpa [seed] using statusFull)
  have afterInvariant :=
    appended.invariant.after_empty_effect closed afterWellFormed
  rw [workspaceEq, valuesEq] at afterInvariant
  exact {
    after := after
    execution := by simpa [seed, logical, outcome] using execution
    effect := effect
    wellFormed := afterWellFormed
    invariant := afterInvariant
  }

structure RecognizerPredictionOkResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (position production index : Nat)
    (beforeInvariant : RecognizerPredictionAppendInvariant grammarLayout
      grammar words tokens workspaceLayout workspace workspaceValues
      grammarCell tokensCell workspaceCell stateCountCell indexCell before
      position production index) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizePredictionAppendStatement .next after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton stateCountCell)
        (CellSet.singleton indexCell))) before after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout
    (appendLogical workspaceLayout.capacity position
      (recognizerPredictionSeed production position) workspace).2
    (appendResultValues workspaceLayout workspace position
      (recognizerPredictionSeed production position) workspaceValues)
    grammarCell tokensCell workspaceCell after
  stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
    (some (.signed .i32 (Int.ofNat
      (appendLogical workspaceLayout.capacity position
        (recognizerPredictionSeed production position)
        workspace).2.states.length)))).holds after
  indexOwned : (Assertion.localPointsTo 33 indexCell
    (some (.signed .i32 (Int.ofNat (index + 1))))).holds after

noncomputable def RecognizerPredictionAppendInvariant.execute_ok
    (invariant : RecognizerPredictionAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell runtime position
      production index)
    (statusOk : (appendLogical workspaceLayout.capacity position
      (recognizerPredictionSeed production position) workspace).1.status =
      .ok) :
    RecognizerPredictionOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime position production index
      invariant := by
  let appended := invariant.evaluate_append
  let result := appended.execute_ok_then_increment 35 33 indexCell
    (.local 23) index (by decide) (by decide) invariant.indexOwned
    invariant.indexSuccI32 invariant.indexBackingDistinct
    invariant.indexParameterDistinct statusOk
  let after := Classical.choose result
  have facts := Classical.choose_spec result
  exact {
    after := after
    execution := by
      rw [extractedParserRecognize_prediction_append_shape]
      simpa [parserRecognizePredictionAppendCall,
        parserRecognizePredictionAppendArguments, recognizerAppendCall,
        recognizerAppendArguments, after] using facts.1
    effect := facts.2.1
    invariant := facts.2.2.1
    stateCountOwned := facts.2.2.2.1
    indexOwned := facts.2.2.2.2
  }
def recognizerParentSeed
    (production dot origin parent completed : Nat) : StateSeed := {
  production := production
  dot := dot + 1
  origin := origin
  previous := some parent
  child := .state completed
}

structure RecognizerParentAppendInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (runtime : State)
    (position production dot origin parent completed : Nat) : Prop where
  frame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime position
  seedDerivation : EarleySeedDerivation grammar tokens workspace position
    (recognizerParentSeed production dot origin parent completed)
  dotSuccI32 : dot + 1 ≤ 2147483647
  originBound : origin ≤ finalPosition workspaceLayout.tokenCount
  positionLocal : runtime.local? 23 =
    some (.signed .i32 (Int.ofNat position))
  completedLocal : runtime.local? 24 =
    some (.signed .i32 (Int.ofNat completed))
  parentLocal : runtime.local? 30 =
    some (.signed .i32 (Int.ofNat parent))
  productionLocal : runtime.local? 31 =
    some (.signed .i32 (Int.ofNat production))
  dotLocal : runtime.local? 32 =
    some (.signed .i32 (Int.ofNat dot))
  originLocal : runtime.local? 34 =
    some (.signed .i32 (Int.ofNat origin))

theorem RecognizerParentAppendInvariant.seed_arguments
    (invariant : RecognizerParentAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position production dot origin
      parent completed) :
    ArgumentsEvaluateTo verifiedParserCore runtime
      parserRecognizeParentSeedArguments
      (parserStateSeedArgumentsValues
        (recognizerParentSeed production dot origin parent completed))
      runtime := by
  have productionResult : Evaluates verifiedParserCore runtime (.local 31)
      (.signed .i32 (Int.ofNat production)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 31 _
      invariant.productionLocal⟩
  have dotResult := evaluatesNatSuccAtLocal runtime 32 dot
    invariant.dotLocal invariant.dotSuccI32
  have originResult : Evaluates verifiedParserCore runtime (.local 34)
      (.signed .i32 (Int.ofNat origin)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 34 _
      invariant.originLocal⟩
  have parentResult : Evaluates verifiedParserCore runtime (.local 30)
      (.signed .i32 (Int.ofNat parent)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 30 _
      invariant.parentLocal⟩
  have childTagResult : Evaluates verifiedParserCore runtime (.constant 39)
      (.signed .i32 2) runtime :=
    evaluatesConstant verifiedParser_child_state_constant
  have completedResult : Evaluates verifiedParserCore runtime (.local 24)
      (.signed .i32 (Int.ofNat completed)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 24 _
      invariant.completedLocal⟩
  have missingKind := evaluatesParserAppendNegativeOne runtime
  simpa [parserRecognizeParentSeedArguments,
      parserStateSeedArgumentsValues, recognizerParentSeed,
      previousValue, encodeStateId, childTag, childPayload, childKind] using
    ArgumentsEvaluateTo.cons productionResult
      (ArgumentsEvaluateTo.cons dotResult
        (ArgumentsEvaluateTo.cons originResult
          (ArgumentsEvaluateTo.cons parentResult
            (ArgumentsEvaluateTo.cons childTagResult
              (ArgumentsEvaluateTo.cons completedResult
                (ArgumentsEvaluateTo.singleton missingKind))))))

noncomputable def RecognizerParentAppendInvariant.evaluate_append
    (invariant : RecognizerParentAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position production dot origin
      parent completed) :
    RecognizerSeededAppendResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position (.local 23)
      parserRecognizeParentSeedCall
      (recognizerParentSeed production dot origin parent completed)
      invariant.frame := by
  let seed := recognizerParentSeed production dot origin parent completed
  let afterSeed := restoreLocals runtime
    (parserStateSeedCallee runtime seed)
  have seedContract := extractedParserStateSeedCall_contract runtime runtime
    parserRecognizeParentSeedArguments seed
    invariant.frame.recognizer.wellFormed invariant.seed_arguments
  have seedEvaluation : Evaluates verifiedParserCore runtime
      parserRecognizeParentSeedCall (stateSeedValue seed) afterSeed := by
    simpa [parserRecognizeParentSeedCall, afterSeed] using seedContract.1
  have seedEffect : ModifiesOnly CellSet.empty runtime afterSeed := by
    simpa [afterSeed] using seedContract.2.1
  have positionResult : Evaluates verifiedParserCore runtime (.local 23)
      (.signed .i32 (Int.ofNat position)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 23 _
      invariant.positionLocal⟩
  exact invariant.frame.evaluate_seeded_append (.local 23)
    parserRecognizeParentSeedCall seed afterSeed invariant.seedDerivation
    invariant.originBound
    positionResult seedEvaluation seedEffect
    (by simpa [afterSeed] using seedContract.2.2)

structure RecognizerParentOkResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (before : State)
    (position production dot origin parent completed : Nat)
    (beforeInvariant : RecognizerParentAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell before position production dot
      origin parent completed) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeParentAppendStatement .next after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell)) before after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout
    (appendLogical workspaceLayout.capacity position
      (recognizerParentSeed production dot origin parent completed)
      workspace).2
    (appendResultValues workspaceLayout workspace position
      (recognizerParentSeed production dot origin parent completed)
      workspaceValues)
    grammarCell tokensCell workspaceCell after
  stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
    (some (.signed .i32 (Int.ofNat
      (appendLogical workspaceLayout.capacity position
        (recognizerParentSeed production dot origin parent completed)
        workspace).2.states.length)))).holds after

noncomputable def RecognizerParentAppendInvariant.execute_ok
    (invariant : RecognizerParentAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position production dot origin
      parent completed)
    (statusOk : (appendLogical workspaceLayout.capacity position
      (recognizerParentSeed production dot origin parent completed)
      workspace).1.status = .ok) :
    RecognizerParentOkResult grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      stateCountCell runtime position production dot origin parent completed
      invariant := by
  let appended := invariant.evaluate_append
  let result := appended.execute_ok 35 (.local 23) (by decide) statusOk
  let after := Classical.choose result
  have facts := Classical.choose_spec result
  exact {
    after := after
    execution := by
      rw [extractedParserRecognize_parent_append_shape]
      simpa [parserRecognizeParentAppendCall,
        parserRecognizeParentAppendArguments, recognizerAppendCall,
        recognizerAppendArguments, after] using facts.1
    effect := facts.2.1
    invariant := facts.2.2.1
    stateCountOwned := facts.2.2.2
  }

structure RecognizerParentFullResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell : CellId)
    (before : State)
    (position production dot origin parent completed : Nat)
    (beforeInvariant : RecognizerParentAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell before position production dot
      origin parent completed) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeParentAppendStatement
    (.returned (some (parseResultValue 2
      (Int.ofNat
        (appendLogical workspaceLayout.capacity position
          (recognizerParentSeed production dot origin parent completed)
          workspace).1.stateCount)
      (-1) (Int.ofNat position)))) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell after

noncomputable def RecognizerParentAppendInvariant.execute_full
    (invariant : RecognizerParentAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position production dot origin
      parent completed)
    (statusFull : (appendLogical workspaceLayout.capacity position
      (recognizerParentSeed production dot origin parent completed)
      workspace).1.status = .full) :
    RecognizerParentFullResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position production dot origin
      parent completed invariant := by
  let appended := invariant.evaluate_append
  have positionAfterAppend : appended.after.local? 23 =
      some (.signed .i32 (Int.ofNat position)) :=
    appended.effect.singleton_preserves_local_of_ne
      invariant.frame.recognizer.wellFormed invariant.positionLocal
      invariant.frame.recognizer.workspaceBacking (by simp [workspaceValue])
  let result := appended.execute_full_at_local 35 23 (by decide)
    positionAfterAppend statusFull
  let after := Classical.choose result
  have facts := Classical.choose_spec result
  exact {
    after := after
    execution := by
      rw [extractedParserRecognize_parent_append_shape]
      simpa [parserRecognizeParentAppendCall,
        parserRecognizeParentAppendArguments, recognizerAppendCall,
        recognizerAppendArguments, after] using facts.1
    effect := facts.2.1
    wellFormed := facts.2.2.1
    invariant := facts.2.2.2
  }

def recognizerInitialSeed (production : Nat) : StateSeed := {
  production := production
  dot := 0
  origin := 0
  previous := none
  child := .none
}

/-- Persistent state of the generated start-production seeding loop.  The
    start row is represented by its compact table interval; later parser
    correctness identifies that interval with the grammar's start row. -/
structure RecognizerInitialLoopInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (runtime : State) (first count index : Nat) : Prop where
  frame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime 0
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
  lhsProductionsOffsetLocal : runtime.local? 15 =
    some (.signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset))
  firstLocal : runtime.local? 16 =
    some (.signed .i32 (Int.ofNat first))
  countLocal : runtime.local? 17 =
    some (.signed .i32 (Int.ofNat count))
  indexOwned : (Assertion.localPointsTo 19 indexCell
    (some (.signed .i32 (Int.ofNat index)))).holds runtime
  indexLe : index ≤ count
  rowRange : first + count ≤ grammar.lhsProductions.length
  rowProductionBound : ∀ (rowIndex : Nat) (rowIndexBound : rowIndex < count),
    grammar.lhsProductions.get ⟨first + rowIndex, by
      have := rowRange
      omega⟩ < grammar.productionCount
  persistentSeparate : InitialLoopFrameSeparated runtime workspaceCell
    stateCountCell indexCell
  indexBackingDistinct :
    indexCell ≠ grammarCell ∧
    indexCell ≠ tokensCell ∧
    indexCell ≠ workspaceCell ∧
    indexCell ≠ stateCountCell

theorem RecognizerInitialLoopInvariant.persistentLocalsSeparate
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (id : VarId) (persistent : InitialLoopPersistentLocal id) :
    runtime.cellId? id ≠ some workspaceCell ∧
      runtime.cellId? id ≠ some stateCountCell ∧
      runtime.cellId? id ≠ some indexCell := by
  have framed := (InitialLoopPersistentLocal_source_frame id).mp persistent
  refine ⟨?_, ?_, ?_⟩
  · intro cellId
    exact invariant.persistentSeparate workspaceCell
      ⟨id, framed, cellId⟩ (Or.inl rfl)
  · intro cellId
    exact invariant.persistentSeparate stateCountCell
      ⟨id, framed, cellId⟩ (Or.inr (Or.inl rfl))
  · intro cellId
    exact invariant.persistentSeparate indexCell
      ⟨id, framed, cellId⟩ (Or.inr (Or.inr rfl))

theorem RecognizerInitialLoopInvariant.indexParameterDistinct
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (id : VarId) (member : id ∈ verifiedParserRecognizerParameterIds) :
    runtime.cellId? id ≠ some indexCell :=
  (invariant.persistentLocalsSeparate id (Or.inl member)).2.2

theorem RecognizerInitialLoopInvariant.condition_true
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (indexBound : index < count) :
    Evaluates verifiedParserCore runtime
      (.binary .less (.local 19) (.local 17)) (.boolean true) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 19)
      (.signed .i32 (Int.ofNat index)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 19 _
      (Assertion.localPointsTo_local 19 indexCell _ runtime
        invariant.indexOwned)⟩
  have right : Evaluates verifiedParserCore runtime (.local 17)
      (.signed .i32 (Int.ofNat count)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 17 _
      invariant.countLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt, indexBound]

theorem RecognizerInitialLoopInvariant.condition_false
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (done : count ≤ index) :
    Evaluates verifiedParserCore runtime
      (.binary .less (.local 19) (.local 17)) (.boolean false) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 19)
      (.signed .i32 (Int.ofNat index)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 19 _
      (Assertion.localPointsTo_local 19 indexCell _ runtime
        invariant.indexOwned)⟩
  have right : Evaluates verifiedParserCore runtime (.local 17)
      (.signed .i32 (Int.ofNat count)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 17 _
      invariant.countLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt]
  omega

/-- Exact evaluation of `grammar[lhs_productions_offset + first + index]`
    in the generated loop body. -/
theorem RecognizerInitialLoopInvariant.read_production
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (indexBound : index < count) :
    Evaluates verifiedParserCore runtime
      (.index (.local 0)
        (.binary .add
          (.binary .add (.local 15) (.local 16)) (.local 19)))
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
  have firstResult : Evaluates verifiedParserCore runtime (.local 16)
      (.signed .i32 (Int.ofNat first)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 16 _
      invariant.firstLocal⟩
  have indexResult : Evaluates verifiedParserCore runtime (.local 19)
      (.signed .i32 (Int.ofNat index)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 19 _
      (Assertion.localPointsTo_local 19 indexCell _ runtime
        invariant.indexOwned)⟩
  have partialBound : grammarLayout.lhsProductionsOffset + first ≤
      2147483647 := Nat.le_trans
    (Nat.le_of_lt (Nat.lt_of_le_of_lt (Nat.le_add_right _ _) physicalBound'))
    invariant.frame.recognizer.wordsI32
  have partialResult : Evaluates verifiedParserCore runtime
      (.binary .add (.local 15) (.local 16))
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
        (.binary .add (.local 15) (.local 16)) (.local 19))
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
        (.binary .add (.local 15) (.local 16)) (.local 19))
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

theorem RecognizerInitialLoopInvariant.index_succ_i32
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (indexBound : index < count) : index + 1 ≤ 2147483647 := by
  have tableFits : grammar.lhsProductions.length ≤ words.length := by
    rcases (invariant.frame.recognizer.grammarEncoded.validation_facts
      invariant.frame.recognizer.grammarWellFormed).prelude.lhsProductionsRange
      with ⟨_, fits⟩
    omega
  have range := invariant.rowRange
  exact Nat.le_trans (by omega)
    (Nat.le_trans tableFits invariant.frame.recognizer.wordsI32)

theorem RecognizerInitialLoopInvariant.after_temporary_bind
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (id : VarId) (value : Value) (temporary : 19 < id) :
    RecognizerInitialLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell (runtime.bindLocal id value)
      first count index := by
  have different (fixed : Nat) (bound : fixed ≤ 19) : id ≠ fixed := by
    intro equal
    rw [equal] at temporary
    exact (Nat.not_lt_of_ge bound) temporary
  have afterWellFormed := bindLocal_preserves_well_formed runtime id value
    invariant.frame.recognizer.wellFormed
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
      stateCountParameterSeparate := by
        unfold RecognizerParameterFrameSeparated
        intro cell framed written
        obtain ⟨queried, queriedBound, cellId⟩ := framed
        have queriedLe :=
          (mem_verifiedParserRecognizerParameterIds_iff queried).mp queriedBound
        have notEqual : id ≠ queried := different queried
          (Nat.le_trans queriedLe (by decide))
        apply invariant.frame.stateCountParameterSeparate cell
        · exact ⟨queried, queriedBound, by
            simpa [State.bindLocal, State.bindCell, State.cellId?, notEqual]
              using cellId⟩
        · exact written
    }
    workspaceWithinGrammar := invariant.workspaceWithinGrammar
    finalPositionLocal :=
      (bindLocal_preserves_other_local invariant.frame.recognizer.wellFormed
        (different 6 (by decide))).trans invariant.finalPositionLocal
    kindCountLocal :=
      (bindLocal_preserves_other_local invariant.frame.recognizer.wellFormed
        (different 11 (by decide))).trans invariant.kindCountLocal
    startNonterminalLocal :=
      (bindLocal_preserves_other_local invariant.frame.recognizer.wellFormed
        (different 12 (by decide))).trans invariant.startNonterminalLocal
    lhsOffsetsOffsetLocal :=
      (bindLocal_preserves_other_local invariant.frame.recognizer.wellFormed
        (different 13 (by decide))).trans invariant.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal :=
      (bindLocal_preserves_other_local invariant.frame.recognizer.wellFormed
        (different 14 (by decide))).trans invariant.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal :=
      (bindLocal_preserves_other_local
        invariant.frame.recognizer.wellFormed
        (different 15 (by decide))).trans
          invariant.lhsProductionsOffsetLocal
    firstLocal :=
      (bindLocal_preserves_other_local
        invariant.frame.recognizer.wellFormed
        (different 16 (by decide))).trans invariant.firstLocal
    countLocal :=
      (bindLocal_preserves_other_local
        invariant.frame.recognizer.wellFormed
        (different 17 (by decide))).trans invariant.countLocal
    indexOwned := bindLocal_preserves_localPointsTo_of_ne runtime id 19 value
      indexCell (some (.signed .i32 (Int.ofNat index)))
      invariant.frame.recognizer.wellFormed (different 19 (by decide))
      invariant.indexOwned
    indexLe := invariant.indexLe
    rowRange := invariant.rowRange
    rowProductionBound := invariant.rowProductionBound
    persistentSeparate := by
      unfold InitialLoopFrameSeparated
      intro cell framed written
      obtain ⟨queried, queriedBound, cellId⟩ := framed
      have queriedPersistent :=
        (InitialLoopPersistentLocal_source_frame queried).mpr queriedBound
      have notEqual : id ≠ queried := different queried
        (Nat.le_trans (Nat.le_of_lt queriedPersistent.lt18) (by decide))
      apply invariant.persistentSeparate cell
        ⟨queried, queriedBound, ?_⟩ written
      simpa [State.bindLocal, State.bindCell, State.cellId?, notEqual] using
        cellId
    indexBackingDistinct := invariant.indexBackingDistinct
  }

structure RecognizerInitialAppendInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (runtime : State) (production index : Nat) : Prop where
  frame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime 0
  seedDerivation : EarleySeedDerivation grammar tokens workspace 0
    (recognizerInitialSeed production)
  productionLocal : runtime.local? 20 =
    some (.signed .i32 (Int.ofNat production))
  indexOwned : (Assertion.localPointsTo 19 indexCell
    (some (.signed .i32 (Int.ofNat index)))).holds runtime
  indexSuccI32 : index + 1 ≤ 2147483647
  indexBackingDistinct :
    indexCell ≠ grammarCell ∧
    indexCell ≠ tokensCell ∧
    indexCell ≠ workspaceCell ∧
    indexCell ≠ stateCountCell
  indexParameterSeparate :
    RecognizerParameterFrameSeparated runtime indexCell

theorem RecognizerInitialAppendInvariant.indexParameterDistinct
    (invariant : RecognizerInitialAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime production index)
    (id : VarId) (member : id ∈ verifiedParserRecognizerParameterIds) :
    runtime.cellId? id ≠ some indexCell :=
  invariant.indexParameterSeparate.localCell_ne_of_singleton member

theorem RecognizerInitialLoopInvariant.bind_production
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (indexBound : index < count) :
    let production := grammar.lhsProductions.get
      ⟨first + index, by
        have := invariant.rowRange
        omega⟩
    RecognizerInitialAppendInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell
      (runtime.bindLocal 20 (.signed .i32 (Int.ofNat production)))
      production index := by
  dsimp only
  let production := grammar.lhsProductions.get
    ⟨first + index, by
      have := invariant.rowRange
      omega⟩
  let value : Value := .signed .i32 (Int.ofNat production)
  let boundInvariant := invariant.after_temporary_bind 20 value (by decide)
  exact {
    frame := boundInvariant.frame
    seedDerivation := {
      languageSound := by
        have productionBound := invariant.rowProductionBound index indexBound
        simpa [recognizerInitialSeed, freshSeed] using
          (freshSeed_sound (grammar := grammar) (tokens := tokens)
            (position := 0) productionBound)
      backpointer := by
        have productionBound := invariant.rowProductionBound index indexBound
        simpa [recognizerInitialSeed, freshSeed] using
          (EarleyBackpointerStep.fresh
            (grammar := grammar) (tokens := tokens) (workspace := workspace)
            (stateId := workspace.states.length) (position := 0)
            productionBound)
    }
    productionLocal := by
      simpa [production, value] using bindLocal_finds_local runtime 20 value
        invariant.frame.recognizer.wellFormed
    indexOwned := boundInvariant.indexOwned
    indexSuccI32 := invariant.index_succ_i32 indexBound
    indexBackingDistinct := invariant.indexBackingDistinct
    indexParameterSeparate := localBindingFrameFootprint_disjoint_singleton
      boundInvariant.indexParameterDistinct
  }

theorem RecognizerInitialAppendInvariant.seed_arguments
    (invariant : RecognizerInitialAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime production index) :
    ArgumentsEvaluateTo verifiedParserCore runtime
      parserRecognizeInitialSeedArguments
      (parserStateSeedArgumentsValues (recognizerInitialSeed production))
      runtime := by
  have productionResult : Evaluates verifiedParserCore runtime (.local 20)
      (.signed .i32 (Int.ofNat production)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 20 _
      invariant.productionLocal⟩
  have zero : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 0)) (.signed .i32 0) runtime := ⟨1, rfl⟩
  have negativeOne := evaluatesParserAppendNegativeOne runtime
  have childNone : Evaluates verifiedParserCore runtime (.constant 37)
      (.signed .i32 0) runtime :=
    evaluatesConstant verifiedParser_child_none_constant
  simpa [parserRecognizeInitialSeedArguments,
      parserStateSeedArgumentsValues, recognizerInitialSeed,
      previousValue, encodeStateId, childTag, childPayload, childKind] using
    ArgumentsEvaluateTo.cons productionResult
      (ArgumentsEvaluateTo.cons zero
        (ArgumentsEvaluateTo.cons zero
          (ArgumentsEvaluateTo.cons negativeOne
            (ArgumentsEvaluateTo.cons childNone
              (ArgumentsEvaluateTo.cons negativeOne
                (ArgumentsEvaluateTo.singleton negativeOne))))))

noncomputable def RecognizerInitialAppendInvariant.evaluate_append
    (invariant : RecognizerInitialAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime production index) :
    RecognizerSeededAppendResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime 0 (.value (.signed .i32 0))
      parserRecognizeInitialSeedCall (recognizerInitialSeed production)
      invariant.frame := by
  let seed := recognizerInitialSeed production
  let afterSeed := restoreLocals runtime
    (parserStateSeedCallee runtime seed)
  have seedContract := extractedParserStateSeedCall_contract runtime runtime
    parserRecognizeInitialSeedArguments seed
    invariant.frame.recognizer.wellFormed invariant.seed_arguments
  have seedEvaluation : Evaluates verifiedParserCore runtime
      parserRecognizeInitialSeedCall (stateSeedValue seed) afterSeed := by
    simpa [parserRecognizeInitialSeedCall, afterSeed] using seedContract.1
  have seedEffect : ModifiesOnly CellSet.empty runtime afterSeed := by
    simpa [afterSeed] using seedContract.2.1
  have zero : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 0)) (.signed .i32 0) runtime := ⟨1, rfl⟩
  exact invariant.frame.evaluate_seeded_append
    (.value (.signed .i32 0)) parserRecognizeInitialSeedCall seed afterSeed
    invariant.seedDerivation (by simp [seed, recognizerInitialSeed]) zero
    seedEvaluation seedEffect
    (by simpa [afterSeed] using seedContract.2.2)

structure RecognizerInitialOkResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (production index : Nat)
    (beforeInvariant : RecognizerInitialAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell before production
      index) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeInitialAppendStatement .next after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton stateCountCell)
        (CellSet.singleton indexCell))) before after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout
    (appendLogical workspaceLayout.capacity 0
      (recognizerInitialSeed production) workspace).2
    (appendResultValues workspaceLayout workspace 0
      (recognizerInitialSeed production) workspaceValues)
    grammarCell tokensCell workspaceCell after
  stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
    (some (.signed .i32 (Int.ofNat
      (appendLogical workspaceLayout.capacity 0
        (recognizerInitialSeed production) workspace).2.states.length)))).holds
      after
  indexOwned : (Assertion.localPointsTo 19 indexCell
    (some (.signed .i32 (Int.ofNat (index + 1))))).holds after

noncomputable def RecognizerInitialAppendInvariant.execute_ok
    (invariant : RecognizerInitialAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime production index)
    (statusOk : (appendLogical workspaceLayout.capacity 0
      (recognizerInitialSeed production) workspace).1.status = .ok) :
    RecognizerInitialOkResult grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      stateCountCell indexCell runtime production index invariant := by
  let appended := invariant.evaluate_append
  let result := appended.execute_ok_then_increment 21 19 indexCell
    (.value (.signed .i32 0)) index (by decide) (by decide)
    invariant.indexOwned invariant.indexSuccI32 invariant.indexBackingDistinct
    invariant.indexParameterDistinct statusOk
  let after := Classical.choose result
  have facts := Classical.choose_spec result
  exact {
    after := after
    execution := by
      rw [extractedParserRecognize_initial_append_shape]
      simpa [parserRecognizeInitialAppendCall,
        parserRecognizeInitialAppendArguments, recognizerAppendCall,
        recognizerAppendArguments, after] using facts.1
    effect := facts.2.1
    invariant := facts.2.2.1
    stateCountOwned := facts.2.2.2.1
    indexOwned := facts.2.2.2.2
  }

structure RecognizerInitialFullResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (production index : Nat)
    (beforeInvariant : RecognizerInitialAppendInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell before production
      index) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeInitialAppendStatement
    (.returned (some (parseResultValue 2
      (Int.ofNat
        (appendLogical workspaceLayout.capacity 0
          (recognizerInitialSeed production) workspace).1.stateCount)
      (-1) 0))) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell after

noncomputable def RecognizerInitialAppendInvariant.execute_full
    (invariant : RecognizerInitialAppendInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime production index)
    (statusFull : (appendLogical workspaceLayout.capacity 0
      (recognizerInitialSeed production) workspace).1.status = .full) :
    RecognizerInitialFullResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime production index
      invariant := by
  let seed := recognizerInitialSeed production
  let logical := appendLogical workspaceLayout.capacity 0 seed workspace
  let outcome := logical.1
  let appended := invariant.evaluate_append
  let bound := appended.after.bindLocal 21 (appendOutcomeValue outcome)
  have boundWellFormed : StateWellFormed bound :=
    bindLocal_preserves_well_formed appended.after 21
      (appendOutcomeValue outcome) appended.invariant.wellFormed
  have resultFound : bound.local? 21 = some (appendOutcomeValue outcome) :=
    bindLocal_finds_local appended.after 21 (appendOutcomeValue outcome)
      appended.invariant.wellFormed
  have zero : Evaluates verifiedParserCore bound
      (.value (.signed .i32 0)) (.signed .i32 0) bound := ⟨1, rfl⟩
  have outcomeStatus : outcome.status = .full := by
    simpa [outcome, logical, seed] using statusFull
  let controlled := executeAppendOutcomeFullThen bound 21 18
    (.value (.signed .i32 0)) (parserRecognizeIncrementLocal 19) outcome 0
    boundWellFormed resultFound zero outcomeStatus
  let after := restoreLocals appended.after controlled.after
  have execution : Executes verifiedParserCore runtime
      parserRecognizeInitialAppendStatement
      (.returned (some (parseResultValue 2
        (Int.ofNat outcome.stateCount) (-1) 0))) after := by
    rw [extractedParserRecognize_initial_append_shape]
    simpa [parserRecognizeInitialAppendCall,
      parserRecognizeInitialAppendArguments, recognizerAppendCall,
      recognizerAppendArguments, bound, after] using
      (executesLetLocal (type := .structure 2) appended.evaluation
        controlled.execution)
  have entered : StoreEffect CellSet.empty appended.after bound := by
    simpa [bound] using
      bindLocal_effect appended.after 21 (appendOutcomeValue outcome)
  have scopedStore : StoreEffect CellSet.empty appended.after
      controlled.after := entered.trans_same controlled.effect.toStoreEffect
  have closed : ModifiesOnly CellSet.empty appended.after after := by
    simpa [after] using scopedStore.restoreLocals
  have effect : ModifiesOnly (CellSet.singleton workspaceCell) runtime after :=
    appended.effect.trans_same (closed.weaken CellSet.empty_subset)
  have afterWellFormed : StateWellFormed after :=
    scopedStore.restoreLocals_wellFormed appended.invariant.wellFormed
      controlled.wellFormed
  have workspaceEq : logical.2 = workspace := by
    simpa [logical, seed] using appendLogical_workspace_eq_of_full statusFull
  have valuesEq : appendResultValues workspaceLayout workspace 0 seed
      workspaceValues = workspaceValues :=
    appendResultValues_eq_of_full (by simpa [seed] using statusFull)
  have afterInvariant :=
    appended.invariant.after_empty_effect closed afterWellFormed
  rw [workspaceEq, valuesEq] at afterInvariant
  exact {
    after := after
    execution := by simpa [seed, logical, outcome] using execution
    effect := effect
    wellFormed := afterWellFormed
    invariant := afterInvariant
  }

structure RecognizerInitialLoopOkStepResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (beforeWorkspace afterWorkspace : LogicalWorkspace)
    (beforeValues afterValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (first count index : Nat)
    (beforeInvariant : RecognizerInitialLoopInvariant grammarLayout grammar
      words tokens workspaceLayout beforeWorkspace beforeValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell before first count
      index) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeInitialLoopBody .next after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton stateCountCell)
        (CellSet.singleton indexCell))) before after
  invariant : RecognizerInitialLoopInvariant grammarLayout grammar words tokens
    workspaceLayout afterWorkspace afterValues grammarCell tokensCell
    workspaceCell stateCountCell indexCell after first count (index + 1)

/-- One ordinary iteration of the exact generated initial-seeding loop:
    read the next packed production, append its seed, update state count and
    index, and close the production temporary while preserving the frame. -/
noncomputable def RecognizerInitialLoopInvariant.execute_ok_step
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (indexBound : index < count)
    (statusOk :
      let production := grammar.lhsProductions.get
        ⟨first + index, by
          have := invariant.rowRange
          omega⟩
      (appendLogical workspaceLayout.capacity 0
        (recognizerInitialSeed production) workspace).1.status = .ok) :
    let production := grammar.lhsProductions.get
      ⟨first + index, by
        have := invariant.rowRange
        omega⟩
    let nextWorkspace := (appendLogical workspaceLayout.capacity 0
      (recognizerInitialSeed production) workspace).2
    let nextValues := appendResultValues workspaceLayout workspace 0
      (recognizerInitialSeed production) workspaceValues
    RecognizerInitialLoopOkStepResult grammarLayout grammar words tokens
      workspaceLayout workspace nextWorkspace workspaceValues nextValues
      grammarCell tokensCell workspaceCell stateCountCell indexCell runtime
      first count index invariant := by
  dsimp only
  let rowBound : first + index < grammar.lhsProductions.length := by
    have := invariant.rowRange
    omega
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let value : Value := .signed .i32 (Int.ofNat production)
  let bound := runtime.bindLocal 20 value
  let appendInvariant := invariant.bind_production indexBound
  have statusOk' : (appendLogical workspaceLayout.capacity 0
      (recognizerInitialSeed production) workspace).1.status = .ok := by
    simpa [production, rowBound] using statusOk
  let appended := appendInvariant.execute_ok statusOk'
  let nextWorkspace := (appendLogical workspaceLayout.capacity 0
    (recognizerInitialSeed production) workspace).2
  let nextValues := appendResultValues workspaceLayout workspace 0
    (recognizerInitialSeed production) workspaceValues
  let after := restoreLocals runtime appended.after
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton indexCell))
  have bodyExecution : Executes verifiedParserCore runtime
      parserRecognizeInitialLoopBody .next after := by
    rw [extractedParserRecognize_initial_loop_body_shape]
    simpa [bound, value, production, rowBound, appendInvariant, after] using
      executesLetLocal (type := parserI32Type)
        (invariant.read_production indexBound) appended.execution
  have entered : StoreEffect CellSet.empty runtime bound := by
    simpa [bound, value] using bindLocal_effect runtime 20 value
  have appendEffect : ModifiesOnly writes bound appended.after := by
    simpa [writes, bound, value, production, rowBound, appendInvariant] using
      appended.effect
  have scopedStore : StoreEffect writes runtime appended.after :=
    (entered.weaken CellSet.empty_subset).trans_same
      appendEffect.toStoreEffect
  have outerEffect : ModifiesOnly writes runtime after := by
    simpa [after] using scopedStore.restoreLocals
  have afterWellFormed : StateWellFormed after := by
    exact scopedStore.restoreLocals_wellFormed
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
        (InitialLoopPersistentLocal_source_frame id).mp (Or.inl idBound)))
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
      (appendResultValues_length workspaceLayout workspace 0
        (recognizerInitialSeed production) workspaceValues)
      (by
        simpa [nextWorkspace, nextValues, production, rowBound,
          appendInvariant] using appended.invariant.workspaceEncoded)
      (by
        simpa [nextWorkspace, production, rowBound, appendInvariant] using
          appended.invariant.derivations)
      newBacking
  have productionBound : production < grammar.productionCount := by
    simpa [production, rowBound] using
      invariant.rowProductionBound index indexBound
  have seedWithin : StateKeyWithinGrammar grammar
      (recognizerInitialSeed production).key := by
    exact {
      productionBound := productionBound
      dotBound := by simp [recognizerInitialSeed, StateSeed.key]
    }
  have nextWithinGrammar : WorkspaceWithinGrammar grammar nextWorkspace := by
    let appendedLogical := appendLogical_refines
      (appendLogical workspaceLayout.capacity 0
        (recognizerInitialSeed production) workspace) rfl
    exact appendedLogical.preserves_withinGrammar
      invariant.workspaceWithinGrammar seedWithin
  have preserveLocal (id : VarId)
      (persistent : InitialLoopPersistentLocal id) (value : Value)
      (found : runtime.local? id = some value) :
      after.local? id = some value :=
    outerEffect.preserves_local_of_disjoint
      invariant.frame.recognizer.wellFormed invariant.persistentSeparate
      ((InitialLoopPersistentLocal_source_frame id).mp persistent) found
  have afterCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat nextWorkspace.states.length)))).holds
      after := by
    constructor
    · change runtime.cellId? 18 = some stateCountCell
      exact invariant.frame.stateCountOwned.1
    · change appended.after.cellEntry? stateCountCell = _
      simpa [nextWorkspace, production, rowBound, appendInvariant] using
        appended.stateCountOwned.2
  have afterIndexOwned : (Assertion.localPointsTo 19 indexCell
      (some (.signed .i32 (Int.ofNat (index + 1))))).holds after := by
    constructor
    · change runtime.cellId? 19 = some indexCell
      exact invariant.indexOwned.1
    · change appended.after.cellEntry? indexCell = _
      simpa [appendInvariant, production, rowBound] using appended.indexOwned.2
  have nextInvariant : RecognizerInitialLoopInvariant grammarLayout grammar
      words tokens workspaceLayout nextWorkspace nextValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell after first count
      (index + 1) := {
    frame := {
      recognizer := nextRecognizer
      positionBound := invariant.frame.positionBound
      stateBaseLocal := preserveLocal 8 (by
        simp [InitialLoopPersistentLocal]) _
        invariant.frame.stateBaseLocal
      stateCapacityLocal := preserveLocal 9 (by
        simp [InitialLoopPersistentLocal]) _
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
    finalPositionLocal := preserveLocal 6 (by
      simp [InitialLoopPersistentLocal]) _ invariant.finalPositionLocal
    kindCountLocal := preserveLocal 11 (by
      simp [InitialLoopPersistentLocal]) _ invariant.kindCountLocal
    startNonterminalLocal := preserveLocal 12 (by
      simp [InitialLoopPersistentLocal]) _ invariant.startNonterminalLocal
    lhsOffsetsOffsetLocal := preserveLocal 13 (by
      simp [InitialLoopPersistentLocal]) _ invariant.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal := preserveLocal 14 (by
      simp [InitialLoopPersistentLocal]) _ invariant.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal := preserveLocal 15 (by
      simp [InitialLoopPersistentLocal]) _
      invariant.lhsProductionsOffsetLocal
    firstLocal := preserveLocal 16 (by
      simp [InitialLoopPersistentLocal]) _ invariant.firstLocal
    countLocal := preserveLocal 17 (by
      simp [InitialLoopPersistentLocal]) _ invariant.countLocal
    indexOwned := afterIndexOwned
    indexLe := by omega
    rowRange := invariant.rowRange
    rowProductionBound := invariant.rowProductionBound
    persistentSeparate := by
      unfold InitialLoopFrameSeparated
      rw [outerEffect.localBindingFrameFootprint_eq
        verifiedParserInitialLoopPersistentBindings]
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

structure RecognizerInitialLoopFullStepResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (before : State) (first count index : Nat)
    (production : Nat)
    (beforeInvariant : RecognizerInitialLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell indexCell before first count
      index) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeInitialLoopBody
    (.returned (some (parseResultValue 2
      (Int.ofNat (appendLogical workspaceLayout.capacity 0
        (recognizerInitialSeed production) workspace).1.stateCount)
      (-1) 0))) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell after

/-- The capacity-full branch escapes the generated loop body without
    executing the loop-index increment; the surrounding `while` therefore
    propagates the same parser result. -/
noncomputable def RecognizerInitialLoopInvariant.execute_full_step
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (indexBound : index < count)
    (statusFull :
      let production := grammar.lhsProductions.get
        ⟨first + index, by
          have := invariant.rowRange
          omega⟩
      (appendLogical workspaceLayout.capacity 0
        (recognizerInitialSeed production) workspace).1.status = .full) :
    let production := grammar.lhsProductions.get
      ⟨first + index, by
        have := invariant.rowRange
        omega⟩
    RecognizerInitialLoopFullStepResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index
      production invariant := by
  dsimp only
  let rowBound : first + index < grammar.lhsProductions.length := by
    have := invariant.rowRange
    omega
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let value : Value := .signed .i32 (Int.ofNat production)
  let bound := runtime.bindLocal 20 value
  let appendInvariant := invariant.bind_production indexBound
  have statusFull' : (appendLogical workspaceLayout.capacity 0
      (recognizerInitialSeed production) workspace).1.status = .full := by
    simpa [production, rowBound] using statusFull
  let appended := appendInvariant.execute_full statusFull'
  let after := restoreLocals runtime appended.after
  have bodyExecution : Executes verifiedParserCore runtime
      parserRecognizeInitialLoopBody
      (.returned (some (parseResultValue 2
        (Int.ofNat (appendLogical workspaceLayout.capacity 0
          (recognizerInitialSeed production) workspace).1.stateCount)
        (-1) 0))) after := by
    rw [extractedParserRecognize_initial_loop_body_shape]
    simpa [bound, value, production, rowBound, appendInvariant, after] using
      executesLetLocal (type := parserI32Type)
        (invariant.read_production indexBound) appended.execution
  have entered : StoreEffect CellSet.empty runtime bound := by
    simpa [bound, value] using bindLocal_effect runtime 20 value
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

abbrev RecognizerInitialLoopOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (first count : Nat) : State → Completion → Prop :=
  WorkspaceLoopOutcome workspaceLayout.capacity beforeWorkspace
    (fun stateCount =>
      .returned (some (parseResultValue 2 (Int.ofNat stateCount) (-1) 0)))
    (fun workspace workspaceValues after =>
      RecognizerInitialLoopInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell indexCell after first count count)
    (fun workspace workspaceValues after =>
      RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
        workspace workspaceValues grammarCell tokensCell workspaceCell after)

structure RecognizerInitialLoopExecution
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
  execution : Executes verifiedParserCore before parserRecognizeInitialLoop
    completion after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton stateCountCell)
        (CellSet.singleton indexCell))) before after
  outcome : RecognizerInitialLoopOutcome grammarLayout grammar words tokens
    workspaceLayout workspace grammarCell tokensCell workspaceCell stateCountCell
    indexCell first count after completion

def recognizerInitialWrites
    (workspaceCell stateCountCell indexCell : CellId) : CellSet :=
  CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton indexCell))

/-- Algorithmic state for the extracted start-production seeding loop.  The
    logical workspace changes after every successful append, so it travels
    existentially with the runtime and its representation invariant. -/
structure RecognizerInitialConfig
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (first count : Nat) where
  workspace : LogicalWorkspace
  workspaceValues : List Int
  runtime : State
  index : Nat
  invariant : RecognizerInitialLoopInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell indexCell runtime first count index

def RecognizerInitialConfig.measure
    (config : RecognizerInitialConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell first count) : Nat :=
  count - config.index

theorem RecognizerTerminalInvariant.scan_entry
    (invariant : RecognizerTerminalInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime position semanticKind) :
    ScanTerminalInvariant grammarLayout grammar words tokens grammarCell
      tokensCell position semanticKind
      (parserScanTerminalCallee runtime words tokens grammarCell tokensCell
        position semanticKind) := by
  exact parserScanTerminalCallee_entry grammarLayout grammar words tokens
    grammarCell tokensCell position semanticKind runtime
    invariant.recognizer.grammarEncoded invariant.recognizer.wordsI32
    invariant.recognizer.tokensI32 invariant.positionAdvanceI32
    invariant.semanticKindBound invariant.recognizer.wellFormed
    invariant.recognizer.grammarBacking invariant.recognizer.tokensBacking

structure RecognizerScanCallResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (before : State) (position semanticKind : Nat)
    (beforeInvariant : RecognizerTerminalInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell before position semanticKind) where
  after : State
  evaluation : Evaluates verifiedParserCore before
    parserRecognizeScanTerminalCall
    (scanTerminalValue (scanTerminal grammar tokens position semanticKind))
    after
  effect : ModifiesOnly CellSet.empty before after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell after

noncomputable def RecognizerTerminalInvariant.evaluate_scan
    (invariant : RecognizerTerminalInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime position semanticKind) :
    RecognizerScanCallResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime position semanticKind invariant := by
  let result := parserRecognizeScanTerminalCall_implements_model runtime
      invariant.recognizer.wellFormed invariant.recognizer.grammarLocal
      invariant.recognizer.tokensLocal invariant.recognizer.tokenCountLocal
      invariant.positionLocal invariant.semanticKindLocal
      invariant.recognizer.grammarBacking invariant.recognizer.tokensBacking
      invariant.scan_entry
  let after := Classical.choose result
  have facts := Classical.choose_spec result
  exact {
    after := after
    evaluation := facts.1
    effect := facts.2.1
    invariant := invariant.recognizer.after_empty_effect facts.2.1
      facts.2.2.1 }

/-- If the mathematical scanner rejects the terminal, the exact extracted
    recognizer branch binds `-1`, skips the append arm, closes the temporary,
    and re-establishes the full recognizer frame without writes. -/
theorem RecognizerTerminalInvariant.executes_no_match
    (invariant : RecognizerTerminalInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime position semanticKind)
    (miss : scanTerminal grammar tokens position semanticKind = none) :
    ∃ after,
      Executes verifiedParserCore runtime parserRecognizeTerminalStatement
        .next after ∧
      ModifiesOnly CellSet.empty runtime after ∧
      StateWellFormed after ∧
      RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
        workspace workspaceValues grammarCell tokensCell workspaceCell after :=
    by
  let scan := invariant.evaluate_scan
  have scanEvaluation : Evaluates verifiedParserCore runtime
      parserRecognizeScanTerminalCall (.signed .i32 (-1)) scan.after := by
    simpa [miss, scanTerminalValue] using scan.evaluation
  let bound := scan.after.bindLocal 30 (.signed .i32 (-1))
  have boundWellFormed : StateWellFormed bound := by
    exact bindLocal_preserves_well_formed scan.after 30
      (.signed .i32 (-1)) scan.invariant.wellFormed
  have resultLocal : bound.local? 30 = some (.signed .i32 (-1)) := by
    exact bindLocal_finds_local scan.after 30 (.signed .i32 (-1))
      scan.invariant.wellFormed
  have left : Evaluates verifiedParserCore bound (.local 30)
      (.signed .i32 (-1)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 30 _ resultLocal⟩
  have right : Evaluates verifiedParserCore bound
      (.value (.signed .i32 0)) (.signed .i32 0) bound := ⟨1, rfl⟩
  have condition : Evaluates verifiedParserCore bound
      (.binary .greaterEqual (.local 30) (.value (.signed .i32 0)))
      (.boolean false) bound := by
    apply evaluatesEagerBinary (by decide) (by decide) left right
    simp [evalBinaryValue, evalSignedBinary]
  have selected : Executes verifiedParserCore bound
      (.ifThenElse
        (.binary .greaterEqual (.local 30) (.value (.signed .i32 0)))
        parserRecognizeTerminalSuccessStatement .skip) .next bound :=
    executesIfFalse condition (executesSkip verifiedParserCore bound)
  have body : Executes verifiedParserCore bound
      (.sequence
        (.ifThenElse
          (.binary .greaterEqual (.local 30) (.value (.signed .i32 0)))
          parserRecognizeTerminalSuccessStatement .skip)
        .skip) .next bound :=
    executesSequence selected (executesSkip verifiedParserCore bound)
  let after := restoreLocals scan.after bound
  have execution : Executes verifiedParserCore runtime
      parserRecognizeTerminalStatement .next after := by
    rw [extractedParserRecognize_terminal_statement_shape]
    simpa [bound, after] using
      (executesLetLocal (type := parserI32Type) scanEvaluation body)
  have entered : StoreEffect CellSet.empty scan.after bound := by
    simpa [bound] using
      bindLocal_effect scan.after 30 (.signed .i32 (-1))
  have closed : ModifiesOnly CellSet.empty scan.after after := by
    simpa [after] using entered.restoreLocals
  have effect : ModifiesOnly CellSet.empty runtime after :=
    scan.effect.trans_same closed
  have afterWellFormed : StateWellFormed after :=
    entered.restoreLocals_wellFormed scan.invariant.wellFormed
      boundWellFormed
  exact ⟨after, execution, effect, afterWellFormed,
    invariant.recognizer.after_empty_effect effect afterWellFormed⟩

end Lanius.Extraction.ParserRecognize
