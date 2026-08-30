import Lanius.Extraction.Parser.Recognize.Root.Commands
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
/-! ## Artifact-derived FunctionalView for final root selection -/
private def rootAdvanceCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 8 :=
  .sequence
    (.setLocal ⟨6, by omega⟩
      (stateValueTerm ⟨1, by omega⟩ ⟨2, by omega⟩ ⟨6, by omega⟩ 32))
    .skip

private def rootExpectedBodyCommand :
    Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 7 :=
  .letValue parserI32Type
    (stateValueTerm ⟨1, by omega⟩ ⟨2, by omega⟩ ⟨6, by omega⟩ 28)
    (.sequence
      (.ifThenElse rootPredicateTerm rootSuccessCommand .skip)
      rootAdvanceCommand)

/-- Constructor-level decomposition of the one mechanically reified root
    body. No independently maintained root program is introduced. -/
private theorem rootBodyCommand_shape :
    rootBodyCommand = rootExpectedBodyCommand := by
  apply stateCommandMatches_sound
  native_decide

private noncomputable abbrev rootTermMachine := nullableTermMachine

private noncomputable abbrev rootStatefulMachine := nullableStatefulMachine

private def rootEnvironment (words : List Int) (workspaceValues : List Int)
    (grammarCell workspaceCell : CellId) (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (stateCount furthest : Nat)
    (candidate : Int) : Lanius.FunctionalView.Env 7
  | ⟨0, _⟩ => parserGrammarValue words grammarCell
  | ⟨1, _⟩ => workspaceValue workspaceValues workspaceCell
  | ⟨2, _⟩ => .signed .i32
      (Int.ofNat (stateBase workspaceLayout.tokenCount))
  | ⟨3, _⟩ => .signed .i32
      (Int.ofNat grammar.grammar.start_nonterminal)
  | ⟨4, _⟩ => .signed .i32 (Int.ofNat stateCount)
  | ⟨5, _⟩ => .signed .i32 (Int.ofNat furthest)
  | ⟨6, _⟩ => .signed .i32 candidate

/-- Values live at the complete root-statement boundary.  Unlike the compact
    root loop, this environment retains local `6`, because the initializer
    reads the final chart position before binding local `41`. -/
def rootStatementEnvironment (words : List Int)
    (workspaceValues : List Int) (grammarCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (stateCount furthest : Nat) : Lanius.FunctionalView.Env 7
  | ⟨0, _⟩ => parserGrammarValue words grammarCell
  | ⟨1, _⟩ => workspaceValue workspaceValues workspaceCell
  | ⟨2, _⟩ => .signed .i32
      (Int.ofNat (finalPosition workspaceLayout.tokenCount))
  | ⟨3, _⟩ => .signed .i32
      (Int.ofNat (stateBase workspaceLayout.tokenCount))
  | ⟨4, _⟩ => .signed .i32
      (Int.ofNat grammar.grammar.start_nonterminal)
  | ⟨5, _⟩ => .signed .i32 (Int.ofNat stateCount)
  | ⟨6, _⟩ => .signed .i32 (Int.ofNat furthest)

/-- After `root_state` is bound, the compact root-loop environment is exactly
    the projection selected by `rootIntoStatementEmbedding`. -/
private theorem rootEnvironment_extends_rootStatementEnvironment
    (words : List Int) (workspaceValues : List Int)
    (grammarCell workspaceCell : CellId) (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (stateCount furthest : Nat) (candidate : Int) :
    Lanius.FunctionalView.Env.Extends rootIntoStatementEmbedding
      (rootEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar stateCount furthest candidate)
      ((rootStatementEnvironment words workspaceValues grammarCell
        workspaceCell workspaceLayout grammar stateCount furthest).push
        (.signed .i32 candidate)) := by
  apply Lanius.FunctionalView.Env.Extends.ofFn
  rfl

/-- At normal position-loop completion, the root statement's compact source
    environment is exactly the projection of the still-open position scopes.
    The advanced position counter is outside that projection. -/
theorem rootStatementEnvironment_extends_positionEnvironment
    (words : List Int) (tokens : List Nat) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (grammarLayout : PackedGrammarLayout) (stateCount furthest position : Nat) :
    Lanius.FunctionalView.Env.Extends rootStatementIntoPositionEmbedding
      (rootStatementEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar stateCount furthest)
      (positionEnvironment words tokens workspaceValues grammarCell tokensCell
        workspaceCell workspaceLayout grammar grammarLayout stateCount furthest
        position) := by
  apply Lanius.FunctionalView.Env.Extends.ofFn
  rfl

/-- Execute the complete root statement inside the still-open position
    scopes.  Both commands use the same recognizer call registry, so only the
    lexical environment is renamed here. -/
noncomputable def rootStatementExecution_in_position_environment
    {beforeWorld afterWorld :
      Lanius.FunctionalView.Core.ReadOnly.World}
    {beforeSmall afterSmall : Lanius.FunctionalView.Env 7}
    {completion : Lanius.FunctionalView.Stateful.Completion}
    (evaluated : Lanius.FunctionalView.Stateful.Command.Evaluates
      (positionTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld beforeSmall rootStatementCommand completion afterWorld
      afterSmall)
    (beforeLarge : Lanius.FunctionalView.Env 15)
    (related : Lanius.FunctionalView.Env.Extends
      rootStatementIntoPositionEmbedding beforeSmall beforeLarge) :
    Lanius.FunctionalView.Stateful.Command.RenameResult
      (positionStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      Lanius.FunctionalView.Core.Stateful.actionRenamer
      rootStatementIntoPositionEmbedding beforeWorld beforeLarge
      rootStatementCommand completion afterWorld afterSmall := by
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
  exact evaluated.renameResult actionSound
    rootStatementIntoPositionEmbedding beforeLarge related

private theorem rootLoop_calls_supported_in_state :
    Lanius.FunctionalView.Core.Stateful.Command.callsSatisfy
      traversalCallAllowedInState rootLoopCommand = true := by
  native_decide

private theorem rootRejected_calls_supported_in_state :
    Lanius.FunctionalView.Core.Stateful.Command.callsSatisfy
      traversalCallAllowedInState rootRejectedCommand = true := by
  native_decide

/-- Transport one compact root command into the full recognizer call registry
    and then place it in the lexical environment of the complete root
    statement. -/
private noncomputable def rootExecution_in_state_environment
    {beforeWorld afterWorld :
      Lanius.FunctionalView.Core.ReadOnly.World}
    {beforeSmall afterSmall : Lanius.FunctionalView.Env 7}
    {command : Lanius.FunctionalView.Stateful.Command
      Lanius.FunctionalView.Core.signature
      Lanius.FunctionalView.Core.Stateful.actions 7}
    {completion : Lanius.FunctionalView.Stateful.Completion}
    (supported :
      Lanius.FunctionalView.Core.Stateful.Command.callsSatisfy
        traversalCallAllowedInState command = true)
    (evaluated : Lanius.FunctionalView.Stateful.Command.Evaluates
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (rootStatefulMachine workspaceLayout grammar words grammarCell)
      beforeWorld beforeSmall command completion afterWorld afterSmall)
    (beforeLarge : Lanius.FunctionalView.Env 8)
    (related : Lanius.FunctionalView.Env.Extends rootIntoStatementEmbedding
      beforeSmall beforeLarge) :
    Lanius.FunctionalView.Stateful.Command.RenameResult
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      Lanius.FunctionalView.Core.Stateful.actionRenamer
      rootIntoStatementEmbedding beforeWorld beforeLarge command completion
      afterWorld afterSmall := by
  let first := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
    words grammarCell
  let second := RecognizerStateCallRegistry.calls workspaceLayout grammar words
    tokens grammarCell tokensCell
  have changed :=
    Lanius.FunctionalView.Core.Stateful.Command.Evaluates.changeCallModel
      (program := verifiedParserCore) (first := first) (second := second)
      traversalCalls_agree_state supported (by
        simpa [rootTermMachine, rootStatefulMachine, nullableTermMachine,
          nullableStatefulMachine, first,
          Lanius.FunctionalView.Core.Effectful.machine,
          Lanius.FunctionalView.Core.Stateful.termMachine] using evaluated)
  have actionSound :
      @Lanius.FunctionalView.Stateful.ActionRenamer.Sound
        Lanius.FunctionalView.Core.signature
        Lanius.FunctionalView.Core.Stateful.actions
        Lanius.FunctionalView.Core.Stateful.actionRenamer
        (stateTermMachine workspaceLayout grammar words tokens grammarCell
          tokensCell)
        (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
          tokensCell) := by
    intro source target embedding world small large relatedEnv action
    have specialized :=
      Lanius.FunctionalView.Core.Stateful.actionRenamer_sound
        verifiedParserCore
        (Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedParserCore second)
        embedding world small large relatedEnv action
    simpa [stateTermMachine, stateStatefulMachine, second] using specialized
  have changed' : Lanius.FunctionalView.Stateful.Command.Evaluates
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      beforeWorld beforeSmall command completion afterWorld afterSmall := by
    simpa [stateTermMachine, stateStatefulMachine, second] using changed
  exact changed'.renameResult actionSound rootIntoStatementEmbedding
    beforeLarge related

private theorem rootStateValueTerm_evaluates
    {arity : Nat} (enough : 7 ≤ arity)
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (environment : Lanius.FunctionalView.Env arity)
    (workspace : LogicalWorkspace) (state : EarleyState)
    (stateId field : Nat) (fieldConstant : ConstantId)
    (grammarDistinct : grammarCell ≠ workspaceCell)
    (tokensDistinct : tokensCell ≠ workspaceCell)
    (workspaceValueEq : environment ⟨1, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (stateBaseEq : environment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (stateIdEq : environment ⟨6, by omega⟩ =
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
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      environment
      (stateValueTerm ⟨1, by omega⟩ ⟨2, by omega⟩ ⟨6, by omega⟩
        fieldConstant) =
      .ok (.signed .i32 (stateFieldValue workspace stateId state field),
        stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell) := by
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let machine := rootTermMachine workspaceLayout grammar words grammarCell
  have workspaceResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨1, by omega⟩) =
      .ok (workspaceValue workspaceValues workspaceCell, world) :=
    Lanius.FunctionalView.Term.evaluate_slot workspaceValueEq
  have baseResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨2, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat
        (stateBase workspaceLayout.tokenCount)), world) :=
    Lanius.FunctionalView.Term.evaluate_slot stateBaseEq
  have stateResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨6, by omega⟩) =
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
      environment [stateSlot ⟨1, by omega⟩, stateSlot ⟨2, by omega⟩,
        stateSlot ⟨6, by omega⟩, constantTerm] =
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
  have worldFound : world.i32Slice? workspaceCell = some workspaceValues :=
    stateWorld_finds_workspace grammarDistinct tokensDistinct
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

private theorem rootRhsLengthTerm_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (environment : Lanius.FunctionalView.Env 8) (production : Nat)
    (productionBound : production < grammar.productionCount)
    (grammarValueEq : environment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell)
    (productionValueEq : environment ⟨7, by omega⟩ =
      .signed .i32 (Int.ofNat production)) :
    Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      environment (stateRhsLengthTerm ⟨0, by omega⟩ ⟨7, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨production, productionBound⟩).rhs.length),
        stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell) := by
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let machine := rootTermMachine workspaceLayout grammar words grammarCell
  have grammarResult := Lanius.FunctionalView.Term.evaluate_slot
    (machine := machine) (world := world) (environment := environment)
    (index := ⟨0, by omega⟩) grammarValueEq
  have productionResult := Lanius.FunctionalView.Term.evaluate_slot
    (machine := machine) (world := world) (environment := environment)
    (index := ⟨7, by omega⟩) productionValueEq
  have argumentsResult := Lanius.FunctionalView.evaluateTerms_cons grammarResult
    (Lanius.FunctionalView.evaluateTerms_cons productionResult
      (Lanius.FunctionalView.evaluateTerms_nil machine world environment))
  have rowBound : production < grammar.rhsLengths.length := by simpa
  have registryResult := RecognizerTraversalCallRegistry.calls_at_rhs_length
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (grammarCell := grammarCell) world production
    stateWorld_finds_grammar rowBound
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

private theorem rootLhsTerm_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat) (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId)
    (environment : Lanius.FunctionalView.Env 8) (production : Nat)
    (productionBound : production < grammar.productionCount)
    (grammarValueEq : environment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell)
    (productionValueEq : environment ⟨7, by omega⟩ =
      .signed .i32 (Int.ofNat production)) :
    Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      environment (stateLhsTerm ⟨0, by omega⟩ ⟨7, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionAt ⟨production, productionBound⟩).lhs),
        stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell) := by
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let machine := rootTermMachine workspaceLayout grammar words grammarCell
  have grammarResult := Lanius.FunctionalView.Term.evaluate_slot
    (machine := machine) (world := world) (environment := environment)
    (index := ⟨0, by omega⟩) grammarValueEq
  have productionResult := Lanius.FunctionalView.Term.evaluate_slot
    (machine := machine) (world := world) (environment := environment)
    (index := ⟨7, by omega⟩) productionValueEq
  have argumentsResult := Lanius.FunctionalView.evaluateTerms_cons grammarResult
    (Lanius.FunctionalView.evaluateTerms_cons productionResult
      (Lanius.FunctionalView.evaluateTerms_nil machine world environment))
  have rowBound : production < grammar.productionLhs.length := by simpa
  have registryResult := RecognizerTraversalCallRegistry.calls_at_lhs
    (workspaceLayout := workspaceLayout) (grammar := grammar)
    (words := words) (grammarCell := grammarCell) world production
    stateWorld_finds_grammar rowBound
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

private theorem rootEnvironment_push_set_candidate
    (words : List Int) (workspaceValues : List Int)
    (grammarCell workspaceCell : CellId) (workspaceLayout : WorkspaceLayout)
    (grammar : IndexedGrammar) (stateCount furthest : Nat)
    (beforeCandidate production afterCandidate : Int) :
    Lanius.FunctionalView.Stateful.Env.pop
        (Lanius.FunctionalView.Stateful.Env.set
          ((rootEnvironment words workspaceValues grammarCell workspaceCell
            workspaceLayout grammar stateCount furthest beforeCandidate).push
            (.signed .i32 production))
          ⟨6, by omega⟩ (.signed .i32 afterCandidate)) =
      rootEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar stateCount furthest afterCandidate := by
  apply Lanius.FunctionalView.Env.eq_ofFn
  rfl

def RootCandidateMatches
    (grammar : IndexedGrammar) (candidate : EarleyState)
    (productionBound : candidate.production < grammar.productionCount) : Prop :=
  candidate.origin = 0 ∧
    (grammar.productionAt ⟨candidate.production, productionBound⟩).lhs =
      grammar.grammar.start_nonterminal ∧
    candidate.dot =
      (grammar.productionAt ⟨candidate.production, productionBound⟩).rhs.length

instance (grammar : IndexedGrammar) (candidate : EarleyState)
    (productionBound : candidate.production < grammar.productionCount) :
    Decidable (RootCandidateMatches grammar candidate productionBound) := by
  unfold RootCandidateMatches
  infer_instance

/-- Read-only state carried by the final-chart root search.  The cursor is the
    only mutable cell; the result count, start symbol, and final position stay
    framed while candidate accessors execute. -/
structure RecognizerRootLoopInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (runtime : State) (current : Nat) (remaining : List Nat) : Type where
  chartCursor : RecognizerChartCursorInvariant grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell cursorCell runtime (finalPosition workspaceLayout.tokenCount)
    41 current remaining
  startNonterminalLocal : runtime.local? 12 = some
    (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal))
  stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
    (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds runtime
  furthestPosition : Nat
  furthestPositionLocal : runtime.local? 22 = some
    (.signed .i32 (Int.ofNat furthestPosition))
  cursorFrameDisjoint : CellSet.Disjoint
    (localBindingFrameFootprint runtime verifiedParserRootLoopBindings)
    (CellSet.singleton cursorCell)

def RecognizerRootLoopInvariant.after_empty_effect
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before current remaining)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell after current remaining := {
  chartCursor := invariant.chartCursor.after_empty_effect effect afterWellFormed
  startNonterminalLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed invariant.startNonterminalLocal
  stateCountOwned := effect.empty_preserves_assertion
    invariant.chartCursor.recognizer.wellFormed
    (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length))))
    invariant.stateCountOwned
  furthestPosition := invariant.furthestPosition
  furthestPositionLocal := effect.empty_preserves_local
    invariant.chartCursor.recognizer.wellFormed
    invariant.furthestPositionLocal
  cursorFrameDisjoint := by
    rw [effect.localBindingFrameFootprint_eq verifiedParserRootLoopBindings]
    exact invariant.cursorFrameDisjoint
}

def RecognizerRootLoopInvariant.after_bind_local
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining)
    (id : VarId) (value : Value) (cursorBefore : 41 < id) :
    RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell (runtime.bindLocal id value)
      current remaining := by
  have persistentBefore : 22 < id := Nat.lt_trans (by decide) cursorBefore
  have different (fixed : Nat) (bound : fixed ≤ 22) : id ≠ fixed :=
    Nat.ne_of_gt (Nat.lt_of_le_of_lt bound persistentBefore)
  exact {
    chartCursor := invariant.chartCursor.after_bind_local id value
      (Nat.lt_trans (by decide) cursorBefore) cursorBefore
    startNonterminalLocal :=
      (bindLocal_preserves_other_local invariant.chartCursor.recognizer.wellFormed
        (different 12 (by decide))).trans invariant.startNonterminalLocal
    stateCountOwned := bindLocal_preserves_localPointsTo_of_ne runtime id 18
      value stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))
      invariant.chartCursor.recognizer.wellFormed (different 18 (by decide))
      invariant.stateCountOwned
    furthestPosition := invariant.furthestPosition
    furthestPositionLocal :=
      (bindLocal_preserves_other_local
        invariant.chartCursor.recognizer.wellFormed
        (Nat.ne_of_gt (Nat.lt_trans (by decide) cursorBefore))).trans
        invariant.furthestPositionLocal
    cursorFrameDisjoint := by
      intro cell framed written
      obtain ⟨queried, queriedBound, same⟩ := framed
      subst cell
      have queriedFramed :=
        (RootLoopFramedLocal_source_frame queried).mpr queriedBound
      have notEqual : id ≠ queried := different queried queriedFramed.le22
      apply invariant.cursorFrameDisjoint.localCell_ne_of_singleton
        queriedBound
      simpa [State.bindLocal, State.bindCell, State.cellId?, notEqual] using same
  }

