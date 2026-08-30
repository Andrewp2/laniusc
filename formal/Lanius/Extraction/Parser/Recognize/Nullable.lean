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
/-! ## Nullable-completion chart traversal -/

def parserRecognizeNullableLoop : Stmt :=
  (recognizerWhileLoops extractedParserRecognizeBody)[5]?.getD .skip

def parserRecognizeNullableLoopBody : Stmt :=
  match parserRecognizeNullableLoop with
  | .whileLoop _ body => body
  | _ => .skip

/-- The nullable replay is exactly a nonnegative `STATE_NEXT` traversal.
    Its body remains artifact-derived and is decomposed by the field-binding
    lemmas below rather than copied into a handwritten AST. -/
theorem extractedParserRecognize_nullable_loop_shape :
    parserRecognizeNullableLoop =
      .whileLoop
        (.binary .greaterEqual (.local 36)
          (.value (.signed .i32 0)))
        parserRecognizeNullableLoopBody := by
  rfl

/-! ## Artifact-derived FunctionalView for nullable completion

The nullable traversal retains exactly the source declarations accessed by
the loop.  Its candidate-field bindings are lexical temporaries recovered by
the checked reifier, not duplicated as persistent proof state.
-/

def nullableLoopLayout : Layout 12 := fun index =>
  [0, 4, 8, 9, 18, 23, 24, 25, 26, 27, 30, 36].get index

private def nullableLoopContext : Context :=
  let c0 := Context.empty.bind 0 (.slice parserI32Type)
  let c1 := c0.bind 4 (.slice parserI32Type)
  let c2 := c1.bind 8 parserI32Type
  let c3 := c2.bind 9 parserI32Type
  let c4 := c3.bind 18 parserI32Type
  let c5 := c4.bind 23 parserI32Type
  let c6 := c5.bind 24 parserI32Type
  let c7 := c6.bind 25 parserI32Type
  let c8 := c7.bind 26 parserI32Type
  let c9 := c8.bind 27 parserI32Type
  let c10 := c9.bind 30 parserI32Type
  c10.bind 36 parserI32Type

private def nullableLoopReification? :=
  reifyCommand? verifiedParserCore (.structure 0) nullableLoopContext true
    nullableLoopLayout 37 parserRecognizeNullableLoop

private theorem nullableLoopReification_exists :
    nullableLoopReification?.isSome := by
  native_decide

/-- Complete mutable FunctionalView command recovered from the checked
    nullable-completion loop. -/
def parserRecognizeNullableLoopView :=
  nullableLoopReification?.get nullableLoopReification_exists

theorem parserRecognizeNullableLoopView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      nullableLoopLayout 37 parserRecognizeNullableLoopView.command =
      parserRecognizeNullableLoop :=
  parserRecognizeNullableLoopView.toCoreExactly

private def nullableBodyReification? :=
  reifyCommand? verifiedParserCore (.structure 0) nullableLoopContext true
    nullableLoopLayout 37 parserRecognizeNullableLoopBody

private theorem nullableBodyReification_exists :
    nullableBodyReification?.isSome := by
  native_decide

private def parserRecognizeNullableBodyView :=
  nullableBodyReification?.get nullableBodyReification_exists

private theorem parserRecognizeNullableBodyView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      nullableLoopLayout 37 parserRecognizeNullableBodyView.command =
      parserRecognizeNullableLoopBody :=
  parserRecognizeNullableBodyView.toCoreExactly

private def nullableSlot {arity : Nat} (index : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .reference (.slot index)

private def nullableLiteral {arity : Nat} (value : Int) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .reference (.literal (.signed .i32 value))

private def nullableStateValueTerm {arity : Nat} (enough : 12 ≤ arity)
    (fieldConstant : ConstantId) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.call extractedParserStateValueFunction.id [
      .slice parserI32Type, parserI32Type, parserI32Type, parserI32Type]
      parserI32Type) [
    nullableSlot ⟨1, by omega⟩,
    nullableSlot ⟨2, by omega⟩,
    nullableSlot ⟨11, by omega⟩,
    .apply (.constant fieldConstant parserI32Type) []]

def nullableEqual {arity : Nat}
    (left right : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.binary .equal parserI32Type parserI32Type (.scalar .bool))
    [left, right]

private def nullableRhsLengthTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 15 :=
  .apply (.call extractedParserRhsLengthFunction.id
    [.slice parserI32Type, parserI32Type] parserI32Type) [
      nullableSlot ⟨0, by omega⟩,
      nullableSlot ⟨12, by omega⟩]

private def nullableLhsTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 15 :=
  .apply (.call extractedParserLhsFunction.id
    [.slice parserI32Type, parserI32Type] parserI32Type) [
      nullableSlot ⟨0, by omega⟩,
      nullableSlot ⟨12, by omega⟩]

/-- The exact three-part condition inside the reified nullable body.  The
    conjunction nodes preserve source short-circuit order: origin, completed
    dot, then expected left-hand side. -/
private def nullableCandidatePredicate :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 15 :=
  Lanius.FunctionalView.Core.logicalAnd
    (Lanius.FunctionalView.Core.logicalAnd
      (nullableEqual (nullableSlot ⟨14, by omega⟩)
        (nullableSlot ⟨5, by omega⟩))
      (nullableEqual (nullableSlot ⟨13, by omega⟩)
        nullableRhsLengthTerm))
    (nullableEqual nullableLhsTerm (nullableSlot ⟨10, by omega⟩))

private def nullableConstant {arity : Nat} (id : ConstantId) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.constant id parserI32Type) []

private def nullableAdd {arity : Nat}
    (left right : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.binary .add parserI32Type parserI32Type parserI32Type) [left, right]

private def nullableNegativeOne {arity : Nat} :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.unary .negate parserI32Type parserI32Type) [nullableLiteral 1]

private def nullableSeedTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 15 :=
  .apply (.call extractedParserStateSeedFunction.id
    (List.replicate 7 parserI32Type) (.structure 1)) [
      nullableSlot ⟨7, by omega⟩,
      nullableAdd (nullableSlot ⟨8, by omega⟩) (nullableLiteral 1),
      nullableSlot ⟨9, by omega⟩,
      nullableSlot ⟨6, by omega⟩,
      nullableConstant 39,
      nullableSlot ⟨11, by omega⟩,
      nullableNegativeOne]

private def nullableAppendArguments : List
    (Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 15) := [
  nullableSlot ⟨1, by omega⟩,
  nullableSlot ⟨2, by omega⟩,
  nullableSlot ⟨3, by omega⟩,
  nullableSlot ⟨5, by omega⟩,
  nullableSeedTerm,
  nullableSlot ⟨4, by omega⟩]

private def nullableAppendTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 15 :=
  .apply (.call extractedParserAppendStateFunction.id [
    .slice parserI32Type, parserI32Type, parserI32Type, parserI32Type,
    .structure 1, parserI32Type] (.structure 2)) nullableAppendArguments

private def nullableFullCondition :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 16 :=
  nullableEqual
    (.apply (.field (.structure 2) 0 parserI32Type)
      [nullableSlot ⟨15, by omega⟩])
    (nullableConstant 41)

private def nullableFullResult :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 16 :=
  .apply (.call extractedParserAppendOrFullFunction.id
    [.structure 2, parserI32Type] (.structure 0)) [
      nullableSlot ⟨15, by omega⟩,
      nullableSlot ⟨5, by omega⟩]

private def nullableStateCountTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 16 :=
  .apply (.field (.structure 2) 2 parserI32Type)
    [nullableSlot ⟨15, by omega⟩]

private def nullableCanonicalBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 12 :=
  .letValue parserI32Type
    (nullableStateValueTerm (arity := 12) (by omega) 28)
    (.letValue parserI32Type
      (nullableStateValueTerm (arity := 13) (by omega) 29)
      (.letValue parserI32Type
        (nullableStateValueTerm (arity := 14) (by omega) 30)
        (.sequence
          (.ifThenElse nullableCandidatePredicate
            (.letValue (.structure 2) nullableAppendTerm
              (.sequence
                (.ifThenElse nullableFullCondition
                  (.sequence (.returnValue (some nullableFullResult)) .skip)
                  .skip)
                (.sequence
                  (.setLocal ⟨4, by omega⟩ nullableStateCountTerm)
                  .skip)))
            .skip)
          (.sequence
            (.setLocal ⟨11, by omega⟩
              (nullableStateValueTerm (arity := 15) (by omega) 32))
            .skip))))

private theorem nullableCanonicalBodyCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      nullableLoopLayout 37 nullableCanonicalBodyCommand =
      parserRecognizeNullableLoopBody := by
  rfl

private def nullableLoopCondition :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 12 :=
  .apply (.binary .greaterEqual parserI32Type parserI32Type
    (.scalar .bool)) [nullableSlot ⟨11, by omega⟩, nullableLiteral 0]

private def nullableBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 12 :=
  nullableCanonicalBodyCommand

def nullableLoopCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 12 :=
  .whileLoop nullableLoopCondition nullableBodyCommand

theorem nullableLoopCommand_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      nullableLoopLayout 37 nullableLoopCommand =
      parserRecognizeNullableLoop := by
  rw [nullableLoopCommand,
    Lanius.FunctionalView.Core.Stateful.toCoreStmt,
    nullableBodyCommand, nullableCanonicalBodyCommand_toCore]
  exact extractedParserRecognize_nullable_loop_shape.symm

def nullableWorld (words : List Int) (tokens : List Nat)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId) :
    Lanius.FunctionalView.Core.ReadOnly.World :=
  recognizerWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell

/-- Persistent source values in the exact checked nullable-loop layout.
    Candidate production, dot, and origin are introduced and removed by the
    reified command's lexical bindings. -/
def nullableEnvironment
    (words workspaceValues : List Int) (grammarCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (stateCount position parentState
      parentProduction parentDot parentOrigin expected : Nat)
    (candidate : Int) : Lanius.FunctionalView.Env 12
  | ⟨0, _⟩ => parserGrammarValue words grammarCell
  | ⟨1, _⟩ => workspaceValue workspaceValues workspaceCell
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat
      (stateBase workspaceLayout.tokenCount))
  | ⟨3, _⟩ => .signed .i32 (Int.ofNat workspaceLayout.capacity)
  | ⟨4, _⟩ => .signed .i32 (Int.ofNat stateCount)
  | ⟨5, _⟩ => .signed .i32 (Int.ofNat position)
  | ⟨6, _⟩ => .signed .i32 (Int.ofNat parentState)
  | ⟨7, _⟩ => .signed .i32 (Int.ofNat parentProduction)
  | ⟨8, _⟩ => .signed .i32 (Int.ofNat parentDot)
  | ⟨9, _⟩ => .signed .i32 (Int.ofNat parentOrigin)
  | ⟨10, _⟩ => .signed .i32 (Int.ofNat expected)
  | ⟨11, _⟩ => .signed .i32 candidate

noncomputable def nullableTermMachine
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int)
    (grammarCell : CellId) :=
  Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
    (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
      grammarCell)

noncomputable def nullableStatefulMachine
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int)
    (grammarCell : CellId) :=
  Lanius.FunctionalView.Core.Stateful.machineWith verifiedParserCore
    (Lanius.FunctionalView.Core.Effectful.evaluateOperation verifiedParserCore
      (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
        grammarCell))

/-- Functional evaluation of one packed state-field read.  The statement is
    polymorphic over lexical extensions, so the same theorem proves all
    three candidate bindings and the final `STATE_NEXT` read. -/
private theorem nullableStateValueTerm_evaluates
    {arity : Nat} (enough : 12 ≤ arity)
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words workspaceValues : List Int) (grammarCell workspaceCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (workspace : LogicalWorkspace) (state : EarleyState)
    (stateId field : Nat) (fieldConstant : ConstantId)
    (different : workspaceCell ≠ grammarCell)
    (worldEq : world = nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    (workspaceValueEq : environment ⟨1, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (stateBaseEq : environment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (stateIdEq : environment ⟨11, by omega⟩ =
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
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world environment (nullableStateValueTerm enough fieldConstant) =
      .ok (.signed .i32 (stateFieldValue workspace stateId state field),
        world) := by
  subst world
  let machine := nullableTermMachine workspaceLayout grammar words grammarCell
  have workspaceResult : Lanius.FunctionalView.Term.evaluate machine
      (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      environment (nullableSlot ⟨1, by omega⟩) =
      .ok (workspaceValue workspaceValues workspaceCell,
        nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) := by
    exact Lanius.FunctionalView.Term.evaluate_slot workspaceValueEq
  have baseResult : Lanius.FunctionalView.Term.evaluate machine
      (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      environment (nullableSlot ⟨2, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat
        (stateBase workspaceLayout.tokenCount)),
        nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) := by
    exact Lanius.FunctionalView.Term.evaluate_slot stateBaseEq
  have stateResult : Lanius.FunctionalView.Term.evaluate machine
      (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      environment (nullableSlot ⟨11, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat stateId),
        nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) := by
    exact Lanius.FunctionalView.Term.evaluate_slot stateIdEq
  let constantTerm : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity :=
    .apply (.constant fieldConstant parserI32Type) []
  have constantAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell)
      (world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      (environment := environment) constantTerm (by rfl)
  have constantReadOnly : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      environment constantTerm =
      .ok (.signed .i32 (Int.ofNat field),
        nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) := by
    exact Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_constant
      constantFound
  have constantResult : Lanius.FunctionalView.Term.evaluate machine
      (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      environment constantTerm =
      .ok (.signed .i32 (Int.ofNat field),
        nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) := by
    exact constantAgreement.trans constantReadOnly
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine
      (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      environment [nullableSlot ⟨1, by omega⟩,
        nullableSlot ⟨2, by omega⟩, nullableSlot ⟨11, by omega⟩,
        constantTerm] =
      .ok ([workspaceValue workspaceValues workspaceCell,
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
        .signed .i32 (Int.ofNat stateId),
        .signed .i32 (Int.ofNat field)],
        nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) :=
    Lanius.FunctionalView.evaluateTerms_cons workspaceResult
      (Lanius.FunctionalView.evaluateTerms_cons baseResult
        (Lanius.FunctionalView.evaluateTerms_cons stateResult
          (Lanius.FunctionalView.evaluateTerms_cons constantResult
            (Lanius.FunctionalView.evaluateTerms_nil machine
              (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
              environment))))
  have addressBound : stateWord (stateBase workspaceLayout.tokenCount)
      stateId field < workspaceValues.length := by
    rw [valuesLength]
    exact encoded.state_address_valid foundState fieldBound
  have worldFound :
      (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell).i32Slice?
        workspaceCell = some workspaceValues := by
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
      (words := words) (grammarCell := grammarCell)
      (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      workspaceValues workspaceCell 0 workspaceValues.length
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
    grammarCell).evaluate
      (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      extractedParserStateValueFunction.id [
        workspaceValue workspaceValues workspaceCell,
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
        .signed .i32 (Int.ofNat stateId),
        .signed .i32 (Int.ofNat field)] = _
  rw [fieldValue] at registryResult
  exact registryResult

/-- Functional evaluation of the nullable predicate's production-RHS lookup.
    The packed-table representation is hidden behind the common recognizer
    traversal registry. -/
private theorem nullableRhsLengthTerm_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words workspaceValues : List Int) (grammarCell workspaceCell : CellId)
    (environment : Lanius.FunctionalView.Env 15) (production : Nat)
    (productionBound : production < grammar.productionCount)
    (grammarValueEq : environment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell)
    (productionValueEq : environment ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat production)) :
    Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      environment nullableRhsLengthTerm =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨production, productionBound⟩).rhs.length),
        nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) := by
  let world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let machine := nullableTermMachine workspaceLayout grammar words grammarCell
  have grammarResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (nullableSlot ⟨0, by omega⟩) =
      .ok (parserGrammarValue words grammarCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot grammarValueEq
  have productionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (nullableSlot ⟨12, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat production), world) :=
    Lanius.FunctionalView.Term.evaluate_slot productionValueEq
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [nullableSlot ⟨0, by omega⟩,
        nullableSlot ⟨12, by omega⟩] =
      .ok ([parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production)], world) :=
    Lanius.FunctionalView.evaluateTerms_cons grammarResult
      (Lanius.FunctionalView.evaluateTerms_cons productionResult
        (Lanius.FunctionalView.evaluateTerms_nil machine world environment))
  have rowBound : production < grammar.rhsLengths.length := by
    simpa using productionBound
  have registryResult := RecognizerTraversalCallRegistry.calls_at_rhs_length
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (grammarCell := grammarCell) world production
    (by simp [world, nullableWorld]) rowBound
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

/-- Functional evaluation of the nullable predicate's production-LHS lookup. -/
private theorem nullableLhsTerm_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words workspaceValues : List Int) (grammarCell workspaceCell : CellId)
    (environment : Lanius.FunctionalView.Env 15) (production : Nat)
    (productionBound : production < grammar.productionCount)
    (grammarValueEq : environment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell)
    (productionValueEq : environment ⟨12, by omega⟩ =
      .signed .i32 (Int.ofNat production)) :
    Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      environment nullableLhsTerm =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨production, productionBound⟩).lhs),
        nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) := by
  let world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let machine := nullableTermMachine workspaceLayout grammar words grammarCell
  have grammarResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (nullableSlot ⟨0, by omega⟩) =
      .ok (parserGrammarValue words grammarCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot grammarValueEq
  have productionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (nullableSlot ⟨12, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat production), world) :=
    Lanius.FunctionalView.Term.evaluate_slot productionValueEq
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [nullableSlot ⟨0, by omega⟩,
        nullableSlot ⟨12, by omega⟩] =
      .ok ([parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production)], world) :=
    Lanius.FunctionalView.evaluateTerms_cons grammarResult
      (Lanius.FunctionalView.evaluateTerms_cons productionResult
        (Lanius.FunctionalView.evaluateTerms_nil machine world environment))
  have rowBound : production < grammar.productionLhs.length := by
    simpa using productionBound
  have registryResult := RecognizerTraversalCallRegistry.calls_at_lhs
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (grammarCell := grammarCell) world production
    (by simp [world, nullableWorld]) rowBound
  have rowValue : grammar.productionLhs.get ⟨production, rowBound⟩ =
      (grammar.productionAt ⟨production, productionBound⟩).lhs := by
    simpa using grammar.productionLhs_get ⟨production, productionBound⟩
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
    grammarCell).evaluate world extractedParserLhsFunction.id
      [parserGrammarValue words grammarCell,
        .signed .i32 (Int.ofNat production)] = _
  rw [rowValue] at registryResult
  exact registryResult

theorem nullableEqual_evaluates
    {arity : Nat} (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (words : List Int) (grammarCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity)
    (left right : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (leftValue rightValue : Nat)
    (leftResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world environment left =
      .ok (.signed .i32 (Int.ofNat leftValue), world))
    (rightResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world environment right =
      .ok (.signed .i32 (Int.ofNat rightValue), world)) :
    Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world environment (nullableEqual left right) =
      .ok (.boolean (decide (leftValue = rightValue)), world) := by
  apply Lanius.FunctionalView.Term.evaluate_apply2 leftResult rightResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedParserCore world
      (.binary .equal parserI32Type parserI32Type (.scalar .bool))
      [.signed .i32 (Int.ofNat leftValue),
        .signed .i32 (Int.ofNat rightValue)] = _
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_equal
    leftValue rightValue

private theorem nullableLoopCondition_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words workspaceValues : List Int)
    (grammarCell workspaceCell : CellId)
    (stateCount position parentState parentProduction parentDot parentOrigin
      expected : Nat) (candidate : Int) :
    Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      (nullableEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout stateCount position parentState parentProduction
        parentDot parentOrigin expected candidate)
      nullableLoopCondition =
      .ok (.boolean (decide (candidate ≥ 0)),
        nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) := by
  simp [nullableTermMachine, nullableWorld, nullableEnvironment,
    nullableLoopCondition, nullableSlot, nullableLiteral,
    Lanius.FunctionalView.Term.evaluate,
    Lanius.FunctionalView.Ref.evaluate,
    Lanius.FunctionalView.evaluateTerms,
    Lanius.FunctionalView.Core.Effectful.machine,
    Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
    evalBinaryValue, evalSignedBinary, bind, Except.bind]

def verifiedParserNullableLoopAccessFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedAccessFrameForCore
    parserRecognizeNullableLoop (by native_decide)

def verifiedParserNullableLoopLiveFrame :
    LocalAccessFrame :=
  verifiedParserRecognizerSymbolic.checkedLiveFrameBeforeCore
    parserRecognizeNullableLoop (by native_decide)

theorem verifiedParser_nullable_loop_access_frame :
    verifiedParserNullableLoopAccessFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("candidate", 36, .readWrite),
      ("workspace", 4, .read),
      ("state_base", 8, .read),
      ("position", 23, .read),
      ("grammar", 0, .read),
      ("expected_nonterminal", 30, .read),
      ("state_capacity", 9, .read),
      ("production", 25, .read),
      ("dot", 26, .read),
      ("origin", 27, .read),
      ("state_id", 24, .read),
      ("state_count", 18, .readWrite)] := by
  native_decide

theorem verifiedParser_nullable_loop_live_frame :
    verifiedParserNullableLoopLiveFrame = verifiedParserNullableLoopAccessFrame := by
  native_decide

/-- Nullable-loop accesses whose cells are shared with its enclosing frames.
    The candidate cursor is omitted because `chartCursor` owns it. -/
def verifiedParserNullableLoopSharedFrame :
    LocalAccessFrame :=
  verifiedParserNullableLoopAccessFrame.excludingName "candidate"

def verifiedParserNullableLoopSharedFrameIds : List VarId :=
  verifiedParserNullableLoopSharedFrame.ids

theorem verifiedParser_nullable_loop_shared_frame_ids :
    verifiedParserNullableLoopSharedFrameIds =
      [4, 8, 23, 0, 30, 9, 25, 26, 27, 24, 18] := by
  native_decide

@[simp] theorem mem_verifiedParserNullableLoopSharedFrameIds_iff
    (id : Nat) :
    id ∈ verifiedParserNullableLoopSharedFrameIds ↔
      id = 4 ∨ id = 8 ∨ id = 23 ∨ id = 0 ∨ id = 30 ∨ id = 9 ∨
        id = 25 ∨ id = 26 ∨ id = 27 ∨ id = 24 ∨ id = 18 := by
  rw [verifiedParser_nullable_loop_shared_frame_ids]
  simp only [List.mem_cons, List.not_mem_nil, or_false]

def verifiedParserNullableLoopPreservedFrame :
    LocalAccessFrame :=
  verifiedParserNullableLoopSharedFrame.excludingName "state_count"

def verifiedParserNullableLoopPreservedFrameIds : List VarId :=
  verifiedParserNullableLoopPreservedFrame.ids

def verifiedParserNullableLoopPersistentBindings : LocalBindingFrame :=
  LocalBindingFrame.union verifiedParserRecognizerParameterFrame
    verifiedParserNullableLoopSharedFrame.bindings

def verifiedParserNullableLoopPreservedBindings : LocalBindingFrame :=
  LocalBindingFrame.union verifiedParserRecognizerParameterFrame
    verifiedParserNullableLoopPreservedFrame.bindings

theorem verifiedParser_nullable_loop_preserved_frame_ids :
    verifiedParserNullableLoopPreservedFrameIds =
      [4, 8, 23, 0, 30, 9, 25, 26, 27, 24] := by
  native_decide

theorem verifiedParserNullableLoopPersistentBindings_core_ids :
    verifiedParserNullableLoopPersistentBindings.coreIds =
      verifiedParserRecognizerParameterIds ++
        verifiedParserNullableLoopSharedFrameIds := by
  native_decide

theorem verifiedParserNullableLoopPreservedBindings_core_ids :
    verifiedParserNullableLoopPreservedBindings.coreIds =
      verifiedParserRecognizerParameterIds ++
        verifiedParserNullableLoopPreservedFrameIds := by
  native_decide

@[simp] theorem mem_verifiedParserNullableLoopPreservedFrameIds_iff
    (id : Nat) :
    id ∈ verifiedParserNullableLoopPreservedFrameIds ↔
      id = 4 ∨ id = 8 ∨ id = 23 ∨ id = 0 ∨ id = 30 ∨ id = 9 ∨
        id = 25 ∨ id = 26 ∨ id = 27 ∨ id = 24 := by
  rw [verifiedParser_nullable_loop_preserved_frame_ids]
  simp only [List.mem_cons, List.not_mem_nil, or_false]

def NullablePersistentLocal (id : VarId) : Prop :=
  id ∈ verifiedParserRecognizerParameterIds ∨
    id ∈ verifiedParserNullableLoopSharedFrameIds

def NullablePreservedLocal (id : VarId) : Prop :=
  id ∈ verifiedParserRecognizerParameterIds ∨
    id ∈ verifiedParserNullableLoopPreservedFrameIds

theorem NullablePersistentLocal_source_frame (id : VarId) :
    NullablePersistentLocal id ↔
      verifiedParserNullableLoopPersistentBindings.ContainsCoreId id := by
  rw [LocalBindingFrame.ContainsCoreId,
    verifiedParserNullableLoopPersistentBindings_core_ids]
  simp [NullablePersistentLocal]

theorem NullablePreservedLocal_source_frame (id : VarId) :
    NullablePreservedLocal id ↔
      verifiedParserNullableLoopPreservedBindings.ContainsCoreId id := by
  rw [LocalBindingFrame.ContainsCoreId,
    verifiedParserNullableLoopPreservedBindings_core_ids]
  simp [NullablePreservedLocal]

theorem nullablePersistentLocalFootprint_eq (runtime : State) :
    localCellFootprint runtime NullablePersistentLocal =
      localBindingFrameFootprint runtime
        verifiedParserNullableLoopPersistentBindings := by
  unfold localBindingFrameFootprint
  congr 1
  funext id
  exact propext (NullablePersistentLocal_source_frame id)

theorem nullablePreservedLocalFootprint_eq (runtime : State) :
    localCellFootprint runtime NullablePreservedLocal =
      localBindingFrameFootprint runtime
        verifiedParserNullableLoopPreservedBindings := by
  unfold localBindingFrameFootprint
  congr 1
  funext id
  exact propext (NullablePreservedLocal_source_frame id)

theorem NullablePreservedLocal_iff (id : VarId) :
    NullablePreservedLocal id ↔ NullablePersistentLocal id ∧ id ≠ 18 := by
  unfold NullablePreservedLocal NullablePersistentLocal
  constructor
  · intro preserved
    rcases preserved with parameter | frame
    · refine ⟨Or.inl parameter, ?_⟩
      have bound :=
        (mem_verifiedParserRecognizerParameterIds_iff id).mp parameter
      exact Nat.ne_of_lt (Nat.lt_of_le_of_lt bound (by decide))
    · refine ⟨Or.inr ?_, ?_⟩
      · rw [mem_verifiedParserNullableLoopPreservedFrameIds_iff] at frame
        rw [mem_verifiedParserNullableLoopSharedFrameIds_iff]
        rcases frame with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
            rfl | rfl <;> simp
      · rw [mem_verifiedParserNullableLoopPreservedFrameIds_iff] at frame
        rcases frame with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
            rfl | rfl <;> decide
  · rintro ⟨persistent, notCount⟩
    rcases persistent with parameter | frame
    · exact Or.inl parameter
    · right
      rw [mem_verifiedParserNullableLoopSharedFrameIds_iff] at frame
      rw [mem_verifiedParserNullableLoopPreservedFrameIds_iff]
      rcases frame with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
          rfl | rfl | rfl <;> simp_all

