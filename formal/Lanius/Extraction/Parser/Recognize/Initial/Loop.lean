import Lanius.Extraction.Parser.Recognize.Root.Commands
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
/-! ## Artifact-derived FunctionalView for final root selection -/
/-! ## Artifact-derived FunctionalView for the initial continuation

The continuation begins after local `19` has been bound.  Its environment is
the union of the initial loop's live values and the thirteen values retained
by the position statement.  Reifying the complete sequence fixes the exact
boundary that the next synchronized loop proof must implement.
-/

private def initialContinuationLayout : Layout 16 := fun index =>
  [0, 2, 3, 4, 6, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19].get index

private def initialContinuationContext : Context :=
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
  let c12 := c11.bind 16 parserI32Type
  let c13 := c12.bind 17 parserI32Type
  let c14 := c13.bind 18 parserI32Type
  c14.bind 19 parserI32Type

private def initialLoopReification? :=
  reifyCommand? verifiedParserCore (.structure 0) initialContinuationContext true
    initialContinuationLayout 20 parserRecognizeInitialLoop

private theorem initialLoopReification_exists :
    initialLoopReification?.isSome := by
  native_decide

/-- Complete start-production loop recovered from the checked recognizer. -/
private def parserRecognizeInitialLoopView :=
  initialLoopReification?.get initialLoopReification_exists

private theorem parserRecognizeInitialLoopView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      initialContinuationLayout 20 parserRecognizeInitialLoopView.command =
      parserRecognizeInitialLoop :=
  parserRecognizeInitialLoopView.toCoreExactly

private def initialBodyReification? :=
  reifyCommand? verifiedParserCore (.structure 0) initialContinuationContext true
    initialContinuationLayout 20 parserRecognizeInitialLoopBody

private theorem initialBodyReification_exists :
    initialBodyReification?.isSome := by
  native_decide

private def parserRecognizeInitialBodyView :=
  initialBodyReification?.get initialBodyReification_exists

private def initialContinuationReification? :=
  reifyCommand? verifiedParserCore (.structure 0) initialContinuationContext false
    initialContinuationLayout 20 parserRecognizeAfterInitialIndexBinding

private theorem initialContinuationReification_exists :
    initialContinuationReification?.isSome := by
  native_decide

/-- Complete initial-loop plus position/root continuation recovered as one
    checked FunctionalView command. -/
private def parserRecognizeInitialContinuationView :=
  initialContinuationReification?.get initialContinuationReification_exists

private theorem parserRecognizeInitialContinuationView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      initialContinuationLayout 20
      parserRecognizeInitialContinuationView.command =
      parserRecognizeAfterInitialIndexBinding :=
  parserRecognizeInitialContinuationView.toCoreExactly

def positionStatementIntoInitialEmbedding :
    Lanius.FunctionalView.Embedding 13 16 where
  slot := fun index => [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 14].get index
  injective := by
    exact Lanius.FunctionalView.Embedding.listGetInjective
      ([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 14] :
        List (Fin 16)) (by decide)

private theorem positionStatementIntoInitialLayout_extends :
    Layout.Extends positionStatementIntoInitialEmbedding
      positionStatementLayout initialContinuationLayout := by
  apply Layout.Extends.ofFn
  native_decide

def initialLoopCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 16 :=
  parserRecognizeInitialLoopView.command

private def initialSlot {arity : Nat} (index : Fin arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .reference (.slot index)

private def initialLiteral {arity : Nat} (value : Int) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .reference (.literal (.signed .i32 value))

private def initialConstant {arity : Nat} (id : ConstantId) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.constant id parserI32Type) []

private def initialBinary {arity : Nat} (operation : BinaryOp)
    (left right : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity) :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.binary operation parserI32Type parserI32Type
    (if operation = .less ∨ operation = .equal then .scalar .bool
      else parserI32Type)) [left, right]

private def initialNegativeOne {arity : Nat} :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature arity :=
  .apply (.unary .negate parserI32Type parserI32Type) [initialLiteral 1]

private def initialProductionTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 16 :=
  .apply (.index (.slice parserI32Type) parserI32Type parserI32Type) [
    initialSlot ⟨0, by omega⟩,
    initialBinary .add
      (initialBinary .add (initialSlot ⟨11, by omega⟩)
        (initialSlot ⟨12, by omega⟩))
      (initialSlot ⟨15, by omega⟩)]

private def initialSeedTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 17 :=
  .apply (.call extractedParserStateSeedFunction.id
    (List.replicate 7 parserI32Type) (.structure 1)) [
      initialSlot ⟨16, by omega⟩,
      initialLiteral 0,
      initialLiteral 0,
      initialNegativeOne,
      initialConstant 37,
      initialNegativeOne,
      initialNegativeOne]

private def initialAppendArguments : List
    (Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 17) := [
      initialSlot ⟨3, by omega⟩,
      initialSlot ⟨5, by omega⟩,
      initialSlot ⟨6, by omega⟩,
      initialLiteral 0,
      initialSeedTerm,
      initialSlot ⟨14, by omega⟩]

private theorem initialAppendArguments_toCore :
    Lanius.FunctionalView.Core.toCoreExprs
      (Layout.push initialContinuationLayout 20) initialAppendArguments =
      parserRecognizeInitialAppendArguments := by
  rfl

private def initialAppendTerm :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 17 :=
  .apply (.call extractedParserAppendStateFunction.id [
    .slice parserI32Type, parserI32Type, parserI32Type, parserI32Type,
    .structure 1, parserI32Type] (.structure 2)) initialAppendArguments

private def initialFullCondition :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 18 :=
  initialBinary .equal
    (.apply (.field (.structure 2) 0 parserI32Type)
      [initialSlot ⟨17, by omega⟩])
    (initialConstant 41)

private def initialFullResult :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 18 :=
  .apply (.call extractedParserAppendOrFullFunction.id
    [.structure 2, parserI32Type] (.structure 0)) [
      initialSlot ⟨17, by omega⟩,
      initialLiteral 0]

private def initialBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 16 :=
  parserRecognizeInitialBodyView.command

private def initialExpectedBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 16 :=
  .letValue parserI32Type initialProductionTerm
    (.letValue (.structure 2) initialAppendTerm
      (.sequence
        (.ifThenElse initialFullCondition
          (.sequence (.returnValue (some initialFullResult)) .skip)
          .skip)
        (.sequence
          (.setLocal ⟨14, by omega⟩
            (.apply (.field (.structure 2) 2 parserI32Type)
              [initialSlot ⟨17, by omega⟩]))
          (.sequence
            (.updateLocal .add ⟨15, by omega⟩ (initialLiteral 1))
            .skip))))