/-- The predicate in the mechanically reified final-root body is exactly the
    logical condition for accepting the current Earley state.  All packed
    workspace and grammar reads pass through the same call registry used by
    the executable FunctionalView command. -/
private theorem RecognizerRootLoopInvariant.functional_predicate
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount) :
    let world := stateWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell
    let environment :=
      (rootEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar workspace.states.length
        invariant.furthestPosition (Int.ofNat current)).push
        (.signed .i32 (Int.ofNat candidate.production))
    Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell)
      world environment rootPredicateTerm =
      .ok (.boolean (decide
        (RootCandidateMatches grammar candidate productionBound)), world) := by
  dsimp only
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let environment :=
    (rootEnvironment words workspaceValues grammarCell workspaceCell
      workspaceLayout grammar workspace.states.length
      invariant.furthestPosition (Int.ofNat current)).push
      (.signed .i32 (Int.ofNat candidate.production))
  have grammarDistinct :=
    invariant.chartCursor.recognizer.grammarWorkspaceDistinct
  have tokensDistinct :=
    invariant.chartCursor.recognizer.tokensWorkspaceDistinct
  have originResult := rootStateValueTerm_evaluates
    (arity := 8) (by omega) workspaceLayout grammar words tokens
    workspaceValues grammarCell tokensCell workspaceCell environment workspace
    candidate current 2 30 grammarDistinct tokensDistinct (by rfl) (by rfl)
    (by rfl) invariant.chartCursor.recognizer.workspaceLength
    invariant.chartCursor.recognizer.workspaceEncoded found (by decide)
    verifiedParser_find_constants.2.2.2.1
  have dotResult := rootStateValueTerm_evaluates
    (arity := 8) (by omega) workspaceLayout grammar words tokens
    workspaceValues grammarCell tokensCell workspaceCell environment workspace
    candidate current 1 29 grammarDistinct tokensDistinct (by rfl) (by rfl)
    (by rfl) invariant.chartCursor.recognizer.workspaceLength
    invariant.chartCursor.recognizer.workspaceEncoded found (by decide)
    verifiedParser_find_constants.2.2.1
  have lhsResult := rootLhsTerm_evaluates workspaceLayout grammar words tokens
    workspaceValues grammarCell tokensCell workspaceCell environment
    candidate.production productionBound (by rfl) (by rfl)
  have rhsLengthResult := rootRhsLengthTerm_evaluates workspaceLayout grammar
    words tokens workspaceValues grammarCell tokensCell workspaceCell
    environment candidate.production productionBound (by rfl) (by rfl)
  have zeroResult : Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell) world
      environment (stateLiteral 0) =
      .ok (.signed .i32 0, world) := by
    rfl
  have startResult : Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell) world
      environment (stateSlot ⟨3, by omega⟩) =
      .ok (.signed .i32
        (Int.ofNat grammar.grammar.start_nonterminal), world) := by
    rfl
  have originMatchRaw := nullableEqual_evaluates workspaceLayout grammar words
    grammarCell world environment _ _ candidate.origin 0 originResult
    zeroResult
  have originMatch : Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell) world
      environment
        (rootEqualTerm
          (stateValueTerm ⟨1, by omega⟩ ⟨2, by omega⟩ ⟨6, by omega⟩ 30)
          (stateLiteral 0)) =
      .ok (.boolean (decide (candidate.origin = 0)), world) := by
    simpa [rootEqualTerm, nullableEqual] using originMatchRaw
  have lhsMatchRaw := nullableEqual_evaluates workspaceLayout grammar words
    grammarCell world environment _ _
    (grammar.productionAt
      ⟨candidate.production, productionBound⟩).lhs
    grammar.grammar.start_nonterminal lhsResult startResult
  have lhsMatch : Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell) world
      environment
        (rootEqualTerm (stateLhsTerm ⟨0, by omega⟩ ⟨7, by omega⟩)
          (stateSlot ⟨3, by omega⟩)) =
      .ok (.boolean (decide
        ((grammar.productionAt
          ⟨candidate.production, productionBound⟩).lhs =
            grammar.grammar.start_nonterminal)), world) := by
    simpa [rootEqualTerm, nullableEqual] using lhsMatchRaw
  have dotMatchRaw := nullableEqual_evaluates workspaceLayout grammar words
    grammarCell world environment _ _ candidate.dot
    (grammar.productionAt
      ⟨candidate.production, productionBound⟩).rhs.length
    dotResult rhsLengthResult
  have dotMatch : Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell) world
      environment
        (rootEqualTerm
          (stateValueTerm ⟨1, by omega⟩ ⟨2, by omega⟩ ⟨6, by omega⟩ 29)
          (stateRhsLengthTerm ⟨0, by omega⟩ ⟨7, by omega⟩)) =
      .ok (.boolean (decide
        (candidate.dot = (grammar.productionAt
          ⟨candidate.production, productionBound⟩).rhs.length)), world) := by
    simpa [rootEqualTerm, nullableEqual] using dotMatchRaw
  have firstTwo := evaluatesLogicalAnd
    (rootTermMachine workspaceLayout grammar words grammarCell) world
    environment _ _ (decide (candidate.origin = 0))
    (decide ((grammar.productionAt
      ⟨candidate.production, productionBound⟩).lhs =
        grammar.grammar.start_nonterminal)) originMatch lhsMatch
  have allThree := evaluatesLogicalAnd
    (rootTermMachine workspaceLayout grammar words grammarCell) world
    environment _ _
    (decide (candidate.origin = 0) &&
      decide ((grammar.productionAt
        ⟨candidate.production, productionBound⟩).lhs =
          grammar.grammar.start_nonterminal))
    (decide (candidate.dot = (grammar.productionAt
      ⟨candidate.production, productionBound⟩).rhs.length))
    firstTwo dotMatch
  have predicateValue :
      ((decide (candidate.origin = 0) &&
        decide ((grammar.productionAt
          ⟨candidate.production, productionBound⟩).lhs =
            grammar.grammar.start_nonterminal)) &&
        decide (candidate.dot = (grammar.productionAt
          ⟨candidate.production, productionBound⟩).rhs.length)) =
      decide (RootCandidateMatches grammar candidate productionBound) := by
    by_cases originMatches : candidate.origin = 0 <;>
      by_cases lhsMatches :
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).lhs =
            grammar.grammar.start_nonterminal <;>
      by_cases dotMatches : candidate.dot =
        (grammar.productionAt
          ⟨candidate.production, productionBound⟩).rhs.length <;>
      simp [RootCandidateMatches, originMatches, lhsMatches, dotMatches]
  rw [predicateValue] at allThree
  simpa [world, environment, rootPredicateTerm] using allThree

/-- The lexical production binding at the head of the root body reads the
    current candidate through the shared packed-state accessor. -/
private theorem RecognizerRootLoopInvariant.functional_production
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate) :
    Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      (rootEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar workspace.states.length
        invariant.furthestPosition (Int.ofNat current))
      (stateValueTerm ⟨1, by omega⟩ ⟨2, by omega⟩ ⟨6, by omega⟩ 28) =
      .ok (.signed .i32 (Int.ofNat candidate.production),
        stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell) := by
  have evaluated := rootStateValueTerm_evaluates
    (arity := 7) (by omega) workspaceLayout grammar words tokens
    workspaceValues grammarCell tokensCell workspaceCell
    (rootEnvironment words workspaceValues grammarCell workspaceCell
      workspaceLayout grammar workspace.states.length
      invariant.furthestPosition (Int.ofNat current))
    workspace candidate current 0 28
    invariant.chartCursor.recognizer.grammarWorkspaceDistinct
    invariant.chartCursor.recognizer.tokensWorkspaceDistinct
    (by rfl) (by rfl) (by rfl)
    invariant.chartCursor.recognizer.workspaceLength
    invariant.chartCursor.recognizer.workspaceEncoded found (by decide)
    verifiedParser_find_constants.2.1
  simpa [stateFieldValue] using evaluated

/-- The root cursor's successor is the next element of the invariant's
    unvisited suffix, using `-1` for exhaustion exactly as the source does. -/
private theorem RecognizerRootLoopInvariant.functional_next
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (environment : Lanius.FunctionalView.Env 8)
    (workspaceValueEq : environment ⟨1, by omega⟩ =
      workspaceValue workspaceValues workspaceCell)
    (stateBaseEq : environment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat (stateBase workspaceLayout.tokenCount)))
    (currentEq : environment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat current)) :
    Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      environment
      (stateValueTerm ⟨1, by omega⟩ ⟨2, by omega⟩ ⟨6, by omega⟩ 32) =
      .ok (.signed .i32 (encodeStateId remaining.head?),
        stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell) := by
  have evaluated := rootStateValueTerm_evaluates
    (arity := 8) (by omega) workspaceLayout grammar words tokens
    workspaceValues grammarCell tokensCell workspaceCell environment workspace
    candidate current 4 32
    invariant.chartCursor.recognizer.grammarWorkspaceDistinct
    invariant.chartCursor.recognizer.tokensWorkspaceDistinct workspaceValueEq
    stateBaseEq currentEq invariant.chartCursor.recognizer.workspaceLength
    invariant.chartCursor.recognizer.workspaceEncoded found (by decide)
    verifiedParser_find_constants.2.2.2.2
  have nextValue : stateFieldValue workspace current candidate 4 =
      encodeStateId remaining.head? := by
    simp only [stateFieldValue, stateNextValue]
    obtain ⟨cursorState, cursorFound, cursorPosition⟩ :=
      invariant.chartCursor.state_at_cursor
    rw [found] at cursorFound
    injection cursorFound with stateEqual
    subst cursorState
    rw [cursorPosition, invariant.chartCursor.cursor.nextAfter]
  rw [nextValue] at evaluated
  exact evaluated

/-- Functional evaluation of the ordinary successful parse-result
    constructor used by final root selection. -/
private theorem rootSuccessResultTerm_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 8)
    (stateCount rootState : Nat)
    (stateCountEq : environment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat stateCount))
    (rootStateEq : environment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat rootState)) :
    Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell)
      world environment rootSuccessResultTerm =
      .ok (parseResultValue 0 (Int.ofNat stateCount)
        (Int.ofNat rootState) 0, world) := by
  let machine := rootTermMachine workspaceLayout grammar words grammarCell
  let statusTerm : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 8 :=
    .apply (.constant 0 parserI32Type) []
  have statusAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell) (world := world) (environment := environment)
      statusTerm (by rfl)
  have statusReadOnly : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment statusTerm =
      .ok (.signed .i32 0, world) := by
    have constantFound : verifiedParserCore.constant? 0 = some {
        id := 0
        type := parserI32Type
        value := .signed .i32 0
      } := by rfl
    exact Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_constant
      constantFound
  have statusResult : Lanius.FunctionalView.Term.evaluate machine world
      environment statusTerm = .ok (.signed .i32 0, world) :=
    statusAgreement.trans statusReadOnly
  have countResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨4, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat stateCount), world) :=
    Lanius.FunctionalView.Term.evaluate_slot stateCountEq
  have rootResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨6, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat rootState), world) :=
    Lanius.FunctionalView.Term.evaluate_slot rootStateEq
  have zeroResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateLiteral 0) = .ok (.signed .i32 0, world) := by
    rfl
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [statusTerm, stateSlot ⟨4, by omega⟩,
        stateSlot ⟨6, by omega⟩, stateLiteral 0] =
      .ok ([.signed .i32 0, .signed .i32 (Int.ofNat stateCount),
        .signed .i32 (Int.ofNat rootState), .signed .i32 0], world) :=
    Lanius.FunctionalView.evaluateTerms_cons statusResult
      (Lanius.FunctionalView.evaluateTerms_cons countResult
        (Lanius.FunctionalView.evaluateTerms_cons rootResult
          (Lanius.FunctionalView.evaluateTerms_cons zeroResult
            (Lanius.FunctionalView.evaluateTerms_nil machine world
              environment))))
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
    grammarCell).evaluate world extractedParserParseResultFunction.id [
      .signed .i32 0, .signed .i32 (Int.ofNat stateCount),
      .signed .i32 (Int.ofNat rootState), .signed .i32 0] = _
  exact RecognizerTraversalCallRegistry.calls_at_parse_result world 0
    (Int.ofNat stateCount) (Int.ofNat rootState) 0

private theorem rootRejectedResultTerm_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 7)
    (stateCount furthest : Nat)
    (stateCountEq : environment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat stateCount))
    (furthestEq : environment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat furthest)) :
    Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell)
      world environment rootRejectedResultTerm =
      .ok (parseResultValue 1 (Int.ofNat stateCount) (-1)
        (Int.ofNat furthest), world) := by
  let machine := rootTermMachine workspaceLayout grammar words grammarCell
  let statusTerm : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 7 :=
    .apply (.constant 1 parserI32Type) []
  let negativeOneTerm : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature 7 :=
    .apply (.unary .negate parserI32Type parserI32Type) [stateLiteral 1]
  have statusAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell) (world := world) (environment := environment)
      statusTerm (by rfl)
  have statusReadOnly : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment statusTerm = .ok (.signed .i32 1, world) := by
    have constantFound : verifiedParserCore.constant? 1 = some {
        id := 1
        type := parserI32Type
        value := .signed .i32 1
      } := by rfl
    exact Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_constant
      constantFound
  have statusResult : Lanius.FunctionalView.Term.evaluate machine world
      environment statusTerm = .ok (.signed .i32 1, world) :=
    statusAgreement.trans statusReadOnly
  have countResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨4, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat stateCount), world) :=
    Lanius.FunctionalView.Term.evaluate_slot stateCountEq
  have negativeAgreement :=
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      (program := verifiedParserCore)
      (calls := RecognizerTraversalCallRegistry.calls workspaceLayout grammar
        words grammarCell) (world := world) (environment := environment)
      negativeOneTerm (by rfl)
  have negativeReadOnly : Lanius.FunctionalView.Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine verifiedParserCore)
      world environment negativeOneTerm =
      .ok (.signed .i32 (-1), world) := by
    rfl
  have negativeResult : Lanius.FunctionalView.Term.evaluate machine world
      environment negativeOneTerm = .ok (.signed .i32 (-1), world) :=
    negativeAgreement.trans negativeReadOnly
  have furthestResult : Lanius.FunctionalView.Term.evaluate machine world
      environment (stateSlot ⟨5, by omega⟩) =
      .ok (.signed .i32 (Int.ofNat furthest), world) :=
    Lanius.FunctionalView.Term.evaluate_slot furthestEq
  have argumentsResult : Lanius.FunctionalView.evaluateTerms machine world
      environment [statusTerm, stateSlot ⟨4, by omega⟩, negativeOneTerm,
        stateSlot ⟨5, by omega⟩] =
      .ok ([.signed .i32 1, .signed .i32 (Int.ofNat stateCount),
        .signed .i32 (-1), .signed .i32 (Int.ofNat furthest)], world) :=
    Lanius.FunctionalView.evaluateTerms_cons statusResult
      (Lanius.FunctionalView.evaluateTerms_cons countResult
        (Lanius.FunctionalView.evaluateTerms_cons negativeResult
          (Lanius.FunctionalView.evaluateTerms_cons furthestResult
            (Lanius.FunctionalView.evaluateTerms_nil machine world
              environment))))
  apply Lanius.FunctionalView.Term.evaluate_apply argumentsResult
  change (RecognizerTraversalCallRegistry.calls workspaceLayout grammar words
    grammarCell).evaluate world extractedParserParseResultFunction.id [
      .signed .i32 1, .signed .i32 (Int.ofNat stateCount),
      .signed .i32 (-1), .signed .i32 (Int.ofNat furthest)] = _
  exact RecognizerTraversalCallRegistry.calls_at_parse_result world 1
    (Int.ofNat stateCount) (-1) (Int.ofNat furthest)

/-- A matching final-chart candidate executes the exact reified root body and
    returns the successful parse result without changing the functional world
    or its persistent environment. -/