def nullableFrameMutableCells
    (workspaceCell stateCountCell cursorCell : CellId) : CellSet :=
  CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton cursorCell))

def NullableFrameSeparated (runtime : State)
    (workspaceCell stateCountCell cursorCell : CellId) : Prop :=
  CellSet.Disjoint
    (localBindingFrameFootprint runtime
      verifiedParserNullableLoopPreservedBindings)
    (nullableFrameMutableCells workspaceCell stateCountCell cursorCell)

theorem NullablePersistentLocal.le30
    (id : Nat) (persistent : NullablePersistentLocal id) : id ≤ 30 := by
  unfold NullablePersistentLocal at persistent
  rcases persistent with parameter | shared
  · exact Nat.le_trans
      ((mem_verifiedParserRecognizerParameterIds_iff id).mp parameter)
      (by decide)
  · rw [mem_verifiedParserNullableLoopSharedFrameIds_iff] at shared
    rcases shared with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
        rfl | rfl | rfl <;> decide

def parserRecognizeNullableProductionBinding : Stmt :=
  (findLetLocalStatement 37 parserRecognizeNullableLoopBody).getD .skip

def parserRecognizeNullableDotBinding : Stmt :=
  (findLetLocalStatement 38 parserRecognizeNullableLoopBody).getD .skip

def parserRecognizeNullableOriginBinding : Stmt :=
  (findLetLocalStatement 39 parserRecognizeNullableLoopBody).getD .skip

def parserRecognizeNullableAdvance : Expr :=
  .assign .set (.local 36) (parserRecognizeStateValueCall 36 32)

def parserRecognizeNullablePredicate : Expr :=
  match parserRecognizeNullableLoopBody with
  | .letLocal 37 _ _ (.letLocal 38 _ _ (.letLocal 39 _ _
      (.sequence (.ifThenElse condition _ _) _))) => condition
  | _ => .value (.boolean false)

def parserRecognizeNullableAfterBindings : Stmt :=
  match parserRecognizeNullableLoopBody with
  | .letLocal 37 _ _ (.letLocal 38 _ _ (.letLocal 39 _ _ body)) => body
  | _ => .skip

theorem extractedParserRecognize_nullable_predicate_shape :
    parserRecognizeNullablePredicate =
      .binary .logicalAnd
        (.binary .logicalAnd
          (.binary .equal (.local 39) (.local 23))
          (.binary .equal (.local 38)
            (.call extractedParserRhsLengthFunction.id
              [.local 0, .local 37])))
        (.binary .equal
          (.call extractedParserLhsFunction.id [.local 0, .local 37])
          (.local 30)) := by
  rfl

theorem extractedParserRecognize_nullable_after_bindings_shape :
    parserRecognizeNullableAfterBindings =
      .sequence
        (.ifThenElse parserRecognizeNullablePredicate
          parserRecognizeNullableAppendStatement .skip)
        (parserRecognizeCursorAdvanceStatement 36) := by
  rfl

theorem extractedParserRecognize_nullable_body_shape :
    parserRecognizeNullableLoopBody =
      .letLocal 37 parserI32Type (parserRecognizeStateValueCall 36 28)
        (.letLocal 38 parserI32Type (parserRecognizeStateValueCall 36 29)
          (.letLocal 39 parserI32Type (parserRecognizeStateValueCall 36 30)
            parserRecognizeNullableAfterBindings)) := by
  rfl

theorem extractedParserRecognize_nullable_production_binding_shape :
    parserRecognizeNullableProductionBinding =
      .letLocal 37 parserI32Type (parserRecognizeStateValueCall 36 28)
        (match parserRecognizeNullableLoopBody with
          | .letLocal 37 _ _ body => body
          | _ => .skip) := by
  rfl

theorem extractedParserRecognize_nullable_dot_binding_shape :
    parserRecognizeNullableDotBinding =
      .letLocal 38 parserI32Type (parserRecognizeStateValueCall 36 29)
        (match parserRecognizeNullableProductionBinding with
          | .letLocal 37 _ _ body =>
              match body with
              | .letLocal 38 _ _ tail => tail
              | _ => .skip
          | _ => .skip) := by
  rfl

theorem extractedParserRecognize_nullable_origin_binding_shape :
    parserRecognizeNullableOriginBinding =
      .letLocal 39 parserI32Type (parserRecognizeStateValueCall 36 30)
        (match parserRecognizeNullableDotBinding with
          | .letLocal 38 _ _ body =>
              match body with
              | .letLocal 39 _ _ tail => tail
              | _ => .skip
          | _ => .skip) := by
  rfl

/-- Persistent semantic and ownership state for the nullable-completion
    traversal.  The parent state being advanced is fixed by the surrounding
    state-processing branch; `current` ranges over the chart at `position`.
    Candidate state fields are temporary bindings and are intentionally not
    part of this invariant. -/
structure RecognizerNullableLoopInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (runtime : State)
    (position parentProduction parentDot parentOrigin parentState
      expected current : Nat)
    (remaining : List Nat) : Type where
  chartCursor : RecognizerChartCursorInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell cursorCell runtime position 36 current remaining
  appendFrame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime position
  positionLocal : runtime.local? 23 =
    some (.signed .i32 (Int.ofNat position))
  parentStateLocal : runtime.local? 24 =
    some (.signed .i32 (Int.ofNat parentState))
  parentProductionLocal : runtime.local? 25 =
    some (.signed .i32 (Int.ofNat parentProduction))
  parentDotLocal : runtime.local? 26 =
    some (.signed .i32 (Int.ofNat parentDot))
  parentOriginLocal : runtime.local? 27 =
    some (.signed .i32 (Int.ofNat parentOrigin))
  expectedLocal : runtime.local? 30 =
    some (.signed .i32 (Int.ofNat expected))
  parentProductionBound : parentProduction < grammar.productionCount
  parentDotBeforeEnd : parentDot <
    (grammar.productionAt ⟨parentProduction, parentProductionBound⟩).rhs.length
  dotSuccI32 : parentDot + 1 ≤ 2147483647
  parentOriginBound : parentOrigin ≤
    finalPosition workspaceLayout.tokenCount
  parentStored : StoredPredecessor workspace parentState parentProduction
    parentDot parentOrigin position
  parentSymbolFound :
    (grammar.productionAt
      ⟨parentProduction, parentProductionBound⟩).rhs[parentDot]? =
      some (grammar.grammar.n_kinds + expected)
  parentAdvanceSound : ∀ child symbol finish,
    (grammar.productionAt
      ⟨parentProduction, parentProductionBound⟩).rhs[parentDot]? =
        some symbol →
    RecognizesSymbol grammar tokens symbol position finish →
    EarleyStateSound grammar tokens
      ((recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState child).atPosition finish)
  persistentSeparate : NullableFrameSeparated runtime workspaceCell
    stateCountCell cursorCell
  cursorStateCountDistinct : cursorCell ≠ stateCountCell

/-- The three lexical candidate bindings at the head of the real nullable
    body evaluate in FunctionalView to the corresponding logical state row.
    This is one reusable proof of the binding chain, not three structural-Core
    replays. -/
private theorem RecognizerNullableLoopInvariant.functional_candidate_reads
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate) :
    let world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let environment := nullableEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length position
      parentState parentProduction parentDot parentOrigin expected
      (Int.ofNat current)
    let productionEnvironment := environment.push
      (.signed .i32 (Int.ofNat candidate.production))
    let dotEnvironment := productionEnvironment.push
      (.signed .i32 (Int.ofNat candidate.dot))
    Lanius.FunctionalView.Term.evaluate
        (nullableTermMachine workspaceLayout grammar words grammarCell)
        world environment (nullableStateValueTerm (arity := 12) (by omega) 28) =
      .ok (.signed .i32 (Int.ofNat candidate.production), world) ∧
    Lanius.FunctionalView.Term.evaluate
        (nullableTermMachine workspaceLayout grammar words grammarCell)
        world productionEnvironment
        (nullableStateValueTerm (arity := 13) (by omega) 29) =
      .ok (.signed .i32 (Int.ofNat candidate.dot), world) ∧
    Lanius.FunctionalView.Term.evaluate
        (nullableTermMachine workspaceLayout grammar words grammarCell)
        world dotEnvironment
        (nullableStateValueTerm (arity := 14) (by omega) 30) =
      .ok (.signed .i32 (Int.ofNat candidate.origin), world) := by
  dsimp only
  let environment := nullableEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length position parentState
    parentProduction parentDot parentOrigin expected (Int.ofNat current)
  have different :=
    invariant.chartCursor.recognizer.grammarWorkspaceDistinct.symm
  have productionRead := nullableStateValueTerm_evaluates
    (arity := 12) (by omega) workspaceLayout grammar words workspaceValues
    grammarCell workspaceCell
    (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    environment workspace candidate current 0 28 different rfl rfl rfl rfl
    invariant.chartCursor.recognizer.workspaceLength
    invariant.chartCursor.recognizer.workspaceEncoded found (by decide)
    verifiedParser_find_constants.2.1
  have dotRead := nullableStateValueTerm_evaluates
    (arity := 13) (by omega) workspaceLayout grammar words workspaceValues
    grammarCell workspaceCell
    (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    (environment.push (.signed .i32 (Int.ofNat candidate.production)))
    workspace candidate current 1 29 different rfl (by rfl) (by rfl) (by rfl)
    invariant.chartCursor.recognizer.workspaceLength
    invariant.chartCursor.recognizer.workspaceEncoded found (by decide)
    verifiedParser_find_constants.2.2.1
  have originRead := nullableStateValueTerm_evaluates
    (arity := 14) (by omega) workspaceLayout grammar words workspaceValues
    grammarCell workspaceCell
    (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    ((environment.push (.signed .i32 (Int.ofNat candidate.production))).push
      (.signed .i32 (Int.ofNat candidate.dot)))
    workspace candidate current 2 30 different rfl (by rfl) (by rfl) (by rfl)
    invariant.chartCursor.recognizer.workspaceLength
    invariant.chartCursor.recognizer.workspaceEncoded found (by decide)
    verifiedParser_find_constants.2.2.2.1
  simpa [environment, stateFieldValue] using And.intro productionRead
    (And.intro dotRead originRead)

/-- Persistent nullable-completion state after the chart cursor has consumed
    its final element and contains the concrete `-1` sentinel. -/
structure RecognizerNullableFinishedInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (runtime : State)
    (position parentProduction parentDot parentOrigin parentState
      expected : Nat) : Type where
  chartCursor : RecognizerChartCursorFinished grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell cursorCell runtime position 36
  appendFrame : RecognizerAppendFrame grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell runtime position
  positionLocal : runtime.local? 23 =
    some (.signed .i32 (Int.ofNat position))
  parentStateLocal : runtime.local? 24 =
    some (.signed .i32 (Int.ofNat parentState))
  parentProductionLocal : runtime.local? 25 =
    some (.signed .i32 (Int.ofNat parentProduction))
  parentDotLocal : runtime.local? 26 =
    some (.signed .i32 (Int.ofNat parentDot))
  parentOriginLocal : runtime.local? 27 =
    some (.signed .i32 (Int.ofNat parentOrigin))
  expectedLocal : runtime.local? 30 =
    some (.signed .i32 (Int.ofNat expected))
  parentProductionBound : parentProduction < grammar.productionCount
  parentDotBeforeEnd : parentDot <
    (grammar.productionAt ⟨parentProduction, parentProductionBound⟩).rhs.length
  dotSuccI32 : parentDot + 1 ≤ 2147483647
  parentOriginBound : parentOrigin ≤
    finalPosition workspaceLayout.tokenCount
  parentStored : StoredPredecessor workspace parentState parentProduction
    parentDot parentOrigin position
  parentSymbolFound :
    (grammar.productionAt
      ⟨parentProduction, parentProductionBound⟩).rhs[parentDot]? =
      some (grammar.grammar.n_kinds + expected)
  parentAdvanceSound : ∀ child symbol finish,
    (grammar.productionAt
      ⟨parentProduction, parentProductionBound⟩).rhs[parentDot]? =
        some symbol →
    RecognizesSymbol grammar tokens symbol position finish →
    EarleyStateSound grammar tokens
      ((recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState child).atPosition finish)
  persistentSeparate : NullableFrameSeparated runtime workspaceCell
    stateCountCell cursorCell
  cursorStateCountDistinct : cursorCell ≠ stateCountCell

theorem nullablePersistentLocalsSeparate
    (separate : NullableFrameSeparated runtime workspaceCell stateCountCell
      cursorCell)
    (stateCountId : runtime.cellId? 18 = some stateCountCell)
    (stateCountWorkspaceDistinct : stateCountCell ≠ workspaceCell)
    (cursorStateCountDistinct : cursorCell ≠ stateCountCell)
    (id : VarId) (persistent : NullablePersistentLocal id) :
    runtime.cellId? id ≠ some workspaceCell ∧
      (id ≠ 18 → runtime.cellId? id ≠ some stateCountCell) ∧
      runtime.cellId? id ≠ some cursorCell := by
  by_cases notStateCount : id ≠ 18
  · have preserved :=
      (NullablePreservedLocal_iff id).mpr ⟨persistent, notStateCount⟩
    have framed := (NullablePreservedLocal_source_frame id).mp preserved
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

theorem RecognizerNullableLoopInvariant.persistentLocalsSeparate
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position parentProduction
      parentDot parentOrigin parentState expected current remaining) :
    ∀ id, NullablePersistentLocal id →
      runtime.cellId? id ≠ some workspaceCell ∧
      (id ≠ 18 → runtime.cellId? id ≠ some stateCountCell) ∧
      runtime.cellId? id ≠ some cursorCell :=
  nullablePersistentLocalsSeparate invariant.persistentSeparate
    invariant.appendFrame.stateCountOwned.1
    invariant.appendFrame.stateCountBackingDistinct.2.2
    invariant.cursorStateCountDistinct

theorem RecognizerNullableFinishedInvariant.persistentLocalsSeparate
    (invariant : RecognizerNullableFinishedInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position parentProduction
      parentDot parentOrigin parentState expected) :
    ∀ id, NullablePersistentLocal id →
      runtime.cellId? id ≠ some workspaceCell ∧
      (id ≠ 18 → runtime.cellId? id ≠ some stateCountCell) ∧
      runtime.cellId? id ≠ some cursorCell :=
  nullablePersistentLocalsSeparate invariant.persistentSeparate
    invariant.appendFrame.stateCountOwned.1
    invariant.appendFrame.stateCountBackingDistinct.2.2
    invariant.cursorStateCountDistinct

theorem RecognizerNullableFinishedInvariant.condition_negative
    (invariant : RecognizerNullableFinishedInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected) :
    Evaluates verifiedParserCore runtime
      (.binary .greaterEqual (.local 36)
        (.value (.signed .i32 0))) (.boolean false) runtime :=
  invariant.chartCursor.condition_negative

/-- Nullable replay inserts the same parent production with its dot advanced
    by one.  This lemma makes the grammar-domain preservation obligation
    explicit before any workspace mutation occurs. -/
theorem RecognizerNullableLoopInvariant.seed_within_grammar
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining) (candidate : Nat) :
    StateKeyWithinGrammar grammar
      (recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState candidate).key := by
  exact {
    productionBound := invariant.parentProductionBound
    dotBound := by
      simpa [recognizerNullableSeed, StateSeed.key] using
        Nat.succ_le_of_lt invariant.parentDotBeforeEnd
  }

def RecognizerNullableLoopInvariant.after_empty_effect
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    RecognizerNullableLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell after position parentProduction
      parentDot parentOrigin parentState expected current remaining := {
  chartCursor := invariant.chartCursor.after_empty_effect effect afterWellFormed
  appendFrame := invariant.appendFrame.after_empty_effect effect afterWellFormed
  positionLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.positionLocal
  parentStateLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.parentStateLocal
  parentProductionLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.parentProductionLocal
  parentDotLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.parentDotLocal
  parentOriginLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.parentOriginLocal
  expectedLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.expectedLocal
  parentProductionBound := invariant.parentProductionBound
  parentDotBeforeEnd := invariant.parentDotBeforeEnd
  dotSuccI32 := invariant.dotSuccI32
  parentOriginBound := invariant.parentOriginBound
  parentSymbolFound := invariant.parentSymbolFound
  parentAdvanceSound := invariant.parentAdvanceSound
  parentStored := invariant.parentStored
  persistentSeparate := by
    unfold NullableFrameSeparated
    rw [effect.localBindingFrameFootprint_eq
      verifiedParserNullableLoopPreservedBindings]
    exact invariant.persistentSeparate
  cursorStateCountDistinct := invariant.cursorStateCountDistinct
}

/-- Temporary artifact locals (`candidate_production`, `candidate_dot`, and
    `candidate_origin`) preserve both the cursor and append frames. -/
def RecognizerNullableLoopInvariant.after_bind_local
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (id : VarId) (value : Value) (temporary : 36 < id) :
    RecognizerNullableLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell (runtime.bindLocal id value)
      position parentProduction parentDot parentOrigin parentState expected
      current remaining := by
  have different (fixed : Nat) (bound : fixed ≤ 36) : id ≠ fixed :=
    Nat.ne_of_gt (Nat.lt_of_le_of_lt bound temporary)
  exact {
    chartCursor := invariant.chartCursor.after_bind_local id value
      (Nat.lt_of_le_of_lt (by decide : 8 ≤ 36) temporary) temporary
    appendFrame := invariant.appendFrame.after_bind_local id value
      (different 0 (by decide)) (different 1 (by decide))
      (different 2 (by decide)) (different 3 (by decide))
      (different 4 (by decide)) (different 5 (by decide))
      (Nat.lt_of_le_of_lt (by decide : 5 ≤ 36) temporary)
      (different 8 (by decide)) (different 9 (by decide))
      (different 18 (by decide))
    positionLocal :=
      (bindLocal_preserves_other_local
        invariant.chartCursor.recognizer.wellFormed
        (different 23 (by decide))).trans invariant.positionLocal
    parentStateLocal :=
      (bindLocal_preserves_other_local
        invariant.chartCursor.recognizer.wellFormed
        (different 24 (by decide))).trans invariant.parentStateLocal
    parentProductionLocal :=
      (bindLocal_preserves_other_local
        invariant.chartCursor.recognizer.wellFormed
        (different 25 (by decide))).trans invariant.parentProductionLocal
    parentDotLocal :=
      (bindLocal_preserves_other_local
        invariant.chartCursor.recognizer.wellFormed
        (different 26 (by decide))).trans invariant.parentDotLocal
    parentOriginLocal :=
      (bindLocal_preserves_other_local
        invariant.chartCursor.recognizer.wellFormed
        (different 27 (by decide))).trans invariant.parentOriginLocal
    expectedLocal :=
      (bindLocal_preserves_other_local
        invariant.chartCursor.recognizer.wellFormed
        (different 30 (by decide))).trans invariant.expectedLocal
    parentProductionBound := invariant.parentProductionBound
    parentDotBeforeEnd := invariant.parentDotBeforeEnd
    dotSuccI32 := invariant.dotSuccI32
    parentOriginBound := invariant.parentOriginBound
    parentSymbolFound := invariant.parentSymbolFound
    parentAdvanceSound := invariant.parentAdvanceSound
    parentStored := invariant.parentStored
    persistentSeparate := by
      unfold NullableFrameSeparated
      intro cell framed written
      obtain ⟨queried, preserved, cellId⟩ := framed
      have queriedBound := (NullablePreservedLocal_iff queried).mp
        ((NullablePreservedLocal_source_frame queried).mpr preserved) |>.1
      have notEqual : id ≠ queried := different queried
        (Nat.le_trans queriedBound.le30 (by decide))
      apply invariant.persistentSeparate cell
        ⟨queried, preserved, ?_⟩ written
      simpa [State.bindLocal, State.bindCell, State.cellId?, notEqual] using
        cellId
    cursorStateCountDistinct := invariant.cursorStateCountDistinct
  }

/-- Recombine the shared append frame with a cursor-local write.  The cursor
    and state-count locals own distinct cells, so advancing `STATE_NEXT`
    cannot disturb the logical workspace or its current state count. -/
def RecognizerNullableLoopInvariant.after_cursor_effect
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (afterCursor : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell after position 36 next nextRemaining)
    (effect : ModifiesOnly (CellSet.singleton cursorCell) before after) :
    RecognizerNullableLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell after position parentProduction
      parentDot parentOrigin parentState expected next nextRemaining := by
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        verifiedParserNullableLoopPersistentBindings)
      (CellSet.singleton cursorCell) :=
    localCellFootprint_disjoint_singleton
      (fun id framed =>
        invariant.persistentLocalsSeparate id
          ((NullablePersistentLocal_source_frame id).mpr framed) |>.2.2)
  have preserveLocal (id : VarId) (persistent : NullablePersistentLocal id)
      (value : Value)
      (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint
      invariant.chartCursor.recognizer.wellFormed frameDisjoint
        ((NullablePersistentLocal_source_frame id).mp persistent) found
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
        simp [NullablePersistentLocal]) _
        invariant.appendFrame.stateCapacityLocal
      stateCountLocal := preserveLocal 18 (by
        simp [NullablePersistentLocal]) _
        invariant.appendFrame.stateCountLocal
      stateCountOwned := countOwned
      stateCountBackingDistinct := invariant.appendFrame.stateCountBackingDistinct
      stateCountParameterSeparate := by
        unfold RecognizerParameterFrameSeparated
        rw [effect.localBindingFrameFootprint_eq
          verifiedParserRecognizerParameterFrame]
        exact invariant.appendFrame.stateCountParameterSeparate
    }
    positionLocal := preserveLocal 23 (by
      simp [NullablePersistentLocal]) _ invariant.positionLocal
    parentStateLocal := preserveLocal 24 (by
      simp [NullablePersistentLocal]) _ invariant.parentStateLocal
    parentProductionLocal := preserveLocal 25 (by
      simp [NullablePersistentLocal]) _
      invariant.parentProductionLocal
    parentDotLocal := preserveLocal 26 (by
      simp [NullablePersistentLocal]) _ invariant.parentDotLocal
    parentOriginLocal := preserveLocal 27 (by
      simp [NullablePersistentLocal]) _
      invariant.parentOriginLocal
    expectedLocal := preserveLocal 30 (by
      simp [NullablePersistentLocal]) _ invariant.expectedLocal
    parentProductionBound := invariant.parentProductionBound
    parentDotBeforeEnd := invariant.parentDotBeforeEnd
    dotSuccI32 := invariant.dotSuccI32
    parentOriginBound := invariant.parentOriginBound
    parentSymbolFound := invariant.parentSymbolFound
    parentAdvanceSound := invariant.parentAdvanceSound
    parentStored := invariant.parentStored
    persistentSeparate := by
      unfold NullableFrameSeparated
      rw [effect.localBindingFrameFootprint_eq
        verifiedParserNullableLoopPreservedBindings]
      exact invariant.persistentSeparate
    cursorStateCountDistinct := invariant.cursorStateCountDistinct
  }

/-- Recombine the nullable append frame with the final cursor write that
    installs `-1`.  This is the terminal counterpart of
    `after_cursor_effect`. -/
def RecognizerNullableLoopInvariant.after_cursor_exhaustion
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current [])
    (afterCursor : RecognizerChartCursorFinished grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell after position 36)
    (effect : ModifiesOnly (CellSet.singleton cursorCell) before after) :
    RecognizerNullableFinishedInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell after position parentProduction
      parentDot parentOrigin parentState expected := by
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        verifiedParserNullableLoopPersistentBindings)
      (CellSet.singleton cursorCell) :=
    localCellFootprint_disjoint_singleton
      (fun id framed =>
        invariant.persistentLocalsSeparate id
          ((NullablePersistentLocal_source_frame id).mpr framed) |>.2.2)
  have preserveLocal (id : VarId) (persistent : NullablePersistentLocal id)
      (value : Value)
      (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint
      invariant.chartCursor.recognizer.wellFormed frameDisjoint
        ((NullablePersistentLocal_source_frame id).mp persistent) found
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
        simp [NullablePersistentLocal]) _
        invariant.appendFrame.stateCapacityLocal
      stateCountLocal := preserveLocal 18 (by
        simp [NullablePersistentLocal]) _
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
    positionLocal := preserveLocal 23 (by
      simp [NullablePersistentLocal]) _ invariant.positionLocal
    parentStateLocal := preserveLocal 24 (by
      simp [NullablePersistentLocal]) _
      invariant.parentStateLocal
    parentProductionLocal := preserveLocal 25 (by
      simp [NullablePersistentLocal]) _
      invariant.parentProductionLocal
    parentDotLocal := preserveLocal 26 (by
      simp [NullablePersistentLocal]) _ invariant.parentDotLocal
    parentOriginLocal := preserveLocal 27 (by
      simp [NullablePersistentLocal]) _
      invariant.parentOriginLocal
    expectedLocal := preserveLocal 30 (by
      simp [NullablePersistentLocal]) _ invariant.expectedLocal
    parentProductionBound := invariant.parentProductionBound
    parentDotBeforeEnd := invariant.parentDotBeforeEnd
    dotSuccI32 := invariant.dotSuccI32
    parentOriginBound := invariant.parentOriginBound
    parentSymbolFound := invariant.parentSymbolFound
    parentAdvanceSound := invariant.parentAdvanceSound
    parentStored := invariant.parentStored
    persistentSeparate := by
      unfold NullableFrameSeparated
      rw [effect.localBindingFrameFootprint_eq
        verifiedParserNullableLoopPreservedBindings]
      exact invariant.persistentSeparate
    cursorStateCountDistinct := invariant.cursorStateCountDistinct
  }

theorem RecognizerNullableLoopInvariant.append_invariant
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining) :
    RecognizerNullableAppendInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell runtime position parentProduction parentDot
      parentOrigin parentState current := {
  frame := invariant.appendFrame
  productionBound := invariant.parentProductionBound
  advanceSound := invariant.parentAdvanceSound
  dotSuccI32 := invariant.dotSuccI32
  originBound := invariant.parentOriginBound
  positionLocal := invariant.positionLocal
  stateIdLocal := invariant.parentStateLocal
  productionLocal := invariant.parentProductionLocal
  dotLocal := invariant.parentDotLocal
  originLocal := invariant.parentOriginLocal
  candidateLocal := Assertion.localPointsTo_local 36 cursorCell _ runtime
    invariant.chartCursor.cursorOwned
}

/-- Reframe a successful nullable append as the next logical workspace while
    retaining a supplied cursor for the possibly extended chart. -/