private theorem initialBodyCommand_shape :
    initialBodyCommand = initialExpectedBodyCommand := by
  apply stateCommandMatches_sound
  native_decide

private def initialLoopCondition :
    Lanius.FunctionalView.Term Lanius.FunctionalView.Core.signature 16 :=
  initialBinary .less (initialSlot ⟨15, by omega⟩)
    (initialSlot ⟨13, by omega⟩)

private def initialExpectedLoopCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 16 :=
  .whileLoop initialLoopCondition initialBodyCommand

private theorem initialLoopCommand_shape :
    initialLoopCommand = initialExpectedLoopCommand := by
  apply stateCommandMatches_sound
  native_decide

private theorem initialLoop_calls_supported :
    Lanius.FunctionalView.Core.Stateful.Command.callsSatisfy
      predictionCallAllowedInState initialLoopCommand = true := by
  native_decide

private abbrev initialContinuationPositionCommand :=
  Lanius.FunctionalView.Stateful.Command.rename
    Lanius.FunctionalView.Core.Stateful.actionRenamer
    positionStatementIntoInitialEmbedding positionStatementCommand

def initialContinuationCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 16 :=
  parserRecognizeInitialContinuationView.command

def initialExpectedContinuationCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 16 :=
  .sequence initialLoopCommand initialContinuationPositionCommand

theorem initialContinuationCommand_shape :
    initialContinuationCommand = initialExpectedContinuationCommand := by
  apply stateCommandMatches_sound
  native_decide

/-- Functional state at the start-production/position continuation boundary.
    The three initial-loop-only values (`first`, `count`, and `index`) remain
    explicit until the surrounding local-19 scope closes. -/
def initialContinuationEnvironment (words : List Int)
    (tokens : List Nat) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (grammarLayout : PackedGrammarLayout)
    (first count stateCount index : Nat) : Lanius.FunctionalView.Env 16
  := fun slot => [
    parserGrammarValue words grammarCell,
    parserTokensValue tokens tokensCell,
    .signed .i32 (Int.ofNat tokens.length),
    workspaceValue workspaceValues workspaceCell,
    .signed .i32 (Int.ofNat (finalPosition workspaceLayout.tokenCount)),
    .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
    .signed .i32 (Int.ofNat workspaceLayout.capacity),
    .signed .i32 (Int.ofNat grammar.grammar.n_kinds),
    .signed .i32 (Int.ofNat grammar.grammar.start_nonterminal),
    .signed .i32 (Int.ofNat grammarLayout.lhsOffsetsOffset),
    .signed .i32 (Int.ofNat grammarLayout.lhsCountsOffset),
    .signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset),
    .signed .i32 (Int.ofNat first),
    .signed .i32 (Int.ofNat count),
    .signed .i32 (Int.ofNat stateCount),
    .signed .i32 (Int.ofNat index)].get slot

theorem positionStatementEnvironment_extends_initialContinuation
    (words : List Int) (tokens : List Nat) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (grammarLayout : PackedGrammarLayout)
    (first count stateCount index : Nat) :
    Lanius.FunctionalView.Env.Extends positionStatementIntoInitialEmbedding
      (positionStatementEnvironment words tokens workspaceValues grammarCell
        tokensCell workspaceCell workspaceLayout grammar grammarLayout
        stateCount)
      (initialContinuationEnvironment words tokens workspaceValues grammarCell
        tokensCell workspaceCell workspaceLayout grammar grammarLayout first count
        stateCount index) := by
  apply Lanius.FunctionalView.Env.Extends.ofFn
  rfl

private theorem RecognizerInitialLoopInvariant.functional_read_production
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (rowBound : first + index < grammar.lhsProductions.length) :
    let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
    let world := predictionWorld words tokens workspaceValues grammarCell
      tokensCell workspaceCell
    let environment := initialContinuationEnvironment words tokens
      workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
      grammarLayout first count workspace.states.length index
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      world environment initialProductionTerm =
      .ok (.signed .i32 (Int.ofNat production), world) := by
  dsimp only
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let world := predictionWorld words tokens workspaceValues grammarCell
    tokensCell workspaceCell
  let environment := initialContinuationEnvironment words tokens
    workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
    grammarLayout first count workspace.states.length index
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
      world environment (initialSlot ⟨11, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat grammarLayout.lhsProductionsOffset),
        world) := by rfl
  have firstResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment (initialSlot ⟨12, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat first), world) := by rfl
  have indexResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment (initialSlot ⟨15, by omega⟩) =
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
      world environment (initialSlot ⟨0, by omega⟩) =
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
      recognizerWorld_finds_grammar physicalBound' physical'
  have agreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerCallRegistry.calls workspaceLayout words grammarCell)
      (world := world) (environment := environment) initialProductionTerm
      (by native_decide)
  exact agreement.trans readOnlyResult