private theorem RecognizerRootLoopInvariant.functional_accept_body
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (candidateMatches : RootCandidateMatches grammar candidate
      productionBound) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (rootStatefulMachine workspaceLayout grammar words grammarCell)
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      (rootEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar workspace.states.length
        invariant.furthestPosition (Int.ofNat current))
      rootBodyCommand
      (.returned (some (parseResultValue 0
        (Int.ofNat workspace.states.length) (Int.ofNat current) 0)))
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      (rootEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar workspace.states.length
        invariant.furthestPosition (Int.ofNat current)) := by
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let beforeEnvironment :=
    rootEnvironment words workspaceValues grammarCell workspaceCell
      workspaceLayout grammar workspace.states.length
      invariant.furthestPosition (Int.ofNat current)
  let productionEnvironment := beforeEnvironment.push
    (.signed .i32 (Int.ofNat candidate.production))
  have productionResult := invariant.functional_production candidate found
  have predicateResult : Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell) world
      productionEnvironment rootPredicateTerm =
      .ok (.boolean true, world) := by
    have evaluated := invariant.functional_predicate candidate found
      productionBound
    simpa [world, beforeEnvironment, productionEnvironment, candidateMatches]
      using evaluated
  have resultTerm := rootSuccessResultTerm_evaluates workspaceLayout grammar
    words grammarCell world productionEnvironment workspace.states.length
    current (by rfl) (by rfl)
  have returned : Lanius.FunctionalView.Stateful.Command.Evaluates
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (rootStatefulMachine workspaceLayout grammar words grammarCell)
      world productionEnvironment (.returnValue (some rootSuccessResultTerm))
      (.returned (some (parseResultValue 0
        (Int.ofNat workspace.states.length) (Int.ofNat current) 0)))
      world productionEnvironment := .returnSome resultTerm
  have success : Lanius.FunctionalView.Stateful.Command.Evaluates
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (rootStatefulMachine workspaceLayout grammar words grammarCell)
      world productionEnvironment rootSuccessCommand
      (.returned (some (parseResultValue 0
        (Int.ofNat workspace.states.length) (Int.ofNat current) 0)))
      world productionEnvironment := by
    rw [rootSuccessCommand]
    exact .sequenceStop returned (by intro impossible; cases impossible)
  have selected : Lanius.FunctionalView.Stateful.Command.Evaluates
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (rootStatefulMachine workspaceLayout grammar words grammarCell)
      world productionEnvironment
      (.ifThenElse rootPredicateTerm rootSuccessCommand .skip)
      (.returned (some (parseResultValue 0
        (Int.ofNat workspace.states.length) (Int.ofNat current) 0)))
      world productionEnvironment := .ifTrue predicateResult success
  have continuation : Lanius.FunctionalView.Stateful.Command.Evaluates
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (rootStatefulMachine workspaceLayout grammar words grammarCell)
      world productionEnvironment
      (.sequence
        (.ifThenElse rootPredicateTerm rootSuccessCommand .skip)
        rootAdvanceCommand)
      (.returned (some (parseResultValue 0
        (Int.ofNat workspace.states.length) (Int.ofNat current) 0)))
      world productionEnvironment :=
    .sequenceStop selected (by intro impossible; cases impossible)
  have assembled :=
    Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
      (type := parserI32Type) productionResult continuation
  simpa [rootBodyCommand_shape, rootExpectedBodyCommand, world,
    beforeEnvironment, productionEnvironment] using assembled

/-- A nonmatching final-chart candidate executes the exact reified root body,
    updates only its functional cursor, and restores the lexical production
    binding before the next iteration. -/
private theorem RecognizerRootLoopInvariant.functional_advance_body
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (productionBound : candidate.production < grammar.productionCount)
    (candidateDoesNotMatch : ¬ RootCandidateMatches grammar candidate
      productionBound) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (rootStatefulMachine workspaceLayout grammar words grammarCell)
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      (rootEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar workspace.states.length
        invariant.furthestPosition (Int.ofNat current))
      rootBodyCommand .next
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      (rootEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar workspace.states.length
        invariant.furthestPosition (encodeStateId remaining.head?)) := by
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let beforeEnvironment :=
    rootEnvironment words workspaceValues grammarCell workspaceCell
      workspaceLayout grammar workspace.states.length
      invariant.furthestPosition (Int.ofNat current)
  let productionEnvironment := beforeEnvironment.push
    (.signed .i32 (Int.ofNat candidate.production))
  have productionResult := invariant.functional_production candidate found
  have predicateResult : Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell) world
      productionEnvironment rootPredicateTerm =
      .ok (.boolean false, world) := by
    have evaluated := invariant.functional_predicate candidate found
      productionBound
    simpa [world, beforeEnvironment, productionEnvironment,
      candidateDoesNotMatch] using evaluated
  have nextResult := invariant.functional_next candidate found
    productionEnvironment (by rfl) (by rfl) (by rfl)
  let afterCursor := Lanius.FunctionalView.Stateful.Env.set
    productionEnvironment ⟨6, by omega⟩
      (.signed .i32 (encodeStateId remaining.head?))
  have selected : Lanius.FunctionalView.Stateful.Command.Evaluates
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (rootStatefulMachine workspaceLayout grammar words grammarCell)
      world productionEnvironment
      (.ifThenElse rootPredicateTerm rootSuccessCommand .skip) .next world
      productionEnvironment := .ifFalse predicateResult .skip
  have advanced : Lanius.FunctionalView.Stateful.Command.Evaluates
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (rootStatefulMachine workspaceLayout grammar words grammarCell)
      world productionEnvironment rootAdvanceCommand .next world
      afterCursor := by
    rw [rootAdvanceCommand]
    exact .sequenceNext (.setLocal nextResult) .skip
  have continuation :=
    Lanius.FunctionalView.Stateful.Command.Evaluates.sequenceNext selected
      advanced
  have assembled :=
    Lanius.FunctionalView.Stateful.Command.Evaluates.letValue
      (type := parserI32Type) productionResult continuation
  have environmentEq : Lanius.FunctionalView.Stateful.Env.pop afterCursor =
      rootEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar workspace.states.length
        invariant.furthestPosition (encodeStateId remaining.head?) := by
    exact rootEnvironment_push_set_candidate words workspaceValues grammarCell
      workspaceCell workspaceLayout grammar workspace.states.length
      invariant.furthestPosition (Int.ofNat current)
      (Int.ofNat candidate.production) (encodeStateId remaining.head?)
  rw [environmentEq] at assembled
  simpa [rootBodyCommand_shape, rootExpectedBodyCommand, world,
    beforeEnvironment, productionEnvironment, afterCursor] using assembled

structure RecognizerRootCandidateBinding
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerRootLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate) where
  afterProductionRead : State
  productionEvaluation : Evaluates verifiedParserCore before
    (parserRecognizeStateValueCall 41 28)
    (.signed .i32 (Int.ofNat candidate.production)) afterProductionRead
  productionEffect : ModifiesOnly CellSet.empty before afterProductionRead
  productionWellFormed : StateWellFormed afterProductionRead
  invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell
    (afterProductionRead.bindLocal 42
      (.signed .i32 (Int.ofNat candidate.production))) current remaining
  productionLocal :
    (afterProductionRead.bindLocal 42
      (.signed .i32 (Int.ofNat candidate.production))).local? 42 =
      some (.signed .i32 (Int.ofNat candidate.production))

noncomputable def RecognizerRootLoopInvariant.bind_candidate
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining)
    (candidate : EarleyState) (found : workspace.state? current = some candidate) :
    RecognizerRootCandidateBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining
      invariant candidate found := by
  let productionRead := invariant.chartCursor.read_state_field candidate found
    0 28 (by decide) verifiedParser_find_constants.2.1
  have productionEvaluation : Evaluates verifiedParserCore runtime
      (parserRecognizeStateValueCall 41 28)
      (.signed .i32 (Int.ofNat candidate.production)) productionRead.after := by
    simpa [stateFieldValue] using productionRead.evaluation
  let afterProduction := invariant.after_empty_effect productionRead.effect
    productionRead.invariant.recognizer.wellFormed
  let bound := productionRead.after.bindLocal 42
    (.signed .i32 (Int.ofNat candidate.production))
  exact {
    afterProductionRead := productionRead.after
    productionEvaluation := productionEvaluation
    productionEffect := productionRead.effect
    productionWellFormed := productionRead.invariant.recognizer.wellFormed
    invariant := by
      simpa [bound] using afterProduction.after_bind_local 42
        (.signed .i32 (Int.ofNat candidate.production)) (by decide)
    productionLocal := by
      simpa [bound] using bindLocal_finds_local productionRead.after 42
        (.signed .i32 (Int.ofNat candidate.production))
        productionRead.invariant.recognizer.wellFormed
  }

structure RecognizerRootPredicateResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerRootLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before current remaining)
    (candidate : EarleyState)
    (productionBound : candidate.production < grammar.productionCount) where
  after : State
  evaluation : Evaluates verifiedParserCore before parserRecognizeRootPredicate
    (.boolean (decide
      (RootCandidateMatches grammar candidate productionBound))) after
  effect : ModifiesOnly CellSet.empty before after
  invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell after current remaining

noncomputable def RecognizerRootCandidateBinding.evaluate_predicate
    (binding : RecognizerRootCandidateBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining
      beforeInvariant candidate found)
    (productionBound : candidate.production < grammar.productionCount) :
    RecognizerRootPredicateResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell
      (binding.afterProductionRead.bindLocal 42
        (.signed .i32 (Int.ofNat candidate.production))) current remaining
      binding.invariant candidate productionBound := by
  let before := binding.afterProductionRead.bindLocal 42
    (.signed .i32 (Int.ofNat candidate.production))
  let productionFin : Fin grammar.productionCount :=
    ⟨candidate.production, productionBound⟩
  let lhs := (grammar.productionAt productionFin).lhs
  let rhsLength := (grammar.productionAt productionFin).rhs.length
  let originRead := binding.invariant.chartCursor.read_state_field candidate
    found 2 30 (by decide) verifiedParser_find_constants.2.2.2.1
  have originEvaluation : Evaluates verifiedParserCore before
      (parserRecognizeStateValueCall 41 30)
      (.signed .i32 (Int.ofNat candidate.origin)) originRead.after := by
    simpa [before, stateFieldValue] using originRead.evaluation
  have zeroEvaluation : Evaluates verifiedParserCore originRead.after
      (.value (.signed .i32 0)) (.signed .i32 0) originRead.after := ⟨1, rfl⟩
  have originEquality := evaluatesNatEqualityThreaded before originRead.after
    originRead.after (parserRecognizeStateValueCall 41 30)
    (.value (.signed .i32 0)) candidate.origin 0 originEvaluation zeroEvaluation
  let afterOrigin := binding.invariant.after_empty_effect originRead.effect
    originRead.invariant.recognizer.wellFormed
  by_cases originMatches : candidate.origin = 0
  · have originTrue : Evaluates verifiedParserCore before
        (.binary .equal (parserRecognizeStateValueCall 41 30)
          (.value (.signed .i32 0))) (.boolean true) originRead.after := by
      simpa [originMatches] using originEquality
    have productionAfterOrigin : originRead.after.local? 42 =
        some (.signed .i32 (Int.ofNat candidate.production)) :=
      originRead.effect.empty_preserves_local
        binding.invariant.chartCursor.recognizer.wellFormed
        binding.productionLocal
    have productionResult : Evaluates verifiedParserCore originRead.after
        (.local 42) (.signed .i32 (Int.ofNat candidate.production))
        originRead.after :=
      ⟨1, evalLocal_of_local 1 verifiedParserCore originRead.after 42 _
        productionAfterOrigin⟩
    let lhsRead := afterOrigin.chartCursor.read_lhs candidate.production
      productionBound (.local 42) productionResult
    have lhsEvaluation : Evaluates verifiedParserCore originRead.after
        (.call extractedParserLhsFunction.id [.local 0, .local 42])
        (.signed .i32 (Int.ofNat lhs)) lhsRead.after := by
      have lhsValue : grammar.productionLhs.get
          ⟨candidate.production, by simpa using productionBound⟩ = lhs := by
        simpa [lhs, productionFin] using grammar.productionLhs_get productionFin
      simpa only [lhsValue] using lhsRead.evaluation
    have startAfterLhs : lhsRead.after.local? 12 = some
        (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal)) :=
      lhsRead.effect.empty_preserves_local
        afterOrigin.chartCursor.recognizer.wellFormed
        afterOrigin.startNonterminalLocal
    have startResult : Evaluates verifiedParserCore lhsRead.after (.local 12)
        (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal))
        lhsRead.after :=
      ⟨1, evalLocal_of_local 1 verifiedParserCore lhsRead.after 12 _
        startAfterLhs⟩
    have lhsEquality := evaluatesNatEqualityThreaded originRead.after
      lhsRead.after lhsRead.after
      (.call extractedParserLhsFunction.id [.local 0, .local 42]) (.local 12)
      lhs grammar.grammar.start_nonterminal lhsEvaluation startResult
    by_cases lhsMatches : lhs = grammar.grammar.start_nonterminal
    · have lhsTrue : Evaluates verifiedParserCore originRead.after
          (.binary .equal
            (.call extractedParserLhsFunction.id [.local 0, .local 42])
            (.local 12)) (.boolean true) lhsRead.after := by
        simpa [lhsMatches] using lhsEquality
      have firstTwo := evaluatesLogicalAndTrue originTrue lhsTrue
      let afterLhs := afterOrigin.after_empty_effect lhsRead.effect
        lhsRead.invariant.recognizer.wellFormed
      let dotRead := afterLhs.chartCursor.read_state_field candidate found
        1 29 (by decide) verifiedParser_find_constants.2.2.1
      have dotEvaluation : Evaluates verifiedParserCore lhsRead.after
          (parserRecognizeStateValueCall 41 29)
          (.signed .i32 (Int.ofNat candidate.dot)) dotRead.after := by
        simpa [stateFieldValue] using dotRead.evaluation
      have productionAfterDot : dotRead.after.local? 42 =
          some (.signed .i32 (Int.ofNat candidate.production)) := by
        have productionAfterLhs : lhsRead.after.local? 42 =
            some (.signed .i32 (Int.ofNat candidate.production)) :=
          lhsRead.effect.empty_preserves_local
            afterOrigin.chartCursor.recognizer.wellFormed
            productionAfterOrigin
        exact dotRead.effect.empty_preserves_local
          afterLhs.chartCursor.recognizer.wellFormed productionAfterLhs
      have productionAfterDotResult : Evaluates verifiedParserCore dotRead.after
          (.local 42) (.signed .i32 (Int.ofNat candidate.production))
          dotRead.after :=
        ⟨1, evalLocal_of_local 1 verifiedParserCore dotRead.after 42 _
          productionAfterDot⟩
      let afterDot := afterLhs.after_empty_effect dotRead.effect
        dotRead.invariant.recognizer.wellFormed
      let rhsRead := afterDot.chartCursor.read_rhs_length candidate.production
        productionBound (.local 42) productionAfterDotResult
      have rhsEvaluation : Evaluates verifiedParserCore dotRead.after
          (.call extractedParserRhsLengthFunction.id [.local 0, .local 42])
          (.signed .i32 (Int.ofNat rhsLength)) rhsRead.after := by
        have rhsValue : grammar.rhsLengths.get
            ⟨candidate.production, by simpa using productionBound⟩ =
            rhsLength := by
          simpa [rhsLength, productionFin] using
            grammar.rhsLengths_get productionFin
        simpa only [rhsValue] using rhsRead.evaluation
      have dotEquality := evaluatesNatEqualityThreaded lhsRead.after
        dotRead.after rhsRead.after (parserRecognizeStateValueCall 41 29)
        (.call extractedParserRhsLengthFunction.id [.local 0, .local 42])
        candidate.dot rhsLength dotEvaluation rhsEvaluation
      let afterRhs := afterDot.after_empty_effect rhsRead.effect
        rhsRead.invariant.recognizer.wellFormed
      exact {
        after := rhsRead.after
        evaluation := by
          rw [extractedParserRecognize_root_predicate_shape]
          have firstTwo' := firstTwo
          have complete := evaluatesLogicalAndTrue firstTwo' dotEquality
          simpa [before, RootCandidateMatches, originMatches, lhsMatches, lhs,
            rhsLength, productionFin] using complete
        effect := originRead.effect.trans_same
          (lhsRead.effect.trans_same
            (dotRead.effect.trans_same rhsRead.effect))
        invariant := by simpa [before] using afterRhs
      }
    · have lhsFalse : Evaluates verifiedParserCore originRead.after
          (.binary .equal
            (.call extractedParserLhsFunction.id [.local 0, .local 42])
            (.local 12)) (.boolean false) lhsRead.after := by
        simpa [lhsMatches] using lhsEquality
      have firstTwo := evaluatesLogicalAndTrue originTrue lhsFalse
      have complete := evaluatesLogicalAndFalse
        (right := .binary .equal (parserRecognizeStateValueCall 41 29)
          (.call extractedParserRhsLengthFunction.id [.local 0, .local 42]))
        firstTwo
      let afterLhs := afterOrigin.after_empty_effect lhsRead.effect
        lhsRead.invariant.recognizer.wellFormed
      exact {
        after := lhsRead.after
        evaluation := by
          rw [extractedParserRecognize_root_predicate_shape]
          have decided : decide (RootCandidateMatches grammar candidate
              productionBound) = false := by
            simp [RootCandidateMatches, originMatches, lhsMatches, lhs,
              productionFin]
          rw [decided]
          exact complete
        effect := originRead.effect.trans_same lhsRead.effect
        invariant := by simpa [before] using afterLhs
      }
  · have originFalse : Evaluates verifiedParserCore before
        (.binary .equal (parserRecognizeStateValueCall 41 30)
          (.value (.signed .i32 0))) (.boolean false) originRead.after := by
      simpa [originMatches] using originEquality
    have firstTwo := evaluatesLogicalAndFalse
      (right := .binary .equal
        (.call extractedParserLhsFunction.id [.local 0, .local 42]) (.local 12))
      originFalse
    have complete := evaluatesLogicalAndFalse
      (right := .binary .equal (parserRecognizeStateValueCall 41 29)
        (.call extractedParserRhsLengthFunction.id [.local 0, .local 42]))
      firstTwo
    exact {
      after := originRead.after
      evaluation := by
        rw [extractedParserRecognize_root_predicate_shape]
        have decided : decide (RootCandidateMatches grammar candidate
            productionBound) = false := by
          simp [RootCandidateMatches, originMatches]
        rw [decided]
        exact complete
      effect := originRead.effect
      invariant := by simpa [before] using afterOrigin
    }