def RecognizerNullableLoopInvariant.after_ok_append
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (appended : RecognizerNullableOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell before position parentProduction parentDot
      parentOrigin parentState current invariant.append_invariant)
    (newRemaining : List Nat)
    (cursor : ChartCursor
      ((appendLogical workspaceLayout.capacity position
        (recognizerNullableSeed parentProduction parentDot parentOrigin
          parentState current) workspace).2.chart position)
      current newRemaining)
    (within : WorkspaceWithinGrammar grammar
      (appendLogical workspaceLayout.capacity position
        (recognizerNullableSeed parentProduction parentDot parentOrigin
          parentState current) workspace).2) :
    RecognizerNullableLoopInvariant grammarLayout grammar words tokens
      workspaceLayout
      (appendLogical workspaceLayout.capacity position
        (recognizerNullableSeed parentProduction parentDot parentOrigin
          parentState current) workspace).2
      (appendResultValues workspaceLayout workspace position
        (recognizerNullableSeed parentProduction parentDot parentOrigin
          parentState current) workspaceValues)
      grammarCell tokensCell workspaceCell stateCountCell cursorCell
      appended.after position parentProduction parentDot parentOrigin
      parentState expected current newRemaining := by
  let nextWorkspace := (appendLogical workspaceLayout.capacity position
    (recognizerNullableSeed parentProduction parentDot parentOrigin
      parentState current) workspace).2
  let nextValues := appendResultValues workspaceLayout workspace position
    (recognizerNullableSeed parentProduction parentDot parentOrigin
      parentState current) workspaceValues
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.singleton stateCountCell)
  have writesMutable : CellSet.Subset writes
      (nullableFrameMutableCells workspaceCell stateCountCell cursorCell) := by
    intro cell written
    exact written.elim Or.inl (fun count => Or.inr (Or.inl count))
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        verifiedParserNullableLoopPreservedBindings) writes :=
    CellSet.Disjoint.mono_right writesMutable invariant.persistentSeparate
  have preserveLocal (id : VarId) (persistent : NullablePersistentLocal id)
      (notStateCount : id ≠ 18) (value : Value)
      (found : before.local? id = some value) :
      appended.after.local? id = some value :=
    appended.effect.preserves_local_of_disjoint
      invariant.chartCursor.recognizer.wellFormed frameDisjoint
      ((NullablePreservedLocal_source_frame id).mp
        ((NullablePreservedLocal_iff id).mpr
          ⟨persistent, notStateCount⟩)) found
  have cursorOwned : (Assertion.localPointsTo 36 cursorCell
      (some (.signed .i32 (Int.ofNat current)))).holds appended.after :=
    appended.effect.preserve invariant.chartCursor.recognizer.wellFormed
      (Assertion.localPointsTo 36 cursorCell
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
      tokensCell workspaceCell cursorCell appended.after position 36 current
      newRemaining := {
    recognizer := by simpa [nextWorkspace, nextValues] using appended.invariant
    workspaceWithinGrammar := by simpa [nextWorkspace] using within
    stateBaseLocal := preserveLocal 8 (by
      simp [NullablePersistentLocal]) (by decide) _
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
        simp [NullablePersistentLocal]) (by decide) _
        invariant.appendFrame.stateCapacityLocal
      stateCountLocal := Assertion.localPointsTo_local 18 stateCountCell _
        appended.after appended.stateCountOwned
      stateCountOwned := by simpa [nextWorkspace] using appended.stateCountOwned
      stateCountBackingDistinct := invariant.appendFrame.stateCountBackingDistinct
      stateCountParameterSeparate := by
        unfold RecognizerParameterFrameSeparated
        rw [appended.effect.localBindingFrameFootprint_eq
          verifiedParserRecognizerParameterFrame]
        exact invariant.appendFrame.stateCountParameterSeparate
    }
    positionLocal := preserveLocal 23 (by
      simp [NullablePersistentLocal]) (by decide) _
      invariant.positionLocal
    parentStateLocal := preserveLocal 24 (by
      simp [NullablePersistentLocal]) (by decide) _
      invariant.parentStateLocal
    parentProductionLocal := preserveLocal 25 (by
      simp [NullablePersistentLocal]) (by decide) _
      invariant.parentProductionLocal
    parentDotLocal := preserveLocal 26 (by
      simp [NullablePersistentLocal]) (by decide) _
      invariant.parentDotLocal
    parentOriginLocal := preserveLocal 27 (by
      simp [NullablePersistentLocal]) (by decide) _
      invariant.parentOriginLocal
    expectedLocal := preserveLocal 30 (by
      simp [NullablePersistentLocal]) (by decide) _
      invariant.expectedLocal
    parentProductionBound := invariant.parentProductionBound
    parentDotBeforeEnd := invariant.parentDotBeforeEnd
    dotSuccI32 := invariant.dotSuccI32
    parentOriginBound := invariant.parentOriginBound
    parentSymbolFound := invariant.parentSymbolFound
    parentAdvanceSound := invariant.parentAdvanceSound
    parentStored := invariant.parentStored.transfer (by
      let appendRefinement := appendLogical_refines
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace) rfl
      exact (appendRefinement.preserves_existing_states
        (List.getElem?_eq_some_iff.mp invariant.parentStored.found |>.1)).trans
          invariant.parentStored.found)
    persistentSeparate := by
      unfold NullableFrameSeparated
      rw [appended.effect.localBindingFrameFootprint_eq
        verifiedParserNullableLoopPreservedBindings]
      exact invariant.persistentSeparate
    cursorStateCountDistinct := invariant.cursorStateCountDistinct
  }

inductive RecognizerNullableOkAppendCursor
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position parentProduction parentDot parentOrigin parentState
      expected current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerNullableLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (appended : RecognizerNullableOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell before position parentProduction parentDot
      parentOrigin parentState current beforeInvariant.append_invariant) : Type
  | unchanged
      (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
        tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2
        (appendResultValues workspaceLayout workspace position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell
        appended.after position parentProduction parentDot parentOrigin
        parentState expected current remaining)
      (countUnchanged :
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2.states.length =
          workspace.states.length) :
      RecognizerNullableOkAppendCursor grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position
        parentProduction parentDot parentOrigin parentState expected current
        remaining beforeInvariant appended
  | extended
      (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
        tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2
        (appendResultValues workspaceLayout workspace position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell
        appended.after position parentProduction parentDot parentOrigin
        parentState expected current
        (remaining ++ [workspace.states.length]))
      (countIncreased :
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2.states.length =
          workspace.states.length + 1) :
      RecognizerNullableOkAppendCursor grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position
        parentProduction parentDot parentOrigin parentState expected current
        remaining beforeInvariant appended

/-- Classify a successful append by its only two possible effects on the
    currently traversed chart: no change, or one newly allocated tail state. -/
noncomputable def RecognizerNullableLoopInvariant.classify_ok_append
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (appended : RecognizerNullableOkResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell before position parentProduction parentDot
      parentOrigin parentState current invariant.append_invariant) :
    RecognizerNullableOkAppendCursor grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position parentProduction
      parentDot parentOrigin parentState expected current remaining invariant
      appended := by
  let seed := recognizerNullableSeed parentProduction parentDot parentOrigin
    parentState current
  let logical := appendLogical workspaceLayout.capacity position seed workspace
  have relation : Append workspaceLayout.capacity position seed workspace
      logical.1 logical.2 := appendLogical_refines logical rfl
  have within : WorkspaceWithinGrammar grammar logical.2 :=
    relation.preserves_withinGrammar invariant.chartCursor.workspaceWithinGrammar
      (by simpa [seed] using invariant.seed_within_grammar current)
  cases transportAppendLogicalCursor workspaceLayout.capacity position seed
      workspace invariant.chartCursor.cursor with
  | inl unchanged =>
    exact .unchanged (invariant.after_ok_append appended remaining (by
      simpa [logical, seed] using unchanged.cursor) (by
      simpa [logical] using within)) (by
      simpa [logical, seed] using unchanged.countUnchanged)
  | inr extended =>
    exact .extended (invariant.after_ok_append appended
      (remaining ++ [workspace.states.length]) (by
        simpa [logical, seed] using extended.1) (by
        simpa [logical] using within)) (by
      simpa [logical] using extended.2)

/-- Concrete trace of the three extracted `state_value` bindings at the head
    of one nullable-loop iteration.  Intermediate states are retained because
    the Core semantics evaluates each initializer before entering its lexical
    local scope. -/
structure RecognizerNullableCandidateBindings
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position parentProduction parentDot parentOrigin parentState
      expected current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerNullableLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (candidateState : EarleyState)
    (found : workspace.state? current = some candidateState) where
  afterProductionRead : State
  productionEvaluation : Evaluates verifiedParserCore before
    (parserRecognizeStateValueCall 36 28)
    (.signed .i32 (Int.ofNat candidateState.production)) afterProductionRead
  productionEffect : ModifiesOnly CellSet.empty before afterProductionRead
  afterProductionWellFormed : StateWellFormed afterProductionRead
  afterDotRead : State
  dotEvaluation : Evaluates verifiedParserCore
    (afterProductionRead.bindLocal 37
      (.signed .i32 (Int.ofNat candidateState.production)))
    (parserRecognizeStateValueCall 36 29)
    (.signed .i32 (Int.ofNat candidateState.dot)) afterDotRead
  dotEffect : ModifiesOnly CellSet.empty
    (afterProductionRead.bindLocal 37
      (.signed .i32 (Int.ofNat candidateState.production))) afterDotRead
  afterDotWellFormed : StateWellFormed afterDotRead
  afterOriginRead : State
  originEvaluation : Evaluates verifiedParserCore
    (afterDotRead.bindLocal 38
      (.signed .i32 (Int.ofNat candidateState.dot)))
    (parserRecognizeStateValueCall 36 30)
    (.signed .i32 (Int.ofNat candidateState.origin)) afterOriginRead
  originEffect : ModifiesOnly CellSet.empty
    (afterDotRead.bindLocal 38
      (.signed .i32 (Int.ofNat candidateState.dot))) afterOriginRead
  afterOriginWellFormed : StateWellFormed afterOriginRead
  invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell
    (afterOriginRead.bindLocal 39
      (.signed .i32 (Int.ofNat candidateState.origin)))
    position parentProduction parentDot parentOrigin parentState expected
    current remaining
  productionLocal :
    (afterOriginRead.bindLocal 39
      (.signed .i32 (Int.ofNat candidateState.origin))).local? 37 =
      some (.signed .i32 (Int.ofNat candidateState.production))
  dotLocal :
    (afterOriginRead.bindLocal 39
      (.signed .i32 (Int.ofNat candidateState.origin))).local? 38 =
      some (.signed .i32 (Int.ofNat candidateState.dot))
  originLocal :
    (afterOriginRead.bindLocal 39
      (.signed .i32 (Int.ofNat candidateState.origin))).local? 39 =
      some (.signed .i32 (Int.ofNat candidateState.origin))

/-- Execute and bind the candidate's production, dot, and origin fields
    exactly as they occur in the extracted nullable-loop body. -/
noncomputable def RecognizerNullableLoopInvariant.bind_candidate_fields
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (candidateState : EarleyState)
    (found : workspace.state? current = some candidateState) :
    RecognizerNullableCandidateBindings grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining invariant candidateState found := by
  let productionRead := invariant.chartCursor.read_production candidateState
    found
  have productionEvaluation : Evaluates verifiedParserCore runtime
      (parserRecognizeStateValueCall 36 28)
      (.signed .i32 (Int.ofNat candidateState.production))
      productionRead.after := by
    simpa [stateFieldValue] using productionRead.evaluation
  let afterProduction := invariant.after_empty_effect productionRead.effect
    productionRead.invariant.recognizer.wellFormed
  let productionScope := productionRead.after.bindLocal 37
    (.signed .i32 (Int.ofNat candidateState.production))
  let productionInvariant := afterProduction.after_bind_local 37
    (.signed .i32 (Int.ofNat candidateState.production)) (by decide)
  let dotRead := productionInvariant.chartCursor.read_dot candidateState found
  have dotEvaluation : Evaluates verifiedParserCore productionScope
      (parserRecognizeStateValueCall 36 29)
      (.signed .i32 (Int.ofNat candidateState.dot)) dotRead.after := by
    simpa [productionScope, productionInvariant, stateFieldValue] using
      dotRead.evaluation
  let afterDot := productionInvariant.after_empty_effect dotRead.effect
    dotRead.invariant.recognizer.wellFormed
  let dotScope := dotRead.after.bindLocal 38
    (.signed .i32 (Int.ofNat candidateState.dot))
  let dotInvariant := afterDot.after_bind_local 38
    (.signed .i32 (Int.ofNat candidateState.dot)) (by decide)
  let originRead := dotInvariant.chartCursor.read_origin candidateState found
  have originEvaluation : Evaluates verifiedParserCore dotScope
      (parserRecognizeStateValueCall 36 30)
      (.signed .i32 (Int.ofNat candidateState.origin)) originRead.after := by
    simpa [dotScope, dotInvariant, stateFieldValue] using originRead.evaluation
  let afterOrigin := dotInvariant.after_empty_effect originRead.effect
    originRead.invariant.recognizer.wellFormed
  let originScope := originRead.after.bindLocal 39
    (.signed .i32 (Int.ofNat candidateState.origin))
  let originInvariant := afterOrigin.after_bind_local 39
    (.signed .i32 (Int.ofNat candidateState.origin)) (by decide)
  have productionAtProductionScope : productionScope.local? 37 =
      some (.signed .i32 (Int.ofNat candidateState.production)) := by
    simpa [productionScope] using bindLocal_finds_local productionRead.after 37
      (.signed .i32 (Int.ofNat candidateState.production))
      productionRead.invariant.recognizer.wellFormed
  have productionAtDotRead : dotRead.after.local? 37 =
      some (.signed .i32 (Int.ofNat candidateState.production)) :=
    dotRead.effect.empty_preserves_local
      productionInvariant.chartCursor.recognizer.wellFormed
      productionAtProductionScope
  have productionAtDotScope : dotScope.local? 37 =
      some (.signed .i32 (Int.ofNat candidateState.production)) := by
    exact (bindLocal_preserves_other_local
      dotRead.invariant.recognizer.wellFormed (by decide : 38 ≠ 37)).trans
      productionAtDotRead
  have dotAtDotScope : dotScope.local? 38 =
      some (.signed .i32 (Int.ofNat candidateState.dot)) := by
    simpa [dotScope] using bindLocal_finds_local dotRead.after 38
      (.signed .i32 (Int.ofNat candidateState.dot))
      dotRead.invariant.recognizer.wellFormed
  have productionAtOriginRead : originRead.after.local? 37 =
      some (.signed .i32 (Int.ofNat candidateState.production)) :=
    originRead.effect.empty_preserves_local
      dotInvariant.chartCursor.recognizer.wellFormed productionAtDotScope
  have dotAtOriginRead : originRead.after.local? 38 =
      some (.signed .i32 (Int.ofNat candidateState.dot)) :=
    originRead.effect.empty_preserves_local
      dotInvariant.chartCursor.recognizer.wellFormed dotAtDotScope
  exact {
    afterProductionRead := productionRead.after
    productionEvaluation := productionEvaluation
    productionEffect := productionRead.effect
    afterProductionWellFormed :=
      productionRead.invariant.recognizer.wellFormed
    afterDotRead := dotRead.after
    dotEvaluation := dotEvaluation
    dotEffect := by simpa [productionScope, productionInvariant] using
      dotRead.effect
    afterDotWellFormed := dotRead.invariant.recognizer.wellFormed
    afterOriginRead := originRead.after
    originEvaluation := originEvaluation
    originEffect := by simpa [dotScope, dotInvariant] using originRead.effect
    afterOriginWellFormed := originRead.invariant.recognizer.wellFormed
    invariant := by simpa [originScope] using originInvariant
    productionLocal := by
      exact (bindLocal_preserves_other_local
        originRead.invariant.recognizer.wellFormed
        (by decide : 39 ≠ 37)).trans productionAtOriginRead
    dotLocal := by
      exact (bindLocal_preserves_other_local
        originRead.invariant.recognizer.wellFormed
        (by decide : 39 ≠ 38)).trans dotAtOriginRead
    originLocal := by
      simpa using bindLocal_finds_local originRead.after 39
        (.signed .i32 (Int.ofNat candidateState.origin))
        originRead.invariant.recognizer.wellFormed
  }

/-- Close the three artifact-derived candidate-field scopes around an inner
    nullable action.  This is the separation-logic boundary that turns an
    execution in the temporary-local state back into an execution of the
    actual loop body, with exactly the inner action's write footprint. -/
structure RecognizerNullableScopedExecution
    (before innerAfter : State) (completion : Completion)
    (writes : CellSet)
    (candidate : EarleyState)
    (beforeInvariant : RecognizerNullableLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (found : workspace.state? current = some candidate)
    (bindings : RecognizerNullableCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining beforeInvariant candidate found) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeNullableLoopBody completion after
  effect : ModifiesOnly writes before after
  wellFormed : StateWellFormed after
  cells : after.cells = innerAfter.cells

noncomputable def RecognizerNullableCandidateBindings.close_scopes
    (bindings : RecognizerNullableCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining beforeInvariant candidate found)
    (innerAfter : State) (completion : Completion) (writes : CellSet)
    (innerExecution : Executes verifiedParserCore
      (bindings.afterOriginRead.bindLocal 39
        (.signed .i32 (Int.ofNat candidate.origin)))
      parserRecognizeNullableAfterBindings completion innerAfter)
    (innerEffect : ModifiesOnly writes
      (bindings.afterOriginRead.bindLocal 39
        (.signed .i32 (Int.ofNat candidate.origin))) innerAfter)
    (innerWellFormed : StateWellFormed innerAfter) :
    RecognizerNullableScopedExecution runtime innerAfter completion writes
      candidate beforeInvariant found bindings := by
  let productionScope := bindings.afterProductionRead.bindLocal 37
    (.signed .i32 (Int.ofNat candidate.production))
  let dotScope := bindings.afterDotRead.bindLocal 38
    (.signed .i32 (Int.ofNat candidate.dot))
  let originScope := bindings.afterOriginRead.bindLocal 39
    (.signed .i32 (Int.ofNat candidate.origin))
  let afterOrigin := restoreLocals bindings.afterOriginRead innerAfter
  let afterDot := restoreLocals bindings.afterDotRead afterOrigin
  let afterProduction := restoreLocals bindings.afterProductionRead afterDot
  have enteredOrigin : StoreEffect CellSet.empty bindings.afterOriginRead
      originScope := by
    simpa [originScope] using bindLocal_effect bindings.afterOriginRead 39
      (.signed .i32 (Int.ofNat candidate.origin))
  have originScopeEffect : StoreEffect writes bindings.afterOriginRead
      innerAfter :=
    (enteredOrigin.weaken CellSet.empty_subset).trans_same
      innerEffect.toStoreEffect
  have closedOrigin : ModifiesOnly writes bindings.afterOriginRead
      afterOrigin := by
    simpa [afterOrigin] using originScopeEffect.restoreLocals
  have afterOriginWellFormed : StateWellFormed afterOrigin :=
    originScopeEffect.restoreLocals_wellFormed
      bindings.afterOriginWellFormed innerWellFormed
  have originBodyEffect : ModifiesOnly writes dotScope afterOrigin :=
    (bindings.originEffect.weaken CellSet.empty_subset).trans_same closedOrigin
  have enteredDot : StoreEffect CellSet.empty bindings.afterDotRead
      dotScope := by
    simpa [dotScope] using bindLocal_effect bindings.afterDotRead 38
      (.signed .i32 (Int.ofNat candidate.dot))
  have dotScopeEffect : StoreEffect writes bindings.afterDotRead afterOrigin :=
    (enteredDot.weaken CellSet.empty_subset).trans_same
      originBodyEffect.toStoreEffect
  have closedDot : ModifiesOnly writes bindings.afterDotRead afterDot := by
    simpa [afterDot] using dotScopeEffect.restoreLocals
  have afterDotWellFormed : StateWellFormed afterDot :=
    dotScopeEffect.restoreLocals_wellFormed
      bindings.afterDotWellFormed
      afterOriginWellFormed
  have dotBodyEffect : ModifiesOnly writes productionScope afterDot :=
    (bindings.dotEffect.weaken CellSet.empty_subset).trans_same closedDot
  have enteredProduction : StoreEffect CellSet.empty
      bindings.afterProductionRead productionScope := by
    simpa [productionScope] using
      bindLocal_effect bindings.afterProductionRead 37
        (.signed .i32 (Int.ofNat candidate.production))
  have productionScopeEffect : StoreEffect writes
      bindings.afterProductionRead afterDot :=
    (enteredProduction.weaken CellSet.empty_subset).trans_same
      dotBodyEffect.toStoreEffect
  have closedProduction : ModifiesOnly writes bindings.afterProductionRead
      afterProduction := by
    simpa [afterProduction] using productionScopeEffect.restoreLocals
  have afterProductionWellFormed : StateWellFormed afterProduction :=
    productionScopeEffect.restoreLocals_wellFormed
      bindings.afterProductionWellFormed
      afterDotWellFormed
  have outerEffect : ModifiesOnly writes runtime afterProduction :=
    (bindings.productionEffect.weaken CellSet.empty_subset).trans_same
      closedProduction
  have originExecution : Executes verifiedParserCore dotScope
      (.letLocal 39 parserI32Type (parserRecognizeStateValueCall 36 30)
        parserRecognizeNullableAfterBindings) completion afterOrigin := by
    simpa [dotScope, originScope, afterOrigin] using
      executesLetLocal (type := parserI32Type) bindings.originEvaluation
        innerExecution
  have dotExecution : Executes verifiedParserCore productionScope
      (.letLocal 38 parserI32Type (parserRecognizeStateValueCall 36 29)
        (.letLocal 39 parserI32Type (parserRecognizeStateValueCall 36 30)
          parserRecognizeNullableAfterBindings)) completion afterDot := by
    simpa [productionScope, dotScope, afterDot] using
      executesLetLocal (type := parserI32Type) bindings.dotEvaluation
        originExecution
  have productionExecution : Executes verifiedParserCore runtime
      (.letLocal 37 parserI32Type (parserRecognizeStateValueCall 36 28)
        (.letLocal 38 parserI32Type (parserRecognizeStateValueCall 36 29)
          (.letLocal 39 parserI32Type (parserRecognizeStateValueCall 36 30)
            parserRecognizeNullableAfterBindings))) completion
      afterProduction := by
    simpa [productionScope, afterProduction] using
      executesLetLocal (type := parserI32Type) bindings.productionEvaluation
        dotExecution
  exact {
    after := afterProduction
    execution := by
      rw [extractedParserRecognize_nullable_body_shape]
      exact productionExecution
    effect := outerEffect
    wellFormed := afterProductionWellFormed
    cells := by
      simp [afterProduction, afterDot, afterOrigin, restoreLocals]
  }

/-- Closing candidate-field scopes restores the caller's persistent local
    environment while retaining the cells produced by the inner action.  If
    that action only mutates the workspace, state-count, or cursor cells, its
    semantic nullable invariant therefore survives scope exit exactly. -/
def RecognizerNullableScopedExecution.restore_invariant
    (closed : RecognizerNullableScopedExecution
      (grammarLayout := grammarLayout) (grammar := grammar) (words := words)
      (tokens := tokens) (workspaceLayout := workspaceLayout)
      (workspace := workspace) (workspaceValues := workspaceValues)
      (grammarCell := grammarCell) (tokensCell := tokensCell)
      (workspaceCell := workspaceCell) (stateCountCell := stateCountCell)
      (cursorCell := cursorCell) (position := position)
      (parentProduction := parentProduction) (parentDot := parentDot)
      (parentOrigin := parentOrigin) (parentState := parentState)
      (expected := expected) (current := current) (remaining := remaining)
      runtime innerAfter completion writes candidate beforeInvariant found
      bindings)
    (innerInvariant : RecognizerNullableLoopInvariant grammarLayout grammar
      words tokens workspaceLayout nextWorkspace nextWorkspaceValues
      grammarCell tokensCell workspaceCell stateCountCell cursorCell innerAfter
      position parentProduction parentDot parentOrigin parentState expected
      nextCurrent nextRemaining)
    (writesMutable : CellSet.Subset writes
      (CellSet.union (CellSet.singleton workspaceCell)
        (CellSet.union (CellSet.singleton stateCountCell)
          (CellSet.singleton cursorCell)))) :
    RecognizerNullableLoopInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextWorkspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell closed.after position
      parentProduction parentDot parentOrigin parentState expected nextCurrent
      nextRemaining := by
  have preserveLocal (id : VarId) (persistent : NullablePersistentLocal id)
      (notStateCount : id ≠ 18) (value : Value)
      (foundLocal : runtime.local? id = some value) :
      closed.after.local? id = some value :=
    closed.effect.preserves_local_of_disjoint
      beforeInvariant.chartCursor.recognizer.wellFormed
      (CellSet.Disjoint.mono_right writesMutable
        beforeInvariant.persistentSeparate)
      ((NullablePreservedLocal_source_frame id).mp
        ((NullablePreservedLocal_iff id).mpr
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
  have cursorOwned : (Assertion.localPointsTo 36 cursorCell
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
    grammarWellFormed :=
      innerInvariant.chartCursor.recognizer.grammarWellFormed
    wordsI32 := innerInvariant.chartCursor.recognizer.wordsI32
    tokensI32 := innerInvariant.chartCursor.recognizer.tokensI32
    workspaceLength :=
      innerInvariant.chartCursor.recognizer.workspaceLength
    workspaceTokenCount :=
      innerInvariant.chartCursor.recognizer.workspaceTokenCount
    workspaceEncoded :=
      innerInvariant.chartCursor.recognizer.workspaceEncoded
    derivations := innerInvariant.chartCursor.recognizer.derivations
    wellFormed := closed.wellFormed
    grammarLocal := preserveLocal 0 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.grammarLocal
    grammarLengthLocal := preserveLocal 1 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.grammarLengthLocal
    tokensLocal := preserveLocal 2 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.tokensLocal
    tokenCountLocal := preserveLocal 3 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.tokenCountLocal
    workspaceLocal := by
      have preserved := preserveLocal 4 (by
        simp [NullablePersistentLocal]) (by decide) _
        beforeInvariant.chartCursor.recognizer.workspaceLocal
      simpa [workspaceValue,
        beforeInvariant.chartCursor.recognizer.workspaceLength,
        innerInvariant.chartCursor.recognizer.workspaceLength] using preserved
    workspaceLengthLocal := by
      have preserved := preserveLocal 5 (by
        simp [NullablePersistentLocal]) (by decide) _
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
        simp [NullablePersistentLocal]) (by decide) _
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
        simp [NullablePersistentLocal]) (by decide) _
        beforeInvariant.appendFrame.stateBaseLocal
      stateCapacityLocal := preserveLocal 9 (by
        simp [NullablePersistentLocal]) (by decide) _
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
    positionLocal := preserveLocal 23 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.positionLocal
    parentStateLocal := preserveLocal 24 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.parentStateLocal
    parentProductionLocal := preserveLocal 25 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.parentProductionLocal
    parentDotLocal := preserveLocal 26 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.parentDotLocal
    parentOriginLocal := preserveLocal 27 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.parentOriginLocal
    expectedLocal := preserveLocal 30 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.expectedLocal
    parentProductionBound := beforeInvariant.parentProductionBound
    parentDotBeforeEnd := beforeInvariant.parentDotBeforeEnd
    dotSuccI32 := beforeInvariant.dotSuccI32
    parentOriginBound := beforeInvariant.parentOriginBound
    parentSymbolFound := beforeInvariant.parentSymbolFound
    parentAdvanceSound := beforeInvariant.parentAdvanceSound
    parentStored := innerInvariant.parentStored
    persistentSeparate := by
      unfold NullableFrameSeparated
      rw [closed.effect.localBindingFrameFootprint_eq
        verifiedParserNullableLoopPreservedBindings]
      exact beforeInvariant.persistentSeparate
    cursorStateCountDistinct := beforeInvariant.cursorStateCountDistinct
  }

/-- Terminal counterpart of `restore_invariant`: retain an updated logical
    workspace and the `-1` cursor while restoring the caller's persistent
    locals after candidate-field scopes close. -/
def RecognizerNullableScopedExecution.restore_finished
    (closed : RecognizerNullableScopedExecution
      (grammarLayout := grammarLayout) (grammar := grammar) (words := words)
      (tokens := tokens) (workspaceLayout := workspaceLayout)
      (workspace := workspace) (workspaceValues := workspaceValues)
      (grammarCell := grammarCell) (tokensCell := tokensCell)
      (workspaceCell := workspaceCell) (stateCountCell := stateCountCell)
      (cursorCell := cursorCell) (position := position)
      (parentProduction := parentProduction) (parentDot := parentDot)
      (parentOrigin := parentOrigin) (parentState := parentState)
      (expected := expected) (current := current) (remaining := remaining)
      runtime innerAfter completion writes candidate beforeInvariant found
      bindings)
    (innerInvariant : RecognizerNullableFinishedInvariant grammarLayout grammar
      words tokens workspaceLayout nextWorkspace nextWorkspaceValues
      grammarCell tokensCell workspaceCell stateCountCell cursorCell innerAfter
      position parentProduction parentDot parentOrigin parentState expected)
    (writesMutable : CellSet.Subset writes
      (CellSet.union (CellSet.singleton workspaceCell)
        (CellSet.union (CellSet.singleton stateCountCell)
          (CellSet.singleton cursorCell)))) :
    RecognizerNullableFinishedInvariant grammarLayout grammar words tokens
      workspaceLayout nextWorkspace nextWorkspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell closed.after position
      parentProduction parentDot parentOrigin parentState expected := by
  have preserveLocal (id : VarId) (persistent : NullablePersistentLocal id)
      (notStateCount : id ≠ 18) (value : Value)
      (foundLocal : runtime.local? id = some value) :
      closed.after.local? id = some value :=
    closed.effect.preserves_local_of_disjoint
      beforeInvariant.chartCursor.recognizer.wellFormed
      (CellSet.Disjoint.mono_right writesMutable
        beforeInvariant.persistentSeparate)
      ((NullablePreservedLocal_source_frame id).mp
        ((NullablePreservedLocal_iff id).mpr
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
  have cursorOwned : (Assertion.localPointsTo 36 cursorCell
      (some (.signed .i32 (-1)))).holds closed.after := by
    constructor
    · unfold State.cellId?
      rw [closed.effect.locals]
      exact beforeInvariant.chartCursor.cursorOwned.1
    · exact entryTransferred cursorCell _ innerInvariant.chartCursor.cursorOwned.2
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
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.grammarLocal
    grammarLengthLocal := preserveLocal 1 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.grammarLengthLocal
    tokensLocal := preserveLocal 2 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.tokensLocal
    tokenCountLocal := preserveLocal 3 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.chartCursor.recognizer.tokenCountLocal
    workspaceLocal := by
      have preserved := preserveLocal 4 (by
        simp [NullablePersistentLocal]) (by decide) _
        beforeInvariant.chartCursor.recognizer.workspaceLocal
      simpa [workspaceValue,
        beforeInvariant.chartCursor.recognizer.workspaceLength,
        innerInvariant.chartCursor.recognizer.workspaceLength] using preserved
    workspaceLengthLocal := by
      have preserved := preserveLocal 5 (by
        simp [NullablePersistentLocal]) (by decide) _
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
        simp [NullablePersistentLocal]) (by decide) _
        beforeInvariant.chartCursor.stateBaseLocal
      cursorOwned := cursorOwned
      cursorFrameSeparate := by
        unfold ChartCursorFrameSeparated
        rw [closed.effect.localBindingFrameFootprint_eq
          verifiedParserChartCursorBindings]
        exact beforeInvariant.chartCursor.cursorFrameSeparate
      cursorBackingDistinct := beforeInvariant.chartCursor.cursorBackingDistinct
      chartPositionBound := innerInvariant.chartCursor.chartPositionBound
    }
    appendFrame := {
      recognizer := recognizer
      positionBound := innerInvariant.appendFrame.positionBound
      stateBaseLocal := preserveLocal 8 (by
        simp [NullablePersistentLocal]) (by decide) _
        beforeInvariant.appendFrame.stateBaseLocal
      stateCapacityLocal := preserveLocal 9 (by
        simp [NullablePersistentLocal]) (by decide) _
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
    positionLocal := preserveLocal 23 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.positionLocal
    parentStateLocal := preserveLocal 24 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.parentStateLocal
    parentProductionLocal := preserveLocal 25 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.parentProductionLocal
    parentDotLocal := preserveLocal 26 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.parentDotLocal
    parentOriginLocal := preserveLocal 27 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.parentOriginLocal
    expectedLocal := preserveLocal 30 (by
      simp [NullablePersistentLocal]) (by decide) _
      beforeInvariant.expectedLocal
    parentProductionBound := beforeInvariant.parentProductionBound
    parentDotBeforeEnd := beforeInvariant.parentDotBeforeEnd
    dotSuccI32 := beforeInvariant.dotSuccI32
    parentOriginBound := beforeInvariant.parentOriginBound
    parentSymbolFound := beforeInvariant.parentSymbolFound
    parentAdvanceSound := beforeInvariant.parentAdvanceSound
    parentStored := innerInvariant.parentStored
    persistentSeparate := by
      unfold NullableFrameSeparated
      rw [closed.effect.localBindingFrameFootprint_eq
        verifiedParserNullableLoopPreservedBindings]
      exact beforeInvariant.persistentSeparate
    cursorStateCountDistinct := beforeInvariant.cursorStateCountDistinct
  }

def NullableCandidateMatches
    (grammar : IndexedGrammar) (candidate : EarleyState)
    (position expected : Nat)
    (productionBound : candidate.key.production < grammar.productionCount) : Prop :=
  candidate.origin = position ∧
    candidate.dot =
      (grammar.productionAt ⟨candidate.production, by
        simpa [EarleyState.key] using productionBound⟩).rhs.length ∧
    (grammar.productionAt ⟨candidate.production, by
      simpa [EarleyState.key] using productionBound⟩).lhs =
      expected

instance nullableCandidateMatchesDecidable
    (grammar : IndexedGrammar) (candidate : EarleyState)
    (position expected : Nat)
    (productionBound : candidate.key.production < grammar.productionCount) :
    Decidable (NullableCandidateMatches grammar candidate position expected
      productionBound) := by
  unfold NullableCandidateMatches
  infer_instance

/-- The predicate from the mechanically reified nullable body evaluates to
    the logical nullable-candidate relation.  In particular, its two grammar
    accessor calls execute through the traversal registry in the same
    short-circuit order as the source expression. -/
private theorem RecognizerNullableLoopInvariant.functional_predicate
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (candidate : EarleyState)
    (candidateWithin : StateKeyWithinGrammar grammar candidate.key) :
    let world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let environment := nullableEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length position
      parentState parentProduction parentDot parentOrigin expected
      (Int.ofNat current)
    let productionEnvironment := environment.push
      (.signed .i32 (Int.ofNat candidate.production))
    let dotEnvironment := productionEnvironment.push
      (.signed .i32 (Int.ofNat candidate.dot))
    let originEnvironment := dotEnvironment.push
      (.signed .i32 (Int.ofNat candidate.origin))
    Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world originEnvironment nullableCandidatePredicate =
      .ok (.boolean (decide (NullableCandidateMatches grammar candidate
        position expected candidateWithin.productionBound)), world) := by
  dsimp only
  let world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let environment := nullableEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length position parentState
    parentProduction parentDot parentOrigin expected (Int.ofNat current)
  let productionEnvironment := environment.push
    (.signed .i32 (Int.ofNat candidate.production))
  let dotEnvironment := productionEnvironment.push
    (.signed .i32 (Int.ofNat candidate.dot))
  let originEnvironment := dotEnvironment.push
    (.signed .i32 (Int.ofNat candidate.origin))
  have productionBound : candidate.production < grammar.productionCount := by
    simpa [EarleyState.key] using candidateWithin.productionBound
  have originResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world originEnvironment (nullableSlot ⟨14, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat candidate.origin), world) := by rfl
  have positionResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world originEnvironment (nullableSlot ⟨5, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat position), world) := by rfl
  have dotResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world originEnvironment (nullableSlot ⟨13, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat candidate.dot), world) := by rfl
  have rhsLengthResult := nullableRhsLengthTerm_evaluates
    (tokens := tokens) (tokensCell := tokensCell) workspaceLayout
    grammar words workspaceValues grammarCell workspaceCell originEnvironment
    candidate.production productionBound (by rfl) (by rfl)
  have lhsResult := nullableLhsTerm_evaluates
    (tokens := tokens) (tokensCell := tokensCell) workspaceLayout grammar words
    workspaceValues grammarCell workspaceCell originEnvironment
    candidate.production productionBound (by rfl) (by rfl)
  have expectedResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world originEnvironment (nullableSlot ⟨10, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat expected), world) := by rfl
  have originMatch := nullableEqual_evaluates workspaceLayout grammar words
    grammarCell world originEnvironment _ _ candidate.origin position
    originResult positionResult
  have dotMatch := nullableEqual_evaluates workspaceLayout grammar words
    grammarCell world originEnvironment _ _ candidate.dot
    (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length
    dotResult rhsLengthResult
  have lhsMatch := nullableEqual_evaluates workspaceLayout grammar words
    grammarCell world originEnvironment _ _
    (grammar.productionAt ⟨candidate.production, productionBound⟩).lhs expected
    lhsResult expectedResult
  have firstTwo := evaluatesLogicalAnd
    (nullableTermMachine workspaceLayout grammar words grammarCell)
    world originEnvironment _ _
    (decide (candidate.origin = position))
    (decide (candidate.dot =
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length))
    originMatch dotMatch
  have allThree := evaluatesLogicalAnd
    (nullableTermMachine workspaceLayout grammar words grammarCell)
    world originEnvironment _ _
    (decide (candidate.origin = position) && decide (candidate.dot =
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length))
    (decide ((grammar.productionAt
      ⟨candidate.production, productionBound⟩).lhs = expected))
    firstTwo lhsMatch
  have predicateValue :
      ((decide (candidate.origin = position) && decide (candidate.dot =
          (grammar.productionAt
            ⟨candidate.production, productionBound⟩).rhs.length)) &&
        decide ((grammar.productionAt
          ⟨candidate.production, productionBound⟩).lhs = expected)) =
      decide (candidate.origin = position ∧ candidate.dot =
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).rhs.length ∧
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).lhs = expected) := by
    by_cases originMatches : candidate.origin = position <;>
      by_cases dotMatches : candidate.dot =
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).rhs.length <;>
      by_cases lhsMatches :
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).lhs = expected <;>
      simp [originMatches, dotMatches, lhsMatches]
  have matchesIff :
      (candidate.origin = position ∧ candidate.dot =
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).rhs.length ∧
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).lhs = expected) ↔
      NullableCandidateMatches grammar candidate position expected
        candidateWithin.productionBound := by
    simp only [NullableCandidateMatches]
  have matchesDecideEq :
      decide (candidate.origin = position ∧ candidate.dot =
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).rhs.length ∧
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).lhs = expected) =
      decide (NullableCandidateMatches grammar candidate position expected
        candidateWithin.productionBound) := by
    by_cases rawMatches : candidate.origin = position ∧ candidate.dot =
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).rhs.length ∧
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).lhs = expected
    · have logicalMatches := matchesIff.mp rawMatches
      simp [rawMatches, logicalMatches]
    · have logicalDoesNotMatch : ¬ NullableCandidateMatches grammar candidate
          position expected candidateWithin.productionBound := fun contrary =>
        rawMatches (matchesIff.mpr contrary)
      simp [rawMatches, logicalDoesNotMatch]
  rw [predicateValue, matchesDecideEq] at allThree
  simpa only [nullableCandidatePredicate,
    Lanius.FunctionalView.Core.logicalAnd] using allThree