private theorem RecognizerInitialLoopInvariant.functional_seed
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (rowBound : first + index < grammar.lhsProductions.length) :
    let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
    let seed := recognizerInitialSeed production
    let world := predictionWorld words tokens workspaceValues grammarCell
      tokensCell workspaceCell
    let environment := (initialContinuationEnvironment words tokens
      workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
      grammarLayout first count workspace.states.length index).push
        (.signed .i32 (Int.ofNat production))
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      world environment initialSeedTerm = .ok (stateSeedValue seed, world) := by
  dsimp only
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let seed := recognizerInitialSeed production
  let world := predictionWorld words tokens workspaceValues grammarCell
    tokensCell workspaceCell
  let environment := (initialContinuationEnvironment words tokens
    workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
    grammarLayout first count workspace.states.length index).push
      (.signed .i32 (Int.ofNat production))
  let machine := predictionTermMachine workspaceLayout words grammarCell
  have productionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (initialSlot ⟨16, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat production), world) := by rfl
  have zeroResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (initialLiteral 0) = .ok (.signed .i32 0, world) := by rfl
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
      (initialNegativeOne : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 17) (by native_decide)
  have negativeOneResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (initialNegativeOne : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 17) =
      .ok (.signed .i32 (-1), world) := by
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
      (initialConstant 37 : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 17) (by native_decide)
  have childNoneResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (initialConstant 37 : Lanius.FunctionalView.Term
        Lanius.FunctionalView.Core.signature 17) =
      .ok (.signed .i32 0, world) :=
    childNoneAgreement.trans childNoneReadOnly
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [initialSlot ⟨16, by omega⟩, initialLiteral 0,
        initialLiteral 0, initialNegativeOne, initialConstant 37,
        initialNegativeOne, initialNegativeOne] =
      .ok (parserStateSeedArgumentsValues seed, world) := by
    simpa [seed, recognizerInitialSeed, parserStateSeedArgumentsValues,
      previousValue, encodeStateId, childTag, childPayload, childKind] using
      Lanius.FunctionalView.evaluateTerms_cons productionResult
        (Lanius.FunctionalView.evaluateTerms_cons zeroResult
          (Lanius.FunctionalView.evaluateTerms_cons zeroResult
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

private theorem
    RecognizerInitialLoopInvariant.functional_append_arguments
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (rowBound : first + index < grammar.lhsProductions.length) :
    let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
    let seed := recognizerInitialSeed production
    let world := predictionWorld words tokens workspaceValues grammarCell
      tokensCell workspaceCell
    let environment := (initialContinuationEnvironment words tokens
      workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
      grammarLayout first count workspace.states.length index).push
        (.signed .i32 (Int.ofNat production))
    Lanius.FunctionalView.evaluateTerms
      (predictionTermMachine workspaceLayout words grammarCell)
      world environment initialAppendArguments = .ok ([
        workspaceValue workspaceValues workspaceCell,
        .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
        .signed .i32 (Int.ofNat workspaceLayout.capacity),
        .signed .i32 0,
        stateSeedValue seed,
        .signed .i32 (Int.ofNat workspace.states.length)], world) := by
  dsimp only
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let seed := recognizerInitialSeed production
  let world := predictionWorld words tokens workspaceValues grammarCell
    tokensCell workspaceCell
  let environment := (initialContinuationEnvironment words tokens
    workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
    grammarLayout first count workspace.states.length index).push
      (.signed .i32 (Int.ofNat production))
  let machine := predictionTermMachine workspaceLayout words grammarCell
  have workspaceResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (initialSlot ⟨3, by omega⟩) =
      .ok (workspaceValue workspaceValues workspaceCell, world) := by rfl
  have baseResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (initialSlot ⟨5, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat
        (stateBase workspaceLayout.tokenCount)), world) := by rfl
  have capacityResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (initialSlot ⟨6, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat workspaceLayout.capacity), world) := by rfl
  have positionResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (initialLiteral 0) = .ok (.signed .i32 0, world) := by rfl
  have seedResult : Lanius.FunctionalView.Term.evaluate machine world
      environment initialSeedTerm = .ok (stateSeedValue seed, world) := by
    exact invariant.functional_seed rowBound
  have stateCountResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (initialSlot ⟨14, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat workspace.states.length), world) := by rfl
  simpa only [initialAppendArguments] using
    Lanius.FunctionalView.evaluateTerms_cons workspaceResult
      (Lanius.FunctionalView.evaluateTerms_cons baseResult
        (Lanius.FunctionalView.evaluateTerms_cons capacityResult
          (Lanius.FunctionalView.evaluateTerms_cons positionResult
            (Lanius.FunctionalView.evaluateTerms_cons seedResult
              (Lanius.FunctionalView.evaluateTerms_cons stateCountResult
                (Lanius.FunctionalView.evaluateTerms_nil machine world
                  environment))))))

private theorem RecognizerInitialLoopInvariant.functional_append
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (indexBound : index < count)
    (rowBound : first + index < grammar.lhsProductions.length) :
    let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
    let seed := recognizerInitialSeed production
    let outcome := (appendLogical workspaceLayout.capacity 0 seed workspace).1
    let nextValues := appendResultValues workspaceLayout workspace 0 seed
      workspaceValues
    let world := predictionWorld words tokens workspaceValues grammarCell
      tokensCell workspaceCell
    let environment := (initialContinuationEnvironment words tokens
      workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
      grammarLayout first count workspace.states.length index).push
        (.signed .i32 (Int.ofNat production))
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      world environment initialAppendTerm = .ok (appendOutcomeValue outcome,
        predictionWorld words tokens nextValues grammarCell tokensCell
          workspaceCell) := by
  dsimp only
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let seed := recognizerInitialSeed production
  let outcome := (appendLogical workspaceLayout.capacity 0 seed workspace).1
  let nextValues := appendResultValues workspaceLayout workspace 0 seed
    workspaceValues
  let world := predictionWorld words tokens workspaceValues grammarCell
    tokensCell workspaceCell
  let environment := (initialContinuationEnvironment words tokens
    workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
    grammarLayout first count workspace.states.length index).push
      (.signed .i32 (Int.ofNat production))
  let machine := predictionTermMachine workspaceLayout words grammarCell
  let callValues : List Value := [
    workspaceValue workspaceValues workspaceCell,
    .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)),
    .signed .i32 (Int.ofNat workspaceLayout.capacity),
    .signed .i32 0,
    stateSeedValue seed,
    .signed .i32 (Int.ofNat workspace.states.length)]
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment initialAppendArguments = .ok (callValues, world) := by
    exact invariant.functional_append_arguments rowBound
  let bound := runtime.bindLocal 20
    (.signed .i32 (Int.ofNat production))
  let appendInvariant := invariant.bind_production indexBound
  let appended := appendInvariant.evaluate_append
  have different : workspaceCell ≠ grammarCell :=
    invariant.frame.recognizer.grammarWorkspaceDistinct.symm
  let input : AppendStateCall.Input workspaceLayout world callValues := {
    workspace := workspace
    values := workspaceValues
    cell := workspaceCell
    position := 0
    seed := seed
    valuesLength := invariant.frame.recognizer.workspaceLength
    encoded := invariant.frame.recognizer.workspaceEncoded
    positionBound := by simp [finalPosition]
    seedOriginBound := by simp [seed, recognizerInitialSeed, finalPosition]
    found := by
      simpa [world, predictionWorld] using
        (recognizerWorld_finds_workspace
          (tokens := tokens) (tokensCell := tokensCell) different)
    argumentsEq := rfl
  }
  have argumentsExecution : ArgumentsEvaluateTo verifiedParserCore bound
      (Lanius.FunctionalView.Core.toCoreExprs
        (Layout.push initialContinuationLayout 20) initialAppendArguments)
      callValues appended.argumentsState := by
    rw [initialAppendArguments_toCore]
    simpa [bound, callValues, seed, production, rowBound, appendInvariant,
      appended, parserRecognizeInitialAppendArguments,
      recognizerAppendArguments] using appended.argumentsEvaluation
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
    appended.argumentsState (Layout.push initialContinuationLayout 20)
    initialAppendArguments appended.argumentsInvariant.wellFormed worldOwned
    argumentsExecution
  have outcomeEq : input.outcome = outcome := by rfl
  have afterWorldEq : input.afterWorld =
      predictionWorld words tokens nextValues grammarCell tokensCell
        workspaceCell := by
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
        predictionWorld words tokens nextValues grammarCell tokensCell
          workspaceCell)
  rw [outcomeEq, afterWorldEq] at registryResult
  exact registryResult