structure RecognizerRootFinishedInvariant
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (runtime : State) : Type where
  chartCursor : RecognizerChartCursorFinished grammarLayout grammar words
    tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell cursorCell runtime (finalPosition workspaceLayout.tokenCount)
    41
  startNonterminalLocal : runtime.local? 12 = some
    (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal))
  stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
    (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds runtime
  furthestPosition : Nat
  furthestPositionLocal : runtime.local? 22 = some
    (.signed .i32 (Int.ofNat furthestPosition))
  cursorFrameDisjoint : CellSet.Disjoint
    (localBindingFrameFootprint runtime verifiedParserRootLoopBindings)
    (CellSet.singleton cursorCell)

/-- The exhausted-root continuation runs the exact reified rejected-result
    command in the canonical final root environment. -/
private theorem RecognizerRootFinishedInvariant.functional_rejected
    (invariant : RecognizerRootFinishedInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before) :
    Lanius.FunctionalView.Stateful.Command.Evaluates
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (rootStatefulMachine workspaceLayout grammar words grammarCell)
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      (rootEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar workspace.states.length
        invariant.furthestPosition (-1))
      rootRejectedCommand
      (.returned (some (parseResultValue 1
        (Int.ofNat workspace.states.length) (-1)
        (Int.ofNat invariant.furthestPosition))))
      (stateWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell)
      (rootEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar workspace.states.length
        invariant.furthestPosition (-1)) := by
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let environment := rootEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout grammar workspace.states.length
    invariant.furthestPosition (-1)
  have resultTerm := rootRejectedResultTerm_evaluates workspaceLayout grammar
    words grammarCell world environment workspace.states.length
    invariant.furthestPosition (by rfl) (by rfl)
  have returned : Lanius.FunctionalView.Stateful.Command.Evaluates
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (rootStatefulMachine workspaceLayout grammar words grammarCell)
      world environment (.returnValue (some rootRejectedResultTerm))
      (.returned (some (parseResultValue 1
        (Int.ofNat workspace.states.length) (-1)
        (Int.ofNat invariant.furthestPosition)))) world environment :=
    .returnSome resultTerm
  rw [rootRejectedCommand_shape, rootExpectedRejectedCommand]
  exact .sequenceStop returned (by intro impossible; cases impossible)

/-- The artifact-derived `root_state` declaration turns a completed position
    traversal into either an active root search or an already exhausted one.
    This is the ownership boundary between the two loops: the final chart head
    is read without stores, local 41 receives a fresh cell, and the exact live
    root-loop frame is proved disjoint from that cell. -/
structure RecognizerRootEntry
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (source : State) (furthest : Nat)
    (sourceInvariant : RecognizerPositionFinishedInvariant grammarLayout
      grammar words tokens workspaceLayout workspace workspaceValues
      grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell source furthest) where
  chartEntry : RecognizerChartLoopEntry grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell source 6 (finalPosition workspaceLayout.tokenCount) 41
    sourceInvariant.frame.appendFrame.recognizer
    sourceInvariant.frame.workspaceWithinGrammar
    sourceInvariant.frame.appendFrame.stateBaseLocal
    sourceInvariant.frame.finalPositionLocal (Nat.le_refl _)
  cursor :
    (Sigma fun current : Nat => Sigma fun remaining : List Nat =>
      RecognizerRootLoopInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell chartEntry.cursorCell chartEntry.bound
        current remaining)
    ⊕ RecognizerRootFinishedInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell chartEntry.cursorCell chartEntry.bound

/-- Enter the exact final-chart root search after the position loop has
    completed normally.  No semantic state is reconstructed on the host: the
    root cursor comes from the encoded workspace chart head. -/
noncomputable def RecognizerPositionFinishedInvariant.enter_root_loop
    (invariant : RecognizerPositionFinishedInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell source
      furthest) :
    RecognizerRootEntry grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      stateCountCell positionCell furthestCell source furthest invariant := by
  let chartEntry := invariant.frame.appendFrame.recognizer.enter_chart_loop
    invariant.frame.workspaceWithinGrammar
    invariant.frame.appendFrame.stateBaseLocal 6
    (finalPosition workspaceLayout.tokenCount) 41
    invariant.frame.finalPositionLocal (Nat.le_refl _) (by decide)
  have startAfterRead : chartEntry.headRead.after.local? 12 = some
      (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal)) :=
    chartEntry.headRead.effect.empty_preserves_local
      invariant.frame.appendFrame.recognizer.wellFormed
      invariant.frame.startNonterminalLocal
  have startAtBound : chartEntry.bound.local? 12 = some
      (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal)) := by
    rw [chartEntry.boundEq]
    exact (bindLocal_preserves_other_local
      chartEntry.headRead.invariant.wellFormed (by decide)).trans
      startAfterRead
  have countAfterRead : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds
      chartEntry.headRead.after :=
    chartEntry.headRead.effect.empty_preserves_assertion
      invariant.frame.appendFrame.recognizer.wellFormed
      (Assertion.localPointsTo 18 stateCountCell
        (some (.signed .i32 (Int.ofNat workspace.states.length))))
      invariant.frame.appendFrame.stateCountOwned
  have countAtBound : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds
      chartEntry.bound := by
    rw [chartEntry.boundEq]
    exact bindLocal_preserves_localPointsTo_of_ne chartEntry.headRead.after
      41 18 (.signed .i32 (chartHeadValue workspace
        (finalPosition workspaceLayout.tokenCount))) stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))
      chartEntry.headRead.invariant.wellFormed (by decide) countAfterRead
  have rootFrameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint chartEntry.bound
        verifiedParserRootLoopBindings)
      (CellSet.singleton chartEntry.cursorCell) := by
    rw [chartEntry.boundEq, chartEntry.cursorCellEq]
    exact bindLocal_fresh_disjoint_from_frame chartEntry.headRead.after 41
      (.signed .i32 (chartHeadValue workspace
        (finalPosition workspaceLayout.tokenCount)))
      verifiedParserRootLoopBindings chartEntry.headRead.invariant.wellFormed
      (by
        intro member
        have framed := (RootLoopFramedLocal_source_frame 41).mpr member
        exact (Nat.not_le_of_gt (by decide)) framed.le22)
  refine { chartEntry := chartEntry, cursor := ?_ }
  cases chartEntry.cursor with
  | inl active =>
      exact .inl ⟨active.1, active.2.1, {
        chartCursor := active.2.2
        startNonterminalLocal := startAtBound
        stateCountOwned := countAtBound
        furthestPosition := furthest
        furthestPositionLocal := by
          rw [chartEntry.boundEq]
          exact (bindLocal_preserves_other_local
            chartEntry.headRead.invariant.wellFormed (by decide)).trans
            (chartEntry.headRead.effect.empty_preserves_local
              invariant.frame.appendFrame.recognizer.wellFormed
              (Assertion.localPointsTo_local 22 furthestCell _ source
                invariant.frame.furthestOwned))
        cursorFrameDisjoint := rootFrameDisjoint
      }⟩
  | inr finished =>
      exact .inr {
        chartCursor := finished
        startNonterminalLocal := startAtBound
        stateCountOwned := countAtBound
        furthestPosition := furthest
        furthestPositionLocal := by
          rw [chartEntry.boundEq]
          exact (bindLocal_preserves_other_local
            chartEntry.headRead.invariant.wellFormed (by decide)).trans
            (chartEntry.headRead.effect.empty_preserves_local
              invariant.frame.appendFrame.recognizer.wellFormed
              (Assertion.localPointsTo_local 22 furthestCell _ source
                invariant.frame.furthestOwned))
        cursorFrameDisjoint := rootFrameDisjoint
      }

def RecognizerRootLoopInvariant.after_cursor_effect
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before current remaining)
    (afterCursor : RecognizerChartCursorInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell after (finalPosition workspaceLayout.tokenCount)
      41 next nextRemaining)
    (effect : ModifiesOnly (CellSet.singleton cursorCell) before after) :
    RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell after next nextRemaining := by
  have preserveLocal (id : VarId) (framed : RootLoopFramedLocal id)
      (value : Value)
      (found : before.local? id = some value) : after.local? id = some value :=
    effect.preserves_local_of_disjoint
      invariant.chartCursor.recognizer.wellFormed
      invariant.cursorFrameDisjoint
      ((RootLoopFramedLocal_source_frame id).mp framed) found
  have stateCountNotCursor : stateCountCell ≠ cursorCell := by
    intro equal
    apply invariant.cursorFrameDisjoint.localCell_ne_of_singleton (id := 18)
      ((RootLoopFramedLocal_source_frame 18).mp (by
        simp [RootLoopFramedLocal]))
    rw [← equal]
    exact invariant.stateCountOwned.1
  have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds after :=
    effect.preserve invariant.chartCursor.recognizer.wellFormed
      (Assertion.localPointsTo 18 stateCountCell
        (some (.signed .i32 (Int.ofNat workspace.states.length))))
      invariant.stateCountOwned (by
        intro cell member written
        change cell = stateCountCell at member
        change cell = cursorCell at written
        subst cell
        exact stateCountNotCursor written)
  exact {
    chartCursor := afterCursor
    startNonterminalLocal := preserveLocal 12 (by
      simp [RootLoopFramedLocal]) _
      invariant.startNonterminalLocal
    stateCountOwned := stateCountOwned
    furthestPosition := invariant.furthestPosition
    furthestPositionLocal := preserveLocal 22 (by
      simp [RootLoopFramedLocal]) _ invariant.furthestPositionLocal
    cursorFrameDisjoint := by
      rw [effect.localBindingFrameFootprint_eq verifiedParserRootLoopBindings]
      exact invariant.cursorFrameDisjoint
  }

def RecognizerRootLoopInvariant.after_cursor_exhaustion
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before current [])
    (afterCursor : RecognizerChartCursorFinished grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell cursorCell after (finalPosition workspaceLayout.tokenCount)
      41)
    (effect : ModifiesOnly (CellSet.singleton cursorCell) before after) :
    RecognizerRootFinishedInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell after := by
  have preserveLocal (id : VarId) (framed : RootLoopFramedLocal id)
      (value : Value)
      (found : before.local? id = some value) : after.local? id = some value :=
    effect.preserves_local_of_disjoint
      invariant.chartCursor.recognizer.wellFormed
      invariant.cursorFrameDisjoint
      ((RootLoopFramedLocal_source_frame id).mp framed) found
  have stateCountNotCursor : stateCountCell ≠ cursorCell := by
    intro equal
    apply invariant.cursorFrameDisjoint.localCell_ne_of_singleton (id := 18)
      ((RootLoopFramedLocal_source_frame 18).mp (by
        simp [RootLoopFramedLocal]))
    rw [← equal]
    exact invariant.stateCountOwned.1
  have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds after :=
    effect.preserve invariant.chartCursor.recognizer.wellFormed
      (Assertion.localPointsTo 18 stateCountCell
        (some (.signed .i32 (Int.ofNat workspace.states.length))))
      invariant.stateCountOwned (by
        intro cell member written
        change cell = stateCountCell at member
        change cell = cursorCell at written
        subst cell
        exact stateCountNotCursor written)
  exact {
    chartCursor := afterCursor
    startNonterminalLocal := preserveLocal 12 (by
      simp [RootLoopFramedLocal]) _
      invariant.startNonterminalLocal
    stateCountOwned := stateCountOwned
    furthestPosition := invariant.furthestPosition
    furthestPositionLocal := preserveLocal 22 (by
      simp [RootLoopFramedLocal]) _ invariant.furthestPositionLocal
    cursorFrameDisjoint := by
      rw [effect.localBindingFrameFootprint_eq verifiedParserRootLoopBindings]
      exact invariant.cursorFrameDisjoint
  }

structure RecognizerRootScopedExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before innerAfter : State) (current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerRootLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before current remaining)
    (candidate : EarleyState)
    (found : workspace.state? current = some candidate)
    (binding : RecognizerRootCandidateBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before current remaining
      beforeInvariant candidate found)
    (completion : Completion) (writes : CellSet) where
  after : State
  execution : Executes verifiedParserCore before parserRecognizeRootLoopBody
    completion after
  effect : ModifiesOnly writes before after
  wellFormed : StateWellFormed after
  cells : after.cells = innerAfter.cells

def RecognizerRootCandidateBinding.close_scope
    (binding : RecognizerRootCandidateBinding grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining
      beforeInvariant candidate found)
    (innerAfter : State) (completion : Completion) (writes : CellSet)
    (innerExecution : Executes verifiedParserCore
      (binding.afterProductionRead.bindLocal 42
        (.signed .i32 (Int.ofNat candidate.production)))
      (.sequence
        (.ifThenElse parserRecognizeRootPredicate
          parserRecognizeRootSuccessBranch .skip)
        (parserRecognizeCursorAdvanceStatement 41)) completion innerAfter)
    (innerEffect : ModifiesOnly writes
      (binding.afterProductionRead.bindLocal 42
        (.signed .i32 (Int.ofNat candidate.production))) innerAfter)
    (innerWellFormed : StateWellFormed innerAfter) :
    RecognizerRootScopedExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime innerAfter current
      remaining beforeInvariant candidate found binding completion writes := by
  let bound := binding.afterProductionRead.bindLocal 42
    (.signed .i32 (Int.ofNat candidate.production))
  let after := restoreLocals binding.afterProductionRead innerAfter
  have entered : StoreEffect CellSet.empty binding.afterProductionRead bound := by
    simpa [bound] using bindLocal_effect binding.afterProductionRead 42
      (.signed .i32 (Int.ofNat candidate.production))
  have scopeEffect : StoreEffect writes binding.afterProductionRead innerAfter :=
    (entered.weaken CellSet.empty_subset).trans_same innerEffect.toStoreEffect
  have closedEffect : ModifiesOnly writes binding.afterProductionRead after := by
    simpa [after] using scopeEffect.restoreLocals
  have outerEffect : ModifiesOnly writes runtime after :=
    (binding.productionEffect.weaken CellSet.empty_subset).trans_same closedEffect
  have bodyExecution : Executes verifiedParserCore runtime
      parserRecognizeRootLoopBody completion after := by
    rw [extractedParserRecognize_root_body_shape]
    simpa [bound, after] using
      executesLetLocal (type := parserI32Type) binding.productionEvaluation
        innerExecution
  exact {
    after := after
    execution := bodyExecution
    effect := outerEffect
    wellFormed := scopeEffect.restoreLocals_wellFormed
      binding.productionWellFormed innerWellFormed
    cells := by simp [after, restoreLocals]
  }

def RecognizerRootScopedExecution.restore_invariant
    (closed : RecognizerRootScopedExecution
      (grammarLayout := grammarLayout) (grammar := grammar) (words := words)
      (tokens := tokens) (workspaceLayout := workspaceLayout)
      (workspace := workspace) (workspaceValues := workspaceValues)
      (grammarCell := grammarCell) (tokensCell := tokensCell)
      (workspaceCell := workspaceCell) (stateCountCell := stateCountCell)
      (cursorCell := cursorCell) (before := runtime) (innerAfter := innerAfter)
      (current := current) (remaining := remaining)
      (beforeInvariant := beforeInvariant) (candidate := candidate)
      (found := found) (binding := binding) (completion := .next)
      (writes := CellSet.singleton cursorCell))
    (innerInvariant : RecognizerRootLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell innerAfter next nextRemaining) :
    RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell closed.after next nextRemaining := by
  have recognizer := beforeInvariant.chartCursor.recognizer
    |>.after_disjoint_scalar_effect cursorCell closed.effect closed.wellFormed
      beforeInvariant.chartCursor.cursorBackingDistinct.1.symm
      beforeInvariant.chartCursor.cursorBackingDistinct.2.1.symm
      beforeInvariant.chartCursor.cursorBackingDistinct.2.2.symm
      (CellSet.Disjoint.mono_left
        (localBindingFrameFootprint_mono (fun id bound =>
          (RootLoopFramedLocal_source_frame id).mp (Or.inl bound)))
        beforeInvariant.cursorFrameDisjoint)
  have entryTransferred (cell : CellId) (entry : Cell)
      (innerEntry : innerAfter.cellEntry? cell = some entry) :
      closed.after.cellEntry? cell = some entry := by
    unfold State.cellEntry? at innerEntry ⊢
    rw [closed.cells]
    exact innerEntry
  have cursorOwned : (Assertion.localPointsTo 41 cursorCell
      (some (.signed .i32 (Int.ofNat next)))).holds closed.after := by
    constructor
    · unfold State.cellId?
      rw [closed.effect.locals]
      exact beforeInvariant.chartCursor.cursorOwned.1
    · exact entryTransferred cursorCell _ innerInvariant.chartCursor.cursorOwned.2
  have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds
      closed.after := by
    constructor
    · unfold State.cellId?
      rw [closed.effect.locals]
      exact beforeInvariant.stateCountOwned.1
    · exact entryTransferred stateCountCell _ innerInvariant.stateCountOwned.2
  exact {
    chartCursor := {
      recognizer := recognizer
      workspaceWithinGrammar := innerInvariant.chartCursor.workspaceWithinGrammar
      stateBaseLocal := closed.effect.preserves_local_of_disjoint
        beforeInvariant.chartCursor.recognizer.wellFormed
        beforeInvariant.cursorFrameDisjoint
        ((RootLoopFramedLocal_source_frame 8).mp (by
          simp [RootLoopFramedLocal]))
        beforeInvariant.chartCursor.stateBaseLocal
      cursorOwned := cursorOwned
      cursorFrameSeparate := by
        unfold ChartCursorFrameSeparated
        rw [closed.effect.localBindingFrameFootprint_eq
          verifiedParserChartCursorBindings]
        exact beforeInvariant.chartCursor.cursorFrameSeparate
      cursorBackingDistinct := beforeInvariant.chartCursor.cursorBackingDistinct
      chartPositionBound := innerInvariant.chartCursor.chartPositionBound
      cursor := innerInvariant.chartCursor.cursor
    }
    startNonterminalLocal := closed.effect.preserves_local_of_disjoint
      beforeInvariant.chartCursor.recognizer.wellFormed
      beforeInvariant.cursorFrameDisjoint
      ((RootLoopFramedLocal_source_frame 12).mp (by
        simp [RootLoopFramedLocal])) beforeInvariant.startNonterminalLocal
    stateCountOwned := stateCountOwned
    furthestPosition := beforeInvariant.furthestPosition
    furthestPositionLocal := closed.effect.preserves_local_of_disjoint
      beforeInvariant.chartCursor.recognizer.wellFormed
      beforeInvariant.cursorFrameDisjoint
      ((RootLoopFramedLocal_source_frame 22).mp (by
        simp [RootLoopFramedLocal])) beforeInvariant.furthestPositionLocal
    cursorFrameDisjoint := by
      rw [closed.effect.localBindingFrameFootprint_eq
        verifiedParserRootLoopBindings]
      exact beforeInvariant.cursorFrameDisjoint
  }