/-- Functional evaluation of the state constructor used by a matching
    nullable candidate.  The constructor remains a normal source helper
    call; this theorem only packages its seven left-to-right arguments. -/
private theorem RecognizerNullableLoopInvariant.functional_seed
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (candidate : EarleyState) :
    let world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let environment := nullableEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length position
      parentState parentProduction parentDot parentOrigin expected
      (Int.ofNat current)
    let originEnvironment := ((environment.push
      (.signed .i32 (Int.ofNat candidate.production))).push
      (.signed .i32 (Int.ofNat candidate.dot))).push
      (.signed .i32 (Int.ofNat candidate.origin))
    Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world originEnvironment nullableSeedTerm =
      .ok (stateSeedValue (recognizerNullableSeed parentProduction parentDot
        parentOrigin parentState current), world) := by
  dsimp only
  let world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let environment := nullableEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length position parentState
    parentProduction parentDot parentOrigin expected (Int.ofNat current)
  let originEnvironment := ((environment.push
    (.signed .i32 (Int.ofNat candidate.production))).push
    (.signed .i32 (Int.ofNat candidate.dot))).push
    (.signed .i32 (Int.ofNat candidate.origin))
  let machine := nullableTermMachine workspaceLayout grammar words grammarCell
  have productionResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (nullableSlot ⟨7, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat parentProduction), world) := by rfl
  have dotReadOnly : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world originEnvironment (nullableSlot ⟨8, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat parentDot), world) := by rfl
  have oneReadOnly : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world originEnvironment (nullableLiteral 1) =
      .ok (.signed .i32 1, world) := by rfl
  have dotSuccReadOnly :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_add
      (leftType := parserI32Type) (rightType := parserI32Type)
      (outputType := parserI32Type) dotReadOnly oneReadOnly
      invariant.dotSuccI32
  have dotSuccAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell)
      (world := world) (environment := originEnvironment)
      (nullableAdd (nullableSlot ⟨8, by omega⟩) (nullableLiteral 1) :
        Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 15)
      (by native_decide)
  have dotSuccResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment
      (nullableAdd (nullableSlot ⟨8, by omega⟩) (nullableLiteral 1)) =
      .ok (.signed .i32 (Int.ofNat (parentDot + 1)), world) := by
    change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
          grammarCell)) world originEnvironment _ = _
    exact dotSuccAgreement.trans dotSuccReadOnly
  have originResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (nullableSlot ⟨9, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat parentOrigin), world) := by rfl
  have parentStateResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (nullableSlot ⟨6, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat parentState), world) := by rfl
  have childStateReadOnly :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_constant
      (program := verifiedParserCore) (world := world)
      (environment := originEnvironment) (type := parserI32Type)
      verifiedParser_child_state_constant
  have childStateAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell)
      (world := world) (environment := originEnvironment)
      (nullableConstant 39 : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 15) (by native_decide)
  have childStateResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (nullableConstant 39 : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 15) =
      .ok (.signed .i32 2, world) := by
    change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
          grammarCell)) world originEnvironment _ = _
    exact childStateAgreement.trans childStateReadOnly
  have candidateResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (nullableSlot ⟨11, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat current), world) := by rfl
  have negativeOneReadOnly :=
    Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_negate_one
      (program := verifiedParserCore) (world := world)
      (environment := originEnvironment) (inputType := parserI32Type)
      (outputType := parserI32Type)
  have negativeOneAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell)
      (world := world) (environment := originEnvironment)
      (nullableNegativeOne : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 15) (by native_decide)
  have negativeOneResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (nullableNegativeOne : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 15) =
      .ok (.signed .i32 (-1), world) := by
    change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
          grammarCell)) world originEnvironment _ = _
    exact negativeOneAgreement.trans negativeOneReadOnly
  let seed := recognizerNullableSeed parentProduction parentDot parentOrigin
    parentState current
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      originEnvironment [
        nullableSlot ⟨7, by omega⟩,
        nullableAdd (nullableSlot ⟨8, by omega⟩) (nullableLiteral 1),
        nullableSlot ⟨9, by omega⟩,
        nullableSlot ⟨6, by omega⟩,
        nullableConstant 39,
        nullableSlot ⟨11, by omega⟩,
        nullableNegativeOne] =
      .ok (parserStateSeedArgumentsValues seed, world) := by
    simpa [seed, recognizerNullableSeed, parserStateSeedArgumentsValues,
      previousValue, encodeStateId, childTag, childPayload, childKind] using
      Lanius.FunctionalView.evaluateTerms_cons productionResult
        (Lanius.FunctionalView.evaluateTerms_cons dotSuccResult
          (Lanius.FunctionalView.evaluateTerms_cons originResult
            (Lanius.FunctionalView.evaluateTerms_cons parentStateResult
              (Lanius.FunctionalView.evaluateTerms_cons childStateResult
                (Lanius.FunctionalView.evaluateTerms_cons candidateResult
                  (Lanius.FunctionalView.evaluateTerms_cons negativeOneResult
                    (Lanius.FunctionalView.evaluateTerms_nil machine world
                      originEnvironment)))))))
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
    grammarCell).evaluate world extractedParserStateSeedFunction.id
      (parserStateSeedArgumentsValues seed) = _
  exact RecognizerTraversalCallRegistry.calls_at_seed world seed

/-- Left-to-right evaluation of the nullable `append_state` arguments.  The
    nested seed call is evaluated in place, so the resulting list is exactly
    the source call's six-value ABI. -/
private theorem RecognizerNullableLoopInvariant.functional_append_arguments
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (candidate : EarleyState) :
    let world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let environment := nullableEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length position
      parentState parentProduction parentDot parentOrigin expected
      (Int.ofNat current)
    let originEnvironment := ((environment.push
      (.signed .i32 (Int.ofNat candidate.production))).push
      (.signed .i32 (Int.ofNat candidate.dot))).push
      (.signed .i32 (Int.ofNat candidate.origin))
    let seed := recognizerNullableSeed parentProduction parentDot parentOrigin
      parentState current
    Lanius.FunctionalView.evaluateTerms
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world originEnvironment nullableAppendArguments =
      .ok ([
        workspaceValue workspaceValues workspaceCell,
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
        .signed .i32 (Int.ofNat workspaceLayout.capacity),
        .signed .i32 (Int.ofNat position),
        stateSeedValue seed,
        .signed .i32 (Int.ofNat workspace.states.length)], world) := by
  dsimp only
  let world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let environment := nullableEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length position parentState
    parentProduction parentDot parentOrigin expected (Int.ofNat current)
  let originEnvironment := ((environment.push
    (.signed .i32 (Int.ofNat candidate.production))).push
    (.signed .i32 (Int.ofNat candidate.dot))).push
    (.signed .i32 (Int.ofNat candidate.origin))
  let machine := nullableTermMachine workspaceLayout grammar words grammarCell
  have workspaceResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (nullableSlot ⟨1, by omega⟩) =
      .ok (workspaceValue workspaceValues workspaceCell, world) := by rfl
  have baseResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (nullableSlot ⟨2, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat
        (stateBase workspaceLayout.tokenCount)), world) := by rfl
  have capacityResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (nullableSlot ⟨3, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat workspaceLayout.capacity), world) := by rfl
  have positionResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (nullableSlot ⟨5, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat position), world) := by rfl
  have seedResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment nullableSeedTerm =
      .ok (stateSeedValue (recognizerNullableSeed parentProduction parentDot
        parentOrigin parentState current), world) :=
    invariant.functional_seed candidate
  have stateCountResult : Lanius.FunctionalView.Term.evaluate machine world
      originEnvironment (nullableSlot ⟨4, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat workspace.states.length), world) := by rfl
  simpa only [nullableAppendArguments] using
    Lanius.FunctionalView.evaluateTerms_cons workspaceResult
      (Lanius.FunctionalView.evaluateTerms_cons baseResult
        (Lanius.FunctionalView.evaluateTerms_cons capacityResult
          (Lanius.FunctionalView.evaluateTerms_cons positionResult
            (Lanius.FunctionalView.evaluateTerms_cons seedResult
              (Lanius.FunctionalView.evaluateTerms_cons stateCountResult
                (Lanius.FunctionalView.evaluateTerms_nil machine world
                  originEnvironment))))))


structure RecognizerNullablePredicateResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position parentProduction parentDot parentOrigin parentState
      expected current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerNullableLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount) where
  after : State
  evaluation : Evaluates verifiedParserCore before
    parserRecognizeNullablePredicate
    (.boolean (decide (NullableCandidateMatches grammar candidate position
      expected productionBound))) after
  effect : ModifiesOnly CellSet.empty before after
  candidateFound : workspace.state? current = some candidate
  invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell after position parentProduction
    parentDot parentOrigin parentState expected current remaining

/-- Evaluate the exact short-circuit nullable predicate.  Grammar accessor
    calls occur only on the branches on which the extracted `&&` expression
    reaches them, so the resulting trace agrees with Core evaluation order. -/