private theorem initialFullCondition_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 17)
    (outcome : AppendOutcome) :
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      world (environment.push (appendOutcomeValue outcome))
      initialFullCondition =
      .ok (.boolean (decide (outcome.status = .full)), world) := by
  have agreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerCallRegistry.calls workspaceLayout words grammarCell)
      (world := world)
      (environment := environment.push (appendOutcomeValue outcome))
      initialFullCondition (by native_decide)
  have readOnlyResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world (environment.push (appendOutcomeValue outcome))
      initialFullCondition =
      .ok (.boolean (decide (outcome.status = .full)), world) := by
    rcases outcome with ⟨status, stateId, stateCount, inserted⟩
    cases status <;> rfl
  exact agreement.trans readOnlyResult

private theorem initialStateCount_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 17)
    (outcome : AppendOutcome) :
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      world (environment.push (appendOutcomeValue outcome))
      (.apply (.field (.structure 2) 2 parserI32Type)
        [initialSlot ⟨17, by omega⟩]) =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), world) := by
  have agreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerCallRegistry.calls workspaceLayout words grammarCell)
      (world := world)
      (environment := environment.push (appendOutcomeValue outcome))
      (.apply (.field (.structure 2) 2 parserI32Type)
        [initialSlot ⟨17, by omega⟩]) (by native_decide)
  have readOnlyResult : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world (environment.push (appendOutcomeValue outcome))
      (.apply (.field (.structure 2) 2 parserI32Type)
        [initialSlot ⟨17, by omega⟩]) =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), world) := by rfl
  exact agreement.trans readOnlyResult

private theorem initialFullResult_evaluates
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 17)
    (outcome : AppendOutcome) :
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      world (environment.push (appendOutcomeValue outcome)) initialFullResult =
      .ok (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1) 0,
        world) := by
  let machine := predictionTermMachine workspaceLayout words grammarCell
  let extended := environment.push (appendOutcomeValue outcome)
  have outcomeResult : Lanius.FunctionalView.Term.evaluate machine world
      extended (initialSlot ⟨17, by omega⟩) =
      .ok (appendOutcomeValue outcome, world) := by rfl
  have zeroResult : Lanius.FunctionalView.Term.evaluate machine world
      extended (initialLiteral 0) = .ok (.signed .i32 0, world) := by rfl
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      extended [initialSlot ⟨17, by omega⟩, initialLiteral 0] =
      .ok ([appendOutcomeValue outcome, .signed .i32 0], world) :=
    Lanius.FunctionalView.evaluateTerms_cons outcomeResult
      (Lanius.FunctionalView.evaluateTerms_cons zeroResult
        (Lanius.FunctionalView.evaluateTerms_nil machine world extended))
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerCallRegistry.calls workspaceLayout words grammarCell).evaluate
    world extractedParserAppendOrFullFunction.id
      [appendOutcomeValue outcome, .signed .i32 0] = _
  exact RecognizerCallRegistry.calls_at_append_or_full world outcome 0

private def initialOkEnvironment
    (environment : Lanius.FunctionalView.Env 17)
    (outcome : AppendOutcome) (index : Nat) :
    Lanius.FunctionalView.Env 16 :=
  Lanius.FunctionalView.Stateful.Env.pop
    (Lanius.FunctionalView.Stateful.Env.pop
      (Lanius.FunctionalView.Stateful.Env.set
        (Lanius.FunctionalView.Stateful.Env.set
          (environment.push (appendOutcomeValue outcome))
        ⟨14, by omega⟩ (.signed .i32 (Int.ofNat outcome.stateCount)))
        ⟨15, by omega⟩ (.signed .i32 (Int.ofNat (index + 1)))))

/-- Closing the two temporaries created by one successful initial-seeding
    iteration yields exactly the environment of the successor configuration.
    This equality is the functional counterpart of the physical loop
    invariant's state-count and index ownership update. -/
private theorem initialOkEnvironment_eq_next
    (beforeValues nextValues : List Int)
    (beforeWorkspace nextWorkspace : LogicalWorkspace)
    (outcome : AppendOutcome) (index : Nat)
    (valuesLengthEq : beforeValues.length = nextValues.length)
    (stateCountEq : outcome.stateCount = nextWorkspace.states.length) :
    let beforeEnvironment := initialContinuationEnvironment words tokens
      beforeValues grammarCell tokensCell workspaceCell workspaceLayout grammar
      grammarLayout first count beforeWorkspace.states.length index
    let productionEnvironment := beforeEnvironment.push
      (.signed .i32 (Int.ofNat production))
    initialOkEnvironment productionEnvironment outcome index =
      initialContinuationEnvironment words tokens nextValues grammarCell
        tokensCell workspaceCell workspaceLayout grammar grammarLayout first count
        nextWorkspace.states.length (index + 1) := by
  dsimp only
  funext slot
  have cases : slot.val = 0 ∨ slot.val = 1 ∨ slot.val = 2 ∨
      slot.val = 3 ∨ slot.val = 4 ∨ slot.val = 5 ∨ slot.val = 6 ∨
      slot.val = 7 ∨ slot.val = 8 ∨ slot.val = 9 ∨ slot.val = 10 ∨
      slot.val = 11 ∨ slot.val = 12 ∨ slot.val = 13 ∨ slot.val = 14 ∨
      slot.val = 15 := by
    omega
  rcases cases with h | h | h | h | h | h | h | h | h | h | h | h | h |
      h | h | h <;>
    simp [initialOkEnvironment, initialContinuationEnvironment,
      workspaceValue, Fin.ext_iff, h, valuesLengthEq, stateCountEq,
      Lanius.FunctionalView.Stateful.Env.pop,
      Lanius.FunctionalView.Stateful.Env.set,
      Lanius.FunctionalView.Env.push] <;>
    first | omega | (split <;> first | omega | rfl)