def RecognizerRootScopedExecution.restore_finished
    (closed : RecognizerRootScopedExecution
      (grammarLayout := grammarLayout) (grammar := grammar) (words := words)
      (tokens := tokens) (workspaceLayout := workspaceLayout)
      (workspace := workspace) (workspaceValues := workspaceValues)
      (grammarCell := grammarCell) (tokensCell := tokensCell)
      (workspaceCell := workspaceCell) (stateCountCell := stateCountCell)
      (cursorCell := cursorCell) (before := runtime) (innerAfter := innerAfter)
      (current := current) (remaining := remaining)
      (beforeInvariant := beforeInvariant) (candidate := candidate)
      (found := found) (binding := binding) (completion := .next)
      (writes := CellSet.singleton cursorCell))
    (innerInvariant : RecognizerRootFinishedInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell innerAfter) :
    RecognizerRootFinishedInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell closed.after := by
  have recognizer := beforeInvariant.chartCursor.recognizer
    |>.after_disjoint_scalar_effect cursorCell closed.effect closed.wellFormed
      beforeInvariant.chartCursor.cursorBackingDistinct.1.symm
      beforeInvariant.chartCursor.cursorBackingDistinct.2.1.symm
      beforeInvariant.chartCursor.cursorBackingDistinct.2.2.symm
      (CellSet.Disjoint.mono_left
        (localBindingFrameFootprint_mono (fun id bound =>
          (RootLoopFramedLocal_source_frame id).mp (Or.inl bound)))
        beforeInvariant.cursorFrameDisjoint)
  have entryTransferred (cell : CellId) (entry : Cell)
      (innerEntry : innerAfter.cellEntry? cell = some entry) :
      closed.after.cellEntry? cell = some entry := by
    unfold State.cellEntry? at innerEntry ⊢
    rw [closed.cells]
    exact innerEntry
  have cursorOwned : (Assertion.localPointsTo 41 cursorCell
      (some (.signed .i32 (-1)))).holds closed.after := by
    constructor
    · unfold State.cellId?
      rw [closed.effect.locals]
      exact beforeInvariant.chartCursor.cursorOwned.1
    · exact entryTransferred cursorCell _ innerInvariant.chartCursor.cursorOwned.2
  have stateCountOwned : (Assertion.localPointsTo 18 stateCountCell
      (some (.signed .i32 (Int.ofNat workspace.states.length)))).holds
      closed.after := by
    constructor
    · unfold State.cellId?
      rw [closed.effect.locals]
      exact beforeInvariant.stateCountOwned.1
    · exact entryTransferred stateCountCell _ innerInvariant.stateCountOwned.2
  exact {
    chartCursor := {
      recognizer := recognizer
      workspaceWithinGrammar := innerInvariant.chartCursor.workspaceWithinGrammar
      stateBaseLocal := closed.effect.preserves_local_of_disjoint
        beforeInvariant.chartCursor.recognizer.wellFormed
        beforeInvariant.cursorFrameDisjoint
        ((RootLoopFramedLocal_source_frame 8).mp (by
          simp [RootLoopFramedLocal]))
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
    startNonterminalLocal := closed.effect.preserves_local_of_disjoint
      beforeInvariant.chartCursor.recognizer.wellFormed
      beforeInvariant.cursorFrameDisjoint
      ((RootLoopFramedLocal_source_frame 12).mp (by
        simp [RootLoopFramedLocal])) beforeInvariant.startNonterminalLocal
    stateCountOwned := stateCountOwned
    furthestPosition := beforeInvariant.furthestPosition
    furthestPositionLocal := closed.effect.preserves_local_of_disjoint
      beforeInvariant.chartCursor.recognizer.wellFormed
      beforeInvariant.cursorFrameDisjoint
      ((RootLoopFramedLocal_source_frame 22).mp (by
        simp [RootLoopFramedLocal])) beforeInvariant.furthestPositionLocal
    cursorFrameDisjoint := by
      rw [closed.effect.localBindingFrameFootprint_eq
        verifiedParserRootLoopBindings]
      exact beforeInvariant.cursorFrameDisjoint
  }

theorem verifiedParserRecognize_parse_success_constant :
    verifiedParserCore.constant? 0 = some {
      id := 0
      type := parserI32Type
      value := .signed .i32 0
    } := by
  rfl

inductive RecognizerRootLoopOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId) :
    (after : State) → (completion : Completion) → Type
  | accepted (rootState : Nat) (candidate : EarleyState)
      (found : workspace.state? rootState = some candidate)
      (productionBound : candidate.production < grammar.productionCount)
      (candidateMatches : RootCandidateMatches grammar candidate productionBound)
      (materializedParse : MaterializedParse grammar tokens)
      (after : State) (wellFormed : StateWellFormed after) :
      RecognizerRootLoopOutcome grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell after
        (.returned (some (parseResultValue 0
          (Int.ofNat workspace.states.length) (Int.ofNat rootState) 0)))
  | exhausted (after : State)
      (invariant : RecognizerRootFinishedInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell after) :
      RecognizerRootLoopOutcome grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell after .next

inductive RecognizerRootStepOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (current : Nat) (remaining : List Nat) : State → Completion → Type
  | accepted (candidate : EarleyState)
      (found : workspace.state? current = some candidate)
      (productionBound : candidate.production < grammar.productionCount)
      (candidateMatches : RootCandidateMatches grammar candidate productionBound)
      (materializedParse : MaterializedParse grammar tokens)
      (after : State) (wellFormed : StateWellFormed after) :
      RecognizerRootStepOutcome grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell current remaining after
        (.returned (some (parseResultValue 0
          (Int.ofNat workspace.states.length) (Int.ofNat current) 0)))
  | advanced (candidate : EarleyState)
      (found : workspace.state? current = some candidate)
      (productionBound : candidate.production < grammar.productionCount)
      (candidateDoesNotMatch : ¬ RootCandidateMatches grammar candidate
        productionBound)
      (next : Nat) (nextRemaining : List Nat) (after : State)
      (invariant : RecognizerRootLoopInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell after next nextRemaining)
      (suffix : next :: nextRemaining = remaining) :
      RecognizerRootStepOutcome grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell current remaining after .next
  | exhausted (candidate : EarleyState)
      (found : workspace.state? current = some candidate)
      (productionBound : candidate.production < grammar.productionCount)
      (candidateDoesNotMatch : ¬ RootCandidateMatches grammar candidate
        productionBound)
      (empty : remaining = [])
      (after : State)
      (invariant : RecognizerRootFinishedInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell after) :
      RecognizerRootStepOutcome grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell current remaining after .next

structure RecognizerRootStepExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerRootLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before current remaining) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before parserRecognizeRootLoopBody
    completion after
  effect : ModifiesOnly (CellSet.singleton cursorCell) before after
  outcome : RecognizerRootStepOutcome grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell current remaining after completion

/-- Execute one final-chart candidate.  A failed candidate advances or
    exhausts the cursor; a matching completed start state returns immediately. -/
private noncomputable def RecognizerRootLoopInvariant.execute_step_structural
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining) :
    RecognizerRootStepExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining
      invariant := by
  let candidate := Classical.choose invariant.chartCursor.state_at_cursor
  have candidateFacts := Classical.choose_spec invariant.chartCursor.state_at_cursor
  have found : workspace.state? current = some candidate := candidateFacts.1
  have within := invariant.chartCursor.state_within_grammar candidate found
  have productionBound : candidate.production < grammar.productionCount := by
    simpa [EarleyState.key] using within.productionBound
  let binding := invariant.bind_candidate candidate found
  let predicate := binding.evaluate_predicate productionBound
  by_cases candidateMatches : RootCandidateMatches grammar candidate productionBound
  · have predicateTrue : Evaluates verifiedParserCore
        (binding.afterProductionRead.bindLocal 42
          (.signed .i32 (Int.ofNat candidate.production)))
        parserRecognizeRootPredicate (.boolean true) predicate.after := by
      simpa [candidateMatches] using predicate.evaluation
    have statusResult : Evaluates verifiedParserCore predicate.after
        (.constant 0) (.signed .i32 0) predicate.after :=
      evaluatesConstant verifiedParserRecognize_parse_success_constant
    have countResult : Evaluates verifiedParserCore predicate.after (.local 18)
        (.signed .i32 (Int.ofNat workspace.states.length)) predicate.after :=
      ⟨1, evalLocal_of_local 1 verifiedParserCore predicate.after 18 _
        (Assertion.localPointsTo_local 18 stateCountCell _ predicate.after
          predicate.invariant.stateCountOwned)⟩
    have rootResult : Evaluates verifiedParserCore predicate.after (.local 41)
        (.signed .i32 (Int.ofNat current)) predicate.after :=
      ⟨1, evalLocal_of_local 1 verifiedParserCore predicate.after 41 _
        (Assertion.localPointsTo_local 41 cursorCell _ predicate.after
          predicate.invariant.chartCursor.cursorOwned)⟩
    have zeroResult : Evaluates verifiedParserCore predicate.after
        (.value (.signed .i32 0)) (.signed .i32 0) predicate.after := ⟨1, rfl⟩
    have arguments : ArgumentsEvaluateTo verifiedParserCore predicate.after
        [.constant 0, .local 18, .local 41, .value (.signed .i32 0)]
        [.signed .i32 0,
          .signed .i32 (Int.ofNat workspace.states.length),
          .signed .i32 (Int.ofNat current), .signed .i32 0]
        predicate.after :=
      ArgumentsEvaluateTo.cons statusResult
        (ArgumentsEvaluateTo.cons countResult
          (ArgumentsEvaluateTo.cons rootResult
            (ArgumentsEvaluateTo.singleton zeroResult)))
    let resultCallee := parserParseResultCallee predicate.after 0
      (Int.ofNat workspace.states.length) (Int.ofNat current) 0
    let resultAfter := restoreLocals predicate.after resultCallee
    have resultFacts :
        Evaluates verifiedParserCore predicate.after
          (.call extractedParserParseResultFunction.id
            [.constant 0, .local 18, .local 41, .value (.signed .i32 0)])
          (parseResultValue 0 (Int.ofNat workspace.states.length)
            (Int.ofNat current) 0) resultAfter ∧
        ModifiesOnly CellSet.empty predicate.after resultAfter ∧
        StateWellFormed resultAfter := by
      simpa [resultCallee, resultAfter] using
        extractedParserParseResultCall_contract predicate.after predicate.after
          [.constant 0, .local 18, .local 41, .value (.signed .i32 0)]
          0 (Int.ofNat workspace.states.length) (Int.ofNat current) 0
          predicate.invariant.chartCursor.recognizer.wellFormed arguments
    have successExecution : Executes verifiedParserCore predicate.after
        parserRecognizeRootSuccessBranch
        (.returned (some (parseResultValue 0
          (Int.ofNat workspace.states.length) (Int.ofNat current) 0)))
        resultAfter := by
      rw [extractedParserRecognize_root_success_shape]
      exact executesSequenceReturned (executesReturnValue resultFacts.1)
    have selected : Executes verifiedParserCore
        (binding.afterProductionRead.bindLocal 42
          (.signed .i32 (Int.ofNat candidate.production)))
        (.ifThenElse parserRecognizeRootPredicate
          parserRecognizeRootSuccessBranch .skip)
        (.returned (some (parseResultValue 0
          (Int.ofNat workspace.states.length) (Int.ofNat current) 0)))
        resultAfter := executesIfTrue predicateTrue successExecution
    have innerExecution : Executes verifiedParserCore
        (binding.afterProductionRead.bindLocal 42
          (.signed .i32 (Int.ofNat candidate.production)))
        (.sequence
          (.ifThenElse parserRecognizeRootPredicate
            parserRecognizeRootSuccessBranch .skip)
          (parserRecognizeCursorAdvanceStatement 41))
        (.returned (some (parseResultValue 0
          (Int.ofNat workspace.states.length) (Int.ofNat current) 0)))
        resultAfter := executesSequenceReturned selected
    have innerEffect : ModifiesOnly CellSet.empty
        (binding.afterProductionRead.bindLocal 42
          (.signed .i32 (Int.ofNat candidate.production))) resultAfter :=
      predicate.effect.trans_same resultFacts.2.1
    let closed := binding.close_scope resultAfter
      (.returned (some (parseResultValue 0
        (Int.ofNat workspace.states.length) (Int.ofNat current) 0)))
      CellSet.empty innerExecution innerEffect resultFacts.2.2
    have candidatePosition :
        candidate.position = finalPosition tokens.length := by
      obtain ⟨cursorState, cursorFound, cursorPosition⟩ :=
        invariant.chartCursor.state_at_cursor
      rw [found] at cursorFound
      injection cursorFound with stateEqual
      subst cursorState
      rw [cursorPosition, ← invariant.chartCursor.recognizer.workspaceTokenCount]
    let materializedParse : MaterializedParse grammar tokens :=
      invariant.chartCursor.recognizer.backpointersSound.materializeStart
        invariant.chartCursor.recognizer.grammarWellFormed found productionBound
        candidateMatches.1 candidateMatches.2.1 candidateMatches.2.2
        candidatePosition
    exact {
      after := closed.after
      completion := .returned (some (parseResultValue 0
        (Int.ofNat workspace.states.length) (Int.ofNat current) 0))
      execution := closed.execution
      effect := closed.effect.weaken CellSet.empty_subset
      outcome := .accepted candidate found productionBound candidateMatches
        materializedParse closed.after closed.wellFormed
    }
  · have predicateFalse : Evaluates verifiedParserCore
        (binding.afterProductionRead.bindLocal 42
          (.signed .i32 (Int.ofNat candidate.production)))
        parserRecognizeRootPredicate (.boolean false) predicate.after := by
      simpa [candidateMatches] using predicate.evaluation
    have selected : Executes verifiedParserCore
        (binding.afterProductionRead.bindLocal 42
          (.signed .i32 (Int.ofNat candidate.production)))
        (.ifThenElse parserRecognizeRootPredicate
          parserRecognizeRootSuccessBranch .skip) .next predicate.after :=
      executesIfFalse predicateFalse (executesSkip verifiedParserCore predicate.after)
    cases remaining with
    | nil =>
        let exhausted := predicate.invariant.chartCursor.exhaust
        let finished := predicate.invariant.after_cursor_exhaustion
          exhausted.finished exhausted.effect
        have innerExecution : Executes verifiedParserCore
            (binding.afterProductionRead.bindLocal 42
              (.signed .i32 (Int.ofNat candidate.production)))
            (.sequence
              (.ifThenElse parserRecognizeRootPredicate
                parserRecognizeRootSuccessBranch .skip)
              (parserRecognizeCursorAdvanceStatement 41)) .next
            exhausted.after := executesSequence selected exhausted.execution
        have innerEffect : ModifiesOnly (CellSet.singleton cursorCell)
            (binding.afterProductionRead.bindLocal 42
              (.signed .i32 (Int.ofNat candidate.production)))
            exhausted.after :=
          (predicate.effect.weaken CellSet.empty_subset).trans_same
            exhausted.effect
        let closed := binding.close_scope exhausted.after .next
          (CellSet.singleton cursorCell) innerExecution innerEffect
          exhausted.finished.recognizer.wellFormed
        let restored := closed.restore_finished finished
        exact {
          after := closed.after
          completion := .next
          execution := closed.execution
          effect := closed.effect
          outcome := .exhausted candidate found productionBound
            candidateMatches rfl closed.after restored
        }
    | cons next tail =>
        let advanced := predicate.invariant.chartCursor.advance
        let nextInner := predicate.invariant.after_cursor_effect
          advanced.invariant advanced.effect
        have innerExecution : Executes verifiedParserCore
            (binding.afterProductionRead.bindLocal 42
              (.signed .i32 (Int.ofNat candidate.production)))
            (.sequence
              (.ifThenElse parserRecognizeRootPredicate
                parserRecognizeRootSuccessBranch .skip)
              (parserRecognizeCursorAdvanceStatement 41)) .next
            advanced.after := executesSequence selected advanced.execution
        have innerEffect : ModifiesOnly (CellSet.singleton cursorCell)
            (binding.afterProductionRead.bindLocal 42
              (.signed .i32 (Int.ofNat candidate.production)))
            advanced.after :=
          (predicate.effect.weaken CellSet.empty_subset).trans_same
            advanced.effect
        let closed := binding.close_scope advanced.after .next
          (CellSet.singleton cursorCell) innerExecution innerEffect
          advanced.invariant.recognizer.wellFormed
        let restored := closed.restore_invariant nextInner
        exact {
          after := closed.after
          completion := .next
          execution := closed.execution
          effect := closed.effect
          outcome := .advanced candidate found productionBound candidateMatches
            next tail closed.after restored rfl
        }

/-- One root-body iteration whose FunctionalView and structural-Core
    executions are constructed from the same candidate decision. -/
private inductive RecognizerRootStepSynchronizedExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerRootLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before current remaining) : Type
  where
  | accepted (candidate : EarleyState)
      (found : workspace.state? current = some candidate)
      (productionBound : candidate.production < grammar.productionCount)
      (candidateMatches : RootCandidateMatches grammar candidate
        productionBound)
      (materializedParse : MaterializedParse grammar tokens)
      (physicalAfter : State) (wellFormed : StateWellFormed physicalAfter)
      (functionalExecution :
        Lanius.FunctionalView.Stateful.Command.Evaluates
          (rootTermMachine workspaceLayout grammar words grammarCell)
          (rootStatefulMachine workspaceLayout grammar words grammarCell)
          (stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell)
          (rootEnvironment words workspaceValues grammarCell workspaceCell
            workspaceLayout grammar workspace.states.length
            beforeInvariant.furthestPosition (Int.ofNat current))
          rootBodyCommand
          (.returned (some (parseResultValue 0
            (Int.ofNat workspace.states.length) (Int.ofNat current) 0)))
          (stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell)
          (rootEnvironment words workspaceValues grammarCell workspaceCell
            workspaceLayout grammar workspace.states.length
            beforeInvariant.furthestPosition (Int.ofNat current)))
      (physicalExecution : Executes verifiedParserCore before
        parserRecognizeRootLoopBody
        (.returned (some (parseResultValue 0
          (Int.ofNat workspace.states.length) (Int.ofNat current) 0)))
        physicalAfter)
      (effect : ModifiesOnly (CellSet.singleton cursorCell) before
        physicalAfter) :
      RecognizerRootStepSynchronizedExecution grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before current remaining
        beforeInvariant
  | advanced (candidate : EarleyState)
      (found : workspace.state? current = some candidate)
      (productionBound : candidate.production < grammar.productionCount)
      (candidateDoesNotMatch : ¬ RootCandidateMatches grammar candidate
        productionBound)
      (next : Nat) (nextRemaining : List Nat) (physicalAfter : State)
      (invariant : RecognizerRootLoopInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell physicalAfter next
        nextRemaining)
      (furthestEq : invariant.furthestPosition =
        beforeInvariant.furthestPosition)
      (suffix : next :: nextRemaining = remaining)
      (functionalExecution :
        Lanius.FunctionalView.Stateful.Command.Evaluates
          (rootTermMachine workspaceLayout grammar words grammarCell)
          (rootStatefulMachine workspaceLayout grammar words grammarCell)
          (stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell)
          (rootEnvironment words workspaceValues grammarCell workspaceCell
            workspaceLayout grammar workspace.states.length
            beforeInvariant.furthestPosition (Int.ofNat current))
          rootBodyCommand .next
          (stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell)
          (rootEnvironment words workspaceValues grammarCell workspaceCell
            workspaceLayout grammar workspace.states.length
            beforeInvariant.furthestPosition
            (encodeStateId remaining.head?)))
      (physicalExecution : Executes verifiedParserCore before
        parserRecognizeRootLoopBody .next physicalAfter)
      (effect : ModifiesOnly (CellSet.singleton cursorCell) before
        physicalAfter) :
      RecognizerRootStepSynchronizedExecution grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before current remaining
        beforeInvariant
  | exhausted (candidate : EarleyState)
      (found : workspace.state? current = some candidate)
      (productionBound : candidate.production < grammar.productionCount)
      (candidateDoesNotMatch : ¬ RootCandidateMatches grammar candidate
        productionBound)
      (empty : remaining = []) (physicalAfter : State)
      (invariant : RecognizerRootFinishedInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell physicalAfter)
      (furthestEq : invariant.furthestPosition =
        beforeInvariant.furthestPosition)
      (functionalExecution :
        Lanius.FunctionalView.Stateful.Command.Evaluates
          (rootTermMachine workspaceLayout grammar words grammarCell)
          (rootStatefulMachine workspaceLayout grammar words grammarCell)
          (stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell)
          (rootEnvironment words workspaceValues grammarCell workspaceCell
            workspaceLayout grammar workspace.states.length
            beforeInvariant.furthestPosition (Int.ofNat current))
          rootBodyCommand .next
          (stateWorld words tokens workspaceValues grammarCell tokensCell
            workspaceCell)
          (rootEnvironment words workspaceValues grammarCell workspaceCell
            workspaceLayout grammar workspace.states.length
            beforeInvariant.furthestPosition (-1)))
      (physicalExecution : Executes verifiedParserCore before
        parserRecognizeRootLoopBody .next physicalAfter)
      (effect : ModifiesOnly (CellSet.singleton cursorCell) before
        physicalAfter) :
      RecognizerRootStepSynchronizedExecution grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell before current remaining
        beforeInvariant

private noncomputable def
    RecognizerRootLoopInvariant.execute_step_synchronized
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining) :
    RecognizerRootStepSynchronizedExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining
      invariant := by
  let physical := invariant.execute_step_structural
  obtain ⟨physicalAfter, completion, physicalExecution, effect, outcome⟩ :=
    physical
  cases outcome with
  | accepted candidate found productionBound candidateMatches materializedParse
      _ wellFormed =>
      exact .accepted candidate found productionBound candidateMatches
        materializedParse physicalAfter wellFormed
        (invariant.functional_accept_body candidate found productionBound
          candidateMatches)
        physicalExecution effect
  | advanced candidate found productionBound candidateDoesNotMatch next
      nextRemaining _ nextInvariant suffix =>
      have preserved : physicalAfter.local? 22 = some (.signed .i32
          (Int.ofNat invariant.furthestPosition)) :=
        effect.preserves_local_of_disjoint
          invariant.chartCursor.recognizer.wellFormed
          invariant.cursorFrameDisjoint
          ((RootLoopFramedLocal_source_frame 22).mp (by
            simp [RootLoopFramedLocal])) invariant.furthestPositionLocal
      have furthestEq : nextInvariant.furthestPosition =
          invariant.furthestPosition := by
        rw [nextInvariant.furthestPositionLocal] at preserved
        injection preserved with valueEq
        injection valueEq with _ intEq
        exact Int.ofNat.inj intEq
      exact .advanced candidate found productionBound candidateDoesNotMatch
        next nextRemaining physicalAfter nextInvariant furthestEq suffix
        (invariant.functional_advance_body candidate found productionBound
          candidateDoesNotMatch)
        physicalExecution effect
  | exhausted candidate found productionBound candidateDoesNotMatch empty _
      finished =>
      have preserved : physicalAfter.local? 22 = some (.signed .i32
          (Int.ofNat invariant.furthestPosition)) :=
        effect.preserves_local_of_disjoint
          invariant.chartCursor.recognizer.wellFormed
          invariant.cursorFrameDisjoint
          ((RootLoopFramedLocal_source_frame 22).mp (by
            simp [RootLoopFramedLocal])) invariant.furthestPositionLocal
      have furthestEq : finished.furthestPosition =
          invariant.furthestPosition := by
        rw [finished.furthestPositionLocal] at preserved
        injection preserved with valueEq
        injection valueEq with _ intEq
        exact Int.ofNat.inj intEq
      have functional := invariant.functional_advance_body candidate found
        productionBound candidateDoesNotMatch
      have functional' :
          Lanius.FunctionalView.Stateful.Command.Evaluates
            (rootTermMachine workspaceLayout grammar words grammarCell)
            (rootStatefulMachine workspaceLayout grammar words grammarCell)
            (stateWorld words tokens workspaceValues grammarCell tokensCell
              workspaceCell)
            (rootEnvironment words workspaceValues grammarCell workspaceCell
              workspaceLayout grammar workspace.states.length
              invariant.furthestPosition (Int.ofNat current))
            rootBodyCommand .next
            (stateWorld words tokens workspaceValues grammarCell tokensCell
              workspaceCell)
            (rootEnvironment words workspaceValues grammarCell workspaceCell
              workspaceLayout grammar workspace.states.length
              invariant.furthestPosition (-1)) := by
        simpa [empty, encodeStateId] using functional
      exact .exhausted candidate found productionBound candidateDoesNotMatch
        empty physicalAfter finished furthestEq functional' physicalExecution
        effect

private def RecognizerRootStepSynchronizedExecution.physical
    (execution : RecognizerRootStepSynchronizedExecution grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before current
      remaining beforeInvariant) :
    RecognizerRootStepExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before current remaining
      beforeInvariant := by
  cases execution with
  | accepted candidate found productionBound candidateMatches materializedParse
      physicalAfter wellFormed _ physicalExecution effect =>
      exact {
        after := physicalAfter
        completion := .returned (some (parseResultValue 0
          (Int.ofNat workspace.states.length) (Int.ofNat current) 0))
        execution := physicalExecution
        effect := effect
        outcome := .accepted candidate found productionBound candidateMatches
          materializedParse physicalAfter wellFormed
      }
  | advanced candidate found productionBound candidateDoesNotMatch next
      nextRemaining physicalAfter invariant _ suffix _ physicalExecution
      effect =>
      exact {
        after := physicalAfter
        completion := .next
        execution := physicalExecution
        effect := effect
        outcome := .advanced candidate found productionBound
          candidateDoesNotMatch next nextRemaining physicalAfter invariant
          suffix
      }
  | exhausted candidate found productionBound candidateDoesNotMatch empty
      physicalAfter invariant _ _ physicalExecution effect =>
      exact {
        after := physicalAfter
        completion := .next
        execution := physicalExecution
        effect := effect
        outcome := .exhausted candidate found productionBound
          candidateDoesNotMatch empty physicalAfter invariant
      }

/-- Execute one root candidate with FunctionalView as the semantic owner;
    structural Core is exposed only as refinement evidence. -/
noncomputable def RecognizerRootLoopInvariant.execute_step
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining) :
    RecognizerRootStepExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining
      invariant :=
  invariant.execute_step_synchronized.physical

/-- Algorithmic state for final-chart root search. -/
structure RecognizerRootConfig
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    where
  runtime : State
  cursor :
    (Sigma fun current : Nat => Sigma fun remaining : List Nat =>
      RecognizerRootLoopInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell runtime current remaining)
    ⊕ RecognizerRootFinishedInvariant grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell runtime

def RecognizerRootConfig.measure
    (config : RecognizerRootConfig grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell) : Nat :=
  match config.cursor with
  | .inl active => active.2.1.length + 1
  | .inr _ => 0

private def RecognizerRootConfig.currentCandidate
    (config : RecognizerRootConfig grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell) : Int :=
  match config.cursor with
  | .inl active => Int.ofNat active.1
  | .inr _ => -1

private def RecognizerRootConfig.currentFurthest
    (config : RecognizerRootConfig grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell) : Nat :=
  match config.cursor with
  | .inl active => active.2.2.furthestPosition
  | .inr finished => finished.furthestPosition

private noncomputable def RecognizerRootConfig.functionalRuntime
    (config : RecognizerRootConfig grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell) :
    Lanius.FunctionalView.Stateful.Loop.Runtime
      (rootTermMachine workspaceLayout grammar words grammarCell) 7 :=
  (stateWorld words tokens workspaceValues grammarCell tokensCell workspaceCell,
    rootEnvironment words workspaceValues grammarCell workspaceCell
      workspaceLayout grammar workspace.states.length config.currentFurthest
      config.currentCandidate)

/-- The functional root-loop configuration selected by the artifact-derived
    root entry. -/
private def RecognizerRootEntry.functionalConfig
    (entry : RecognizerRootEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source furthest
      sourceInvariant) :
    RecognizerRootConfig grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      stateCountCell entry.chartEntry.cursorCell := {
  runtime := entry.chartEntry.bound
  cursor := entry.cursor
}

private theorem RecognizerRootEntry.functionalConfig_candidate
    (entry : RecognizerRootEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source furthest
      sourceInvariant) :
    entry.functionalConfig.currentCandidate =
      chartHeadValue workspace (finalPosition workspaceLayout.tokenCount) := by
  have chartLocal : entry.chartEntry.bound.local? 41 =
      some (.signed .i32
        (chartHeadValue workspace (finalPosition workspaceLayout.tokenCount))) := by
    rw [entry.chartEntry.boundEq]
    exact bindLocal_finds_local entry.chartEntry.headRead.after 41
      (.signed .i32
        (chartHeadValue workspace (finalPosition workspaceLayout.tokenCount)))
      entry.chartEntry.headRead.invariant.wellFormed
  cases cursorEq : entry.cursor with
  | inl active =>
      obtain ⟨current, remaining, invariant⟩ := active
      have currentLocal : entry.chartEntry.bound.local? 41 =
          some (.signed .i32 (Int.ofNat current)) :=
        Assertion.localPointsTo_local 41 entry.chartEntry.cursorCell _
          entry.chartEntry.bound invariant.chartCursor.cursorOwned
      have valueEq : Int.ofNat current =
          chartHeadValue workspace
            (finalPosition workspaceLayout.tokenCount) := by
        have equal := Option.some.inj (currentLocal.symm.trans chartLocal)
        injection equal
      simpa [RecognizerRootEntry.functionalConfig,
        RecognizerRootConfig.currentCandidate, cursorEq] using valueEq
  | inr finished =>
      have currentLocal : entry.chartEntry.bound.local? 41 =
          some (.signed .i32 (-1)) :=
        Assertion.localPointsTo_local 41 entry.chartEntry.cursorCell _
          entry.chartEntry.bound finished.chartCursor.cursorOwned
      have valueEq : (-1 : Int) =
          chartHeadValue workspace
            (finalPosition workspaceLayout.tokenCount) := by
        have equal := Option.some.inj (currentLocal.symm.trans chartLocal)
        injection equal
      simpa [RecognizerRootEntry.functionalConfig,
        RecognizerRootConfig.currentCandidate, cursorEq] using valueEq

private theorem RecognizerRootEntry.functionalConfig_furthest
    (entry : RecognizerRootEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source furthest
      sourceInvariant) :
    entry.functionalConfig.currentFurthest = furthest := by
  have sourceLocal : source.local? 22 =
      some (.signed .i32 (Int.ofNat furthest)) :=
    Assertion.localPointsTo_local 22 furthestCell _ source
      sourceInvariant.frame.furthestOwned
  have afterReadLocal : entry.chartEntry.headRead.after.local? 22 =
      some (.signed .i32 (Int.ofNat furthest)) :=
    entry.chartEntry.headRead.effect.empty_preserves_local
      sourceInvariant.frame.appendFrame.recognizer.wellFormed sourceLocal
  have boundLocal : entry.chartEntry.bound.local? 22 =
      some (.signed .i32 (Int.ofNat furthest)) := by
    rw [entry.chartEntry.boundEq]
    exact (bindLocal_preserves_other_local
      entry.chartEntry.headRead.invariant.wellFormed (by decide)).trans
      afterReadLocal
  cases cursorEq : entry.cursor with
  | inl active =>
      obtain ⟨current, remaining, invariant⟩ := active
      have equal := invariant.furthestPositionLocal.symm.trans boundLocal
      have valueEq : invariant.furthestPosition = furthest := by
        injection equal with signedEq
        injection signedEq with _ intEq
        exact Int.ofNat.inj intEq
      simpa [RecognizerRootEntry.functionalConfig,
        RecognizerRootConfig.currentFurthest, cursorEq] using valueEq
  | inr finished =>
      have equal := finished.furthestPositionLocal.symm.trans boundLocal
      have valueEq : finished.furthestPosition = furthest := by
        injection equal with signedEq
        injection signedEq with _ intEq
        exact Int.ofNat.inj intEq
      simpa [RecognizerRootEntry.functionalConfig,
        RecognizerRootConfig.currentFurthest, cursorEq] using valueEq

private theorem RecognizerRootEntry.functional_environment_extends
    (entry : RecognizerRootEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source furthest
      sourceInvariant) :
    Lanius.FunctionalView.Env.Extends rootIntoStatementEmbedding
      entry.functionalConfig.functionalRuntime.environment
      ((rootStatementEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar workspace.states.length furthest).push
        (.signed .i32 (chartHeadValue workspace
          (finalPosition workspaceLayout.tokenCount)))) := by
  have candidateEq := entry.functionalConfig_candidate
  have furthestEq := entry.functionalConfig_furthest
  change Lanius.FunctionalView.Env.Extends rootIntoStatementEmbedding
    (rootEnvironment words workspaceValues grammarCell workspaceCell
      workspaceLayout grammar workspace.states.length
      entry.functionalConfig.currentFurthest
      entry.functionalConfig.currentCandidate)
    ((rootStatementEnvironment words workspaceValues grammarCell workspaceCell
      workspaceLayout grammar workspace.states.length furthest).push
      (.signed .i32 (chartHeadValue workspace
        (finalPosition workspaceLayout.tokenCount))))
  rw [candidateEq, furthestEq]
  exact rootEnvironment_extends_rootStatementEnvironment words workspaceValues
    grammarCell workspaceCell workspaceLayout grammar workspace.states.length
    furthest
    (chartHeadValue workspace (finalPosition workspaceLayout.tokenCount))

private theorem rootLoopCondition_evaluates
    (workspaceLayout : WorkspaceLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (environment : Lanius.FunctionalView.Env 7) (candidate : Int)
    (candidateEq : environment ⟨6, by omega⟩ =
      .signed .i32 candidate) :
    Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell) world
      environment rootLoopCondition =
      .ok (.boolean (decide (candidate ≥ 0)), world) := by
  have candidateResult : Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell) world
      environment (stateSlot ⟨6, by omega⟩) =
      .ok (.signed .i32 candidate, world) :=
    Lanius.FunctionalView.Term.evaluate_slot candidateEq
  have zeroResult : Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell) world
      environment (stateLiteral 0) =
      .ok (.signed .i32 0, world) := by rfl
  apply Lanius.FunctionalView.Term.evaluate_apply2 candidateResult zeroResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedParserCore world
      (.binary .greaterEqual parserI32Type parserI32Type (.scalar .bool))
      [.signed .i32 candidate, .signed .i32 0] = _
  exact
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_greaterEqual_int
      candidate 0