noncomputable def RecognizerNullableCandidateBindings.evaluate_predicate
    (bindings : RecognizerNullableCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining beforeInvariant candidate found)
    (candidateWithin : StateKeyWithinGrammar grammar candidate.key) :
    RecognizerNullablePredicateResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterOriginRead.bindLocal 39
        (.signed .i32 (Int.ofNat candidate.origin)))
      position parentProduction parentDot parentOrigin parentState expected
      current remaining bindings.invariant candidate
      candidateWithin.productionBound := by
  let bound := bindings.afterOriginRead.bindLocal 39
    (.signed .i32 (Int.ofNat candidate.origin))
  let productionFin : Fin grammar.productionCount :=
    ⟨candidate.production, by
      simpa [EarleyState.key] using candidateWithin.productionBound⟩
  have candidateProductionBound : candidate.production <
      grammar.productionCount := by
    simpa [EarleyState.key] using candidateWithin.productionBound
  let rhsLength := (grammar.productionAt productionFin).rhs.length
  let lhs := (grammar.productionAt productionFin).lhs
  have originResult : Evaluates verifiedParserCore bound (.local 39)
      (.signed .i32 (Int.ofNat candidate.origin)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 39 _
      bindings.originLocal⟩
  have positionResult : Evaluates verifiedParserCore bound (.local 23)
      (.signed .i32 (Int.ofNat position)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 23 _
      bindings.invariant.positionLocal⟩
  have originEquality := evaluatesNatEqualityThreaded bound bound bound
    (.local 39) (.local 23) candidate.origin position originResult
    positionResult
  by_cases originMatches : candidate.origin = position
  · have originTrue : Evaluates verifiedParserCore bound
        (.binary .equal (.local 39) (.local 23)) (.boolean true) bound := by
      simpa [originMatches] using originEquality
    have productionResult : Evaluates verifiedParserCore bound (.local 37)
        (.signed .i32 (Int.ofNat candidate.production)) bound :=
      ⟨1, evalLocal_of_local 1 verifiedParserCore bound 37 _
        bindings.productionLocal⟩
    let rhsRead := bindings.invariant.chartCursor.read_rhs_length
      candidate.production candidateProductionBound (.local 37)
      productionResult
    have rhsEvaluation : Evaluates verifiedParserCore bound
        (.call extractedParserRhsLengthFunction.id [.local 0, .local 37])
        (.signed .i32 (Int.ofNat rhsLength)) rhsRead.after := by
      have rhsValue : grammar.rhsLengths.get
          ⟨candidate.production, by
            simpa using candidateProductionBound⟩ = rhsLength := by
        simpa [rhsLength, productionFin] using
          grammar.rhsLengths_get productionFin
      simpa only [rhsValue] using rhsRead.evaluation
    have dotResult : Evaluates verifiedParserCore bound (.local 38)
        (.signed .i32 (Int.ofNat candidate.dot)) bound :=
      ⟨1, evalLocal_of_local 1 verifiedParserCore bound 38 _
        bindings.dotLocal⟩
    have dotEquality := evaluatesNatEqualityThreaded bound bound rhsRead.after
      (.local 38)
      (.call extractedParserRhsLengthFunction.id [.local 0, .local 37])
      candidate.dot rhsLength dotResult rhsEvaluation
    by_cases dotMatches : candidate.dot = rhsLength
    · have dotTrue : Evaluates verifiedParserCore bound
          (.binary .equal (.local 38)
            (.call extractedParserRhsLengthFunction.id [.local 0, .local 37]))
          (.boolean true) rhsRead.after := by
        simpa [dotMatches] using dotEquality
      have firstTwo := evaluatesLogicalAndTrue originTrue dotTrue
      let afterRhsInvariant := bindings.invariant.after_empty_effect
        rhsRead.effect rhsRead.invariant.recognizer.wellFormed
      have productionAfterRhs : rhsRead.after.local? 37 =
          some (.signed .i32 (Int.ofNat candidate.production)) :=
        rhsRead.effect.empty_preserves_local
          bindings.invariant.chartCursor.recognizer.wellFormed
          bindings.productionLocal
      have productionAfterRhsResult : Evaluates verifiedParserCore
          rhsRead.after (.local 37)
          (.signed .i32 (Int.ofNat candidate.production)) rhsRead.after :=
        ⟨1, evalLocal_of_local 1 verifiedParserCore rhsRead.after 37 _
          productionAfterRhs⟩
      let lhsRead := afterRhsInvariant.chartCursor.read_lhs
        candidate.production candidateProductionBound (.local 37)
        productionAfterRhsResult
      have lhsEvaluation : Evaluates verifiedParserCore rhsRead.after
          (.call extractedParserLhsFunction.id [.local 0, .local 37])
          (.signed .i32 (Int.ofNat lhs)) lhsRead.after := by
        have lhsValue : grammar.productionLhs.get
            ⟨candidate.production, by
              simpa using candidateProductionBound⟩ = lhs := by
          simpa [lhs, productionFin] using
            grammar.productionLhs_get productionFin
        simpa only [lhsValue] using lhsRead.evaluation
      have expectedAfterLhs : lhsRead.after.local? 30 =
          some (.signed .i32 (Int.ofNat expected)) :=
        lhsRead.effect.empty_preserves_local
          afterRhsInvariant.chartCursor.recognizer.wellFormed
          afterRhsInvariant.expectedLocal
      have expectedResult : Evaluates verifiedParserCore lhsRead.after
          (.local 30) (.signed .i32 (Int.ofNat expected)) lhsRead.after :=
        ⟨1, evalLocal_of_local 1 verifiedParserCore lhsRead.after 30 _
          expectedAfterLhs⟩
      have lhsEquality := evaluatesNatEqualityThreaded rhsRead.after
        lhsRead.after lhsRead.after
        (.call extractedParserLhsFunction.id [.local 0, .local 37])
        (.local 30) lhs expected lhsEvaluation expectedResult
      have predicateEvaluation := evaluatesLogicalAndTrue firstTwo lhsEquality
      let afterLhsInvariant := afterRhsInvariant.after_empty_effect
        lhsRead.effect lhsRead.invariant.recognizer.wellFormed
      exact {
        after := lhsRead.after
        evaluation := by
          rw [extractedParserRecognize_nullable_predicate_shape]
          have resultValue : decide (NullableCandidateMatches grammar candidate
              position expected candidateWithin.productionBound) =
              decide (lhs = expected) := by
            simp [NullableCandidateMatches, originMatches, dotMatches,
              rhsLength, lhs, productionFin]
          rw [resultValue]
          exact predicateEvaluation
        effect := rhsRead.effect.trans_same lhsRead.effect
        candidateFound := found
        invariant := by simpa [bound] using afterLhsInvariant
      }
    · have dotFalse : Evaluates verifiedParserCore bound
          (.binary .equal (.local 38)
            (.call extractedParserRhsLengthFunction.id [.local 0, .local 37]))
          (.boolean false) rhsRead.after := by
        simpa [dotMatches] using dotEquality
      have firstTwo := evaluatesLogicalAndTrue originTrue dotFalse
      have predicateEvaluation := evaluatesLogicalAndFalse
        (right := .binary .equal
          (.call extractedParserLhsFunction.id [.local 0, .local 37])
          (.local 30)) firstTwo
      let afterRhsInvariant := bindings.invariant.after_empty_effect
        rhsRead.effect rhsRead.invariant.recognizer.wellFormed
      exact {
        after := rhsRead.after
        evaluation := by
          rw [extractedParserRecognize_nullable_predicate_shape]
          have resultValue : decide (NullableCandidateMatches grammar candidate
              position expected candidateWithin.productionBound) = false := by
            simp [NullableCandidateMatches, originMatches, dotMatches,
              rhsLength, productionFin]
          rw [resultValue]
          exact predicateEvaluation
        effect := rhsRead.effect
        candidateFound := found
        invariant := by simpa [bound] using afterRhsInvariant
      }
  · have originFalse : Evaluates verifiedParserCore bound
        (.binary .equal (.local 39) (.local 23)) (.boolean false) bound := by
      simpa [originMatches] using originEquality
    have firstTwo := evaluatesLogicalAndFalse
      (right := .binary .equal (.local 38)
        (.call extractedParserRhsLengthFunction.id [.local 0, .local 37]))
      originFalse
    have predicateEvaluation := evaluatesLogicalAndFalse
      (right := .binary .equal
        (.call extractedParserLhsFunction.id [.local 0, .local 37])
        (.local 30)) firstTwo
    exact {
      after := bound
      evaluation := by
        rw [extractedParserRecognize_nullable_predicate_shape]
        have resultValue : decide (NullableCandidateMatches grammar candidate
            position expected candidateWithin.productionBound) = false := by
          simp [NullableCandidateMatches, originMatches]
        rw [resultValue]
        exact predicateEvaluation
      effect := ModifiesOnly.reflAny CellSet.empty bound
      candidateFound := found
      invariant := by simpa [bound] using bindings.invariant
    }

/-- A nullable candidate selected by the source predicate supplies the
    zero-width nonterminal derivation used to advance the parent item. -/
theorem RecognizerNullablePredicateResult.seed_sound
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining beforeInvariant candidate productionBound)
    (doesMatch : NullableCandidateMatches grammar candidate position expected
      productionBound) :
    EarleyStateSound grammar tokens
      ((recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState current).atPosition position) := by
  have candidateSound :=
    predicate.invariant.chartCursor.recognizer.languageSound current candidate
      predicate.candidateFound
  have candidatePosition : candidate.position = position := by
    obtain ⟨cursorState, cursorFound, cursorPosition⟩ :=
      predicate.invariant.chartCursor.state_at_cursor
    rw [predicate.candidateFound] at cursorFound
    injection cursorFound with stateEqual
    subst cursorState
    exact cursorPosition
  have lhsBound :=
    predicate.invariant.chartCursor.recognizer.grammarWellFormed
      |>.production_validation.lhsInBounds
        ⟨candidate.production, by
          simpa [EarleyState.key] using productionBound⟩
  have completed := candidateSound.complete lhsBound doesMatch.2.1
  have recognized : RecognizesSymbol grammar tokens
      (grammar.grammar.n_kinds + expected) position position := by
    simpa [doesMatch.1, doesMatch.2.2, candidatePosition] using completed
  exact predicate.invariant.parentAdvanceSound current
    (grammar.grammar.n_kinds + expected) position
    predicate.invariant.parentSymbolFound recognized

/-- The same nullable match also records the exact predecessor and completed
    child used by the appended state, making later tree reconstruction
    independent of the declarative soundness proof above. -/
theorem RecognizerNullablePredicateResult.seed_derivation
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining beforeInvariant candidate productionBound)
    (doesMatch : NullableCandidateMatches grammar candidate position expected
      productionBound) :
    EarleySeedDerivation grammar tokens workspace position
      (recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState current) := by
  refine {
    languageSound := predicate.seed_sound doesMatch
    backpointer := ?_
  }
  have candidatePosition : candidate.position = position := by
    obtain ⟨cursorState, cursorFound, cursorPosition⟩ :=
      predicate.invariant.chartCursor.state_at_cursor
    rw [predicate.candidateFound] at cursorFound
    injection cursorFound with stateEqual
    subst cursorState
    exact cursorPosition
  have previousBefore : parentState < workspace.states.length :=
    List.getElem?_eq_some_iff.mp predicate.invariant.parentStored.found |>.1
  have childBefore : current < workspace.states.length :=
    List.getElem?_eq_some_iff.mp predicate.candidateFound |>.1
  have previousProductionBound :
      predicate.invariant.parentStored.state.production <
        grammar.productionCount := by
    simpa [predicate.invariant.parentStored.productionEq] using
      predicate.invariant.parentProductionBound
  have childProductionBound : candidate.production < grammar.productionCount := by
    simpa [EarleyState.key] using productionBound
  have childLhsBound :=
    predicate.invariant.chartCursor.recognizer.grammarWellFormed
      |>.production_validation.lhsInBounds
        ⟨candidate.production, childProductionBound⟩
  have symbolFound :
      (grammar.productionAt
        ⟨predicate.invariant.parentStored.state.production,
          previousProductionBound⟩).rhs[
            predicate.invariant.parentStored.state.dot]? =
        some (grammar.grammar.n_kinds +
          (grammar.productionAt
            ⟨candidate.production, childProductionBound⟩).lhs) := by
    simpa [predicate.invariant.parentStored.productionEq,
      predicate.invariant.parentStored.dotEq, doesMatch.2.2] using
      predicate.invariant.parentSymbolFound
  have childOrigin : candidate.origin =
      predicate.invariant.parentStored.state.position :=
    doesMatch.1.trans predicate.invariant.parentStored.positionEq.symm
  have step := EarleyBackpointerStep.nonterminal
    (grammar := grammar) (tokens := tokens) (workspace := workspace)
    (stateId := workspace.states.length)
    predicate.invariant.parentStored.found previousBefore
    predicate.candidateFound childBefore previousProductionBound
    childProductionBound symbolFound childLhsBound childOrigin doesMatch.2.1
  simpa [recognizerNullableSeed, EarleyState.advanceSeed,
    predicate.invariant.parentStored.productionEq,
    predicate.invariant.parentStored.dotEq,
    predicate.invariant.parentStored.originEq, candidatePosition] using step

/-- Functional execution of the nullable workspace append.  The proof uses
    the existing append contract as the semantic boundary, but the argument
    evaluation and world transition are both expressed by FunctionalView. -/
private theorem RecognizerNullableLoopInvariant.functional_append
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (candidateWithin : StateKeyWithinGrammar grammar candidate.key)
    (doesMatch : NullableCandidateMatches grammar candidate position expected
      candidateWithin.productionBound) :
    let seed := recognizerNullableSeed parentProduction parentDot parentOrigin
      parentState current
    let outcome := (appendLogical workspaceLayout.capacity position seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace position seed
      workspaceValues
    let world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let afterWorld := nullableWorld words tokens nextValues grammarCell tokensCell workspaceCell
    let environment := nullableEnvironment words workspaceValues grammarCell
      workspaceCell workspaceLayout workspace.states.length position
      parentState parentProduction parentDot parentOrigin expected
      (Int.ofNat current)
    let originEnvironment := ((environment.push
      (.signed .i32 (Int.ofNat candidate.production))).push
      (.signed .i32 (Int.ofNat candidate.dot))).push
      (.signed .i32 (Int.ofNat candidate.origin))
    Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world originEnvironment nullableAppendTerm =
      .ok (appendOutcomeValue outcome, afterWorld) := by
  dsimp only
  let seed := recognizerNullableSeed parentProduction parentDot parentOrigin
    parentState current
  let outcome := (appendLogical workspaceLayout.capacity position seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace position seed
    workspaceValues
  let world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let afterWorld := nullableWorld words tokens nextValues grammarCell tokensCell workspaceCell
  let environment := nullableEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length position parentState
    parentProduction parentDot parentOrigin expected (Int.ofNat current)
  let originEnvironment := ((environment.push
    (.signed .i32 (Int.ofNat candidate.production))).push
    (.signed .i32 (Int.ofNat candidate.dot))).push
    (.signed .i32 (Int.ofNat candidate.origin))
  let machine := nullableTermMachine workspaceLayout grammar words grammarCell
  let callValues : List Value := [
    workspaceValue workspaceValues workspaceCell,
    .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
    .signed .i32 (Int.ofNat workspaceLayout.capacity),
    .signed .i32 (Int.ofNat position),
    stateSeedValue seed,
    .signed .i32 (Int.ofNat workspace.states.length)]
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      originEnvironment nullableAppendArguments = .ok (callValues, world) := by
    change Lanius.FunctionalView.evaluateTerms
      (nullableTermMachine workspaceLayout grammar words grammarCell) world
      originEnvironment nullableAppendArguments = .ok (callValues, world)
    exact invariant.functional_append_arguments candidate
  let bindings := invariant.bind_candidate_fields candidate found
  let predicate := bindings.evaluate_predicate candidateWithin
  let appendInvariant := predicate.invariant.append_invariant
  let appended := appendInvariant.evaluate_append
    (predicate.seed_derivation doesMatch)
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
      simpa [seed, recognizerNullableSeed] using invariant.parentOriginBound
    found := by
      simpa [world, nullableWorld] using
        (recognizerWorld_finds_workspace
          (tokens := tokens) (tokensCell := tokensCell) different)
    argumentsEq := rfl
  }
  let commandLayout := Layout.push
    (Layout.push (Layout.push nullableLoopLayout 37) 38) 39
  have argumentsExecution : ArgumentsEvaluateTo verifiedParserCore
      predicate.after
      (Lanius.FunctionalView.Core.toCoreExprs commandLayout
        nullableAppendArguments) callValues appended.argumentsState := by
    change ArgumentsEvaluateTo verifiedParserCore predicate.after
      parserRecognizeNullableAppendArguments callValues appended.argumentsState
    simpa [callValues, seed, parserRecognizeNullableAppendArguments,
      recognizerAppendArguments] using appended.argumentsEvaluation
  have worldRepresents :
      Lanius.FunctionalView.Core.ReadOnly.World.Represents world
        appended.argumentsState := by
    simpa [world, nullableWorld] using
      recognizerWorld_represents appended.argumentsInvariant
  have worldOwned :
      (Lanius.FunctionalView.Core.ReadOnly.World.owns world).holds
        appended.argumentsState :=
    (Lanius.FunctionalView.Core.ReadOnly.World.owns_iff_represents
      appended.argumentsInvariant.wellFormed).2 worldRepresents
  have registryResult :=
    RecognizerTraversalCallRegistry.calls_at_append_input
      (grammar := grammar) (words := words) (grammarCell := grammarCell)
      input predicate.after appended.argumentsState commandLayout
      nullableAppendArguments appended.argumentsInvariant.wellFormed worldOwned
      argumentsExecution
  have outcomeEq : input.outcome = outcome := by rfl
  have afterWorldEq : input.afterWorld = afterWorld := by
    change Lanius.FunctionalView.Core.ReadOnly.World.setI32Slice world
        workspaceCell nextValues = afterWorld
    simpa [world, afterWorld, nullableWorld] using
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


/-- The nullable append continuation branches only on the append status
    field.  It is call-free and therefore identical in the read-only and
    traversal machines. -/
private theorem nullableFullCondition_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 15)
    (outcome : AppendOutcome) :
    Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world (environment.push (appendOutcomeValue outcome))
      nullableFullCondition =
      .ok (.boolean (decide (outcome.status = .full)), world) := by
  have agreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell)
      (world := world)
      (environment := environment.push (appendOutcomeValue outcome))
      nullableFullCondition (by native_decide)
  have readOnlyResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world (environment.push (appendOutcomeValue outcome))
      nullableFullCondition =
      .ok (.boolean (decide (outcome.status = .full)), world) := by
    rcases outcome with ⟨status, stateId, stateCount, inserted⟩
    cases status <;> rfl
  change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
          grammarCell)) world
      (environment.push (appendOutcomeValue outcome)) nullableFullCondition = _
  exact agreement.trans readOnlyResult

/-- Field two of the nullable append result is the updated state count. -/
private theorem nullableStateCountTerm_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 15)
    (outcome : AppendOutcome) :
    Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world (environment.push (appendOutcomeValue outcome))
      nullableStateCountTerm =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), world) := by
  have agreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell)
      (world := world)
      (environment := environment.push (appendOutcomeValue outcome))
      nullableStateCountTerm (by native_decide)
  have readOnlyResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world (environment.push (appendOutcomeValue outcome))
      nullableStateCountTerm =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), world) := by rfl
  change Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.Effectful.machine verifiedParserCore
        (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
          grammarCell)) world
      (environment.push (appendOutcomeValue outcome)) nullableStateCountTerm = _
  exact agreement.trans readOnlyResult

/-- Functional evaluation of the capacity diagnostic returned by a full
    nullable append. -/
private theorem nullableFullResult_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 15)
    (outcome : AppendOutcome) (position : Nat)
    (positionValue : environment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat position)) :
    Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world (environment.push (appendOutcomeValue outcome))
      nullableFullResult =
      .ok (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position), world) := by
  let machine := nullableTermMachine workspaceLayout grammar words grammarCell
  let extended := environment.push (appendOutcomeValue outcome)
  have outcomeResult : Lanius.FunctionalView.Term.evaluate machine world
      extended (nullableSlot ⟨15, by omega⟩) =
      .ok (appendOutcomeValue outcome, world) := by rfl
  have positionResult : Lanius.FunctionalView.Term.evaluate machine world
      extended (nullableSlot ⟨5, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat position), world) := by
    apply Lanius.FunctionalView.Term.evaluate_slot
    change environment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat position)
    exact positionValue
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      extended [nullableSlot ⟨15, by omega⟩,
        nullableSlot ⟨5, by omega⟩] =
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

/-- Read the next chart link from any nullable-loop invariant.  The logical
    result is the head of the invariant's unvisited suffix, encoded with the
    same `-1` sentinel used by the source representation. -/
private theorem RecognizerNullableLoopInvariant.functional_next
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (environment : Lanius.FunctionalView.Env 15)
    (workspaceValueEq : environment ⟨1, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (stateBaseEq : environment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (currentEq : environment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat current)) :
    Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
      environment (nullableStateValueTerm (arity := 15) (by omega) 32) =
      .ok (.signed .i32 (encodeStateId remaining.head?),
        nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell) := by
  let candidate := Classical.choose invariant.chartCursor.state_at_cursor
  have candidateFacts :=
    Classical.choose_spec invariant.chartCursor.state_at_cursor
  have found : workspace.state? current = some candidate := candidateFacts.1
  have positionEq : candidate.position = position := candidateFacts.2
  have evaluated := nullableStateValueTerm_evaluates
    (arity := 15) (by omega) workspaceLayout grammar words workspaceValues
    grammarCell workspaceCell
    (nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
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

/-- One nonmatching nullable candidate executes the real body without an
    append, then advances the chart cursor. -/
private theorem RecognizerNullableLoopInvariant.functional_no_match_body
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (candidateWithin : StateKeyWithinGrammar grammar candidate.key)
    (notMatches : ¬ NullableCandidateMatches grammar candidate position
      expected candidateWithin.productionBound) :
    let world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let beforeEnvironment := nullableEnvironment words workspaceValues
      grammarCell workspaceCell workspaceLayout workspace.states.length
      position parentState parentProduction parentDot parentOrigin expected
      (Int.ofNat current)
    let afterEnvironment := nullableEnvironment words workspaceValues
      grammarCell workspaceCell workspaceLayout workspace.states.length
      position parentState parentProduction parentDot parentOrigin expected
      (encodeStateId remaining.head?)
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      world beforeEnvironment nullableBodyCommand .next world
      afterEnvironment := by
  dsimp only
  let world := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let beforeEnvironment := nullableEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length position parentState
    parentProduction parentDot parentOrigin expected (Int.ofNat current)
  let productionEnvironment := beforeEnvironment.push
    (.signed .i32 (Int.ofNat candidate.production))
  let dotEnvironment := productionEnvironment.push
    (.signed .i32 (Int.ofNat candidate.dot))
  let originEnvironment := dotEnvironment.push
    (.signed .i32 (Int.ofNat candidate.origin))
  have reads := invariant.functional_candidate_reads candidate found
  have productionResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world beforeEnvironment
      (nullableStateValueTerm (arity := 12) (by omega) 28) =
      .ok (.signed .i32 (Int.ofNat candidate.production), world) := reads.1
  have dotResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world productionEnvironment
      (nullableStateValueTerm (arity := 13) (by omega) 29) =
      .ok (.signed .i32 (Int.ofNat candidate.dot), world) := reads.2.1
  have originResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world dotEnvironment
      (nullableStateValueTerm (arity := 14) (by omega) 30) =
      .ok (.signed .i32 (Int.ofNat candidate.origin), world) := reads.2.2
  have predicateResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world originEnvironment nullableCandidatePredicate =
      .ok (.boolean false, world) := by
    have evaluated := invariant.functional_predicate candidate candidateWithin
    simpa [world, originEnvironment, dotEnvironment, productionEnvironment,
      beforeEnvironment, notMatches] using evaluated
  have nextResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      world originEnvironment
      (nullableStateValueTerm (arity := 15) (by omega) 32) =
      .ok (.signed .i32 (encodeStateId remaining.head?), world) :=
    invariant.functional_next originEnvironment (by rfl) (by rfl) (by rfl)
  let afterCursor := Lanius.FunctionalView.Stateful.Env.set originEnvironment
    ⟨11, by omega⟩ (.signed .i32 (encodeStateId remaining.head?))
  have body : Lanius.FunctionalView.Stateful.Command.Evaluates
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      world originEnvironment
      (.sequence
        (.ifThenElse nullableCandidatePredicate
          (.letValue (.structure 2) nullableAppendTerm
            (.sequence
              (.ifThenElse nullableFullCondition
                (.sequence (.returnValue (some nullableFullResult)) .skip)
                .skip)
              (.sequence
                (.setLocal ⟨4, by omega⟩ nullableStateCountTerm)
                .skip)))
          .skip)
        (.sequence
          (.setLocal ⟨11, by omega⟩
            (nullableStateValueTerm (arity := 15) (by omega) 32))
          .skip))
      .next world afterCursor :=
    .sequenceNext (.ifFalse predicateResult .skip)
      (.sequenceNext (.setLocal nextResult) .skip)
  have assembled :=
    Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
      (type := parserI32Type) productionResult
      (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
        (type := parserI32Type) dotResult
        (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
          (type := parserI32Type) originResult body))
  have environmentEq :
      Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop afterCursor)) =
      nullableEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout workspace.states.length position parentState
        parentProduction parentDot parentOrigin expected
        (encodeStateId remaining.head?) := by
    funext index
    have indexCases : index = (0 : Fin 12) ∨ index = (1 : Fin 12) ∨
        index = (2 : Fin 12) ∨ index = (3 : Fin 12) ∨
        index = (4 : Fin 12) ∨ index = (5 : Fin 12) ∨
        index = (6 : Fin 12) ∨ index = (7 : Fin 12) ∨
        index = (8 : Fin 12) ∨ index = (9 : Fin 12) ∨
        index = (10 : Fin 12) ∨ index = (11 : Fin 12) := by omega
    rcases indexCases with h | h | h | h | h | h | h | h | h | h | h | h <;>
      subst index <;> rfl
  rw [environmentEq] at assembled
  simpa [nullableBodyCommand, nullableCanonicalBodyCommand, world,
    beforeEnvironment] using assembled

/-- One matching, non-full nullable candidate executes the append, installs
    the returned state count, and advances through the post-append chart. -/