private theorem RecognizerInitialLoopInvariant.functional_ok_body
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (indexBound : index < count)
    (rowBound : first + index < grammar.lhsProductions.length)
    (statusOk :
      let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
      let seed := recognizerInitialSeed production
      (appendLogical workspaceLayout.capacity 0 seed workspace).1.status =
        .ok) :
    let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
    let seed := recognizerInitialSeed production
    let outcome := (appendLogical workspaceLayout.capacity 0 seed workspace).1
    let nextValues := appendResultValues workspaceLayout workspace 0 seed
      workspaceValues
    let beforeWorld := predictionWorld words tokens workspaceValues grammarCell
      tokensCell workspaceCell
    let afterWorld := predictionWorld words tokens nextValues grammarCell
      tokensCell workspaceCell
    let beforeEnvironment := initialContinuationEnvironment words tokens
      workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
      grammarLayout first count workspace.states.length index
    let productionEnvironment := beforeEnvironment.push
      (.signed .i32 (Int.ofNat production))
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      beforeWorld beforeEnvironment initialBodyCommand .next afterWorld
      (initialOkEnvironment productionEnvironment outcome index) := by
  dsimp only
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let seed := recognizerInitialSeed production
  let outcome := (appendLogical workspaceLayout.capacity 0 seed workspace).1
  let nextValues := appendResultValues workspaceLayout workspace 0 seed
    workspaceValues
  let beforeWorld := predictionWorld words tokens workspaceValues grammarCell
    tokensCell workspaceCell
  let afterWorld := predictionWorld words tokens nextValues grammarCell
    tokensCell workspaceCell
  let beforeEnvironment := initialContinuationEnvironment words tokens
    workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
    grammarLayout first count workspace.states.length index
  let productionEnvironment := beforeEnvironment.push
    (.signed .i32 (Int.ofNat production))
  let resultEnvironment := productionEnvironment.push
    (appendOutcomeValue outcome)
  have productionResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      beforeWorld beforeEnvironment initialProductionTerm =
      .ok (.signed .i32 (Int.ofNat production), beforeWorld) :=
    invariant.functional_read_production rowBound
  have appendResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      beforeWorld productionEnvironment initialAppendTerm =
      .ok (appendOutcomeValue outcome, afterWorld) :=
    invariant.functional_append indexBound rowBound
  have fullCondition : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment initialFullCondition =
      .ok (.boolean false, afterWorld) := by
    have evaluated := initialFullCondition_evaluates
      (workspaceLayout := workspaceLayout) (words := words)
      (grammarCell := grammarCell) afterWorld productionEnvironment outcome
    have statusOk' : outcome.status = .ok := by
      simpa [outcome, seed, production] using statusOk
    rw [statusOk'] at evaluated
    simpa [resultEnvironment] using evaluated
  have countResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment
      (.apply (.field (.structure 2) 2 parserI32Type)
        [initialSlot ⟨17, by omega⟩]) =
      .ok (.signed .i32 (Int.ofNat outcome.stateCount), afterWorld) := by
    simpa [resultEnvironment] using initialStateCount_evaluates
      (workspaceLayout := workspaceLayout) (words := words)
      (grammarCell := grammarCell) afterWorld productionEnvironment outcome
  let afterCount := Lanius.FunctionalView.Stateful.Env.set resultEnvironment
    ⟨14, by omega⟩ (.signed .i32 (Int.ofNat outcome.stateCount))
  have oneResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      afterWorld afterCount (initialLiteral 1) =
      .ok (.signed .i32 1, afterWorld) := by rfl
  have currentIndex : afterCount ⟨15, by omega⟩ =
      .signed .i32 (Int.ofNat index) := by
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
        .add (afterCount ⟨15, by omega⟩) (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (index + 1))) := by
    rw [currentIndex]
    simpa [predictionStatefulMachine,
      Lanius.FunctionalView.Core.Stateful.machineWith] using updated
  rw [initialBodyCommand_shape, initialExpectedBodyCommand]
  exact .letValue productionResult (.letValue appendResult
    (.sequenceNext (.ifFalse fullCondition .skip)
      (.sequenceNext (.setLocal countResult)
        (.sequenceNext (.updateLocal oneResult updateResult) .skip))))

private theorem RecognizerInitialLoopInvariant.functional_full_body
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index)
    (indexBound : index < count)
    (rowBound : first + index < grammar.lhsProductions.length)
    (statusFull :
      let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
      let seed := recognizerInitialSeed production
      (appendLogical workspaceLayout.capacity 0 seed workspace).1.status =
        .full) :
    let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
    let seed := recognizerInitialSeed production
    let outcome := (appendLogical workspaceLayout.capacity 0 seed workspace).1
    let nextValues := appendResultValues workspaceLayout workspace 0 seed
      workspaceValues
    let beforeWorld := predictionWorld words tokens workspaceValues grammarCell
      tokensCell workspaceCell
    let afterWorld := predictionWorld words tokens nextValues grammarCell
      tokensCell workspaceCell
    let beforeEnvironment := initialContinuationEnvironment words tokens
      workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
      grammarLayout first count workspace.states.length index
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      beforeWorld beforeEnvironment initialBodyCommand
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount)
        (-1) 0))) afterWorld beforeEnvironment := by
  dsimp only
  let production := grammar.lhsProductions.get ⟨first + index, rowBound⟩
  let seed := recognizerInitialSeed production
  let outcome := (appendLogical workspaceLayout.capacity 0 seed workspace).1
  let nextValues := appendResultValues workspaceLayout workspace 0 seed
    workspaceValues
  let beforeWorld := predictionWorld words tokens workspaceValues grammarCell
    tokensCell workspaceCell
  let afterWorld := predictionWorld words tokens nextValues grammarCell
    tokensCell workspaceCell
  let beforeEnvironment := initialContinuationEnvironment words tokens
    workspaceValues grammarCell tokensCell workspaceCell workspaceLayout grammar
    grammarLayout first count workspace.states.length index
  let productionEnvironment := beforeEnvironment.push
    (.signed .i32 (Int.ofNat production))
  let resultEnvironment := productionEnvironment.push
    (appendOutcomeValue outcome)
  have productionResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      beforeWorld beforeEnvironment initialProductionTerm =
      .ok (.signed .i32 (Int.ofNat production), beforeWorld) :=
    invariant.functional_read_production rowBound
  have appendResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      beforeWorld productionEnvironment initialAppendTerm =
      .ok (appendOutcomeValue outcome, afterWorld) :=
    invariant.functional_append indexBound rowBound
  have fullCondition : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment initialFullCondition =
      .ok (.boolean true, afterWorld) := by
    have evaluated := initialFullCondition_evaluates
      (workspaceLayout := workspaceLayout) (words := words)
      (grammarCell := grammarCell) afterWorld productionEnvironment outcome
    have statusFull' : outcome.status = .full := by
      simpa [outcome, seed, production] using statusFull
    rw [statusFull'] at evaluated
    simpa [resultEnvironment] using evaluated
  have fullResult : Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment initialFullResult =
      .ok (parseResultValue 2 (Int.ofNat outcome.stateCount) (-1) 0,
        afterWorld) := by
    simpa [resultEnvironment] using initialFullResult_evaluates
      (workspaceLayout := workspaceLayout) (words := words)
      (grammarCell := grammarCell) afterWorld productionEnvironment outcome
  have returned : Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment (.returnValue (some initialFullResult))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount)
        (-1) 0))) afterWorld resultEnvironment := .returnSome fullResult
  have selected : Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment
      (.ifThenElse initialFullCondition
        (.sequence (.returnValue (some initialFullResult)) .skip) .skip)
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount)
        (-1) 0))) afterWorld resultEnvironment :=
    .ifTrue fullCondition (.sequenceStop returned
      (by intro impossible; cases impossible))
  have stopped : Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      afterWorld resultEnvironment
      (.sequence
        (.ifThenElse initialFullCondition
          (.sequence (.returnValue (some initialFullResult)) .skip) .skip)
        (.sequence
          (.setLocal ⟨14, by omega⟩
            (.apply (.field (.structure 2) 2 parserI32Type)
              [initialSlot ⟨17, by omega⟩]))
          (.sequence
            (.updateLocal .add ⟨15, by omega⟩ (initialLiteral 1)) .skip)))
      (.returned (some (parseResultValue 2 (Int.ofNat outcome.stateCount)
        (-1) 0))) afterWorld resultEnvironment :=
    .sequenceStop selected (by intro impossible; cases impossible)
  have assembled := Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
    (type := parserI32Type) productionResult
    (Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
      (type := .structure 2) appendResult stopped)
  have popped : Lanius.FunctionalView.Stateful.Env.pop
      (Lanius.FunctionalView.Stateful.Env.pop resultEnvironment) =
      beforeEnvironment := by
    simp [resultEnvironment, productionEnvironment]
  rw [popped] at assembled
  rw [initialBodyCommand_shape, initialExpectedBodyCommand]
  exact assembled