private theorem RecognizerRootConfig.functional_condition
    (config : RecognizerRootConfig grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell) :
    Lanius.FunctionalView.Term.evaluate
      (rootTermMachine workspaceLayout grammar words grammarCell)
      config.functionalRuntime.world config.functionalRuntime.environment
      rootLoopCondition =
      .ok (.boolean (decide (config.currentCandidate ≥ 0)),
        config.functionalRuntime.world) := by
  apply rootLoopCondition_evaluates workspaceLayout grammar words grammarCell
  rfl

/-! The final root loop carries one FunctionalView runtime and one matching
structural Core state through every edge. -/

private inductive RecognizerRootSynchronizedOutcome
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (functionalAfter : Lanius.FunctionalView.Stateful.Loop.Runtime
      (rootTermMachine workspaceLayout grammar words grammarCell) 7) :
    State → Lanius.FunctionalView.Stateful.Completion → Type where
  | accepted (rootState : Nat) (candidate : EarleyState)
      (found : workspace.state? rootState = some candidate)
      (productionBound : candidate.production < grammar.productionCount)
      (candidateMatches : RootCandidateMatches grammar candidate
        productionBound)
      (materializedParse : MaterializedParse grammar tokens)
      (physicalAfter : State) (wellFormed : StateWellFormed physicalAfter) :
      RecognizerRootSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell functionalAfter physicalAfter
        (.returned (some (parseResultValue 0
          (Int.ofNat workspace.states.length) (Int.ofNat rootState) 0)))
  | exhausted (physicalAfter : State)
      (invariant : RecognizerRootFinishedInvariant grammarLayout grammar words
        tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell physicalAfter)
      (worldEq : functionalAfter.world =
        stateWorld words tokens workspaceValues grammarCell tokensCell
          workspaceCell)
      (environmentEq : functionalAfter.environment =
        rootEnvironment words workspaceValues grammarCell workspaceCell
          workspaceLayout grammar workspace.states.length
          invariant.furthestPosition (-1)) :
      RecognizerRootSynchronizedOutcome grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell functionalAfter physicalAfter
        .next

private def RecognizerRootSynchronizedOutcome.physical
    (outcome : RecognizerRootSynchronizedOutcome grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell functionalAfter physicalAfter
      completion) :
    RecognizerRootLoopOutcome grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      stateCountCell cursorCell physicalAfter
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion) := by
  cases outcome with
  | accepted rootState candidate found productionBound candidateMatches
      materializedParse physicalAfter wellFormed =>
      exact .accepted rootState candidate found productionBound candidateMatches
        materializedParse physicalAfter wellFormed
  | exhausted physicalAfter invariant _ _ =>
      exact .exhausted physicalAfter invariant