private theorem RecognizerNullableLoopInvariant.functional_ok_body
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (candidateWithin : StateKeyWithinGrammar grammar candidate.key)
    (doesMatch : NullableCandidateMatches grammar candidate position expected
      candidateWithin.productionBound)
    (statusOk :
      let seed := recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState current
      (appendLogical workspaceLayout.capacity position seed workspace).1.status =
        .ok)
    (nextRemaining : List Nat) (afterRuntime : State)
    (afterInvariant :
      let seed := recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState current
      RecognizerNullableLoopInvariant grammarLayout grammar words tokens
        workspaceLayout
        (appendLogical workspaceLayout.capacity position seed workspace).2
        (appendResultValues workspaceLayout workspace position seed
          workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell
        afterRuntime position parentProduction parentDot parentOrigin
        parentState expected current nextRemaining) :
    let seed := recognizerNullableSeed parentProduction parentDot parentOrigin
      parentState current
    let outcome := (appendLogical workspaceLayout.capacity position seed
      workspace).1
    let nextWorkspace := (appendLogical workspaceLayout.capacity position seed
      workspace).2
    let nextValues := appendResultValues workspaceLayout workspace position seed
      workspaceValues
    let beforeWorld := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let afterWorld := nullableWorld words tokens nextValues grammarCell tokensCell workspaceCell
    let beforeEnvironment := nullableEnvironment words workspaceValues
      grammarCell workspaceCell workspaceLayout workspace.states.length
      position parentState parentProduction parentDot parentOrigin expected
      (Int.ofNat current)
    let afterEnvironment := nullableEnvironment words nextValues grammarCell
      workspaceCell workspaceLayout nextWorkspace.states.length position
      parentState parentProduction parentDot parentOrigin expected
      (encodeStateId nextRemaining.head?)
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld beforeEnvironment nullableBodyCommand .next afterWorld
      afterEnvironment := by
  dsimp only
  let seed := recognizerNullableSeed parentProduction parentDot parentOrigin
    parentState current
  let outcome := (appendLogical workspaceLayout.capacity position seed
    workspace).1
  let nextWorkspace := (appendLogical workspaceLayout.capacity position seed
    workspace).2
  let nextValues := appendResultValues workspaceLayout workspace position seed
    workspaceValues
  let beforeWorld := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let afterWorld := nullableWorld words tokens nextValues grammarCell tokensCell workspaceCell
  let beforeEnvironment := nullableEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length position parentState
    parentProduction parentDot parentOrigin expected (Int.ofNat current)
  let productionEnvironment := beforeEnvironment.push
    (.signed .i32 (Int.ofNat candidate.production))
  let dotEnvironment := productionEnvironment.push
    (.signed .i32 (Int.ofNat candidate.dot))
  let originEnvironment := dotEnvironment.push
    (.signed .i32 (Int.ofNat candidate.origin))
  let resultEnvironment := originEnvironment.push (appendOutcomeValue outcome)
  have reads := invariant.functional_candidate_reads candidate found
  have productionResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld beforeEnvironment
      (nullableStateValueTerm (arity := 12) (by omega) 28) =
      .ok (.signed .i32 (Int.ofNat candidate.production), beforeWorld) :=
    reads.1
  have dotResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld productionEnvironment
      (nullableStateValueTerm (arity := 13) (by omega) 29) =
      .ok (.signed .i32 (Int.ofNat candidate.dot), beforeWorld) := reads.2.1
  have originResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld dotEnvironment
      (nullableStateValueTerm (arity := 14) (by omega) 30) =
      .ok (.signed .i32 (Int.ofNat candidate.origin), beforeWorld) := reads.2.2
  have predicateResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld originEnvironment nullableCandidatePredicate =
      .ok (.boolean true, beforeWorld) := by
    have evaluated := invariant.functional_predicate candidate candidateWithin
    simpa [beforeWorld, originEnvironment, dotEnvironment,
      productionEnvironment, beforeEnvironment, doesMatch] using evaluated
  have appendResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld originEnvironment nullableAppendTerm =
      .ok (appendOutcomeValue outcome, afterWorld) := by
    exact invariant.functional_append candidate found candidateWithin doesMatch
  have statusOk' : outcome.status = .ok := by
    simpa [outcome, seed] using statusOk
  have fullCondition : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment nullableFullCondition =
      .ok (.boolean false, afterWorld) := by
    have evaluated := nullableFullCondition_evaluates
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (grammarCell := grammarCell) afterWorld
      originEnvironment outcome
    rw [statusOk'] at evaluated
    simpa [resultEnvironment] using evaluated
  have countResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment nullableStateCountTerm =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), afterWorld) := by
    simpa [resultEnvironment] using nullableStateCountTerm_evaluates
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (grammarCell := grammarCell) afterWorld
      originEnvironment outcome
  let afterCount := Lanius.FunctionalView.Stateful.Env.set resultEnvironment
    ⟨4, by omega⟩ (.signed .i32 (Int.ofNat outcome.stateCount))
  have appendContinuation :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (nullableTermMachine workspaceLayout grammar words grammarCell)
        (nullableStatefulMachine workspaceLayout grammar words grammarCell)
        afterWorld resultEnvironment
        (.sequence
          (.ifThenElse nullableFullCondition
            (.sequence (.returnValue (some nullableFullResult)) .skip)
            .skip)
          (.sequence
            (.setLocal ⟨4, by omega⟩ nullableStateCountTerm) .skip))
        .next afterWorld afterCount :=
    .sequenceNext (.ifFalse fullCondition .skip)
      (.sequenceNext (.setLocal countResult) .skip)
  have appendBranch :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (nullableTermMachine workspaceLayout grammar words grammarCell)
        (nullableStatefulMachine workspaceLayout grammar words grammarCell)
        beforeWorld originEnvironment
        (.letValue (.structure 2) nullableAppendTerm
          (.sequence
            (.ifThenElse nullableFullCondition
              (.sequence (.returnValue (some nullableFullResult)) .skip)
              .skip)
            (.sequence
              (.setLocal ⟨4, by omega⟩ nullableStateCountTerm) .skip)))
        .next afterWorld
        (Lanius.FunctionalView.Stateful.Env.pop afterCount) :=
    .letValue appendResult appendContinuation
  have selected :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (nullableTermMachine workspaceLayout grammar words grammarCell)
        (nullableStatefulMachine workspaceLayout grammar words grammarCell)
        beforeWorld originEnvironment
        (.ifThenElse nullableCandidatePredicate
          (.letValue (.structure 2) nullableAppendTerm
            (.sequence
              (.ifThenElse nullableFullCondition
                (.sequence (.returnValue (some nullableFullResult)) .skip)
                .skip)
              (.sequence
                (.setLocal ⟨4, by omega⟩ nullableStateCountTerm) .skip)))
          .skip)
        .next afterWorld
        (Lanius.FunctionalView.Stateful.Env.pop afterCount) :=
    .ifTrue predicateResult appendBranch
  let afterAppendEnvironment :=
    Lanius.FunctionalView.Stateful.Env.pop afterCount
  have workspaceValueEq : afterAppendEnvironment ⟨1, by omega⟩ =
      workspaceValue nextValues workspaceCell := by
    simp [afterAppendEnvironment, afterCount, resultEnvironment,
      originEnvironment, dotEnvironment, productionEnvironment,
      beforeEnvironment, Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push, nullableEnvironment, workspaceValue,
      nextValues, appendResultValues_length]
  have stateBaseEq : afterAppendEnvironment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)) := by
    rfl
  have currentEq : afterAppendEnvironment ⟨11, by omega⟩ =
      .signed .i32 (Int.ofNat current) := by rfl
  have nextResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      afterWorld afterAppendEnvironment
      (nullableStateValueTerm (arity := 15) (by omega) 32) =
      .ok (.signed .i32 (encodeStateId nextRemaining.head?), afterWorld) := by
    simpa [afterWorld, nextValues, nextWorkspace, seed] using
      afterInvariant.functional_next afterAppendEnvironment workspaceValueEq
        stateBaseEq currentEq
  let afterCursor := Lanius.FunctionalView.Stateful.Env.set
    afterAppendEnvironment ⟨11, by omega⟩
      (.signed .i32 (encodeStateId nextRemaining.head?))
  have body : Lanius.FunctionalView.Stateful.Command.Evaluates
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld originEnvironment
      (.sequence
        (.ifThenElse nullableCandidatePredicate
          (.letValue (.structure 2) nullableAppendTerm
            (.sequence
              (.ifThenElse nullableFullCondition
                (.sequence (.returnValue (some nullableFullResult)) .skip)
                .skip)
              (.sequence
                (.setLocal ⟨4, by omega⟩ nullableStateCountTerm) .skip)))
          .skip)
        (.sequence
          (.setLocal ⟨11, by omega⟩
            (nullableStateValueTerm (arity := 15) (by omega) 32)) .skip))
      .next afterWorld afterCursor :=
    .sequenceNext selected (.sequenceNext (.setLocal nextResult) .skip)
  have assembled :=
    Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
      (type := parserI32Type) productionResult
      (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
        (type := parserI32Type) dotResult
        (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
          (type := parserI32Type) originResult body))
  have collapsedEnvironment :
      Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop afterCursor)) =
      Lanius.FunctionalView.Stateful.Env.set
        (Lanius.FunctionalView.Stateful.Env.set beforeEnvironment
          ⟨4, by omega⟩ (.signed .i32 (Int.ofNat outcome.stateCount)))
        ⟨11, by omega⟩
        (.signed .i32 (encodeStateId nextRemaining.head?)) := by
    dsimp [afterCursor, afterAppendEnvironment, afterCount,
      resultEnvironment, originEnvironment, dotEnvironment,
      productionEnvironment]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 14) (before := by native_decide)]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 13) (before := by native_decide)]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 12) (before := by native_decide)]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 15) (before := by native_decide)]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 14) (before := by native_decide)]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 13) (before := by native_decide)]
    rw [Lanius.FunctionalView.Stateful.Env.pop_set_of_lt
      (arity := 12) (before := by native_decide)]
    congr
    simp
  have environmentEq :
      Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop afterCursor)) =
      nullableEnvironment words nextValues grammarCell workspaceCell
        workspaceLayout nextWorkspace.states.length position parentState
        parentProduction parentDot parentOrigin expected
        (encodeStateId nextRemaining.head?) := by
    rw [collapsedEnvironment]
    funext index
    rcases index with ⟨index, indexBound⟩
    have indexCases : index = 0 ∨ index = 1 ∨ index = 2 ∨
        index = 3 ∨ index = 4 ∨ index = 5 ∨
        index = 6 ∨ index = 7 ∨ index = 8 ∨
        index = 9 ∨ index = 10 ∨ index = 11 := by omega
    rcases indexCases with zero | one | two | three | four | five | six |
      seven | eight | nine | ten | eleven
    · subst index
      simp [afterCursor, afterAppendEnvironment, afterCount,
        resultEnvironment, originEnvironment, dotEnvironment,
        productionEnvironment, beforeEnvironment,
        Lanius.FunctionalView.Stateful.Env.pop,
        Lanius.FunctionalView.Stateful.Env.set,
        Lanius.FunctionalView.Env.push, nullableEnvironment]
    · subst index
      simp [afterCursor, afterAppendEnvironment, afterCount,
        resultEnvironment, originEnvironment, dotEnvironment,
        productionEnvironment, beforeEnvironment,
        Lanius.FunctionalView.Stateful.Env.pop,
        Lanius.FunctionalView.Stateful.Env.set,
        Lanius.FunctionalView.Env.push, nullableEnvironment, workspaceValue,
        nextValues, appendResultValues_length]
    · subst index
      simp [afterCursor, afterAppendEnvironment, afterCount,
        resultEnvironment, originEnvironment, dotEnvironment,
        productionEnvironment, beforeEnvironment,
        Lanius.FunctionalView.Stateful.Env.pop,
        Lanius.FunctionalView.Stateful.Env.set,
        Lanius.FunctionalView.Env.push, nullableEnvironment]
    · subst index
      rw [Lanius.FunctionalView.Stateful.Env.set_other
        (different := by
          intro equal
          have valuesEqual := congrArg Fin.val equal
          change 3 = 11 at valuesEqual
          omega)]
      rw [Lanius.FunctionalView.Stateful.Env.set_other
        (different := by
          intro equal
          have valuesEqual := congrArg Fin.val equal
          change 3 = 4 at valuesEqual
          omega)]
      simp [beforeEnvironment, nullableEnvironment]
    · subst index
      simp [afterCursor, afterAppendEnvironment, afterCount,
        resultEnvironment, originEnvironment, dotEnvironment,
        productionEnvironment, beforeEnvironment,
        Lanius.FunctionalView.Stateful.Env.pop,
        Lanius.FunctionalView.Stateful.Env.set,
        Lanius.FunctionalView.Env.push, nullableEnvironment,
        nextWorkspace, outcome, seed, appendLogical_stateCount_eq]
    · subst index
      simp [afterCursor, afterAppendEnvironment, afterCount,
        resultEnvironment, originEnvironment, dotEnvironment,
        productionEnvironment, beforeEnvironment,
        Lanius.FunctionalView.Stateful.Env.pop,
        Lanius.FunctionalView.Stateful.Env.set,
        Lanius.FunctionalView.Env.push, nullableEnvironment]
    · subst index
      simp [afterCursor, afterAppendEnvironment, afterCount,
        resultEnvironment, originEnvironment, dotEnvironment,
        productionEnvironment, beforeEnvironment,
        Lanius.FunctionalView.Stateful.Env.pop,
        Lanius.FunctionalView.Stateful.Env.set,
        Lanius.FunctionalView.Env.push, nullableEnvironment]
    · subst index
      simp [afterCursor, afterAppendEnvironment, afterCount,
        resultEnvironment, originEnvironment, dotEnvironment,
        productionEnvironment, beforeEnvironment,
        Lanius.FunctionalView.Stateful.Env.pop,
        Lanius.FunctionalView.Stateful.Env.set,
        Lanius.FunctionalView.Env.push, nullableEnvironment]
    · subst index
      rw [Lanius.FunctionalView.Stateful.Env.set_other
        (different := by
          intro equal
          have valuesEqual := congrArg Fin.val equal
          change 8 = 11 at valuesEqual
          omega)]
      rw [Lanius.FunctionalView.Stateful.Env.set_other
        (different := by
          intro equal
          have valuesEqual := congrArg Fin.val equal
          change 8 = 4 at valuesEqual
          omega)]
      simp [beforeEnvironment, nullableEnvironment]
    · subst index
      rw [Lanius.FunctionalView.Stateful.Env.set_other
        (different := by
          intro equal
          have valuesEqual := congrArg Fin.val equal
          change 9 = 11 at valuesEqual
          omega)]
      rw [Lanius.FunctionalView.Stateful.Env.set_other
        (different := by
          intro equal
          have valuesEqual := congrArg Fin.val equal
          change 9 = 4 at valuesEqual
          omega)]
      simp [beforeEnvironment, nullableEnvironment]
    · subst index
      rw [Lanius.FunctionalView.Stateful.Env.set_other
        (different := by
          intro equal
          have valuesEqual := congrArg Fin.val equal
          change 10 = 11 at valuesEqual
          omega)]
      rw [Lanius.FunctionalView.Stateful.Env.set_other
        (different := by
          intro equal
          have valuesEqual := congrArg Fin.val equal
          change 10 = 4 at valuesEqual
          omega)]
      simp [beforeEnvironment, nullableEnvironment]
    · subst index
      simp [afterCursor, afterAppendEnvironment, afterCount,
        resultEnvironment, originEnvironment, dotEnvironment,
        productionEnvironment, beforeEnvironment,
        Lanius.FunctionalView.Stateful.Env.pop,
        Lanius.FunctionalView.Stateful.Env.set,
        Lanius.FunctionalView.Env.push, nullableEnvironment]
    all_goals simp_all [Fin.ext_iff, Fin.ofNat]
  rw [environmentEq] at assembled
  simpa [nullableBodyCommand, nullableCanonicalBodyCommand, beforeWorld,
    beforeEnvironment] using assembled

/-- A matching nullable candidate whose append reports full returns the
    capacity diagnostic immediately. The later state-count and cursor updates
    are unreachable, and every lexical binding is restored on return. -/
private theorem RecognizerNullableLoopInvariant.functional_full_body
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (candidateWithin : StateKeyWithinGrammar grammar candidate.key)
    (doesMatch : NullableCandidateMatches grammar candidate position expected
      candidateWithin.productionBound)
    (statusFull :
      let seed := recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState current
      (appendLogical workspaceLayout.capacity position seed workspace).1.status =
        .full) :
    let seed := recognizerNullableSeed parentProduction parentDot parentOrigin
      parentState current
    let outcome := (appendLogical workspaceLayout.capacity position seed
      workspace).1
    let nextValues := appendResultValues workspaceLayout workspace position seed
      workspaceValues
    let beforeWorld := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
    let afterWorld := nullableWorld words tokens nextValues grammarCell tokensCell workspaceCell
    let beforeEnvironment := nullableEnvironment words workspaceValues
      grammarCell workspaceCell workspaceLayout workspace.states.length
      position parentState parentProduction parentDot parentOrigin expected
      (Int.ofNat current)
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld beforeEnvironment nullableBodyCommand
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld beforeEnvironment := by
  dsimp only
  let seed := recognizerNullableSeed parentProduction parentDot parentOrigin
    parentState current
  let outcome := (appendLogical workspaceLayout.capacity position seed
    workspace).1
  let nextValues := appendResultValues workspaceLayout workspace position seed
    workspaceValues
  let beforeWorld := nullableWorld words tokens workspaceValues grammarCell tokensCell workspaceCell
  let afterWorld := nullableWorld words tokens nextValues grammarCell tokensCell workspaceCell
  let beforeEnvironment := nullableEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout workspace.states.length position parentState
    parentProduction parentDot parentOrigin expected (Int.ofNat current)
  let productionEnvironment := beforeEnvironment.push
    (.signed .i32 (Int.ofNat candidate.production))
  let dotEnvironment := productionEnvironment.push
    (.signed .i32 (Int.ofNat candidate.dot))
  let originEnvironment := dotEnvironment.push
    (.signed .i32 (Int.ofNat candidate.origin))
  let resultEnvironment := originEnvironment.push (appendOutcomeValue outcome)
  have reads := invariant.functional_candidate_reads candidate found
  have productionResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld beforeEnvironment
      (nullableStateValueTerm (arity := 12) (by omega) 28) =
      .ok (.signed .i32 (Int.ofNat candidate.production), beforeWorld) :=
    reads.1
  have dotResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld productionEnvironment
      (nullableStateValueTerm (arity := 13) (by omega) 29) =
      .ok (.signed .i32 (Int.ofNat candidate.dot), beforeWorld) := reads.2.1
  have originResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld dotEnvironment
      (nullableStateValueTerm (arity := 14) (by omega) 30) =
      .ok (.signed .i32 (Int.ofNat candidate.origin), beforeWorld) := reads.2.2
  have predicateResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld originEnvironment nullableCandidatePredicate =
      .ok (.boolean true, beforeWorld) := by
    have evaluated := invariant.functional_predicate candidate candidateWithin
    simpa [beforeWorld, originEnvironment, dotEnvironment,
      productionEnvironment, beforeEnvironment, doesMatch] using evaluated
  have appendResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      beforeWorld originEnvironment nullableAppendTerm =
      .ok (appendOutcomeValue outcome, afterWorld) :=
    invariant.functional_append candidate found candidateWithin doesMatch
  have statusFull' : outcome.status = .full := by
    simpa [outcome, seed] using statusFull
  have fullCondition : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment nullableFullCondition =
      .ok (.boolean true, afterWorld) := by
    have evaluated := nullableFullCondition_evaluates
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (grammarCell := grammarCell) afterWorld
      originEnvironment outcome
    rw [statusFull'] at evaluated
    simpa [resultEnvironment] using evaluated
  have positionValue : originEnvironment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat position) := by
    let position12 : Fin 12 := ⟨5, by decide⟩
    let position13 : Fin 13 := ⟨5, by decide⟩
    let position14 : Fin 14 := ⟨5, by decide⟩
    let position15 : Fin 15 := ⟨5, by decide⟩
    have position15Eq : position15 =
        ⟨position14.val, Nat.lt_succ_of_lt position14.isLt⟩ := Fin.ext rfl
    have position14Eq : position14 =
        ⟨position13.val, Nat.lt_succ_of_lt position13.isLt⟩ := Fin.ext rfl
    have position13Eq : position13 =
        ⟨position12.val, Nat.lt_succ_of_lt position12.isLt⟩ := Fin.ext rfl
    change originEnvironment position15 = _
    unfold originEnvironment dotEnvironment productionEnvironment
    rw [position15Eq, Lanius.FunctionalView.Env.push_before]
    rw [position14Eq, Lanius.FunctionalView.Env.push_before]
    rw [position13Eq, Lanius.FunctionalView.Env.push_before]
    rfl
  have fullResult : Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment nullableFullResult =
      .ok (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position), afterWorld) := by
    simpa [resultEnvironment] using nullableFullResult_evaluates
      (workspaceLayout := workspaceLayout) (grammar := grammar)
      (words := words) (grammarCell := grammarCell) afterWorld
      originEnvironment outcome position positionValue
  have returned : Lanius.FunctionalView.Stateful.Command.Evaluates
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment
      (.returnValue (some nullableFullResult))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment :=
    .returnSome fullResult
  have fullBranch : Lanius.FunctionalView.Stateful.Command.Evaluates
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment
      (.sequence (.returnValue (some nullableFullResult)) .skip)
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment :=
    .sequenceStop returned
      (by intro impossible; cases impossible)
  have selectedFull : Lanius.FunctionalView.Stateful.Command.Evaluates
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      afterWorld resultEnvironment
      (.ifThenElse nullableFullCondition
        (.sequence (.returnValue (some nullableFullResult)) .skip) .skip)
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld resultEnvironment :=
    .ifTrue fullCondition fullBranch
  have appendContinuation :
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (nullableTermMachine workspaceLayout grammar words grammarCell)
        (nullableStatefulMachine workspaceLayout grammar words grammarCell)
        afterWorld resultEnvironment
        (.sequence
          (.ifThenElse nullableFullCondition
            (.sequence (.returnValue (some nullableFullResult)) .skip) .skip)
          (.sequence (.setLocal ⟨4, by omega⟩ nullableStateCountTerm) .skip))
        (.returned (some (parseResultValue 2
          (Int.ofNat outcome.stateCount) (-1) (Int.ofNat position))))
        afterWorld resultEnvironment :=
    .sequenceStop selectedFull
      (by intro impossible; cases impossible)
  have appendBranch : Lanius.FunctionalView.Stateful.Command.Evaluates
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld originEnvironment
      (.letValue (.structure 2) nullableAppendTerm
        (.sequence
          (.ifThenElse nullableFullCondition
            (.sequence (.returnValue (some nullableFullResult)) .skip) .skip)
          (.sequence (.setLocal ⟨4, by omega⟩ nullableStateCountTerm) .skip)))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop resultEnvironment) :=
    .letValue appendResult appendContinuation
  have selected : Lanius.FunctionalView.Stateful.Command.Evaluates
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld originEnvironment
      (.ifThenElse nullableCandidatePredicate
        (.letValue (.structure 2) nullableAppendTerm
          (.sequence
            (.ifThenElse nullableFullCondition
              (.sequence (.returnValue (some nullableFullResult)) .skip) .skip)
            (.sequence (.setLocal ⟨4, by omega⟩ nullableStateCountTerm) .skip)))
        .skip)
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop resultEnvironment) :=
    .ifTrue predicateResult appendBranch
  have body : Lanius.FunctionalView.Stateful.Command.Evaluates
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld originEnvironment
      (.sequence
        (.ifThenElse nullableCandidatePredicate
          (.letValue (.structure 2) nullableAppendTerm
            (.sequence
              (.ifThenElse nullableFullCondition
                (.sequence (.returnValue (some nullableFullResult)) .skip)
                .skip)
              (.sequence
                (.setLocal ⟨4, by omega⟩ nullableStateCountTerm) .skip)))
          .skip)
        (.sequence
          (.setLocal ⟨11, by omega⟩
            (nullableStateValueTerm (arity := 15) (by omega) 32)) .skip))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1)
        (Int.ofNat position)))) afterWorld
      (Lanius.FunctionalView.Stateful.Env.pop resultEnvironment) :=
    .sequenceStop selected
      (by intro impossible; cases impossible)
  have assembled :=
    Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
      (type := parserI32Type) productionResult
      (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
        (type := parserI32Type) dotResult
        (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
          (type := parserI32Type) originResult body))
  have popped :
      Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.pop
          (Lanius.FunctionalView.Stateful.Env.pop
            (Lanius.FunctionalView.Stateful.Env.pop resultEnvironment))) =
      beforeEnvironment := by
    simp [resultEnvironment, originEnvironment, dotEnvironment,
      productionEnvironment]
  rw [popped] at assembled
  have outcomeCountEq : outcome.stateCount =
      (appendLogical workspaceLayout.capacity position seed workspace).2.states.length := by
    simpa [outcome] using appendLogical_stateCount_eq
      workspaceLayout.capacity position seed workspace
  rw [outcomeCountEq] at assembled
  simpa [nullableBodyCommand, nullableCanonicalBodyCommand, beforeWorld,
    beforeEnvironment] using assembled

structure RecognizerNullableNoMatchAdvance
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position parentProduction parentDot parentOrigin parentState
      expected current next : Nat)
    (tail : List Nat)
    (beforeInvariant : RecognizerNullableLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      (next :: tail))
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount)
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      (next :: tail) beforeInvariant candidate productionBound)
    (notMatches : ¬ NullableCandidateMatches grammar candidate position
      expected productionBound) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeNullableAfterBindings .next after
  effect : ModifiesOnly (CellSet.singleton cursorCell) before after
  invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell after position parentProduction
    parentDot parentOrigin parentState expected next tail

/-- A nonmatching final candidate consumes the empty chart suffix and leaves
    the cursor at the concrete `-1` sentinel. -/
structure RecognizerNullableNoMatchFinish
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position parentProduction parentDot parentOrigin parentState
      expected current : Nat)
    (beforeInvariant : RecognizerNullableLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current [])
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount)
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current []
      beforeInvariant candidate productionBound)
    (notMatches : ¬ NullableCandidateMatches grammar candidate position
      expected productionBound) where
  after : State
  execution : Executes verifiedParserCore before
    parserRecognizeNullableAfterBindings .next after
  effect : ModifiesOnly (CellSet.singleton cursorCell) before after
  invariant : RecognizerNullableFinishedInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell after position parentProduction
    parentDot parentOrigin parentState expected

/-- A nonmatching candidate skips the append and performs exactly one
    `STATE_NEXT` cursor advance. -/
noncomputable def RecognizerNullablePredicateResult.advance_no_match
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      (next :: tail) beforeInvariant candidate productionBound)
    (notMatches : ¬ NullableCandidateMatches grammar candidate position
      expected productionBound) :
    RecognizerNullableNoMatchAdvance grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current next
      tail beforeInvariant candidate productionBound predicate notMatches := by
  have conditionFalse : Evaluates verifiedParserCore runtime
      parserRecognizeNullablePredicate (.boolean false) predicate.after := by
    simpa [notMatches] using predicate.evaluation
  have selected : Executes verifiedParserCore runtime
      (.ifThenElse parserRecognizeNullablePredicate
        parserRecognizeNullableAppendStatement .skip) .next predicate.after :=
    executesIfFalse conditionFalse (executesSkip verifiedParserCore _)
  let advanced := predicate.invariant.chartCursor.advance
  let nextInvariant := predicate.invariant.after_cursor_effect
    advanced.invariant advanced.effect
  exact {
    after := advanced.after
    execution := by
      rw [extractedParserRecognize_nullable_after_bindings_shape]
      exact executesSequence selected advanced.execution
    effect := by
      simpa using
        (predicate.effect.weaken CellSet.empty_subset).trans_same
          advanced.effect
    invariant := nextInvariant
  }

/-- The terminal counterpart of `advance_no_match`: execute the skipped
    nullable append, read the final `STATE_NEXT`, and install `-1`. -/
noncomputable def RecognizerNullablePredicateResult.finish_no_match
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current []
      beforeInvariant candidate productionBound)
    (notMatches : ¬ NullableCandidateMatches grammar candidate position
      expected productionBound) :
    RecognizerNullableNoMatchFinish grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      beforeInvariant candidate productionBound predicate notMatches := by
  have conditionFalse : Evaluates verifiedParserCore runtime
      parserRecognizeNullablePredicate (.boolean false) predicate.after := by
    simpa [notMatches] using predicate.evaluation
  have selected : Executes verifiedParserCore runtime
      (.ifThenElse parserRecognizeNullablePredicate
        parserRecognizeNullableAppendStatement .skip) .next predicate.after :=
    executesIfFalse conditionFalse (executesSkip verifiedParserCore _)
  let exhausted := predicate.invariant.chartCursor.exhaust
  let finishedInvariant := predicate.invariant.after_cursor_exhaustion
    exhausted.finished exhausted.effect
  exact {
    after := exhausted.after
    execution := by
      rw [extractedParserRecognize_nullable_after_bindings_shape]
      exact executesSequence selected exhausted.execution
    effect := by
      simpa using
        (predicate.effect.weaken CellSet.empty_subset).trans_same
          exhausted.effect
    invariant := finishedInvariant
  }

/-- Close a nonmatching advance back to the exact extracted loop-body scope. -/
noncomputable def RecognizerNullableCandidateBindings.close_no_match_advance
    (bindings : RecognizerNullableCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      (next :: tail) beforeInvariant candidate found)
    (productionBound : candidate.key.production < grammar.productionCount)
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterOriginRead.bindLocal 39
        (.signed .i32 (Int.ofNat candidate.origin)))
      position parentProduction parentDot parentOrigin parentState expected
      current (next :: tail) bindings.invariant candidate productionBound)
    (notMatches : ¬ NullableCandidateMatches grammar candidate position
      expected productionBound) :
    let advanced := predicate.advance_no_match notMatches
    RecognizerNullableScopedExecution runtime advanced.after .next
      (CellSet.singleton cursorCell) candidate beforeInvariant found bindings := by
  dsimp only
  let advanced := predicate.advance_no_match notMatches
  exact bindings.close_scopes advanced.after .next
    (CellSet.singleton cursorCell) advanced.execution advanced.effect
    advanced.invariant.chartCursor.recognizer.wellFormed

/-- The nonmatching path's next-iteration invariant after the three temporary
    candidate locals have left scope. -/
noncomputable def RecognizerNullableCandidateBindings.after_no_match_advance
    (bindings : RecognizerNullableCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      (next :: tail) beforeInvariant candidate found)
    (productionBound : candidate.key.production < grammar.productionCount)
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterOriginRead.bindLocal 39
        (.signed .i32 (Int.ofNat candidate.origin)))
      position parentProduction parentDot parentOrigin parentState expected
      current (next :: tail) bindings.invariant candidate productionBound)
    (notMatches : ¬ NullableCandidateMatches grammar candidate position
      expected productionBound) :
    let closed := bindings.close_no_match_advance productionBound predicate
      notMatches
    RecognizerNullableLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell closed.after position
      parentProduction parentDot parentOrigin parentState expected next tail := by
  dsimp only
  let advanced := predicate.advance_no_match notMatches
  let closed := bindings.close_no_match_advance productionBound predicate
    notMatches
  exact closed.restore_invariant advanced.invariant (by
    intro cell written
    exact .inr (.inr written))

/-- Close the terminal nonmatching path back through the extracted candidate
    bindings. -/
noncomputable def RecognizerNullableCandidateBindings.close_no_match_finish
    (bindings : RecognizerNullableCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current []
      beforeInvariant candidate found)
    (productionBound : candidate.key.production < grammar.productionCount)
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterOriginRead.bindLocal 39
        (.signed .i32 (Int.ofNat candidate.origin)))
      position parentProduction parentDot parentOrigin parentState expected
      current [] bindings.invariant candidate productionBound)
    (notMatches : ¬ NullableCandidateMatches grammar candidate position
      expected productionBound) :
    let finished := predicate.finish_no_match notMatches
    RecognizerNullableScopedExecution runtime finished.after .next
      (CellSet.singleton cursorCell) candidate beforeInvariant found bindings := by
  dsimp only
  let finished := predicate.finish_no_match notMatches
  exact bindings.close_scopes finished.after .next
    (CellSet.singleton cursorCell) finished.execution finished.effect
    finished.invariant.chartCursor.recognizer.wellFormed

/-- Restore the complete terminal nullable invariant after the final
    nonmatching candidate's temporary bindings leave scope. -/