/-- Pure FunctionalView state corresponding to one start-production seeding
    configuration.  The physical runtime remains refinement evidence in the
    configuration; it does not determine the functional execution. -/
def RecognizerInitialConfig.functionalRuntime
    (config : RecognizerInitialConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell first count) :
    Lanius.FunctionalView.Stateful.Loop.Runtime
      (predictionTermMachine workspaceLayout words grammarCell) 16 :=
  (predictionWorld words tokens config.workspaceValues grammarCell tokensCell
      workspaceCell,
    initialContinuationEnvironment words tokens config.workspaceValues
      grammarCell tokensCell workspaceCell workspaceLayout grammar grammarLayout
      first count config.workspace.states.length config.index)

private theorem RecognizerInitialConfig.functional_condition
    (config : RecognizerInitialConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell first count) :
    Lanius.FunctionalView.Term.evaluate
      (predictionTermMachine workspaceLayout words grammarCell)
      config.functionalRuntime.world config.functionalRuntime.environment
      initialLoopCondition =
      .ok (.boolean (Decidable.decide (config.index < count)),
        config.functionalRuntime.world) := by
  have indexValue : config.functionalRuntime.environment ⟨15, by omega⟩ =
      .signed .i32 (Int.ofNat config.index) := by
    rfl
  have countValue : config.functionalRuntime.environment ⟨13, by omega⟩ =
      .signed .i32 (Int.ofNat count) := by
    rfl
  simp only [initialLoopCondition, initialBinary, initialSlot,
    Lanius.FunctionalView.Term.evaluate,
    Lanius.FunctionalView.Ref.evaluate,
    Lanius.FunctionalView.evaluateTerms,
    Lanius.FunctionalView.Core.Effectful.machine,
    Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation]
  rw [indexValue, countValue]
  simp [predictionTermMachine,
    Lanius.FunctionalView.Core.Effectful.machine,
    Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
    evalBinaryValue, evalSignedBinary, bind, Except.bind, Int.ofNat_lt]

/-- Joint functional/physical result of the initial-seeding loop.  Normal
    completion identifies the exact workspace and environment used by the
    following position statement; a capacity return carries the terminal
    physical invariant and needs no continuation environment. -/
private inductive RecognizerInitialSynchronizedOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (beforeWorkspace : LogicalWorkspace)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (first count : Nat)
    (after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (predictionTermMachine workspaceLayout words grammarCell) 16) :
    State → Lanius.FunctionalView.Stateful.Completion → Type where
  | completed (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell indexCell physicalAfter first count count)
      (worldEq : after.world = predictionWorld words tokens workspaceValues
        grammarCell tokensCell workspaceCell)
      (environmentEq : after.environment = initialContinuationEnvironment words
        tokens workspaceValues grammarCell tokensCell workspaceCell
        workspaceLayout grammar grammarLayout first count
        workspace.states.length count) :
      RecognizerInitialSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell indexCell first count after physicalAfter .next
  | full (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (physicalAfter : State)
      (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
        workspace)
      (terminal : RecognizerInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell physicalAfter)
      (stateCount : Nat) (wellFormed : StateWellFormed physicalAfter) :
      RecognizerInitialSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
        stateCountCell indexCell first count after physicalAfter
        (.returned (some
          (parseResultValue 2 (Int.ofNat stateCount) (-1) 0)))

private theorem RecognizerInitialSynchronizedOutcome.physical
    (outcome : RecognizerInitialSynchronizedOutcome grammarLayout grammar words
      tokens workspaceLayout beforeWorkspace grammarCell tokensCell
      workspaceCell stateCountCell indexCell first count after physicalAfter
      completion) :
    RecognizerInitialLoopOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell indexCell first count physicalAfter
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion) := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter growth invariant _ _ =>
      exact .completed workspace workspaceValues physicalAfter growth invariant
  | full workspace workspaceValues physicalAfter growth terminal stateCount
      wellFormed =>
      exact .full workspace workspaceValues physicalAfter growth terminal
        stateCount wellFormed

private def RecognizerInitialSynchronizedOutcome.prepend_growth
    {grammarLayout : PackedGrammarLayout} {grammar : IndexedGrammar}
    {words : List Int} {tokens : List Nat}
    {workspaceLayout : WorkspaceLayout}
    {grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId}
    {first count : Nat}
    {beforeWorkspace middleWorkspace : LogicalWorkspace}
    {after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (predictionTermMachine workspaceLayout words grammarCell) 16}
    {physicalAfter : State}
    {completion : Lanius.FunctionalView.Stateful.Completion}
    (outcome : RecognizerInitialSynchronizedOutcome grammarLayout grammar words
      tokens workspaceLayout middleWorkspace grammarCell tokensCell workspaceCell
      stateCountCell indexCell first count after physicalAfter completion)
    (growth : WorkspaceAppendClosure workspaceLayout.capacity beforeWorkspace
      middleWorkspace) :
    RecognizerInitialSynchronizedOutcome grammarLayout grammar words tokens
      workspaceLayout beforeWorkspace grammarCell tokensCell workspaceCell
      stateCountCell indexCell first count after physicalAfter completion := by
  cases outcome with
  | completed workspace workspaceValues physicalAfter nextGrowth invariant
      worldEq environmentEq =>
      exact .completed workspace workspaceValues physicalAfter
        (growth.trans nextGrowth) invariant worldEq environmentEq
  | full workspace workspaceValues physicalAfter nextGrowth terminal stateCount
      wellFormed =>
      exact .full workspace workspaceValues physicalAfter
        (growth.trans nextGrowth) terminal stateCount wellFormed

structure RecognizerInitialFunctionalResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout)
    (grammarCell tokensCell workspaceCell stateCountCell indexCell : CellId)
    (first count : Nat)
    (config : RecognizerInitialConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell first count)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (_after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (predictionTermMachine workspaceLayout words grammarCell) 16) where
  physicalAfter : State
  execution : Executes verifiedParserCore config.runtime
    parserRecognizeInitialLoop
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
    physicalAfter
  effect : ModifiesOnly
    (recognizerInitialWrites workspaceCell stateCountCell indexCell)
    config.runtime physicalAfter
  outcome : RecognizerInitialSynchronizedOutcome grammarLayout grammar words
    tokens workspaceLayout config.workspace grammarCell tokensCell workspaceCell
    stateCountCell indexCell first count _after physicalAfter
    completion

/-- One FunctionalView decision for the extracted start-production loop.  Its
    control edge is determined by the functional command; the Core step is
    retained only as refinement evidence. -/
private noncomputable def RecognizerInitialConfig.functional_decide
    (config : RecognizerInitialConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell first count) :
    Lanius.FunctionalView.Stateful.Loop.Decision
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      initialLoopCondition initialBodyCommand
      (RecognizerInitialConfig grammarLayout grammar words tokens
        workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
        indexCell first count)
      RecognizerInitialConfig.functionalRuntime
      RecognizerInitialConfig.measure
      (RecognizerInitialFunctionalResult grammarLayout grammar words tokens
        workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
        indexCell first count) config := by
  by_cases done : config.index = count
  · apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
    have functionalFalse : Lanius.FunctionalView.Term.evaluate
        (predictionTermMachine workspaceLayout words grammarCell)
        config.functionalRuntime.world config.functionalRuntime.environment
        initialLoopCondition =
        .ok (.boolean false, config.functionalRuntime.world) := by
      simpa [done] using config.functional_condition
    exact {
      completion := .next
      after := config.functionalRuntime
      edge := .conditionFalse functionalFalse
      result := {
        physicalAfter := config.runtime
        execution := config.invariant.condition_false (by omega) |>
          executesWhileFalse
        effect := ModifiesOnly.reflAny
          (recognizerInitialWrites workspaceCell stateCountCell indexCell)
          config.runtime
        outcome := by
          apply RecognizerInitialSynchronizedOutcome.completed config.workspace
            config.workspaceValues config.runtime (.refl config.workspace)
            (by simpa [done] using config.invariant)
          · rfl
          · change initialContinuationEnvironment words tokens
              config.workspaceValues grammarCell tokensCell workspaceCell
              workspaceLayout grammar grammarLayout first count
              config.workspace.states.length config.index = _
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
    let seed := recognizerInitialSeed production
    let logical := appendLogical workspaceLayout.capacity 0 seed
      config.workspace
    let nextValues := appendResultValues workspaceLayout config.workspace 0 seed
      config.workspaceValues
    have functionalTrue : Lanius.FunctionalView.Term.evaluate
        (predictionTermMachine workspaceLayout words grammarCell)
        config.functionalRuntime.world config.functionalRuntime.environment
        initialLoopCondition =
        .ok (.boolean true, config.functionalRuntime.world) := by
      simpa [indexBound] using config.functional_condition
    cases statusEq : logical.1.status with
    | ok =>
        have statusOk : (appendLogical workspaceLayout.capacity 0 seed
            config.workspace).1.status = .ok := by
          simpa [logical]
        let step := config.invariant.execute_ok_step indexBound (by
          simpa [seed, production, rowBound] using statusOk)
        let next : RecognizerInitialConfig grammarLayout grammar words tokens
            workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
            indexCell first count := {
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
        have environmentEq := initialOkEnvironment_eq_next
          (words := words) (tokens := tokens) (grammarCell := grammarCell)
          (tokensCell := tokensCell) (workspaceCell := workspaceCell)
          (workspaceLayout := workspaceLayout) (grammar := grammar)
          (grammarLayout := grammarLayout) (first := first) (count := count)
          (production := production) config.workspaceValues nextValues
          config.workspace logical.2 logical.1 config.index
          (by simpa [nextValues, seed] using
            (appendResultValues_length workspaceLayout config.workspace 0 seed
              config.workspaceValues).symm)
          (by simpa [logical] using
            (appendLogical_stateCount_eq workspaceLayout.capacity 0 seed
              config.workspace))
        have functionalBody :
            Lanius.FunctionalView.Stateful.Command.Evaluates
              (predictionTermMachine workspaceLayout words grammarCell)
              (predictionStatefulMachine workspaceLayout words grammarCell)
              config.functionalRuntime.world
              config.functionalRuntime.environment initialBodyCommand .next
              next.functionalRuntime.world next.functionalRuntime.environment := by
          dsimp only at bodyResult environmentEq
          rw [environmentEq] at bodyResult
          simpa [RecognizerInitialConfig.functionalRuntime, next, logical,
            nextValues, seed, production, rowBound,
            Lanius.FunctionalView.Stateful.Loop.Runtime.world,
            Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
              bodyResult
        apply Lanius.FunctionalView.Stateful.Loop.Decision.next next
        · exact .next functionalTrue functionalBody
        · dsimp [RecognizerInitialConfig.measure, next]
          change count - (config.index + 1) < count - config.index
          omega
        · intro completion after result
          exact {
            physicalAfter := result.physicalAfter
            execution := executesWhileTrueThen
              (config.invariant.condition_true indexBound) step.execution
              result.execution
            effect := by
              simpa [recognizerInitialWrites] using
                step.effect.trans_same result.effect
            outcome := result.outcome.prepend_growth
              (WorkspaceAppendClosure.single workspaceLayout.capacity 0 seed
                config.workspace)
          }
    | full =>
        have statusFull : (appendLogical workspaceLayout.capacity 0 seed
            config.workspace).1.status = .full := by
          simpa [logical]
        let step := config.invariant.execute_full_step indexBound (by
          simpa [seed, production, rowBound] using statusFull)
        let stateCount := logical.1.stateCount
        have bodyResult := config.invariant.functional_full_body indexBound
          rowBound (by simpa [seed, production, rowBound] using statusFull)
        have functionalBody :
            Lanius.FunctionalView.Stateful.Command.Evaluates
              (predictionTermMachine workspaceLayout words grammarCell)
              (predictionStatefulMachine workspaceLayout words grammarCell)
              config.functionalRuntime.world
              config.functionalRuntime.environment initialBodyCommand
              (.returned (some
                (parseResultValue 2 (Int.ofNat stateCount) (-1) 0)))
              config.functionalRuntime.world
              config.functionalRuntime.environment := by
          have valuesEq := appendResultValues_eq_of_full
            (layout := workspaceLayout) (workspace := config.workspace)
            (position := 0) (seed := seed) (values := config.workspaceValues)
            statusFull
          dsimp only at bodyResult
          rw [valuesEq] at bodyResult
          simpa [RecognizerInitialConfig.functionalRuntime, logical,
            nextValues, valuesEq, stateCount, seed, production, rowBound,
            Lanius.FunctionalView.Stateful.Loop.Runtime.world,
            Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
              bodyResult
        apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
        exact {
          completion := .returned (some
            (parseResultValue 2 (Int.ofNat stateCount) (-1) 0))
          after := config.functionalRuntime
          edge := .returned functionalTrue functionalBody
          result := {
            physicalAfter := step.after
            execution := by
              rw [extractedParserRecognize_initial_loop_shape,
                ← extractedParserRecognize_initial_loop_body_shape]
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

noncomputable def RecognizerInitialConfig.functional_run
    (config : RecognizerInitialConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell first count) :=
  Lanius.FunctionalView.Stateful.Loop.run
    (predictionTermMachine workspaceLayout words grammarCell)
    (predictionStatefulMachine workspaceLayout words grammarCell)
    initialLoopCondition initialBodyCommand
    (RecognizerInitialConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell first count)
    RecognizerInitialConfig.functionalRuntime
    RecognizerInitialConfig.measure
    (RecognizerInitialFunctionalResult grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell first count)
    RecognizerInitialConfig.functional_decide config

theorem RecognizerInitialConfig.functional_run_evaluates
    (config : RecognizerInitialConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell first count) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      config.functionalRuntime.world config.functionalRuntime.environment
      initialLoopCommand config.functional_run.completion
      config.functional_run.after.world config.functional_run.after.environment := by
  rw [initialLoopCommand_shape, initialExpectedLoopCommand]
  exact config.functional_run.trace.evaluates

/-- Public physical projection of the synchronized FunctionalView initial
    loop.  Enclosing source proofs no longer need the older physical-only loop
    driver. -/
private noncomputable def RecognizerInitialLoopInvariant.functional_execute_loop
    (invariant : RecognizerInitialLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index) :
    RecognizerInitialLoopExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell indexCell runtime first count index
      invariant := by
  let initial : RecognizerInitialConfig grammarLayout grammar words tokens
      workspaceLayout grammarCell tokensCell workspaceCell stateCountCell
      indexCell first count := {
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

/-- Interpret the initial loop under the call registry used by the following
    position statement.  Agreement is required only for calls that actually
    occur in the mechanically reified loop. -/
theorem initialLoopExecution_in_position_machine
    {beforeWorld afterWorld : Lanius.FunctionalView.Core.ReadOnly.World}
    {beforeEnvironment afterEnvironment : Lanius.FunctionalView.Env 16}
    {completion : Lanius.FunctionalView.Stateful.Completion}
    (evaluated : Lanius.FunctionalView.Stateful.Command.Evaluates
      (predictionTermMachine workspaceLayout words grammarCell)
      (predictionStatefulMachine workspaceLayout words grammarCell)
      beforeWorld beforeEnvironment initialLoopCommand completion afterWorld
      afterEnvironment) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld beforeEnvironment initialLoopCommand completion afterWorld
      afterEnvironment := by
  let first := RecognizerCallRegistry.calls workspaceLayout words grammarCell
  let second := RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell
  have changed :=
    Lanius.FunctionalView.Core.Stateful.Command.Evaluates.changeCallModel
      (program := verifiedParserCore) (first := first) (second := second)
      predictionCalls_agree_state initialLoop_calls_supported (by
        simpa [predictionTermMachine, predictionStatefulMachine, first,
          Lanius.FunctionalView.Core.Effectful.machine,
          Lanius.FunctionalView.Core.Stateful.termMachine] using evaluated)
  simpa [positionTermMachine, positionStatefulMachine, stateTermMachine,
    stateStatefulMachine, second] using changed

/-- Execute the position statement inside the larger initial-continuation
    environment.  The call registry is already shared, so this is purely a
    lexical renaming/refinement step. -/
noncomputable def positionStatementExecution_in_initial_environment
    {beforeWorld afterWorld : Lanius.FunctionalView.Core.ReadOnly.World}
    {beforeSmall afterSmall : Lanius.FunctionalView.Env 13}
    {completion : Lanius.FunctionalView.Stateful.Completion}
    (evaluated : Lanius.FunctionalView.Stateful.Command.Evaluates
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld beforeSmall positionStatementCommand completion afterWorld
      afterSmall)
    (beforeLarge : Lanius.FunctionalView.Env 16)
    (related : Lanius.FunctionalView.Env.Extends
      positionStatementIntoInitialEmbedding beforeSmall beforeLarge) :
    Lanius.FunctionalView.Stateful.Command.RenameResult
      (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      Lanius.FunctionalView.Core.Stateful.actionRenamer
      positionStatementIntoInitialEmbedding beforeWorld beforeLarge
      positionStatementCommand completion afterWorld afterSmall := by
  let calls := RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell
  have actionSound :
      @Lanius.FunctionalView.Stateful.ActionRenamer.Sound
        Lanius.FunctionalView.Core.signature
        Lanius.FunctionalView.Core.Stateful.actions
        Lanius.FunctionalView.Core.Stateful.actionRenamer
        (positionTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell) := by
    intro source target embedding world small large relatedEnv action
    exact
      Lanius.FunctionalView.Core.Stateful.actionRenamer_sound verifiedParserCore
        (Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedParserCore calls)
        embedding world small large relatedEnv action
  exact evaluated.renameResult actionSound positionStatementIntoInitialEmbedding
    beforeLarge related


end Lanius.Extraction.ParserRecognize