private structure RecognizerRootFunctionalResult
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (config : RecognizerRootConfig grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (functionalAfter : Lanius.FunctionalView.Stateful.Loop.Runtime
      (rootTermMachine workspaceLayout grammar words grammarCell) 7) where
  physicalAfter : State
  execution : Executes verifiedParserCore config.runtime parserRecognizeRootLoop
    (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion)
    physicalAfter
  effect : ModifiesOnly (CellSet.singleton cursorCell) config.runtime
    physicalAfter
  outcome : RecognizerRootSynchronizedOutcome grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell functionalAfter physicalAfter
    completion

/-- One root-loop decision shared by the mechanically reified FunctionalView
    command and the exact extracted Core loop. -/
private noncomputable def RecognizerRootConfig.functional_decide
    (config : RecognizerRootConfig grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell) :
    Lanius.FunctionalView.Stateful.Loop.Decision
      (rootTermMachine workspaceLayout grammar words grammarCell)
      (rootStatefulMachine workspaceLayout grammar words grammarCell)
      rootLoopCondition rootBodyCommand
      (RecognizerRootConfig grammarLayout grammar words tokens workspaceLayout
        workspace workspaceValues grammarCell tokensCell workspaceCell
        stateCountCell cursorCell)
      RecognizerRootConfig.functionalRuntime RecognizerRootConfig.measure
      (RecognizerRootFunctionalResult grammarLayout grammar words tokens
        workspaceLayout workspace workspaceValues grammarCell tokensCell
        workspaceCell stateCountCell cursorCell) config := by
  cases cursorShape : config.cursor with
  | inr finished =>
      have functionalFalse : Lanius.FunctionalView.Term.evaluate
          (rootTermMachine workspaceLayout grammar words grammarCell)
          config.functionalRuntime.world config.functionalRuntime.environment
          rootLoopCondition =
          .ok (.boolean false, config.functionalRuntime.world) := by
        simpa [RecognizerRootConfig.currentCandidate, cursorShape] using
          config.functional_condition
      apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
      exact {
        completion := .next
        after := config.functionalRuntime
        edge := .conditionFalse functionalFalse
        result := {
          physicalAfter := config.runtime
          execution := by
            rw [extractedParserRecognize_root_loop_shape]
            exact executesWhileFalse finished.chartCursor.condition_negative
          effect := ModifiesOnly.reflAny (CellSet.singleton cursorCell)
            config.runtime
          outcome := by
            apply RecognizerRootSynchronizedOutcome.exhausted config.runtime
              finished
            · rfl
            · change rootEnvironment words workspaceValues grammarCell
                  workspaceCell workspaceLayout grammar workspace.states.length
                  config.currentFurthest config.currentCandidate = _
              rw [show config.currentFurthest = finished.furthestPosition by
                    simp [RecognizerRootConfig.currentFurthest, cursorShape],
                show config.currentCandidate = -1 by
                    simp [RecognizerRootConfig.currentCandidate, cursorShape]]
        }
      }
  | inl active =>
      obtain ⟨current, remaining, invariant⟩ := active
      let step := invariant.execute_step_synchronized
      have configRuntimeEq : config.functionalRuntime =
          (stateWorld words tokens workspaceValues grammarCell tokensCell
              workspaceCell,
            rootEnvironment words workspaceValues grammarCell workspaceCell
              workspaceLayout grammar workspace.states.length
              invariant.furthestPosition (Int.ofNat current)) := by
        unfold RecognizerRootConfig.functionalRuntime
        rw [show config.currentFurthest = invariant.furthestPosition by
              simp [RecognizerRootConfig.currentFurthest, cursorShape],
          show config.currentCandidate = Int.ofNat current by
              simp [RecognizerRootConfig.currentCandidate, cursorShape]]
        rfl
      have functionalTrue : Lanius.FunctionalView.Term.evaluate
          (rootTermMachine workspaceLayout grammar words grammarCell)
          config.functionalRuntime.world config.functionalRuntime.environment
          rootLoopCondition =
          .ok (.boolean true, config.functionalRuntime.world) := by
        simpa [RecognizerRootConfig.currentCandidate, cursorShape] using
          config.functional_condition
      have physicalTrue := invariant.chartCursor.condition_nonnegative
      cases step with
      | accepted candidate found productionBound candidateMatches
          materializedParse physicalAfter wellFormed functionalBody physicalBody
          stepEffect =>
          apply Lanius.FunctionalView.Stateful.Loop.Decision.exit
          exact {
            completion := .returned (some (parseResultValue 0
              (Int.ofNat workspace.states.length) (Int.ofNat current) 0))
            after := config.functionalRuntime
            edge := .returned functionalTrue (by
              simpa only [configRuntimeEq,
                Lanius.FunctionalView.Stateful.Loop.Runtime.world,
                Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                  functionalBody)
            result := {
              physicalAfter := physicalAfter
              execution := by
                rw [extractedParserRecognize_root_loop_shape]
                exact executesWhileReturned physicalTrue physicalBody
              effect := stepEffect
              outcome := .accepted current candidate found productionBound
                candidateMatches materializedParse physicalAfter wellFormed
            }
          }
      | advanced candidate found productionBound candidateDoesNotMatch next
          nextRemaining physicalAfter nextInvariant furthestEq suffix
          functionalBody physicalBody stepEffect =>
          let nextConfig : RecognizerRootConfig grammarLayout grammar words
              tokens workspaceLayout workspace workspaceValues grammarCell
              tokensCell workspaceCell stateCountCell cursorCell := {
            runtime := physicalAfter
            cursor := .inl ⟨next, nextRemaining, nextInvariant⟩
          }
          have headEq : encodeStateId remaining.head? = Int.ofNat next := by
            rw [← suffix]
            rfl
          have nextRuntimeEq : nextConfig.functionalRuntime =
              (stateWorld words tokens workspaceValues grammarCell tokensCell
                  workspaceCell,
                rootEnvironment words workspaceValues grammarCell workspaceCell
                  workspaceLayout grammar workspace.states.length
                  invariant.furthestPosition (encodeStateId remaining.head?)) := by
            unfold RecognizerRootConfig.functionalRuntime
            change (stateWorld words tokens workspaceValues grammarCell
                tokensCell workspaceCell,
              rootEnvironment words workspaceValues grammarCell workspaceCell
                workspaceLayout grammar workspace.states.length
                nextInvariant.furthestPosition (Int.ofNat next)) = _
            rw [furthestEq, headEq]
          apply Lanius.FunctionalView.Stateful.Loop.Decision.next nextConfig
          · apply Lanius.FunctionalView.Stateful.Loop.Iteration.next
              functionalTrue
            simpa only [configRuntimeEq, nextRuntimeEq,
              Lanius.FunctionalView.Stateful.Loop.Runtime.world,
              Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                functionalBody
          · simp only [WellFoundedRelation.rel, RecognizerRootConfig.measure,
              nextConfig]
            have decreases : nextRemaining.length + 1 < remaining.length + 1 := by
              rw [← suffix]
              simp
            show sizeOf (nextRemaining.length + 1) < sizeOf
              (match config.cursor with
              | .inl active => active.2.1.length + 1
              | .inr _ => 0)
            simpa [cursorShape] using decreases
          · intro completion after result
            exact {
              physicalAfter := result.physicalAfter
              execution := by
                rw [extractedParserRecognize_root_loop_shape]
                exact executesWhileTrueThen physicalTrue physicalBody
                  result.execution
              effect := stepEffect.trans_same result.effect
              outcome := result.outcome
            }
      | exhausted candidate found productionBound candidateDoesNotMatch empty
          physicalAfter finished furthestEq functionalBody physicalBody
          stepEffect =>
          let nextConfig : RecognizerRootConfig grammarLayout grammar words
              tokens workspaceLayout workspace workspaceValues grammarCell
              tokensCell workspaceCell stateCountCell cursorCell := {
            runtime := physicalAfter
            cursor := .inr finished
          }
          have nextRuntimeEq : nextConfig.functionalRuntime =
              (stateWorld words tokens workspaceValues grammarCell tokensCell
                  workspaceCell,
                rootEnvironment words workspaceValues grammarCell workspaceCell
                  workspaceLayout grammar workspace.states.length
                  invariant.furthestPosition (-1)) := by
            unfold RecognizerRootConfig.functionalRuntime
            change (stateWorld words tokens workspaceValues grammarCell
                tokensCell workspaceCell,
              rootEnvironment words workspaceValues grammarCell workspaceCell
                workspaceLayout grammar workspace.states.length
                finished.furthestPosition (-1)) = _
            rw [furthestEq]
          apply Lanius.FunctionalView.Stateful.Loop.Decision.next nextConfig
          · apply Lanius.FunctionalView.Stateful.Loop.Iteration.next
              functionalTrue
            simpa only [configRuntimeEq, nextRuntimeEq,
              Lanius.FunctionalView.Stateful.Loop.Runtime.world,
              Lanius.FunctionalView.Stateful.Loop.Runtime.environment] using
                functionalBody
          · simp only [WellFoundedRelation.rel, RecognizerRootConfig.measure,
              nextConfig]
            show sizeOf 0 < sizeOf
              (match config.cursor with
              | .inl active => active.2.1.length + 1
              | .inr _ => 0)
            simpa [cursorShape] using Nat.zero_lt_succ remaining.length
          · intro completion after result
            exact {
              physicalAfter := result.physicalAfter
              execution := by
                rw [extractedParserRecognize_root_loop_shape]
                exact executesWhileTrueThen physicalTrue physicalBody
                  result.execution
              effect := stepEffect.trans_same result.effect
              outcome := result.outcome
            }

private noncomputable def RecognizerRootConfig.functional_run
    (config : RecognizerRootConfig grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell) :=
  Lanius.FunctionalView.Stateful.Loop.run
    (rootTermMachine workspaceLayout grammar words grammarCell)
    (rootStatefulMachine workspaceLayout grammar words grammarCell)
    rootLoopCondition rootBodyCommand
    (RecognizerRootConfig grammarLayout grammar words tokens workspaceLayout
      workspace workspaceValues grammarCell tokensCell workspaceCell
      stateCountCell cursorCell)
    RecognizerRootConfig.functionalRuntime RecognizerRootConfig.measure
    (RecognizerRootFunctionalResult grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell)
    RecognizerRootConfig.functional_decide config

/-- Execute the total compact root loop under the full recognizer call model
    and in the bound environment of the complete root statement. -/
private noncomputable def RecognizerRootEntry.functional_execute_loop
    (entry : RecognizerRootEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source furthest
      sourceInvariant) :
    Lanius.FunctionalView.Stateful.Command.RenameResult
      (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      Lanius.FunctionalView.Core.Stateful.actionRenamer
      rootIntoStatementEmbedding entry.functionalConfig.functionalRuntime.world
      ((rootStatementEnvironment words workspaceValues grammarCell workspaceCell
        workspaceLayout grammar workspace.states.length furthest).push
        (.signed .i32 (chartHeadValue workspace
          (finalPosition workspaceLayout.tokenCount))))
      rootLoopCommand entry.functionalConfig.functional_run.completion
      entry.functionalConfig.functional_run.after.world
      entry.functionalConfig.functional_run.after.environment :=
  rootExecution_in_state_environment rootLoop_calls_supported_in_state
    entry.functionalConfig.functional_run.trace.evaluates _
    entry.functional_environment_extends

structure RecognizerRootLoopExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State) (current : Nat) (remaining : List Nat)
    (beforeInvariant : RecognizerRootLoopInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before current remaining) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before parserRecognizeRootLoop
    completion after
  effect : ModifiesOnly (CellSet.singleton cursorCell) before after
  outcome : RecognizerRootLoopOutcome grammarLayout grammar words tokens
    workspaceLayout workspace workspaceValues grammarCell tokensCell
    workspaceCell stateCountCell cursorCell after completion

/-- Total execution of the exact extracted root-selection loop. FunctionalView
    owns the loop trace; structural Core is its refinement result. -/
noncomputable def RecognizerRootLoopInvariant.execute_loop
    (invariant : RecognizerRootLoopInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining) :
    RecognizerRootLoopExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell runtime current remaining
      invariant := by
  let initial : RecognizerRootConfig grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell := {
    runtime := runtime
    cursor := .inl ⟨current, remaining, invariant⟩
  }
  let assembled := initial.functional_run
  exact {
    after := assembled.result.physicalAfter
    completion := Lanius.FunctionalView.Core.Stateful.toCoreCompletion
      assembled.completion
    execution := by simpa [initial] using assembled.result.execution
    effect := by simpa [initial] using assembled.result.effect
    outcome := by simpa [initial] using assembled.result.outcome.physical
  }

theorem verifiedParserRecognize_parse_rejected_constant :
    verifiedParserCore.constant? 1 = some {
      id := 1
      type := parserI32Type
      value := .signed .i32 1
    } := by
  rfl

structure RecognizerRejectedExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell cursorCell : CellId)
    (before : State)
    (beforeInvariant : RecognizerRootFinishedInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell cursorCell before) where
  after : State
  execution : Executes verifiedParserCore before parserRecognizeRejectedReturn
    (.returned (some (parseResultValue 1
      (Int.ofNat workspace.states.length) (-1)
      (Int.ofNat beforeInvariant.furthestPosition)))) after
  effect : ModifiesOnly CellSet.empty before after
  wellFormed : StateWellFormed after

/-- Execute the exact rejected `parse_result` return after root-cursor
    exhaustion. -/
noncomputable def RecognizerRootFinishedInvariant.execute_rejected
    (invariant : RecognizerRootFinishedInvariant grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before) :
    RecognizerRejectedExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell cursorCell before invariant := by
  have statusResult : Evaluates verifiedParserCore before (.constant 1)
      (.signed .i32 1) before :=
    evaluatesConstant verifiedParserRecognize_parse_rejected_constant
  have countResult : Evaluates verifiedParserCore before (.local 18)
      (.signed .i32 (Int.ofNat workspace.states.length)) before :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore before 18 _
      (Assertion.localPointsTo_local 18 stateCountCell _ before
        invariant.stateCountOwned)⟩
  have negativeOne : Evaluates verifiedParserCore before
      (.unary .negate (.value (.signed .i32 1)))
      (.signed .i32 (-1)) before :=
    evaluatesParserAppendNegativeOne before
  have furthestResult : Evaluates verifiedParserCore before (.local 22)
      (.signed .i32 (Int.ofNat invariant.furthestPosition)) before :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore before 22 _
      invariant.furthestPositionLocal⟩
  have arguments : ArgumentsEvaluateTo verifiedParserCore before [
      .constant 1, .local 18,
      .unary .negate (.value (.signed .i32 1)), .local 22] [
      .signed .i32 1,
      .signed .i32 (Int.ofNat workspace.states.length),
      .signed .i32 (-1),
      .signed .i32 (Int.ofNat invariant.furthestPosition)] before :=
    ArgumentsEvaluateTo.cons statusResult
      (ArgumentsEvaluateTo.cons countResult
        (ArgumentsEvaluateTo.cons negativeOne
          (ArgumentsEvaluateTo.singleton furthestResult)))
  let callee := parserParseResultCallee before 1
    (Int.ofNat workspace.states.length) (-1)
    (Int.ofNat invariant.furthestPosition)
  let after := restoreLocals before callee
  have result := extractedParserParseResultCall_contract before before [
    .constant 1, .local 18,
    .unary .negate (.value (.signed .i32 1)), .local 22]
    1 (Int.ofNat workspace.states.length) (-1)
    (Int.ofNat invariant.furthestPosition)
    invariant.chartCursor.recognizer.wellFormed arguments
  exact {
    after := after
    execution := by
      rw [extractedParserRecognize_rejected_return_shape]
      exact executesSequenceReturned (executesReturnValue result.1)
    effect := by simpa [callee, after] using result.2.1
    wellFormed := result.2.2
  }

inductive RecognizerRootStatementOutcome
    (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) :
    Completion → Type
  | accepted (rootState : Nat) (candidate : EarleyState)
      (found : workspace.state? rootState = some candidate)
      (productionBound : candidate.production < grammar.productionCount)
      (candidateMatches : RootCandidateMatches grammar candidate productionBound)
      (materializedParse : MaterializedParse grammar tokens) :
      RecognizerRootStatementOutcome grammar tokens workspace
        (.returned (some (parseResultValue 0
          (Int.ofNat workspace.states.length) (Int.ofNat rootState) 0)))
  | rejected (furthest : Nat) :
      RecognizerRootStatementOutcome grammar tokens workspace
        (.returned (some (parseResultValue 1
          (Int.ofNat workspace.states.length) (-1) (Int.ofNat furthest))))

/-- Functional execution of the complete, mechanically reified root
    statement.  Both outcomes are terminal, so the returned value is exposed
    directly while the proof retains the exact post-world and scoped
    post-environment. -/
structure RecognizerRootStatementFunctionalExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (source : State) (furthest : Nat)
    (sourceInvariant : RecognizerPositionFinishedInvariant grammarLayout
      grammar words tokens workspaceLayout workspace workspaceValues
      grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell source furthest)
    (entry : RecognizerRootEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source furthest
      sourceInvariant) where
  resultValue : Value
  afterWorld : Lanius.FunctionalView.Core.ReadOnly.World
  afterEnvironment : Lanius.FunctionalView.Env 7
  execution : Lanius.FunctionalView.Stateful.Command.Evaluates
    (stateTermMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
      tokensCell)
    (stateWorld words tokens workspaceValues grammarCell tokensCell workspaceCell)
    (rootStatementEnvironment words workspaceValues grammarCell workspaceCell
      workspaceLayout grammar workspace.states.length furthest)
    rootStatementCommand (.returned (some resultValue)) afterWorld
    afterEnvironment
  physicalAfter : State
  physicalExecution : Executes verifiedParserCore source
    parserRecognizeRootStatement (.returned (some resultValue)) physicalAfter
  physicalEffect : ModifiesOnly CellSet.empty source physicalAfter
  physicalWellFormed : StateWellFormed physicalAfter
  outcome : RecognizerRootStatementOutcome grammar tokens workspace
    (.returned (some resultValue))

/-- Execute root-head initialization, total root search, and the rejected
    fallback as one FunctionalView statement.  The loop and fallback are
    transported through the generic call-model and environment refinements;
    no physical trace is replayed to decide the functional result. -/
noncomputable def RecognizerRootEntry.functional_execute_statement
    (entry : RecognizerRootEntry grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source furthest
      sourceInvariant) :
    RecognizerRootStatementFunctionalExecution grammarLayout grammar words
      tokens workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell source furthest
      sourceInvariant entry := by
  let world := stateWorld words tokens workspaceValues grammarCell tokensCell
    workspaceCell
  let environment := rootStatementEnvironment words workspaceValues grammarCell
    workspaceCell workspaceLayout grammar workspace.states.length furthest
  let rootValue := chartHeadValue workspace
    (finalPosition workspaceLayout.tokenCount)
  have initializerResult : Lanius.FunctionalView.Term.evaluate
      (stateTermMachine workspaceLayout grammar words tokens grammarCell
        tokensCell)
      world environment (stateChartHeadTerm ⟨1, by omega⟩ ⟨2, by omega⟩) =
      .ok (.signed .i32 rootValue, world) :=
    stateChartHeadTerm_evaluates workspaceLayout grammar words tokens
      grammarCell tokensCell workspaceCell world environment
      ⟨1, by omega⟩ ⟨2, by omega⟩ workspace workspaceValues
      (finalPosition workspaceLayout.tokenCount) (by rfl) (by rfl)
      (stateWorld_finds_workspace
        sourceInvariant.frame.appendFrame.recognizer.grammarWorkspaceDistinct
        sourceInvariant.frame.appendFrame.recognizer.tokensWorkspaceDistinct)
      sourceInvariant.frame.appendFrame.recognizer.workspaceLength
      sourceInvariant.frame.appendFrame.recognizer.workspaceEncoded
      (Nat.le_refl _)
  generalize runEq : entry.functionalConfig.functional_run = assembled
  obtain ⟨completion, functionalAfter, trace, result⟩ := assembled
  have sourceCompletionEq :
      entry.functionalConfig.functional_run.completion = completion := by
    simpa using congrArg (fun run => run.completion) runEq
  have sourceAfterEq :
      entry.functionalConfig.functional_run.after = functionalAfter := by
    simpa using congrArg (fun run => run.after) runEq
  have initialWorldEq : entry.functionalConfig.functionalRuntime.world =
      world := by
    rfl
  let loop := entry.functional_execute_loop
  cases completion with
  | returned returnedValue =>
    cases result.outcome with
    | accepted rootState candidate found productionBound candidateMatches
        materializedParse physicalAfter wellFormed =>
      have loopExecution : Lanius.FunctionalView.Stateful.Command.Evaluates
          (stateTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          world (environment.push (.signed .i32 rootValue))
          rootStatementLoopCommand
          (.returned (some (parseResultValue 0
            (Int.ofNat workspace.states.length) (Int.ofNat rootState) 0)))
          functionalAfter.world loop.afterLarge := by
        simpa only [loop, stateTermMachine, world, environment, rootValue,
          initialWorldEq, sourceCompletionEq, sourceAfterEq] using loop.evaluated
      have bodyExecution : Lanius.FunctionalView.Stateful.Command.Evaluates
          (stateTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          world (environment.push (.signed .i32 rootValue))
          (.sequence rootStatementLoopCommand rootStatementRejectedCommand)
          (.returned (some (parseResultValue 0
            (Int.ofNat workspace.states.length) (Int.ofNat rootState) 0)))
          functionalAfter.world loop.afterLarge :=
        .sequenceStop loopExecution (by intro impossible; cases impossible)
      let outerAfter := restoreLocals entry.chartEntry.headRead.after
        result.physicalAfter
      have loopPhysical : Executes verifiedParserCore entry.chartEntry.bound
          parserRecognizeRootLoop
          (.returned (some (parseResultValue 0
            (Int.ofNat workspace.states.length) (Int.ofNat rootState) 0)))
          result.physicalAfter := by
        simpa [RecognizerRootEntry.functionalConfig,
          Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
            result.execution
      have loopPhysicalEffect : ModifiesOnly
          (CellSet.singleton entry.chartEntry.cursorCell)
          entry.chartEntry.bound result.physicalAfter := by
        simpa [RecognizerRootEntry.functionalConfig] using result.effect
      have bodyPhysical : Executes verifiedParserCore
          (entry.chartEntry.headRead.after.bindLocal 41 (.signed .i32 rootValue))
          (.sequence parserRecognizeRootLoop parserRecognizeRejectedReturn)
          (.returned (some (parseResultValue 0
            (Int.ofNat workspace.states.length) (Int.ofNat rootState) 0)))
          result.physicalAfter := by
        rw [show rootValue = chartHeadValue workspace
          (finalPosition workspaceLayout.tokenCount) by rfl]
        rw [← entry.chartEntry.boundEq]
        exact executesSequenceReturned loopPhysical
      have entered : StoreEffect CellSet.empty
          entry.chartEntry.headRead.after entry.chartEntry.bound := by
        simpa [entry.chartEntry.boundEq] using
          bindLocal_effect entry.chartEntry.headRead.after 41
            (.signed .i32 rootValue)
      have scopedStore : StoreEffect
          (CellSet.singleton entry.chartEntry.cursorCell)
          entry.chartEntry.headRead.after result.physicalAfter :=
        (entered.weaken CellSet.empty_subset).trans_same
          loopPhysicalEffect.toStoreEffect
      have cursorClosed : ModifiesOnly
          (CellSet.singleton entry.chartEntry.cursorCell)
          entry.chartEntry.headRead.after outerAfter := by
        simpa [outerAfter] using scopedStore.restoreLocals
      have cursorHidden : ModifiesOnly CellSet.empty
          entry.chartEntry.headRead.after outerAfter := by
        apply cursorClosed.hideFreshWrites
        intro cell written
        change cell = entry.chartEntry.cursorCell at written
        subst cell
        rw [entry.chartEntry.cursorCellEq]
        exact Nat.le_refl _
      have outerEffect : ModifiesOnly CellSet.empty source outerAfter :=
        entry.chartEntry.headRead.effect.trans_same cursorHidden
      exact {
        resultValue := parseResultValue 0 (Int.ofNat workspace.states.length)
          (Int.ofNat rootState) 0
        afterWorld := functionalAfter.world
        afterEnvironment :=
          Lanius.FunctionalView.Stateful.Env.pop loop.afterLarge
        execution := by
          rw [rootStatementCommand_shape, rootExpectedStatementCommand]
          exact .letValue initializerResult bodyExecution
        physicalAfter := outerAfter
        physicalExecution := by
          rw [extractedParserRecognize_root_statement_shape]
          simpa [extractedParserRecognize_root_head_expr_shape,
            entry.chartEntry.boundEq, outerAfter, rootValue] using
            executesLetLocal entry.chartEntry.headRead.evaluation bodyPhysical
        physicalEffect := outerEffect
        physicalWellFormed := by
          exact scopedStore.restoreLocals_wellFormed
            entry.chartEntry.headRead.invariant.wellFormed wellFormed
        outcome := .accepted rootState candidate found productionBound
          candidateMatches materializedParse
      }
  | next =>
    cases result.outcome with
    | exhausted physicalAfter finished worldEq environmentEq =>
      have loopExecution : Lanius.FunctionalView.Stateful.Command.Evaluates
          (stateTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          world (environment.push (.signed .i32 rootValue))
          rootStatementLoopCommand .next functionalAfter.world
          loop.afterLarge := by
        simpa only [loop, stateTermMachine, world, environment, rootValue,
          initialWorldEq, sourceCompletionEq, sourceAfterEq] using loop.evaluated
      have loopExecution' : Lanius.FunctionalView.Stateful.Command.Evaluates
          (stateTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          world (environment.push (.signed .i32 rootValue))
          rootStatementLoopCommand .next world loop.afterLarge := by
        simpa [world, worldEq] using loopExecution
      have rejectedRelated : Lanius.FunctionalView.Env.Extends
          rootIntoStatementEmbedding
          (rootEnvironment words workspaceValues grammarCell workspaceCell
            workspaceLayout grammar workspace.states.length
            finished.furthestPosition (-1))
          loop.afterLarge := by
        rw [← environmentEq]
        simpa only [loop, sourceAfterEq] using loop.related
      let rejected := rootExecution_in_state_environment
        (tokens := tokens) (tokensCell := tokensCell)
        rootRejected_calls_supported_in_state finished.functional_rejected
        loop.afterLarge rejectedRelated
      have bodyExecution : Lanius.FunctionalView.Stateful.Command.Evaluates
          (stateTermMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          (stateStatefulMachine workspaceLayout grammar words tokens grammarCell
            tokensCell)
          world (environment.push (.signed .i32 rootValue))
          (.sequence rootStatementLoopCommand rootStatementRejectedCommand)
          (.returned (some (parseResultValue 1
            (Int.ofNat workspace.states.length) (-1)
            (Int.ofNat finished.furthestPosition))))
          world rejected.afterLarge := by
        exact .sequenceNext loopExecution' (by
          simpa [rejected, world] using rejected.evaluated)
      have loopPhysical : Executes verifiedParserCore entry.chartEntry.bound
          parserRecognizeRootLoop .next result.physicalAfter := by
        simpa [RecognizerRootEntry.functionalConfig,
          Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using
            result.execution
      have loopPhysicalEffect : ModifiesOnly
          (CellSet.singleton entry.chartEntry.cursorCell)
          entry.chartEntry.bound result.physicalAfter := by
        simpa [RecognizerRootEntry.functionalConfig] using result.effect
      let physicalRejected := finished.execute_rejected
      let outerAfter := restoreLocals entry.chartEntry.headRead.after
        physicalRejected.after
      have bodyPhysical : Executes verifiedParserCore
          (entry.chartEntry.headRead.after.bindLocal 41 (.signed .i32 rootValue))
          (.sequence parserRecognizeRootLoop parserRecognizeRejectedReturn)
          (.returned (some (parseResultValue 1
            (Int.ofNat workspace.states.length) (-1)
            (Int.ofNat finished.furthestPosition))))
          physicalRejected.after := by
        rw [show rootValue = chartHeadValue workspace
          (finalPosition workspaceLayout.tokenCount) by rfl]
        rw [← entry.chartEntry.boundEq]
        exact executesSequence loopPhysical physicalRejected.execution
      have bodyStore : StoreEffect
          (CellSet.singleton entry.chartEntry.cursorCell)
          entry.chartEntry.bound physicalRejected.after :=
        loopPhysicalEffect.toStoreEffect.trans_same
          (physicalRejected.effect.toStoreEffect.weaken CellSet.empty_subset)
      have entered : StoreEffect CellSet.empty
          entry.chartEntry.headRead.after entry.chartEntry.bound := by
        simpa [entry.chartEntry.boundEq] using
          bindLocal_effect entry.chartEntry.headRead.after 41
            (.signed .i32 rootValue)
      have scopedStore : StoreEffect
          (CellSet.singleton entry.chartEntry.cursorCell)
          entry.chartEntry.headRead.after physicalRejected.after :=
        (entered.weaken CellSet.empty_subset).trans_same bodyStore
      have cursorClosed : ModifiesOnly
          (CellSet.singleton entry.chartEntry.cursorCell)
          entry.chartEntry.headRead.after outerAfter := by
        simpa [outerAfter] using scopedStore.restoreLocals
      have cursorHidden : ModifiesOnly CellSet.empty
          entry.chartEntry.headRead.after outerAfter := by
        apply cursorClosed.hideFreshWrites
        intro cell written
        change cell = entry.chartEntry.cursorCell at written
        subst cell
        rw [entry.chartEntry.cursorCellEq]
        exact Nat.le_refl _
      have outerEffect : ModifiesOnly CellSet.empty source outerAfter :=
        entry.chartEntry.headRead.effect.trans_same cursorHidden
      exact {
        resultValue := parseResultValue 1 (Int.ofNat workspace.states.length)
          (-1) (Int.ofNat finished.furthestPosition)
        afterWorld := world
        afterEnvironment :=
          Lanius.FunctionalView.Stateful.Env.pop rejected.afterLarge
        execution := by
          rw [rootStatementCommand_shape, rootExpectedStatementCommand]
          exact .letValue initializerResult bodyExecution
        physicalAfter := outerAfter
        physicalExecution := by
          rw [extractedParserRecognize_root_statement_shape]
          simpa [extractedParserRecognize_root_head_expr_shape,
            entry.chartEntry.boundEq, outerAfter, rootValue] using
            executesLetLocal entry.chartEntry.headRead.evaluation bodyPhysical
        physicalEffect := outerEffect
        physicalWellFormed := by
          exact scopedStore.restoreLocals_wellFormed
            entry.chartEntry.headRead.invariant.wellFormed
            physicalRejected.wellFormed
        outcome := .rejected finished.furthestPosition
      }
  | breakLoop =>
    cases result.outcome
  | continueLoop =>
    cases result.outcome

structure RecognizerRootStatementExecution
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (workspaceLayout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell : CellId)
    (before : State) (furthest : Nat)
    (beforeInvariant : RecognizerPositionFinishedInvariant grammarLayout
      grammar words tokens workspaceLayout workspace workspaceValues
      grammarCell tokensCell workspaceCell stateCountCell positionCell
      furthestCell before furthest) where
  after : State
  completion : Completion
  execution : Executes verifiedParserCore before parserRecognizeRootStatement
    completion after
  effect : ModifiesOnly CellSet.empty before after
  wellFormed : StateWellFormed after
  outcome : RecognizerRootStatementOutcome grammar tokens workspace completion

/-- Execute root-head binding, complete root search, and the rejected fallback
    as one artifact-derived continuation. -/
noncomputable def RecognizerPositionFinishedInvariant.execute_root_statement
    (invariant : RecognizerPositionFinishedInvariant grammarLayout grammar
      words tokens workspaceLayout workspace workspaceValues grammarCell
      tokensCell workspaceCell stateCountCell positionCell furthestCell before
      furthest) :
    RecognizerRootStatementExecution grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell stateCountCell positionCell furthestCell before furthest
      invariant := by
  let entry := invariant.enter_root_loop
  let synchronized := entry.functional_execute_statement
  exact {
    after := synchronized.physicalAfter
    completion := .returned (some synchronized.resultValue)
    execution := synchronized.physicalExecution
    effect := synchronized.physicalEffect
    wellFormed := synchronized.physicalWellFormed
    outcome := synchronized.outcome
  }


end Lanius.Extraction.ParserRecognize