noncomputable def RecognizerNullableCandidateBindings.after_no_match_finish
    (bindings : RecognizerNullableCandidateBindings grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current []
      beforeInvariant candidate found)
    (productionBound : candidate.key.production < grammar.productionCount)
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (bindings.afterOriginRead.bindLocal 39
        (.signed .i32 (Int.ofNat candidate.origin)))
      position parentProduction parentDot parentOrigin parentState expected
      current [] bindings.invariant candidate productionBound)
    (notMatches : ¬ NullableCandidateMatches grammar candidate position
      expected productionBound) :
    let closed := bindings.close_no_match_finish productionBound predicate
      notMatches
    RecognizerNullableFinishedInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell closed.after position
      parentProduction parentDot parentOrigin parentState expected := by
  dsimp only
  let finished := predicate.finish_no_match notMatches
  let closed := bindings.close_no_match_finish productionBound predicate
    notMatches
  exact closed.restore_finished finished.invariant (by
    intro cell written
    exact .inr (.inr written))

structure RecognizerNullableMatchedAppend
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position parentProduction parentDot parentOrigin parentState
      expected current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerNullableLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount)
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining beforeInvariant candidate productionBound)
    (doesMatch : NullableCandidateMatches grammar candidate position expected
      productionBound)
    (statusOk : (appendLogical workspaceLayout.capacity position
      (recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState current) workspace).1.status = .ok) where
  appended : RecognizerNullableOkResult grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell predicate.after position parentProduction
    parentDot parentOrigin parentState current
    predicate.invariant.append_invariant
  execution : Executes verifiedParserCore before
    (.ifThenElse parserRecognizeNullablePredicate
      parserRecognizeNullableAppendStatement .skip) .next appended.after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.singleton stateCountCell)) before appended.after
  cursorResult : RecognizerNullableOkAppendCursor grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell predicate.after position
    parentProduction parentDot parentOrigin parentState expected current
    remaining predicate.invariant appended

/-- On a true nullable predicate, execute the shared append operation and
    transport the active chart cursor across deduplication or insertion. -/
noncomputable def RecognizerNullablePredicateResult.execute_matched_append
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining beforeInvariant candidate productionBound)
    (doesMatch : NullableCandidateMatches grammar candidate position expected
      productionBound)
    (statusOk : (appendLogical workspaceLayout.capacity position
      (recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState current) workspace).1.status = .ok) :
    RecognizerNullableMatchedAppend grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining beforeInvariant candidate productionBound predicate doesMatch
      statusOk := by
  have conditionTrue : Evaluates verifiedParserCore runtime
      parserRecognizeNullablePredicate (.boolean true) predicate.after := by
    simpa [doesMatch] using predicate.evaluation
  let appended := predicate.invariant.append_invariant.execute_ok
    (predicate.seed_derivation doesMatch) statusOk
  exact {
    appended := appended
    execution := executesIfTrue conditionTrue appended.execution
    effect := by
      exact (predicate.effect.weaken CellSet.empty_subset).trans_same
        appended.effect
    cursorResult := predicate.invariant.classify_ok_append appended
  }

inductive RecognizerNullableMatchedAdvance
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position parentProduction parentDot parentOrigin parentState
      expected current next : Nat)
    (tail : List Nat)
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount)
    (beforeInvariant : RecognizerNullableLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      (next :: tail))
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      (next :: tail) beforeInvariant candidate productionBound)
    (doesMatch : NullableCandidateMatches grammar candidate position expected
      productionBound)
    (statusOk : (appendLogical workspaceLayout.capacity position
      (recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState current) workspace).1.status = .ok)
    (matched : RecognizerNullableMatchedAppend grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position parentProduction
      parentDot parentOrigin parentState expected current (next :: tail)
      beforeInvariant candidate productionBound predicate doesMatch statusOk) :
    Type
  | unchanged
      (after : State)
      (execution : Executes verifiedParserCore before
        parserRecognizeNullableAfterBindings .next after)
      (effect : ModifiesOnly
        (CellSet.union (CellSet.singleton workspaceCell)
          (CellSet.union (CellSet.singleton stateCountCell)
            (CellSet.singleton cursorCell))) before after)
      (beforeAdvance : RecognizerNullableLoopInvariant grammarLayout grammar
        words tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2
        (appendResultValues workspaceLayout workspace position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell
        matched.appended.after position parentProduction parentDot
        parentOrigin parentState expected current (next :: tail))
      (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
        tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2
        (appendResultValues workspaceLayout workspace position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell after
        position parentProduction parentDot parentOrigin parentState expected
        next tail)
      (countUnchanged :
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2.states.length =
          workspace.states.length) :
      RecognizerNullableMatchedAdvance grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position
        parentProduction parentDot parentOrigin parentState expected current
        next tail candidate productionBound beforeInvariant predicate
        doesMatch statusOk matched
  | extended
      (after : State)
      (execution : Executes verifiedParserCore before
        parserRecognizeNullableAfterBindings .next after)
      (effect : ModifiesOnly
        (CellSet.union (CellSet.singleton workspaceCell)
          (CellSet.union (CellSet.singleton stateCountCell)
            (CellSet.singleton cursorCell))) before after)
      (beforeAdvance : RecognizerNullableLoopInvariant grammarLayout grammar
        words tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2
        (appendResultValues workspaceLayout workspace position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell
        matched.appended.after position parentProduction parentDot
        parentOrigin parentState expected current
        ((next :: tail) ++ [workspace.states.length]))
      (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
        tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2
        (appendResultValues workspaceLayout workspace position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell after
        position parentProduction parentDot parentOrigin parentState expected
        next (tail ++ [workspace.states.length]))
      (countIncreased :
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2.states.length =
          workspace.states.length + 1) :
      RecognizerNullableMatchedAdvance grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position
        parentProduction parentDot parentOrigin parentState expected current
        next tail candidate productionBound beforeInvariant predicate
        doesMatch statusOk matched

/-- After a successful matching append, read the current state's updated
    `STATE_NEXT`.  If insertion extended the chart, the new state remains in
    the unvisited tail and will be processed by the same loop. -/
noncomputable def RecognizerNullableMatchedAppend.advance
    (matched : RecognizerNullableMatchedAppend grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position parentProduction
      parentDot parentOrigin parentState expected current (next :: tail)
      beforeInvariant candidate productionBound predicate doesMatch statusOk) :
    RecognizerNullableMatchedAdvance grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position parentProduction
      parentDot parentOrigin parentState expected current next tail candidate
      productionBound beforeInvariant predicate doesMatch statusOk matched := by
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton cursorCell))
  cases matched.cursorResult with
  | unchanged cursorInvariant countUnchanged =>
      let advanced := cursorInvariant.chartCursor.advance
      let nextInvariant := cursorInvariant.after_cursor_effect
        advanced.invariant advanced.effect
      exact .unchanged advanced.after (by
        rw [extractedParserRecognize_nullable_after_bindings_shape]
        exact executesSequence matched.execution advanced.execution) (by
        have first : ModifiesOnly writes runtime matched.appended.after :=
          matched.effect.weaken (by
            intro cell listed
            exact match listed with
            | .inl workspace => .inl workspace
            | .inr count => .inr (.inl count))
        have second : ModifiesOnly writes matched.appended.after
            advanced.after := advanced.effect.weaken (by
          intro cell listed
          exact .inr (.inr listed))
        exact first.trans_same second) cursorInvariant nextInvariant
        countUnchanged
  | extended cursorInvariant countIncreased =>
      have suffixShape : (next :: tail) ++ [workspace.states.length] =
          next :: (tail ++ [workspace.states.length]) := by simp
      have normalized : RecognizerNullableLoopInvariant grammarLayout grammar
          words tokens workspaceLayout
          (appendLogical workspaceLayout.capacity position
            (recognizerNullableSeed parentProduction parentDot parentOrigin
              parentState current) workspace).2
          (appendResultValues workspaceLayout workspace position
            (recognizerNullableSeed parentProduction parentDot parentOrigin
              parentState current) workspaceValues)
          grammarCell tokensCell workspaceCell stateCountCell cursorCell
          matched.appended.after position parentProduction parentDot
          parentOrigin parentState expected current
          (next :: (tail ++ [workspace.states.length])) := by
        simpa only [suffixShape] using cursorInvariant
      let advanced := normalized.chartCursor.advance
      let nextInvariant := normalized.after_cursor_effect advanced.invariant
        advanced.effect
      exact .extended advanced.after (by
        rw [extractedParserRecognize_nullable_after_bindings_shape]
        exact executesSequence matched.execution advanced.execution) (by
        have first : ModifiesOnly writes runtime matched.appended.after :=
          matched.effect.weaken (by
            intro cell listed
            exact match listed with
            | .inl workspace => .inl workspace
            | .inr count => .inr (.inl count))
        have second : ModifiesOnly writes matched.appended.after
            advanced.after := advanced.effect.weaken (by
          intro cell listed
          exact .inr (.inr listed))
        exact first.trans_same second) normalized nextInvariant countIncreased

/-- Result of processing a matching candidate that was the final element of
    the pre-append chart. Deduplication exhausts the cursor; insertion extends
    the chart by one state and advances to that newly inserted state. -/
inductive RecognizerNullableMatchedLast
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position parentProduction parentDot parentOrigin parentState
      expected current : Nat)
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount)
    (beforeInvariant : RecognizerNullableLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current [])
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current []
      beforeInvariant candidate productionBound)
    (doesMatch : NullableCandidateMatches grammar candidate position expected
      productionBound)
    (statusOk : (appendLogical workspaceLayout.capacity position
      (recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState current) workspace).1.status = .ok)
    (matched : RecognizerNullableMatchedAppend grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position parentProduction
      parentDot parentOrigin parentState expected current [] beforeInvariant
      candidate productionBound predicate doesMatch statusOk) : Type
  | finished
      (after : State)
      (execution : Executes verifiedParserCore before
        parserRecognizeNullableAfterBindings .next after)
      (effect : ModifiesOnly
        (CellSet.union (CellSet.singleton workspaceCell)
          (CellSet.union (CellSet.singleton stateCountCell)
            (CellSet.singleton cursorCell))) before after)
      (beforeExhaust : RecognizerNullableLoopInvariant grammarLayout grammar
        words tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2
        (appendResultValues workspaceLayout workspace position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell
        matched.appended.after position parentProduction parentDot
        parentOrigin parentState expected current [])
      (invariant : RecognizerNullableFinishedInvariant grammarLayout grammar
        words tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2
        (appendResultValues workspaceLayout workspace position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell after
        position parentProduction parentDot parentOrigin parentState expected)
      (countUnchanged :
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2.states.length =
          workspace.states.length) :
      RecognizerNullableMatchedLast grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position parentProduction
        parentDot parentOrigin parentState expected current candidate
        productionBound beforeInvariant predicate doesMatch statusOk matched
  | extended
      (after : State)
      (execution : Executes verifiedParserCore before
        parserRecognizeNullableAfterBindings .next after)
      (effect : ModifiesOnly
        (CellSet.union (CellSet.singleton workspaceCell)
          (CellSet.union (CellSet.singleton stateCountCell)
            (CellSet.singleton cursorCell))) before after)
      (beforeAdvance : RecognizerNullableLoopInvariant grammarLayout grammar
        words tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2
        (appendResultValues workspaceLayout workspace position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell
        matched.appended.after position parentProduction parentDot
        parentOrigin parentState expected current [workspace.states.length])
      (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
        tokens workspaceLayout
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2
        (appendResultValues workspaceLayout workspace position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspaceValues)
        grammarCell tokensCell workspaceCell stateCountCell cursorCell after
        position parentProduction parentDot parentOrigin parentState expected
        workspace.states.length [])
      (countIncreased :
        (appendLogical workspaceLayout.capacity position
          (recognizerNullableSeed parentProduction parentDot parentOrigin
            parentState current) workspace).2.states.length =
          workspace.states.length + 1) :
      RecognizerNullableMatchedLast grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before position parentProduction
        parentDot parentOrigin parentState expected current candidate
        productionBound beforeInvariant predicate doesMatch statusOk matched

/-- Execute the final candidate's cursor transition after a successful
    matching append. -/
noncomputable def RecognizerNullableMatchedAppend.finish_or_extend
    (matched : RecognizerNullableMatchedAppend grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position parentProduction
      parentDot parentOrigin parentState expected current [] beforeInvariant
      candidate productionBound predicate doesMatch statusOk) :
    RecognizerNullableMatchedLast grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position parentProduction
      parentDot parentOrigin parentState expected current candidate
      productionBound beforeInvariant predicate doesMatch statusOk matched := by
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton cursorCell))
  cases matched.cursorResult with
  | unchanged cursorInvariant countUnchanged =>
      let exhausted := cursorInvariant.chartCursor.exhaust
      let finishedInvariant := cursorInvariant.after_cursor_exhaustion
        exhausted.finished exhausted.effect
      exact .finished exhausted.after (by
        rw [extractedParserRecognize_nullable_after_bindings_shape]
        exact executesSequence matched.execution exhausted.execution) (by
        have first : ModifiesOnly writes runtime matched.appended.after :=
          matched.effect.weaken (by
            intro cell listed
            exact match listed with
            | .inl workspace => .inl workspace
            | .inr count => .inr (.inl count))
        have second : ModifiesOnly writes matched.appended.after
            exhausted.after := exhausted.effect.weaken (by
          intro cell listed
          exact .inr (.inr listed))
        exact first.trans_same second) cursorInvariant finishedInvariant
        countUnchanged
  | extended cursorInvariant countIncreased =>
      have suffixShape : [] ++ [workspace.states.length] =
          [workspace.states.length] := by simp
      have normalized : RecognizerNullableLoopInvariant grammarLayout grammar
          words tokens workspaceLayout
          (appendLogical workspaceLayout.capacity position
            (recognizerNullableSeed parentProduction parentDot parentOrigin
              parentState current) workspace).2
          (appendResultValues workspaceLayout workspace position
            (recognizerNullableSeed parentProduction parentDot parentOrigin
              parentState current) workspaceValues)
          grammarCell tokensCell workspaceCell stateCountCell cursorCell
          matched.appended.after position parentProduction parentDot
          parentOrigin parentState expected current [workspace.states.length] :=
        by simpa only [suffixShape] using cursorInvariant
      let advanced := normalized.chartCursor.advance
      let nextInvariant := normalized.after_cursor_effect advanced.invariant
        advanced.effect
      exact .extended advanced.after (by
        rw [extractedParserRecognize_nullable_after_bindings_shape]
        exact executesSequence matched.execution advanced.execution) (by
        have first : ModifiesOnly writes runtime matched.appended.after :=
          matched.effect.weaken (by
            intro cell listed
            exact match listed with
            | .inl workspace => .inl workspace
            | .inr count => .inr (.inl count))
        have second : ModifiesOnly writes matched.appended.after
            advanced.after := advanced.effect.weaken (by
          intro cell listed
          exact .inr (.inr listed))
        exact first.trans_same second) normalized nextInvariant countIncreased

structure RecognizerNullableMatchedFull
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position parentProduction parentDot parentOrigin parentState
      expected current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerNullableLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining)
    (candidate : EarleyState)
    (productionBound : candidate.key.production < grammar.productionCount)
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining beforeInvariant candidate productionBound)
    (doesMatch : NullableCandidateMatches grammar candidate position expected
      productionBound)
    (statusFull : (appendLogical workspaceLayout.capacity position
      (recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState current) workspace).1.status = .full) where
  after : State
  execution : Executes verifiedParserCore before
    (.ifThenElse parserRecognizeNullablePredicate
      parserRecognizeNullableAppendStatement .skip)
    (.returned (some (parseResultValue 2
      (Int.ofNat (appendLogical workspaceLayout.capacity position
        (recognizerNullableSeed parentProduction parentDot parentOrigin
          parentState current) workspace).1.stateCount)
      (-1) (Int.ofNat position)))) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  invariant : RecognizerInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell after

noncomputable def RecognizerNullablePredicateResult.execute_matched_full
    (predicate : RecognizerNullablePredicateResult grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining beforeInvariant candidate productionBound)
    (doesMatch : NullableCandidateMatches grammar candidate position expected
      productionBound)
    (statusFull : (appendLogical workspaceLayout.capacity position
      (recognizerNullableSeed parentProduction parentDot parentOrigin
        parentState current) workspace).1.status = .full) :
    RecognizerNullableMatchedFull grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining beforeInvariant candidate productionBound predicate doesMatch
      statusFull := by
  have conditionTrue : Evaluates verifiedParserCore runtime
      parserRecognizeNullablePredicate (.boolean true) predicate.after := by
    simpa [doesMatch] using predicate.evaluation
  let full := predicate.invariant.append_invariant.execute_full
    (predicate.seed_derivation doesMatch) statusFull
  exact {
    after := full.after
    execution := executesIfTrue conditionTrue full.execution
    effect := by
      exact (predicate.effect.weaken CellSet.empty_subset).trans_same
        full.effect
    wellFormed := full.wellFormed
    invariant := full.invariant
  }

abbrev RecognizerNullableLoopOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position parentProduction parentDot parentOrigin parentState
      expected : Nat) : State → Completion → Prop :=
  WorkspaceLoopOutcome workspaceLayout.capacity beforeWorkspace
    (parserCapacityCompletion position)
    (fun workspace workspaceValues after =>
      RecognizerNullableFinishedInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell after position parentProduction
        parentDot parentOrigin parentState expected)
    (fun workspace workspaceValues after =>
      RecognizerInvariant grammarLayout grammar words tokens workspaceLayout
        workspace workspaceValues grammarCell tokensCell workspaceCell after)

structure RecognizerNullableLoopExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (position parentProduction parentDot parentOrigin parentState
      expected current : Nat)
    (remaining : List Nat)
    (beforeInvariant : RecognizerNullableLoopInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before position
      parentProduction parentDot parentOrigin parentState expected current
      remaining) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before parserRecognizeNullableLoop
    completion after
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton stateCountCell)
        (CellSet.singleton cursorCell))) before after
  outcome : RecognizerNullableLoopOutcome grammarLayout grammar words tokens
    workspaceLayout workspace grammarCell tokensCell workspaceCell stateCountCell
    cursorCell position parentProduction parentDot parentOrigin parentState
    expected after completion

/-- One active nullable-traversal configuration.  The physical runtime is
    retained solely as refinement evidence for the enclosing Core proof. -/
structure RecognizerNullableActiveConfig
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position parentProduction parentDot parentOrigin parentState
      expected : Nat) where
  workspace : LogicalWorkspace
  workspaceValues : List Int
  runtime : State
  current : Nat
  remaining : List Nat
  invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell runtime position
    parentProduction parentDot parentOrigin parentState expected current
    remaining

/-- The explicit sentinel configuration reached after the final chart state.
    Giving this state a first-class constructor is what allows the generic
    FunctionalView loop to observe the real final false condition. -/
structure RecognizerNullableSentinelConfig
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position parentProduction parentDot parentOrigin parentState
      expected : Nat) where
  workspace : LogicalWorkspace
  workspaceValues : List Int
  runtime : State
  invariant : RecognizerNullableFinishedInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell runtime position
    parentProduction parentDot parentOrigin parentState expected

inductive RecognizerNullableConfig
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position parentProduction parentDot parentOrigin parentState
      expected : Nat) where
  | active (config : RecognizerNullableActiveConfig grammarLayout grammar words
      tokens workspaceLayout grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position parentProduction parentDot
      parentOrigin parentState expected)
  | sentinel (config : RecognizerNullableSentinelConfig grammarLayout grammar
      words tokens workspaceLayout grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position parentProduction parentDot
      parentOrigin parentState expected)

@[simp] def RecognizerNullableConfig.workspace
    (config : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected) : LogicalWorkspace :=
  match config with
  | RecognizerNullableConfig.active activeConfig => activeConfig.workspace
  | RecognizerNullableConfig.sentinel sentinelConfig => sentinelConfig.workspace

@[simp] def RecognizerNullableConfig.workspaceValues
    (config : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected) : List Int :=
  match config with
  | RecognizerNullableConfig.active activeConfig => activeConfig.workspaceValues
  | RecognizerNullableConfig.sentinel sentinelConfig =>
      sentinelConfig.workspaceValues

@[simp] def RecognizerNullableConfig.runtime
    (config : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected) : State :=
  match config with
  | RecognizerNullableConfig.active activeConfig => activeConfig.runtime
  | RecognizerNullableConfig.sentinel sentinelConfig => sentinelConfig.runtime

@[simp] def RecognizerNullableConfig.candidate
    (config : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected) : Int :=
  match config with
  | RecognizerNullableConfig.active activeConfig =>
      Int.ofNat activeConfig.current
  | RecognizerNullableConfig.sentinel _ => -1

/-- Pure FunctionalView state corresponding to a nullable traversal
    configuration. -/
def RecognizerNullableConfig.functionalRuntime
    (config : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected) :
    Lanius.FunctionalView.Stateful.Loop.Runtime
      (nullableTermMachine workspaceLayout grammar words grammarCell) 12 :=
  (nullableWorld words tokens config.workspaceValues grammarCell tokensCell workspaceCell,
    nullableEnvironment words config.workspaceValues grammarCell workspaceCell
      workspaceLayout config.workspace.states.length position parentState
      parentProduction parentDot parentOrigin expected config.candidate)

/-- Lexicographic termination measure.  Active configurations reserve one
    extra suffix step so the sentinel is strictly smaller even when no
    workspace insertion occurs on the final iteration. -/
def RecognizerNullableConfig.measure
    (config : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected) : Nat × Nat :=
  match config with
  | RecognizerNullableConfig.active activeConfig =>
      (workspaceLayout.capacity - activeConfig.workspace.states.length,
        activeConfig.remaining.length + 1)
  | RecognizerNullableConfig.sentinel sentinelConfig =>
      (workspaceLayout.capacity - sentinelConfig.workspace.states.length, 0)

theorem RecognizerNullableConfig.functional_condition
    (config : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected) :
    Lanius.FunctionalView.Term.evaluate
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      config.functionalRuntime.world config.functionalRuntime.environment
      nullableLoopCondition =
      .ok (.boolean (decide (config.candidate ≥ 0)),
        config.functionalRuntime.world) := by
  cases config with
  | active activeConfig =>
      simpa [RecognizerNullableConfig.functionalRuntime,
        RecognizerNullableConfig.workspace,
        RecognizerNullableConfig.workspaceValues,
        RecognizerNullableConfig.candidate,
        Lanius.FunctionalView.Stateful.Loop.Runtime.world,
        Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
        nullableLoopCondition_evaluates workspaceLayout grammar words
          activeConfig.workspaceValues grammarCell workspaceCell
          activeConfig.workspace.states.length position parentState
          parentProduction parentDot parentOrigin expected
          (Int.ofNat activeConfig.current)
  | sentinel sentinelConfig =>
      simpa [RecognizerNullableConfig.functionalRuntime,
        RecognizerNullableConfig.workspace,
        RecognizerNullableConfig.workspaceValues,
        RecognizerNullableConfig.candidate,
        Lanius.FunctionalView.Stateful.Loop.Runtime.world,
        Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
        nullableLoopCondition_evaluates workspaceLayout grammar words
          sentinelConfig.workspaceValues grammarCell workspaceCell
          sentinelConfig.workspace.states.length position parentState
          parentProduction parentDot parentOrigin expected (-1)

/-- Nullable traversal outcome synchronized across the compact FunctionalView
    runtime and the physical extracted-parser state.  Normal completion feeds
    the enclosing state loop, so it records the exact final workspace world
    and sentinel environment.  Capacity exhaustion returns immediately and
    needs no continuation relation. -/
inductive RecognizerNullableSynchronizedOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position parentProduction parentDot parentOrigin parentState
      expected : Nat)
    (after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (nullableTermMachine workspaceLayout grammar words grammarCell) 12) :
    State → Completion → Prop where
  | completed (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (invariant : RecognizerNullableFinishedInvariant grammarLayout grammar
        words tokens workspaceLayout workspace workspaceValues grammarCell
        tokensCell workspaceCell stateCountCell cursorCell physicalAfter
        position parentProduction parentDot parentOrigin parentState expected)
      (worldEq : after.world = nullableWorld words tokens workspaceValues
        grammarCell tokensCell workspaceCell)
      (environmentEq : after.environment = nullableEnvironment words
        workspaceValues grammarCell workspaceCell workspaceLayout
        workspace.states.length position parentState parentProduction parentDot
        parentOrigin expected (-1)) :
      RecognizerNullableSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell cursorCell position parentProduction parentDot
        parentOrigin parentState expected after physicalAfter .next
  | full (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (terminal : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter) :
      RecognizerNullableSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell cursorCell position parentProduction parentDot
        parentOrigin parentState expected after physicalAfter
        (parserCapacityCompletion position stateCount)

theorem RecognizerNullableSynchronizedOutcome.physical
    (outcome : RecognizerNullableSynchronizedOutcome grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position parentProduction
      parentDot parentOrigin parentState expected after physicalAfter
      completion) :
    RecognizerNullableLoopOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position parentProduction parentDot parentOrigin
      parentState expected physicalAfter completion := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter growth invariant _ _ =>
      exact .completed workspace workspaceValues physicalAfter growth invariant
  | full workspace workspaceValues physicalAfter growth terminal stateCount
      wellFormed =>
      exact .full workspace workspaceValues physicalAfter growth terminal
        stateCount wellFormed

/-- Proof-irrelevant data view of a synchronized nullable outcome.  Enclosing
    source-command proofs use this rather than eliminating the proof object
    directly, so the exact workspace world survives nullable replay. -/
theorem RecognizerNullableSynchronizedOutcome.view
    (outcome : RecognizerNullableSynchronizedOutcome grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position parentProduction
      parentDot parentOrigin parentState expected after physicalAfter
      completion) :
    (completion = .next ∧
      ∃ workspace : LogicalWorkspace,
      ∃ workspaceValues : List Int,
      ∃ growth : WorkspaceAppendClosure workspaceLayout.capacity
          beforeWorkspace workspace,
      ∃ invariant : RecognizerNullableFinishedInvariant grammarLayout grammar
          words tokens workspaceLayout workspace workspaceValues grammarCell
          tokensCell workspaceCell stateCountCell cursorCell physicalAfter
          position parentProduction parentDot parentOrigin parentState expected,
        after.world = nullableWorld words tokens workspaceValues grammarCell
          tokensCell workspaceCell ∧
        after.environment = nullableEnvironment words workspaceValues
          grammarCell workspaceCell workspaceLayout workspace.states.length
          position parentState parentProduction parentDot parentOrigin expected
          (-1)) ∨
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

theorem RecognizerNullableSynchronizedOutcome.prepend_growth
    (outcome : RecognizerNullableSynchronizedOutcome grammarLayout grammar words
      tokens workspaceLayout middleWorkspace grammarCell tokensCell
      workspaceCell stateCountCell cursorCell position parentProduction
      parentDot parentOrigin parentState expected after physicalAfter
      completion)
    (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
      middleWorkspace) :
    RecognizerNullableSynchronizedOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell cursorCell position parentProduction parentDot parentOrigin
      parentState expected after physicalAfter completion := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter nextGrowth invariant
      worldEq environmentEq =>
      exact .completed workspace workspaceValues physicalAfter
        (growth.trans nextGrowth) invariant worldEq environmentEq
  | full workspace workspaceValues physicalAfter nextGrowth terminal stateCount
      wellFormed =>
      exact .full workspace workspaceValues physicalAfter
        (growth.trans nextGrowth) terminal stateCount wellFormed

/-- Result transported by the FunctionalView nullable traversal.  The loop
    trace is the semantic execution; the structural-Core fields connect that
    trace to the exact extracted recognizer while the migration is in
    progress. -/
structure RecognizerNullableFunctionalResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (position parentProduction parentDot parentOrigin parentState
      expected : Nat)
    (config : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (_after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (nullableTermMachine workspaceLayout grammar words grammarCell) 12) where
  physicalAfter : State
  execution : Executes verifiedParserCore config.runtime
    parserRecognizeNullableLoop
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
    physicalAfter
  effect : ModifiesOnly
    (CellSet.union (CellSet.singleton workspaceCell)
      (CellSet.union (CellSet.singleton stateCountCell)
        (CellSet.singleton cursorCell))) config.runtime physicalAfter
  outcome : RecognizerNullableSynchronizedOutcome grammarLayout grammar words
    tokens workspaceLayout config.workspace grammarCell tokensCell workspaceCell
    stateCountCell cursorCell position parentProduction parentDot parentOrigin
    parentState expected _after physicalAfter
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)

/-- One nullable-traversal decision whose semantic edge is the exact
    artifact-derived FunctionalView body. -/
noncomputable def RecognizerNullableConfig.functional_decide
    (config : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected) :
    Lanius.FunctionalView.Stateful.Loop.Decision
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      nullableLoopCondition nullableBodyCommand
      (RecognizerNullableConfig grammarLayout grammar words tokens
        workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
        cursorCell position parentProduction parentDot parentOrigin parentState
        expected)
      RecognizerNullableConfig.functionalRuntime
      RecognizerNullableConfig.measure
      (RecognizerNullableFunctionalResult grammarLayout grammar words tokens
        workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
        cursorCell position parentProduction parentDot parentOrigin parentState
        expected) config := by
  let writes := CellSet.union (CellSet.singleton workspaceCell)
    (CellSet.union (CellSet.singleton stateCountCell)
      (CellSet.singleton cursorCell))
  cases config with
  | sentinel sentinelConfig =>
      have functionalFalse : Lanius.FunctionalView.Term.evaluate
          (nullableTermMachine workspaceLayout grammar words grammarCell)
          (RecognizerNullableConfig.functionalRuntime
            (.sentinel sentinelConfig)).world
          (RecognizerNullableConfig.functionalRuntime
            (.sentinel sentinelConfig)).environment
          nullableLoopCondition =
          .ok (.boolean false,
            (RecognizerNullableConfig.functionalRuntime
              (.sentinel sentinelConfig)).world) := by
        simpa [RecognizerNullableConfig.candidate] using
          (RecognizerNullableConfig.functional_condition
            (.sentinel sentinelConfig))
      apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
      exact {
        completion := .next
        after := RecognizerNullableConfig.functionalRuntime
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
      let predicate := bindings.evaluate_predicate candidateWithin
      have conditionTrue := invariant.chartCursor.condition_nonnegative
      have functionalTrue : Lanius.FunctionalView.Term.evaluate
          (nullableTermMachine workspaceLayout grammar words grammarCell)
          (RecognizerNullableConfig.functionalRuntime
            (.active activeConfig)).world
          (RecognizerNullableConfig.functionalRuntime
            (.active activeConfig)).environment
          nullableLoopCondition =
          .ok (.boolean true,
            (RecognizerNullableConfig.functionalRuntime
              (.active activeConfig)).world) := by
        simpa [RecognizerNullableConfig.candidate] using
          (RecognizerNullableConfig.functional_condition
            (.active activeConfig))
      by_cases doesMatch : NullableCandidateMatches grammar candidate position
          expected candidateWithin.productionBound
      · let seed := recognizerNullableSeed parentProduction parentDot
          parentOrigin parentState activeConfig.current
        let logical := appendLogical workspaceLayout.capacity position seed
          activeConfig.workspace
        let nextValues := appendResultValues workspaceLayout
          activeConfig.workspace position seed activeConfig.workspaceValues
        cases statusEq : logical.1.status with
        | full =>
            have statusFull : (appendLogical workspaceLayout.capacity position
                seed activeConfig.workspace).1.status = .full := by
              simpa [logical]
            let matched := predicate.execute_matched_full doesMatch (by
              simpa [seed] using statusFull)
            let innerExecution : Executes verifiedParserCore
                (bindings.afterOriginRead.bindLocal 39
                  (.signed .i32 (Int.ofNat candidate.origin)))
                parserRecognizeNullableAfterBindings
                (.returned (some (parseResultValue 2
                  (Int.ofNat logical.1.stateCount) (-1)
                  (Int.ofNat position)))) matched.after := by
              rw [extractedParserRecognize_nullable_after_bindings_shape]
              apply executesSequenceReturned
              simpa [logical, seed] using matched.execution
            let closed := bindings.close_scopes matched.after
              (.returned (some (parseResultValue 2
                (Int.ofNat logical.1.stateCount) (-1)
                (Int.ofNat position))))
              (CellSet.singleton workspaceCell) innerExecution matched.effect
              matched.wellFormed
            have closedInvariant : RecognizerInvariant grammarLayout grammar
                words tokens workspaceLayout activeConfig.workspace
                activeConfig.workspaceValues grammarCell tokensCell
                workspaceCell closed.after := by
              apply RecognizerInvariant.after_same_workspace_effect
                invariant.chartCursor.recognizer closed.effect
                closed.wellFormed matched.invariant closed.cells
            have bodyResult := invariant.functional_full_body candidate found
              candidateWithin doesMatch (by simpa [seed] using statusFull)
            let returnedRuntime :
                Lanius.FunctionalView.Stateful.Loop.Runtime
                  (nullableTermMachine workspaceLayout grammar words
                    grammarCell) 12 :=
              (nullableWorld words tokens nextValues grammarCell tokensCell workspaceCell,
                (RecognizerNullableConfig.functionalRuntime
                  (.active activeConfig)).environment)
            have functionalBody :
                Lanius.FunctionalView.Stateful.Command.Evaluates
                  (nullableTermMachine workspaceLayout grammar words grammarCell)
                  (nullableStatefulMachine workspaceLayout grammar words
                    grammarCell)
                  (RecognizerNullableConfig.functionalRuntime
                    (.active activeConfig)).world
                  (RecognizerNullableConfig.functionalRuntime
                    (.active activeConfig)).environment nullableBodyCommand
                  (.returned (some (parseResultValue 2
                    (Int.ofNat logical.1.stateCount) (-1)
                    (Int.ofNat position))))
                  returnedRuntime.world returnedRuntime.environment := by
              simpa [RecognizerNullableConfig.functionalRuntime,
                RecognizerNullableConfig.candidate, logical, returnedRuntime,
                nextValues, seed,
                Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                  bodyResult
            apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
            exact {
              completion := .returned (some (parseResultValue 2
                (Int.ofNat logical.1.stateCount) (-1)
                (Int.ofNat position)))
              after := returnedRuntime
              edge := .returned functionalTrue functionalBody
              result := {
                physicalAfter := closed.after
                execution := by
                  rw [extractedParserRecognize_nullable_loop_shape]
                  exact executesWhileReturned conditionTrue closed.execution
                effect := closed.effect.weaken (by
                  intro cell written
                  exact .inl written)
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
            cases remainingEq : activeConfig.remaining with
            | nil =>
                have caseInvariant : RecognizerNullableLoopInvariant
                    grammarLayout grammar words tokens workspaceLayout
                    activeConfig.workspace activeConfig.workspaceValues
                    grammarCell tokensCell workspaceCell stateCountCell
                    cursorCell activeConfig.runtime position parentProduction
                    parentDot parentOrigin parentState expected
                    activeConfig.current [] := by
                  simpa [remainingEq] using invariant
                let caseBindings := caseInvariant.bind_candidate_fields
                  candidate found
                let casePredicate := caseBindings.evaluate_predicate
                  candidateWithin
                let matched := casePredicate.execute_matched_append doesMatch (by
                  simpa [seed] using statusOk)
                let last := matched.finish_or_extend
                cases last with
                | finished innerAfter innerExecution innerEffect
                    beforeExhaust innerInvariant countUnchanged =>
                    let closed := caseBindings.close_scopes innerAfter .next writes
                      innerExecution innerEffect
                      innerInvariant.chartCursor.recognizer.wellFormed
                    let finished := closed.restore_finished innerInvariant (by
                      intro cell written
                      exact written)
                    let nextConfig : RecognizerNullableConfig grammarLayout
                        grammar words tokens workspaceLayout grammarCell
                        tokensCell workspaceCell stateCountCell cursorCell
                        position parentProduction parentDot parentOrigin
                        parentState expected := .sentinel {
                      workspace := logical.2
                      workspaceValues := nextValues
                      runtime := closed.after
                      invariant := by
                        simpa [logical, nextValues, seed] using finished
                    }
                    have bodyResult := caseInvariant.functional_ok_body candidate
                      found candidateWithin doesMatch (by
                        simpa [seed] using statusOk) []
                      matched.appended.after (by
                        simpa [logical, nextValues, seed] using beforeExhaust)
                    have functionalBody :
                        Lanius.FunctionalView.Stateful.Command.Evaluates
                          (nullableTermMachine workspaceLayout grammar words
                            grammarCell)
                          (nullableStatefulMachine workspaceLayout grammar words
                            grammarCell)
                          (RecognizerNullableConfig.functionalRuntime
                            (.active activeConfig)).world
                          (RecognizerNullableConfig.functionalRuntime
                            (.active activeConfig)).environment
                          nullableBodyCommand .next
                          nextConfig.functionalRuntime.world
                          nextConfig.functionalRuntime.environment := by
                      simpa [nextConfig,
                        RecognizerNullableConfig.functionalRuntime, logical,
                        nextValues, seed, encodeStateId,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
                        using bodyResult
                    apply Lanius.FunctionalView.Stateful.Loop.Decision.next
                      nextConfig
                    · exact .next functionalTrue functionalBody
                    · simp only [WellFoundedRelation.rel,
                        RecognizerNullableConfig.measure, nextConfig]
                      rw [countUnchanged]
                      apply Prod.Lex.right
                      show sizeOf 0 < sizeOf
                        (activeConfig.remaining.length + 1)
                      simpa [remainingEq] using Nat.zero_lt_one
                    · intro completion after result
                      exact {
                        physicalAfter := result.physicalAfter
                        execution := by
                          rw [extractedParserRecognize_nullable_loop_shape]
                          exact executesWhileTrueThen conditionTrue
                            closed.execution result.execution
                        effect := by
                          simpa [writes] using
                            closed.effect.trans_same result.effect
                        outcome := result.outcome.prepend_growth
                          (WorkspaceAppendClosure.single
                            workspaceLayout.capacity position seed
                            activeConfig.workspace)
                      }
                | extended innerAfter innerExecution innerEffect beforeAdvance
                    innerInvariant countIncreased =>
                    let closed := caseBindings.close_scopes innerAfter .next writes
                      innerExecution innerEffect
                      innerInvariant.chartCursor.recognizer.wellFormed
                    let nextInvariant := closed.restore_invariant innerInvariant
                      (by intro cell written; exact written)
                    let nextConfig : RecognizerNullableConfig grammarLayout
                        grammar words tokens workspaceLayout grammarCell
                        tokensCell workspaceCell stateCountCell cursorCell
                        position parentProduction parentDot parentOrigin
                        parentState expected := .active {
                      workspace := logical.2
                      workspaceValues := nextValues
                      runtime := closed.after
                      current := activeConfig.workspace.states.length
                      remaining := []
                      invariant := by
                        simpa [logical, nextValues, seed] using nextInvariant
                    }
                    have bodyResult := caseInvariant.functional_ok_body candidate
                      found candidateWithin doesMatch (by
                        simpa [seed] using statusOk)
                      [activeConfig.workspace.states.length]
                      matched.appended.after (by
                        simpa [logical, nextValues, seed] using beforeAdvance)
                    have functionalBody :
                        Lanius.FunctionalView.Stateful.Command.Evaluates
                          (nullableTermMachine workspaceLayout grammar words
                            grammarCell)
                          (nullableStatefulMachine workspaceLayout grammar words
                            grammarCell)
                          (RecognizerNullableConfig.functionalRuntime
                            (.active activeConfig)).world
                          (RecognizerNullableConfig.functionalRuntime
                            (.active activeConfig)).environment
                          nullableBodyCommand .next
                          nextConfig.functionalRuntime.world
                          nextConfig.functionalRuntime.environment := by
                      simpa [nextConfig,
                        RecognizerNullableConfig.functionalRuntime, logical,
                        nextValues, seed, encodeStateId,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
                        using bodyResult
                    apply Lanius.FunctionalView.Stateful.Loop.Decision.next
                      nextConfig
                    · exact .next functionalTrue functionalBody
                    · simp only [WellFoundedRelation.rel,
                        RecognizerNullableConfig.measure, nextConfig]
                      have afterFits := innerInvariant.chartCursor.recognizer
                        |>.workspaceEncoded.stateCountFits
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
                          rw [extractedParserRecognize_nullable_loop_shape]
                          exact executesWhileTrueThen conditionTrue
                            closed.execution result.execution
                        effect := by
                          simpa [writes] using
                            closed.effect.trans_same result.effect
                        outcome := result.outcome.prepend_growth
                          (WorkspaceAppendClosure.single
                            workspaceLayout.capacity position seed
                            activeConfig.workspace)
                      }
            | cons next tail =>
                have caseInvariant : RecognizerNullableLoopInvariant
                    grammarLayout grammar words tokens workspaceLayout
                    activeConfig.workspace activeConfig.workspaceValues
                    grammarCell tokensCell workspaceCell stateCountCell
                    cursorCell activeConfig.runtime position parentProduction
                    parentDot parentOrigin parentState expected
                    activeConfig.current (next :: tail) := by
                  simpa [remainingEq] using invariant
                let caseBindings := caseInvariant.bind_candidate_fields
                  candidate found
                let casePredicate := caseBindings.evaluate_predicate
                  candidateWithin
                let matched := casePredicate.execute_matched_append doesMatch (by
                  simpa [seed] using statusOk)
                let advanced := matched.advance
                cases advanced with
                | unchanged innerAfter innerExecution innerEffect
                    beforeAdvance innerInvariant countUnchanged =>
                    let closed := caseBindings.close_scopes innerAfter .next writes
                      innerExecution innerEffect
                      innerInvariant.chartCursor.recognizer.wellFormed
                    let nextInvariant := closed.restore_invariant innerInvariant
                      (by intro cell written; exact written)
                    let nextConfig : RecognizerNullableConfig grammarLayout
                        grammar words tokens workspaceLayout grammarCell
                        tokensCell workspaceCell stateCountCell cursorCell
                        position parentProduction parentDot parentOrigin
                        parentState expected := .active {
                      workspace := logical.2
                      workspaceValues := nextValues
                      runtime := closed.after
                      current := next
                      remaining := tail
                      invariant := by
                        simpa [logical, nextValues, seed] using nextInvariant
                    }
                    have bodyResult := caseInvariant.functional_ok_body candidate
                      found candidateWithin doesMatch (by
                        simpa [seed] using statusOk) (next :: tail)
                      matched.appended.after (by
                        simpa [logical, nextValues, seed] using beforeAdvance)
                    have functionalBody :
                        Lanius.FunctionalView.Stateful.Command.Evaluates
                          (nullableTermMachine workspaceLayout grammar words
                            grammarCell)
                          (nullableStatefulMachine workspaceLayout grammar words
                            grammarCell)
                          (RecognizerNullableConfig.functionalRuntime
                            (.active activeConfig)).world
                          (RecognizerNullableConfig.functionalRuntime
                            (.active activeConfig)).environment
                          nullableBodyCommand .next
                          nextConfig.functionalRuntime.world
                          nextConfig.functionalRuntime.environment := by
                      simpa [nextConfig,
                        RecognizerNullableConfig.functionalRuntime, logical,
                        nextValues, seed, encodeStateId,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
                        using bodyResult
                    apply Lanius.FunctionalView.Stateful.Loop.Decision.next
                      nextConfig
                    · exact .next functionalTrue functionalBody
                    · simp only [WellFoundedRelation.rel,
                        RecognizerNullableConfig.measure, nextConfig]
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
                          rw [extractedParserRecognize_nullable_loop_shape]
                          exact executesWhileTrueThen conditionTrue
                            closed.execution result.execution
                        effect := by
                          simpa [writes] using
                            closed.effect.trans_same result.effect
                        outcome := result.outcome.prepend_growth
                          (WorkspaceAppendClosure.single
                            workspaceLayout.capacity position seed
                            activeConfig.workspace)
                      }
                | extended innerAfter innerExecution innerEffect beforeAdvance
                    innerInvariant countIncreased =>
                    let closed := caseBindings.close_scopes innerAfter .next writes
                      innerExecution innerEffect
                      innerInvariant.chartCursor.recognizer.wellFormed
                    let nextInvariant := closed.restore_invariant innerInvariant
                      (by intro cell written; exact written)
                    let nextConfig : RecognizerNullableConfig grammarLayout
                        grammar words tokens workspaceLayout grammarCell
                        tokensCell workspaceCell stateCountCell cursorCell
                        position parentProduction parentDot parentOrigin
                        parentState expected := .active {
                      workspace := logical.2
                      workspaceValues := nextValues
                      runtime := closed.after
                      current := next
                      remaining := tail ++ [activeConfig.workspace.states.length]
                      invariant := by
                        simpa [logical, nextValues, seed] using nextInvariant
                    }
                    have bodyResult := caseInvariant.functional_ok_body candidate
                      found candidateWithin doesMatch (by
                        simpa [seed] using statusOk)
                      ((next :: tail) ++
                        [activeConfig.workspace.states.length])
                      matched.appended.after (by
                        simpa [logical, nextValues, seed] using beforeAdvance)
                    have functionalBody :
                        Lanius.FunctionalView.Stateful.Command.Evaluates
                          (nullableTermMachine workspaceLayout grammar words
                            grammarCell)
                          (nullableStatefulMachine workspaceLayout grammar words
                            grammarCell)
                          (RecognizerNullableConfig.functionalRuntime
                            (.active activeConfig)).world
                          (RecognizerNullableConfig.functionalRuntime
                            (.active activeConfig)).environment
                          nullableBodyCommand .next
                          nextConfig.functionalRuntime.world
                          nextConfig.functionalRuntime.environment := by
                      simpa [nextConfig,
                        RecognizerNullableConfig.functionalRuntime, logical,
                        nextValues, seed, encodeStateId,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                        Lanius.FunctionalView.Stateful.Loop.Runtime.environment]
                        using bodyResult
                    apply Lanius.FunctionalView.Stateful.Loop.Decision.next
                      nextConfig
                    · exact .next functionalTrue functionalBody
                    · simp only [WellFoundedRelation.rel,
                        RecognizerNullableConfig.measure, nextConfig]
                      have afterFits := innerInvariant.chartCursor.recognizer
                        |>.workspaceEncoded.stateCountFits
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
                          rw [extractedParserRecognize_nullable_loop_shape]
                          exact executesWhileTrueThen conditionTrue
                            closed.execution result.execution
                        effect := by
                          simpa [writes] using
                            closed.effect.trans_same result.effect
                        outcome := result.outcome.prepend_growth
                          (WorkspaceAppendClosure.single
                            workspaceLayout.capacity position seed
                            activeConfig.workspace)
                      }
      · cases remainingEq : activeConfig.remaining with
        | nil =>
            have caseInvariant : RecognizerNullableLoopInvariant grammarLayout
                grammar words tokens workspaceLayout activeConfig.workspace
                activeConfig.workspaceValues grammarCell tokensCell
                workspaceCell stateCountCell cursorCell activeConfig.runtime
                position parentProduction parentDot parentOrigin parentState
                expected activeConfig.current [] := by
              simpa [remainingEq] using invariant
            let caseBindings := caseInvariant.bind_candidate_fields candidate
              found
            let casePredicate := caseBindings.evaluate_predicate candidateWithin
            let closed := caseBindings.close_no_match_finish
              candidateWithin.productionBound casePredicate doesMatch
            let finished := caseBindings.after_no_match_finish
              candidateWithin.productionBound casePredicate doesMatch
            let nextConfig : RecognizerNullableConfig grammarLayout grammar
                words tokens workspaceLayout grammarCell tokensCell
                workspaceCell stateCountCell cursorCell position
                parentProduction parentDot parentOrigin parentState expected :=
              .sentinel {
                workspace := activeConfig.workspace
                workspaceValues := activeConfig.workspaceValues
                runtime := closed.after
                invariant := finished
              }
            have bodyResult := caseInvariant.functional_no_match_body candidate
              found candidateWithin doesMatch
            have functionalBody :
                Lanius.FunctionalView.Stateful.Command.Evaluates
                  (nullableTermMachine workspaceLayout grammar words grammarCell)
                  (nullableStatefulMachine workspaceLayout grammar words
                    grammarCell)
                  (RecognizerNullableConfig.functionalRuntime
                    (.active activeConfig)).world
                  (RecognizerNullableConfig.functionalRuntime
                    (.active activeConfig)).environment nullableBodyCommand
                  .next nextConfig.functionalRuntime.world
                  nextConfig.functionalRuntime.environment := by
              simpa [nextConfig,
                RecognizerNullableConfig.functionalRuntime,
                encodeStateId,
                Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                  bodyResult
            apply Lanius.FunctionalView.Stateful.Loop.Decision.next nextConfig
            · exact .next functionalTrue functionalBody
            · simp only [WellFoundedRelation.rel,
                RecognizerNullableConfig.measure, nextConfig]
              apply Prod.Lex.right
              show sizeOf 0 < sizeOf
                (activeConfig.remaining.length + 1)
              simpa [remainingEq] using Nat.zero_lt_one
            · intro completion after result
              exact {
                physicalAfter := result.physicalAfter
                execution := by
                  rw [extractedParserRecognize_nullable_loop_shape]
                  exact executesWhileTrueThen conditionTrue closed.execution
                    result.execution
                effect := by
                  have first : ModifiesOnly writes activeConfig.runtime
                      closed.after := closed.effect.weaken (by
                    intro cell written
                    exact .inr (.inr written))
                  simpa [writes] using first.trans_same result.effect
                outcome := result.outcome
              }
        | cons next tail =>
            have caseInvariant : RecognizerNullableLoopInvariant grammarLayout
                grammar words tokens workspaceLayout activeConfig.workspace
                activeConfig.workspaceValues grammarCell tokensCell
                workspaceCell stateCountCell cursorCell activeConfig.runtime
                position parentProduction parentDot parentOrigin parentState
                expected activeConfig.current (next :: tail) := by
              simpa [remainingEq] using invariant
            let caseBindings := caseInvariant.bind_candidate_fields candidate
              found
            let casePredicate := caseBindings.evaluate_predicate candidateWithin
            let closed := caseBindings.close_no_match_advance
              candidateWithin.productionBound casePredicate doesMatch
            let nextInvariant := caseBindings.after_no_match_advance
              candidateWithin.productionBound casePredicate doesMatch
            let nextConfig : RecognizerNullableConfig grammarLayout grammar
                words tokens workspaceLayout grammarCell tokensCell
                workspaceCell stateCountCell cursorCell position
                parentProduction parentDot parentOrigin parentState expected :=
              .active {
                workspace := activeConfig.workspace
                workspaceValues := activeConfig.workspaceValues
                runtime := closed.after
                current := next
                remaining := tail
                invariant := nextInvariant
              }
            have bodyResult := caseInvariant.functional_no_match_body candidate
              found candidateWithin doesMatch
            have functionalBody :
                Lanius.FunctionalView.Stateful.Command.Evaluates
                  (nullableTermMachine workspaceLayout grammar words grammarCell)
                  (nullableStatefulMachine workspaceLayout grammar words
                    grammarCell)
                  (RecognizerNullableConfig.functionalRuntime
                    (.active activeConfig)).world
                  (RecognizerNullableConfig.functionalRuntime
                    (.active activeConfig)).environment nullableBodyCommand
                  .next nextConfig.functionalRuntime.world
                  nextConfig.functionalRuntime.environment := by
              simpa [nextConfig,
                RecognizerNullableConfig.functionalRuntime,
                encodeStateId,
                Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                  bodyResult
            apply Lanius.FunctionalView.Stateful.Loop.Decision.next nextConfig
            · exact .next functionalTrue functionalBody
            · simp only [WellFoundedRelation.rel,
                RecognizerNullableConfig.measure, nextConfig]
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
                  rw [extractedParserRecognize_nullable_loop_shape]
                  exact executesWhileTrueThen conditionTrue closed.execution
                    result.execution
                effect := by
                  have first : ModifiesOnly writes activeConfig.runtime
                      closed.after := closed.effect.weaken (by
                    intro cell written
                    exact .inr (.inr written))
                  simpa [writes] using first.trans_same result.effect
                outcome := result.outcome
              }

/-- The total compact FunctionalView execution retained independently of its
    structural-Core refinement so an enclosing recognizer command can embed
    the same semantic trace. -/
noncomputable def RecognizerNullableConfig.functional_run
    (config : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected) :=
  Lanius.FunctionalView.Stateful.Loop.run
    (nullableTermMachine workspaceLayout grammar words grammarCell)
    (nullableStatefulMachine workspaceLayout grammar words grammarCell)
    nullableLoopCondition nullableBodyCommand
    (RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected)
    RecognizerNullableConfig.functionalRuntime
    RecognizerNullableConfig.measure
    (RecognizerNullableFunctionalResult grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected)
    RecognizerNullableConfig.functional_decide config

theorem RecognizerNullableConfig.functional_run_evaluates
    (config : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (nullableTermMachine workspaceLayout grammar words grammarCell)
      (nullableStatefulMachine workspaceLayout grammar words grammarCell)
      config.functionalRuntime.world config.functionalRuntime.environment
      nullableLoopCommand config.functional_run.completion
      config.functional_run.after.world
      config.functional_run.after.environment :=
  config.functional_run.trace.evaluates

/-- Total execution of the exact artifact-derived nullable-completion loop.
    The lexicographic measure first counts remaining workspace capacity and
    then the unvisited chart suffix. Insertion can extend the suffix only when
    it strictly consumes capacity; every other iteration shortens the suffix. -/
noncomputable def RecognizerNullableLoopInvariant.execute_loop
    (invariant : RecognizerNullableLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining) :
    RecognizerNullableLoopExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime position
      parentProduction parentDot parentOrigin parentState expected current
      remaining invariant := by
  let initial : RecognizerNullableConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      cursorCell position parentProduction parentDot parentOrigin parentState
      expected := .active {
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
