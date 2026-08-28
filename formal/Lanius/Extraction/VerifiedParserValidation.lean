import Lanius.Extraction.VerifiedParserAccessors

namespace Lanius.Extraction.ParserValidation

set_option maxRecDepth 100000

open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction
open Lanius.Extraction.ParserBasics
open Lanius.Extraction.ParserAccessors
open Lanius.Compiler.Parser
open Lanius.SymbolicCore
open Lanius.Extraction.SymbolicLocalChecker

def extractedParserGrammarValidWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "grammar_is_valid"

def extractedParserGrammarValidFunction : Function :=
  CoreDecode.function extractedParserGrammarValidWire

def extractedParserGrammarValidBody : Stmt :=
  extractedParserGrammarValidFunction.body.getD .skip

theorem extractedParserGrammarValid_function_shape :
    extractedParserGrammarValidFunction.id = 8 ∧
      extractedParserGrammarValidFunction.parameters = [
        (0, .slice parserI32Type), (1, parserI32Type)] ∧
      extractedParserGrammarValidFunction.returnType = parserBoolType ∧
      extractedParserGrammarValidFunction.body =
        some extractedParserGrammarValidBody ∧
      extractedParserGrammarValidFunction.external = none := by
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem verifiedParserCore_finds_grammarValid :
    verifiedParserCore.function? extractedParserGrammarValidFunction.id =
      some extractedParserGrammarValidFunction := by
  unfold verifiedParserCore extractedParserGrammarValidFunction
    extractedParserGrammarValidWire
  rfl

def parserGrammarLengthGuardExpr : Expr :=
  .binary .less (.local 1) (.constant 6)

def parserGrammarVersionGuardExpr : Expr :=
  .binary .notEqual
    (.index (.local 0) (.constant 7))
    (.constant 5)

def parserGrammarRejectStmt : Stmt :=
  .sequence (.returnValue (some (.value (.boolean false)))) .skip

def parserGrammarLengthGuardStmt : Stmt :=
  .ifThenElse parserGrammarLengthGuardExpr parserGrammarRejectStmt .skip

def parserGrammarVersionGuardStmt : Stmt :=
  .ifThenElse parserGrammarVersionGuardExpr parserGrammarRejectStmt .skip

/-- The remainder is selected from the checked artifact rather than copied by
    hand.  The equality below still checks that the first two source guards
    have exactly the expected Core form. -/
def parserGrammarValidationAfterPreludeGuards : Stmt :=
  match extractedParserGrammarValidBody with
  | .sequence _ (.sequence _ remainder) => remainder
  | _ => .skip

theorem extractedParserGrammarValid_initial_shape :
    extractedParserGrammarValidBody =
      .sequence parserGrammarLengthGuardStmt
        (.sequence parserGrammarVersionGuardStmt
          parserGrammarValidationAfterPreludeGuards) := by
  rfl

theorem verifiedParser_grammar_guard_constants :
    verifiedParserCore.constant? 7 = some {
        id := 7
        type := parserI32Type
        value := .signed .i32 0
      } ∧
      verifiedParserCore.constant? 5 = some {
        id := 5
        type := parserI32Type
        value := .signed .i32 1
      } := by
  have evidence :
      (verifiedParserCore.constant? 7).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (7, parserI32Type, some 0) ∧
      (verifiedParserCore.constant? 5).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (5, parserI32Type, some 1) := by
    native_decide
  exact ⟨
    constant_eq_of_signed_i32_evidence verifiedParserCore 7 0 evidence.1,
    constant_eq_of_signed_i32_evidence verifiedParserCore 5 1 evidence.2⟩

/-- A packed-table range accepted by the semantic encoding is accepted by the
    exact wrapped-i32 predicate computed by extracted `range_valid`. -/
theorem parserRangeValidValue_accepts_packed
    (offset count wordLength : Nat)
    (wordLengthI32 : wordLength ≤ 2147483647)
    (valid : PackedRangeValid offset count wordLength) :
    parserRangeValidValue verifiedParserCore.target
        (Int.ofNat offset) (Int.ofNat count) (Int.ofNat wordLength) = true := by
  have wordLengthBound : Int.ofNat wordLength ≤ 2147483647 := by
    change (wordLength : Int) ≤ 2147483647
    exact Int.ofNat_le.mpr wordLengthI32
  apply (parserRangeValidValue_eq_true_iff verifiedParserCore.target
    (Int.ofNat offset) (Int.ofNat count) (Int.ofNat wordLength)
    wordLengthBound).2
  rcases valid with ⟨afterHeader, offsetBound, countBound⟩
  constructor
  · simp only [grammarHeaderWords] at afterHeader
    change (17 : Int) ≤ (offset : Int)
    exact Int.ofNat_le.mpr afterHeader
  constructor
  · change (0 : Int) ≤ (count : Int)
    exact Int.natCast_nonneg count
  constructor
  · change (offset : Int) ≤ (wordLength : Int)
    exact Int.ofNat_le.mpr offsetBound
  · change (count : Int) ≤ (wordLength : Int) - (offset : Int)
    rw [← Int.natCast_sub offsetBound]
    exact Int.ofNat_le.mpr countBound

/-- Source-call rule specialized to one validated packed table.  This is the
    reusable rule needed eight times by the validator prelude. -/
theorem extractedParserRangeValidCall_accepts_packed
    (before afterArguments : State) (arguments : List Expr)
    (offset count wordLength : Nat)
    (wordLengthI32 : wordLength ≤ 2147483647)
    (valid : PackedRangeValid offset count wordLength)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      .signed .i32 (Int.ofNat offset), .signed .i32 (Int.ofNat count),
      .signed .i32 (Int.ofNat wordLength)] afterArguments) :
    let callee := parserRangeValidCallee afterArguments
      (Int.ofNat offset) (Int.ofNat count) (Int.ofNat wordLength)
    let after := restoreLocals afterArguments callee
    Evaluates verifiedParserCore before
        (.call extractedParserRangeValidFunction.id arguments)
        (.boolean true) after ∧
      ModifiesOnly CellSet.empty afterArguments after ∧
      StateWellFormed after := by
  have call := extractedParserRangeValidCall_evaluates before afterArguments
    arguments (Int.ofNat offset) (Int.ofNat count) (Int.ofNat wordLength)
    afterArgumentsWellFormed argumentsResult
  have accepted := parserRangeValidValue_accepts_packed offset count
    wordLength wordLengthI32 valid
  simpa only [accepted] using call

/-- Stable call-state boundary for the extracted grammar validator.  It owns
    no grammar memory: the backing cell remains framed while temporary locals
    are allocated and restored around helper calls and loops. -/
structure GrammarValidationInvariant
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId) (state : State) : Prop where
  encoded : EncodesGrammar layout grammar words
  grammarWellFormed : grammar.WellFormed
  wordsI32 : words.length ≤ 2147483647
  stateWellFormed : StateWellFormed state
  grammarLocal : state.local? 0 =
    some (parserGrammarValue words grammarCell)
  grammarLengthLocal : state.local? 1 =
    some (.signed .i32 (Int.ofNat words.length))
  grammarBacking : state.cellEntry? grammarCell = some {
    id := grammarCell
    value := some (.array (signedI32Values words))
  }

theorem GrammarValidationInvariant.after_empty_effect
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell before)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    GrammarValidationInvariant layout grammar words grammarCell after := {
  encoded := invariant.encoded
  grammarWellFormed := invariant.grammarWellFormed
  wordsI32 := invariant.wordsI32
  stateWellFormed := afterWellFormed
  grammarLocal := effect.empty_preserves_local invariant.stateWellFormed
    invariant.grammarLocal
  grammarLengthLocal := effect.empty_preserves_local invariant.stateWellFormed
    invariant.grammarLengthLocal
  grammarBacking := effect.empty_preserves_entry invariant.stateWellFormed
    invariant.grammarBacking
}

theorem GrammarValidationInvariant.after_bind_local
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell state)
    (id : VarId) (value : Value) (notGrammar : id ≠ 0)
    (notLength : id ≠ 1) :
    GrammarValidationInvariant layout grammar words grammarCell
      (state.bindLocal id value) := {
  encoded := invariant.encoded
  grammarWellFormed := invariant.grammarWellFormed
  wordsI32 := invariant.wordsI32
  stateWellFormed := bindLocal_preserves_well_formed state id value
    invariant.stateWellFormed
  grammarLocal :=
    (bindLocal_preserves_other_local invariant.stateWellFormed notGrammar).trans
      invariant.grammarLocal
  grammarLengthLocal :=
    (bindLocal_preserves_other_local invariant.stateWellFormed notLength).trans
      invariant.grammarLengthLocal
  grammarBacking := by
    have old := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant.stateWellFormed invariant.grammarBacking
    exact ((bindLocal_effect state id value).oldCells grammarCell old
      (by simp [CellSet.empty])).trans invariant.grammarBacking
}

theorem GrammarValidationInvariant.evaluates_header
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell state)
    (headerConstant : ConstantId) (headerIndex value : Nat)
    (header : HeaderWord words headerIndex value)
    (constantFound : verifiedParserCore.constant? headerConstant = some {
      id := headerConstant
      type := parserI32Type
      value := .signed .i32 (Int.ofNat headerIndex)
    }) :
    Evaluates verifiedParserCore state
      (.index (.local 0) (.constant headerConstant))
      (.signed .i32 (Int.ofNat value)) state := by
  have result := evaluatesParserHeaderRead words grammarCell headerConstant
    headerIndex header.index_in_bounds state invariant.grammarLocal
    invariant.grammarBacking constantFound
  have headerValue : words.get ⟨headerIndex, header.index_in_bounds⟩ =
      Int.ofNat value := by
    simpa using header.get
  rw [headerValue] at result
  exact result

structure ValidatedRangeCall
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (before : State) (headerConstant : ConstantId)
    (countExpression : Expr) (offset count : Nat) where
  after : State
  evaluation : Evaluates verifiedParserCore before
    (.call extractedParserRangeValidFunction.id [
      .index (.local 0) (.constant headerConstant),
      countExpression, .local 1])
    (.boolean true) after
  effect : ModifiesOnly CellSet.empty before after
  invariant : GrammarValidationInvariant layout grammar words grammarCell after

/-- Evaluate one of the validator's eight table-range calls. Header reads and
    scalar arguments are pure; the helper's temporary call frame is hidden by
    the separation-logic effect and the grammar invariant is re-established
    on the returned state. -/
noncomputable def GrammarValidationInvariant.evaluate_range_call
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell state)
    (headerConstant : ConstantId) (headerIndex offset count : Nat)
    (countExpression : Expr)
    (header : HeaderWord words headerIndex offset)
    (constantFound : verifiedParserCore.constant? headerConstant = some {
      id := headerConstant
      type := parserI32Type
      value := .signed .i32 (Int.ofNat headerIndex)
    })
    (countResult : Evaluates verifiedParserCore state countExpression
      (.signed .i32 (Int.ofNat count)) state)
    (valid : PackedRangeValid offset count words.length) :
    ValidatedRangeCall layout grammar words grammarCell state
      headerConstant countExpression offset count := by
  have offsetResult := evaluatesParserHeaderRead words grammarCell
    headerConstant headerIndex header.index_in_bounds state
    invariant.grammarLocal invariant.grammarBacking constantFound
  have headerValue : words.get ⟨headerIndex, header.index_in_bounds⟩ =
      Int.ofNat offset := by
    simpa using header.get
  rw [headerValue] at offsetResult
  have lengthResult : Evaluates verifiedParserCore state (.local 1)
      (.signed .i32 (Int.ofNat words.length)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 1
      (.signed .i32 (Int.ofNat words.length))
      invariant.grammarLengthLocal⟩
  have argumentsResult : ArgumentsEvaluateTo verifiedParserCore state [
      .index (.local 0) (.constant headerConstant), countExpression,
      .local 1] [
      .signed .i32 (Int.ofNat offset), .signed .i32 (Int.ofNat count),
      .signed .i32 (Int.ofNat words.length)] state :=
    ArgumentsEvaluateTo.cons offsetResult
      (ArgumentsEvaluateTo.cons countResult
        (ArgumentsEvaluateTo.singleton lengthResult))
  have call := extractedParserRangeValidCall_accepts_packed state state [
      .index (.local 0) (.constant headerConstant), countExpression,
      .local 1] offset count words.length invariant.wordsI32 valid
      invariant.stateWellFormed argumentsResult
  let callee := parserRangeValidCallee state
    (Int.ofNat offset) (Int.ofNat count) (Int.ofNat words.length)
  let after := restoreLocals state callee
  refine {
    after := after
    evaluation := ?_
    effect := ?_
    invariant := ?_ }
  · simpa [callee, after] using call.1
  · simpa [callee, after] using call.2.1
  · exact invariant.after_empty_effect (by
      simpa [callee, after] using call.2.1) (by
      simpa [callee, after] using call.2.2)

structure GrammarRangeInvariant
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId) (state : State) : Prop where
  validation : GrammarValidationInvariant layout grammar words grammarCell state
  kindCountLocal : state.local? 2 =
    some (.signed .i32 (Int.ofNat grammar.grammar.n_kinds))
  productionCountLocal : state.local? 3 =
    some (.signed .i32 (Int.ofNat grammar.productionCount))
  nonterminalCountLocal : state.local? 4 =
    some (.signed .i32 (Int.ofNat grammar.grammar.n_nonterminals))
  startNonterminalLocal : state.local? 5 =
    some (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal))
  rhsSymbolCountLocal : state.local? 6 =
    some (.signed .i32 (Int.ofNat grammar.rhsSymbols.length))
  lhsProductionCountLocal : state.local? 7 =
    some (.signed .i32 (Int.ofNat grammar.lhsProductions.length))

def parserGrammarCountBindings (grammar : IndexedGrammar) :
    List (VarId × Value) := [
  (2, .signed .i32 (Int.ofNat grammar.grammar.n_kinds)),
  (3, .signed .i32 (Int.ofNat grammar.productionCount)),
  (4, .signed .i32 (Int.ofNat grammar.grammar.n_nonterminals)),
  (5, .signed .i32 (Int.ofNat grammar.grammar.start_nonterminal)),
  (6, .signed .i32 (Int.ofNat grammar.rhsSymbols.length)),
  (7, .signed .i32 (Int.ofNat grammar.lhsProductions.length))]

def parserGrammarRangeState (state : State) (grammar : IndexedGrammar) : State :=
  state.bindLocals (parserGrammarCountBindings grammar)

theorem GrammarValidationInvariant.range_state_invariant
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell state) :
    GrammarRangeInvariant layout grammar words grammarCell
      (parserGrammarRangeState state grammar) := by
  let kindValue : Value :=
    .signed .i32 (Int.ofNat grammar.grammar.n_kinds)
  let productionValue : Value :=
    .signed .i32 (Int.ofNat grammar.productionCount)
  let nonterminalValue : Value :=
    .signed .i32 (Int.ofNat grammar.grammar.n_nonterminals)
  let startValue : Value :=
    .signed .i32 (Int.ofNat grammar.grammar.start_nonterminal)
  let rhsSymbolValue : Value :=
    .signed .i32 (Int.ofNat grammar.rhsSymbols.length)
  let lhsProductionValue : Value :=
    .signed .i32 (Int.ofNat grammar.lhsProductions.length)
  let state2 := state.bindLocal 2 kindValue
  let invariant2 := invariant.after_bind_local 2 kindValue (by decide)
    (by decide)
  let state3 := state2.bindLocal 3 productionValue
  let invariant3 := invariant2.after_bind_local 3 productionValue (by decide)
    (by decide)
  let state4 := state3.bindLocal 4 nonterminalValue
  let invariant4 := invariant3.after_bind_local 4 nonterminalValue (by decide)
    (by decide)
  let state5 := state4.bindLocal 5 startValue
  let invariant5 := invariant4.after_bind_local 5 startValue (by decide)
    (by decide)
  let state6 := state5.bindLocal 6 rhsSymbolValue
  let invariant6 := invariant5.after_bind_local 6 rhsSymbolValue (by decide)
    (by decide)
  let state7 := state6.bindLocal 7 lhsProductionValue
  let invariant7 := invariant6.after_bind_local 7 lhsProductionValue
    (by decide) (by decide)
  have finalState : state7 = parserGrammarRangeState state grammar := by
    rfl
  refine {
    validation := ?_
    kindCountLocal := ?_
    productionCountLocal := ?_
    nonterminalCountLocal := ?_
    startNonterminalLocal := ?_
    rhsSymbolCountLocal := ?_
    lhsProductionCountLocal := ?_ }
  · rw [← finalState]
    exact invariant7
  · simpa [state7, state6, state5, state4, state3, state2, kindValue,
      productionValue, nonterminalValue, startValue, rhsSymbolValue,
      lhsProductionValue, parserGrammarRangeState, parserGrammarCountBindings]
      using bindLocals_local_of_binding state [] [
        (3, productionValue), (4, nonterminalValue), (5, startValue),
        (6, rhsSymbolValue), (7, lhsProductionValue)] 2 kindValue
        invariant.stateWellFormed (by simp)
  · simpa [state7, state6, state5, state4, state3, state2, kindValue,
      productionValue, nonterminalValue, startValue, rhsSymbolValue,
      lhsProductionValue, parserGrammarRangeState, parserGrammarCountBindings]
      using bindLocals_local_of_binding state [(2, kindValue)] [
        (4, nonterminalValue), (5, startValue), (6, rhsSymbolValue),
        (7, lhsProductionValue)] 3 productionValue
        invariant.stateWellFormed (by simp)
  · simpa [state7, state6, state5, state4, state3, state2, kindValue,
      productionValue, nonterminalValue, startValue, rhsSymbolValue,
      lhsProductionValue, parserGrammarRangeState, parserGrammarCountBindings]
      using bindLocals_local_of_binding state [
        (2, kindValue), (3, productionValue)] [
        (5, startValue), (6, rhsSymbolValue), (7, lhsProductionValue)]
        4 nonterminalValue invariant.stateWellFormed (by simp)
  · simpa [state7, state6, state5, state4, state3, state2, kindValue,
      productionValue, nonterminalValue, startValue, rhsSymbolValue,
      lhsProductionValue, parserGrammarRangeState, parserGrammarCountBindings]
      using bindLocals_local_of_binding state [
        (2, kindValue), (3, productionValue), (4, nonterminalValue)] [
        (6, rhsSymbolValue), (7, lhsProductionValue)] 5 startValue
        invariant.stateWellFormed (by simp)
  · simpa [state7, state6, state5, state4, state3, state2, kindValue,
      productionValue, nonterminalValue, startValue, rhsSymbolValue,
      lhsProductionValue, parserGrammarRangeState, parserGrammarCountBindings]
      using bindLocals_local_of_binding state [
        (2, kindValue), (3, productionValue), (4, nonterminalValue),
        (5, startValue)] [(7, lhsProductionValue)] 6 rhsSymbolValue
        invariant.stateWellFormed (by simp)
  · simpa [state7, state6, state5, state4, state3, state2, kindValue,
      productionValue, nonterminalValue, startValue, rhsSymbolValue,
      lhsProductionValue, parserGrammarRangeState, parserGrammarCountBindings]
      using bindLocals_local_of_binding state [
        (2, kindValue), (3, productionValue), (4, nonterminalValue),
        (5, startValue), (6, rhsSymbolValue)] [] 7 lhsProductionValue
        invariant.stateWellFormed (by simp)

theorem GrammarRangeInvariant.after_empty_effect
    (invariant : GrammarRangeInvariant layout grammar words
      grammarCell before)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    GrammarRangeInvariant layout grammar words grammarCell after := {
  validation := invariant.validation.after_empty_effect effect afterWellFormed
  kindCountLocal := effect.empty_preserves_local
    invariant.validation.stateWellFormed invariant.kindCountLocal
  productionCountLocal := effect.empty_preserves_local
    invariant.validation.stateWellFormed invariant.productionCountLocal
  nonterminalCountLocal := effect.empty_preserves_local
    invariant.validation.stateWellFormed invariant.nonterminalCountLocal
  startNonterminalLocal := effect.empty_preserves_local
    invariant.validation.stateWellFormed invariant.startNonterminalLocal
  rhsSymbolCountLocal := effect.empty_preserves_local
    invariant.validation.stateWellFormed invariant.rhsSymbolCountLocal
  lhsProductionCountLocal := effect.empty_preserves_local
    invariant.validation.stateWellFormed invariant.lhsProductionCountLocal
}

theorem GrammarRangeInvariant.after_bind_local
    (invariant : GrammarRangeInvariant layout grammar words grammarCell state)
    (id : VarId) (value : Value)
    (notGrammar : id ≠ 0) (notLength : id ≠ 1)
    (notKindCount : id ≠ 2) (notProductionCount : id ≠ 3)
    (notNonterminalCount : id ≠ 4) (notStart : id ≠ 5)
    (notRhsSymbolCount : id ≠ 6) (notLhsProductionCount : id ≠ 7) :
    GrammarRangeInvariant layout grammar words grammarCell
      (state.bindLocal id value) := {
  validation := invariant.validation.after_bind_local id value
    notGrammar notLength
  kindCountLocal :=
    (bindLocal_preserves_other_local invariant.validation.stateWellFormed
      notKindCount).trans invariant.kindCountLocal
  productionCountLocal :=
    (bindLocal_preserves_other_local invariant.validation.stateWellFormed
      notProductionCount).trans invariant.productionCountLocal
  nonterminalCountLocal :=
    (bindLocal_preserves_other_local invariant.validation.stateWellFormed
      notNonterminalCount).trans invariant.nonterminalCountLocal
  startNonterminalLocal :=
    (bindLocal_preserves_other_local invariant.validation.stateWellFormed
      notStart).trans invariant.startNonterminalLocal
  rhsSymbolCountLocal :=
    (bindLocal_preserves_other_local invariant.validation.stateWellFormed
      notRhsSymbolCount).trans invariant.rhsSymbolCountLocal
  lhsProductionCountLocal :=
    (bindLocal_preserves_other_local invariant.validation.stateWellFormed
      notLhsProductionCount).trans invariant.lhsProductionCountLocal
}

structure ValidatedRangeStep
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (before : State) (headerConstant : ConstantId)
    (countExpression : Expr) (offset count : Nat) where
  after : State
  evaluation : Evaluates verifiedParserCore before
    (.call extractedParserRangeValidFunction.id [
      .index (.local 0) (.constant headerConstant),
      countExpression, .local 1])
    (.boolean true) after
  effect : ModifiesOnly CellSet.empty before after
  invariant : GrammarRangeInvariant layout grammar words grammarCell after

noncomputable def GrammarRangeInvariant.evaluate_range
    (invariant : GrammarRangeInvariant layout grammar words grammarCell state)
    (headerConstant : ConstantId) (headerIndex offset count : Nat)
    (countExpression : Expr)
    (header : HeaderWord words headerIndex offset)
    (constantFound : verifiedParserCore.constant? headerConstant = some {
      id := headerConstant
      type := parserI32Type
      value := .signed .i32 (Int.ofNat headerIndex)
    })
    (countResult : Evaluates verifiedParserCore state countExpression
      (.signed .i32 (Int.ofNat count)) state)
    (valid : PackedRangeValid offset count words.length) :
    ValidatedRangeStep layout grammar words grammarCell state
      headerConstant countExpression offset count := by
  let call := invariant.validation.evaluate_range_call headerConstant
    headerIndex offset count countExpression header constantFound countResult
    valid
  refine {
    after := call.after
    evaluation := call.evaluation
    effect := call.effect
    invariant := ?_ }
  exact invariant.after_empty_effect call.effect
    call.invariant.stateWellFormed

def parserRangeCallExpr
    (headerConstant : ConstantId) (countExpression : Expr) : Expr :=
  .call extractedParserRangeValidFunction.id [
    .index (.local 0) (.constant headerConstant),
    countExpression, .local 1]

structure ValidatedFalseExpr
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (before : State) (expression : Expr) where
  after : State
  evaluation : Evaluates verifiedParserCore before expression
    (.boolean false) after
  effect : ModifiesOnly CellSet.empty before after
  invariant : GrammarRangeInvariant layout grammar words grammarCell after

noncomputable def ValidatedRangeStep.negated
    (step : ValidatedRangeStep layout grammar words grammarCell before
      headerConstant countExpression offset count) :
    ValidatedFalseExpr layout grammar words grammarCell before
      (.unary .logicalNot
        (parserRangeCallExpr headerConstant countExpression)) := by
  refine {
    after := step.after
    evaluation := ?_
    effect := step.effect
    invariant := step.invariant }
  apply evaluatesUnary step.evaluation
  simp [evalUnaryValue]

noncomputable def ValidatedFalseExpr.logicalOr
    (left : ValidatedFalseExpr layout grammar words grammarCell before
      leftExpression)
    (right : ValidatedFalseExpr layout grammar words grammarCell left.after
      rightExpression) :
    ValidatedFalseExpr layout grammar words grammarCell before
      (.binary .logicalOr leftExpression rightExpression) := {
  after := right.after
  evaluation := evaluatesLogicalOrFalse left.evaluation right.evaluation
  effect := left.effect.trans_same right.effect
  invariant := right.invariant
}

theorem verifiedParser_range_header_constants :
    verifiedParserCore.constant? 14 = some {
        id := 14
        type := parserI32Type
        value := .signed .i32 7
      } ∧
      verifiedParserCore.constant? 15 = some {
        id := 15
        type := parserI32Type
        value := .signed .i32 8
      } ∧
      verifiedParserCore.constant? 16 = some {
        id := 16
        type := parserI32Type
        value := .signed .i32 9
      } ∧
      verifiedParserCore.constant? 17 = some {
        id := 17
        type := parserI32Type
        value := .signed .i32 10
      } ∧
      verifiedParserCore.constant? 18 = some {
        id := 18
        type := parserI32Type
        value := .signed .i32 11
      } ∧
      verifiedParserCore.constant? 20 = some {
        id := 20
        type := parserI32Type
        value := .signed .i32 13
      } ∧
      verifiedParserCore.constant? 21 = some {
        id := 21
        type := parserI32Type
        value := .signed .i32 14
      } ∧
      verifiedParserCore.constant? 22 = some {
        id := 22
        type := parserI32Type
        value := .signed .i32 15
      } := by
  have evidence14 :
      (verifiedParserCore.constant? 14).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (14, parserI32Type, some 7) := by native_decide
  have evidence15 :
      (verifiedParserCore.constant? 15).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (15, parserI32Type, some 8) := by native_decide
  have evidence16 :
      (verifiedParserCore.constant? 16).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (16, parserI32Type, some 9) := by native_decide
  have evidence17 :
      (verifiedParserCore.constant? 17).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (17, parserI32Type, some 10) := by native_decide
  have evidence18 :
      (verifiedParserCore.constant? 18).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (18, parserI32Type, some 11) := by native_decide
  have evidence20 :
      (verifiedParserCore.constant? 20).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (20, parserI32Type, some 13) := by native_decide
  have evidence21 :
      (verifiedParserCore.constant? 21).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (21, parserI32Type, some 14) := by native_decide
  have evidence22 :
      (verifiedParserCore.constant? 22).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (22, parserI32Type, some 15) := by native_decide
  exact ⟨
    constant_eq_of_signed_i32_evidence verifiedParserCore 14 7 evidence14,
    constant_eq_of_signed_i32_evidence verifiedParserCore 15 8 evidence15,
    constant_eq_of_signed_i32_evidence verifiedParserCore 16 9 evidence16,
    constant_eq_of_signed_i32_evidence verifiedParserCore 17 10 evidence17,
    constant_eq_of_signed_i32_evidence verifiedParserCore 18 11 evidence18,
    constant_eq_of_signed_i32_evidence verifiedParserCore 20 13 evidence20,
    constant_eq_of_signed_i32_evidence verifiedParserCore 21 14 evidence21,
    constant_eq_of_signed_i32_evidence verifiedParserCore 22 15 evidence22⟩

theorem verifiedParser_count_header_constants :
    verifiedParserCore.constant? 8 = some {
        id := 8
        type := parserI32Type
        value := .signed .i32 1
      } ∧
      verifiedParserCore.constant? 9 = some {
        id := 9
        type := parserI32Type
        value := .signed .i32 2
      } ∧
      verifiedParserCore.constant? 10 = some {
        id := 10
        type := parserI32Type
        value := .signed .i32 3
      } ∧
      verifiedParserCore.constant? 11 = some {
        id := 11
        type := parserI32Type
        value := .signed .i32 4
      } ∧
      verifiedParserCore.constant? 19 = some {
        id := 19
        type := parserI32Type
        value := .signed .i32 12
      } ∧
      verifiedParserCore.constant? 23 = some {
        id := 23
        type := parserI32Type
        value := .signed .i32 16
      } := by
  have evidence8 :
      (verifiedParserCore.constant? 8).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (8, parserI32Type, some 1) := by native_decide
  have evidence9 :
      (verifiedParserCore.constant? 9).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (9, parserI32Type, some 2) := by native_decide
  have evidence10 :
      (verifiedParserCore.constant? 10).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (10, parserI32Type, some 3) := by native_decide
  have evidence11 :
      (verifiedParserCore.constant? 11).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (11, parserI32Type, some 4) := by native_decide
  have evidence19 :
      (verifiedParserCore.constant? 19).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (19, parserI32Type, some 12) := by native_decide
  have evidence23 :
      (verifiedParserCore.constant? 23).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (23, parserI32Type, some 16) := by native_decide
  exact ⟨
    constant_eq_of_signed_i32_evidence verifiedParserCore 8 1 evidence8,
    constant_eq_of_signed_i32_evidence verifiedParserCore 9 2 evidence9,
    constant_eq_of_signed_i32_evidence verifiedParserCore 10 3 evidence10,
    constant_eq_of_signed_i32_evidence verifiedParserCore 11 4 evidence11,
    constant_eq_of_signed_i32_evidence verifiedParserCore 19 12 evidence19,
    constant_eq_of_signed_i32_evidence verifiedParserCore 23 16 evidence23⟩

noncomputable def GrammarRangeInvariant.canonical_kinds_range
    (invariant : GrammarRangeInvariant layout grammar words
      grammarCell state) :
    ValidatedRangeStep layout grammar words grammarCell state 14 (.local 2)
      layout.canonicalKindsOffset grammar.grammar.n_kinds :=
  invariant.evaluate_range 14 7 layout.canonicalKindsOffset
    grammar.grammar.n_kinds (.local 2)
    invariant.validation.encoded.canonicalKindsOffset
    verifiedParser_range_header_constants.1
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 2
      (.signed .i32 (Int.ofNat grammar.grammar.n_kinds))
      invariant.kindCountLocal⟩
    (invariant.validation.encoded.validation_facts
      invariant.validation.grammarWellFormed).prelude.canonicalKindsRange

noncomputable def GrammarRangeInvariant.production_lhs_range
    (invariant : GrammarRangeInvariant layout grammar words
      grammarCell state) :
    ValidatedRangeStep layout grammar words grammarCell state 15 (.local 3)
      layout.productionLhsOffset grammar.productionCount :=
  invariant.evaluate_range 15 8 layout.productionLhsOffset
    grammar.productionCount (.local 3)
    invariant.validation.encoded.productionLhsOffset
    verifiedParser_range_header_constants.2.1
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 3
      (.signed .i32 (Int.ofNat grammar.productionCount))
      invariant.productionCountLocal⟩
    (invariant.validation.encoded.validation_facts
      invariant.validation.grammarWellFormed).prelude.productionLhsRange

noncomputable def GrammarRangeInvariant.rhs_offsets_range
    (invariant : GrammarRangeInvariant layout grammar words
      grammarCell state) :
    ValidatedRangeStep layout grammar words grammarCell state 16 (.local 3)
      layout.rhsOffsetsOffset grammar.productionCount :=
  invariant.evaluate_range 16 9 layout.rhsOffsetsOffset
    grammar.productionCount (.local 3)
    invariant.validation.encoded.rhsOffsetsOffset
    verifiedParser_range_header_constants.2.2.1
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 3
      (.signed .i32 (Int.ofNat grammar.productionCount))
      invariant.productionCountLocal⟩
    (invariant.validation.encoded.validation_facts
      invariant.validation.grammarWellFormed).prelude.rhsOffsetsRange

noncomputable def GrammarRangeInvariant.rhs_lengths_range
    (invariant : GrammarRangeInvariant layout grammar words
      grammarCell state) :
    ValidatedRangeStep layout grammar words grammarCell state 17 (.local 3)
      layout.rhsLengthsOffset grammar.productionCount :=
  invariant.evaluate_range 17 10 layout.rhsLengthsOffset
    grammar.productionCount (.local 3)
    invariant.validation.encoded.rhsLengthsOffset
    verifiedParser_range_header_constants.2.2.2.1
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 3
      (.signed .i32 (Int.ofNat grammar.productionCount))
      invariant.productionCountLocal⟩
    (invariant.validation.encoded.validation_facts
      invariant.validation.grammarWellFormed).prelude.rhsLengthsRange

noncomputable def GrammarRangeInvariant.rhs_symbols_range
    (invariant : GrammarRangeInvariant layout grammar words
      grammarCell state) :
    ValidatedRangeStep layout grammar words grammarCell state 18 (.local 6)
      layout.rhsSymbolsOffset grammar.rhsSymbols.length :=
  invariant.evaluate_range 18 11 layout.rhsSymbolsOffset
    grammar.rhsSymbols.length (.local 6)
    invariant.validation.encoded.rhsSymbolsOffset
    verifiedParser_range_header_constants.2.2.2.2.1
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 6
      (.signed .i32 (Int.ofNat grammar.rhsSymbols.length))
      invariant.rhsSymbolCountLocal⟩
    (invariant.validation.encoded.validation_facts
      invariant.validation.grammarWellFormed).prelude.rhsSymbolsRange

noncomputable def GrammarRangeInvariant.lhs_offsets_range
    (invariant : GrammarRangeInvariant layout grammar words
      grammarCell state) :
    ValidatedRangeStep layout grammar words grammarCell state 20 (.local 4)
      layout.lhsOffsetsOffset grammar.grammar.n_nonterminals :=
  invariant.evaluate_range 20 13 layout.lhsOffsetsOffset
    grammar.grammar.n_nonterminals (.local 4)
    invariant.validation.encoded.lhsOffsetsOffset
    verifiedParser_range_header_constants.2.2.2.2.2.1
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 4
      (.signed .i32 (Int.ofNat grammar.grammar.n_nonterminals))
      invariant.nonterminalCountLocal⟩
    (invariant.validation.encoded.validation_facts
      invariant.validation.grammarWellFormed).prelude.lhsOffsetsRange

noncomputable def GrammarRangeInvariant.lhs_counts_range
    (invariant : GrammarRangeInvariant layout grammar words
      grammarCell state) :
    ValidatedRangeStep layout grammar words grammarCell state 21 (.local 4)
      layout.lhsCountsOffset grammar.grammar.n_nonterminals :=
  invariant.evaluate_range 21 14 layout.lhsCountsOffset
    grammar.grammar.n_nonterminals (.local 4)
    invariant.validation.encoded.lhsCountsOffset
    verifiedParser_range_header_constants.2.2.2.2.2.2.1
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 4
      (.signed .i32 (Int.ofNat grammar.grammar.n_nonterminals))
      invariant.nonterminalCountLocal⟩
    (invariant.validation.encoded.validation_facts
      invariant.validation.grammarWellFormed).prelude.lhsCountsRange

noncomputable def GrammarRangeInvariant.lhs_productions_range
    (invariant : GrammarRangeInvariant layout grammar words
      grammarCell state) :
    ValidatedRangeStep layout grammar words grammarCell state 22 (.local 7)
      layout.lhsProductionsOffset grammar.lhsProductions.length :=
  invariant.evaluate_range 22 15 layout.lhsProductionsOffset
    grammar.lhsProductions.length (.local 7)
    invariant.validation.encoded.lhsProductionsOffset
    verifiedParser_range_header_constants.2.2.2.2.2.2.2
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 7
      (.signed .i32 (Int.ofNat grammar.lhsProductions.length))
      invariant.lhsProductionCountLocal⟩
    (invariant.validation.encoded.validation_facts
      invariant.validation.grammarWellFormed).prelude.lhsProductionsRange

def parserInvalidRangeExpr
    (headerConstant : ConstantId) (countExpression : Expr) : Expr :=
  .unary .logicalNot (parserRangeCallExpr headerConstant countExpression)

def parserGrammarInvalidRangesExpr : Expr :=
  .binary .logicalOr
    (.binary .logicalOr
      (.binary .logicalOr
        (.binary .logicalOr
          (.binary .logicalOr
            (.binary .logicalOr
              (.binary .logicalOr
                (parserInvalidRangeExpr 14 (.local 2))
                (parserInvalidRangeExpr 15 (.local 3)))
              (parserInvalidRangeExpr 16 (.local 3)))
            (parserInvalidRangeExpr 17 (.local 3)))
          (parserInvalidRangeExpr 18 (.local 6)))
        (parserInvalidRangeExpr 20 (.local 4)))
      (parserInvalidRangeExpr 21 (.local 4)))
    (parserInvalidRangeExpr 22 (.local 7))

noncomputable def GrammarRangeInvariant.evaluate_invalid_ranges
    (invariant : GrammarRangeInvariant layout grammar words
      grammarCell state) :
    ValidatedFalseExpr layout grammar words grammarCell state
      parserGrammarInvalidRangesExpr := by
  let first := invariant.canonical_kinds_range.negated
  let second := first.invariant.production_lhs_range.negated
  let firstTwo := first.logicalOr second
  let third := firstTwo.invariant.rhs_offsets_range.negated
  let firstThree := firstTwo.logicalOr third
  let fourth := firstThree.invariant.rhs_lengths_range.negated
  let firstFour := firstThree.logicalOr fourth
  let fifth := firstFour.invariant.rhs_symbols_range.negated
  let firstFive := firstFour.logicalOr fifth
  let sixth := firstFive.invariant.lhs_offsets_range.negated
  let firstSix := firstFive.logicalOr sixth
  let seventh := firstSix.invariant.lhs_counts_range.negated
  let firstSeven := firstSix.logicalOr seventh
  let eighth := firstSeven.invariant.lhs_productions_range.negated
  let all := firstSeven.logicalOr eighth
  simpa [parserGrammarInvalidRangesExpr, parserInvalidRangeExpr,
    parserRangeCallExpr, first, second, firstTwo, third, firstThree, fourth,
    firstFour, fifth, firstFive, sixth, firstSix, seventh, firstSeven,
    eighth] using all

def parserGrammarInvalidRangesGuardStmt : Stmt :=
  .ifThenElse parserGrammarInvalidRangesExpr parserGrammarRejectStmt .skip

def parserGrammarCountsInvalidExpr : Expr :=
  .binary .logicalOr
    (.binary .logicalOr
      (.binary .logicalOr
        (.binary .logicalOr
          (.binary .lessEqual (.local 2) (.value (.signed .i32 0)))
          (.binary .lessEqual (.local 3) (.value (.signed .i32 0))))
        (.binary .lessEqual (.local 4) (.value (.signed .i32 0))))
      (.binary .less (.local 5) (.value (.signed .i32 0))))
    (.binary .greaterEqual (.local 5) (.local 4))

def parserGrammarCountsGuardStmt : Stmt :=
  .ifThenElse parserGrammarCountsInvalidExpr parserGrammarRejectStmt .skip

theorem GrammarRangeInvariant.counts_guard_evaluates_false
    (invariant : GrammarRangeInvariant layout grammar words grammarCell state) :
    Evaluates verifiedParserCore state parserGrammarCountsInvalidExpr
      (.boolean false) state := by
  have zero : Evaluates verifiedParserCore state (.value (.signed .i32 0))
      (.signed .i32 0) state := ⟨1, rfl⟩
  have kindLocal : Evaluates verifiedParserCore state (.local 2)
      (.signed .i32 (Int.ofNat grammar.grammar.n_kinds)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 2 _
      invariant.kindCountLocal⟩
  have productionLocal : Evaluates verifiedParserCore state (.local 3)
      (.signed .i32 (Int.ofNat grammar.productionCount)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 3 _
      invariant.productionCountLocal⟩
  have nonterminalLocal : Evaluates verifiedParserCore state (.local 4)
      (.signed .i32 (Int.ofNat grammar.grammar.n_nonterminals)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 4 _
      invariant.nonterminalCountLocal⟩
  have startLocal : Evaluates verifiedParserCore state (.local 5)
      (.signed .i32 (Int.ofNat grammar.grammar.start_nonterminal)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 5 _
      invariant.startNonterminalLocal⟩
  have kindValid : Evaluates verifiedParserCore state
      (.binary .lessEqual (.local 2) (.value (.signed .i32 0)))
      (.boolean false) state := by
    have facts := invariant.validation.encoded.validation_facts
      invariant.validation.grammarWellFormed
    have nonzero : grammar.grammar.n_kinds ≠ 0 :=
      Nat.ne_of_gt facts.prelude.kindCountPositive
    apply evaluatesEagerBinary (by decide) (by decide) kindLocal zero
    simpa [evalBinaryValue, evalSignedBinary] using nonzero
  have productionValid : Evaluates verifiedParserCore state
      (.binary .lessEqual (.local 3) (.value (.signed .i32 0)))
      (.boolean false) state := by
    have facts := invariant.validation.encoded.validation_facts
      invariant.validation.grammarWellFormed
    have nonzero : grammar.productionCount ≠ 0 :=
      Nat.ne_of_gt facts.prelude.productionCountPositive
    apply evaluatesEagerBinary (by decide) (by decide) productionLocal zero
    simpa [evalBinaryValue, evalSignedBinary] using nonzero
  have nonterminalValid : Evaluates verifiedParserCore state
      (.binary .lessEqual (.local 4) (.value (.signed .i32 0)))
      (.boolean false) state := by
    have facts := invariant.validation.encoded.validation_facts
      invariant.validation.grammarWellFormed
    have nonzero : grammar.grammar.n_nonterminals ≠ 0 :=
      Nat.ne_of_gt facts.prelude.nonterminalCountPositive
    apply evaluatesEagerBinary (by decide) (by decide) nonterminalLocal zero
    simpa [evalBinaryValue, evalSignedBinary] using nonzero
  have startNonnegative : Evaluates verifiedParserCore state
      (.binary .less (.local 5) (.value (.signed .i32 0)))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) startLocal zero
    simp [evalBinaryValue, evalSignedBinary]
  have startInBounds : Evaluates verifiedParserCore state
      (.binary .greaterEqual (.local 5) (.local 4))
      (.boolean false) state := by
    have facts := invariant.validation.encoded.validation_facts
      invariant.validation.grammarWellFormed
    have bound : Int.ofNat grammar.grammar.start_nonterminal <
        Int.ofNat grammar.grammar.n_nonterminals :=
      Int.ofNat_lt.mpr facts.prelude.startNonterminalInBounds
    apply evaluatesEagerBinary (by decide) (by decide) startLocal
      nonterminalLocal
    simpa [evalBinaryValue, evalSignedBinary] using bound
  have firstTwo := evaluatesPureLogicalOr kindValid productionValid
  have firstThree := evaluatesPureLogicalOr firstTwo nonterminalValid
  have firstFour := evaluatesPureLogicalOr firstThree startNonnegative
  simpa [parserGrammarCountsInvalidExpr] using
    evaluatesPureLogicalOr firstFour startInBounds

theorem GrammarRangeInvariant.counts_guard_executes
    (invariant : GrammarRangeInvariant layout grammar words grammarCell state) :
    Executes verifiedParserCore state parserGrammarCountsGuardStmt .next state :=
  executesIfFalse invariant.counts_guard_evaluates_false
    (executesSkip verifiedParserCore state)

structure GrammarRangeGuardResult
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId) (before : State) where
  after : State
  execution : Executes verifiedParserCore before
    parserGrammarInvalidRangesGuardStmt .next after
  effect : ModifiesOnly CellSet.empty before after
  invariant : GrammarRangeInvariant layout grammar words grammarCell after

noncomputable def GrammarRangeInvariant.execute_invalid_ranges_guard
    (invariant : GrammarRangeInvariant layout grammar words
      grammarCell state) :
    GrammarRangeGuardResult layout grammar words grammarCell state := by
  let checked := invariant.evaluate_invalid_ranges
  refine {
    after := checked.after
    execution := ?_
    effect := checked.effect
    invariant := checked.invariant }
  exact executesIfFalse checked.evaluation
    (executesSkip verifiedParserCore checked.after)

def parserGrammarCountScopes (continuation : Stmt) : Stmt :=
  .letLocal 2 parserI32Type
    (.index (.local 0) (.constant 8))
    (.letLocal 3 parserI32Type
      (.index (.local 0) (.constant 9))
      (.letLocal 4 parserI32Type
        (.index (.local 0) (.constant 10))
        (.letLocal 5 parserI32Type
          (.index (.local 0) (.constant 11))
          (.letLocal 6 parserI32Type
            (.index (.local 0) (.constant 19))
            (.letLocal 7 parserI32Type
              (.index (.local 0) (.constant 23))
              (.sequence parserGrammarCountsGuardStmt continuation))))))

def parserGrammarValidationAfterCountGuard : Stmt :=
  match parserGrammarValidationAfterPreludeGuards with
  | .letLocal _ _ _
      (.letLocal _ _ _
        (.letLocal _ _ _
          (.letLocal _ _ _
            (.letLocal _ _ _
              (.letLocal _ _ _ (.sequence _ continuation)))))) => continuation
  | _ => .skip

def parserGrammarValidationAfterRangeGuard : Stmt :=
  match parserGrammarValidationAfterCountGuard with
  | .sequence _ continuation => continuation
  | _ => .skip

theorem extractedParserGrammarValid_count_scope_shape :
    parserGrammarValidationAfterPreludeGuards =
      parserGrammarCountScopes parserGrammarValidationAfterCountGuard := by
  rfl

theorem extractedParserGrammarValid_range_guard_shape :
    parserGrammarValidationAfterCountGuard =
      .sequence parserGrammarInvalidRangesGuardStmt
        parserGrammarValidationAfterRangeGuard := by
  rfl

def parserGrammarProductionScopes (loop continuation : Stmt) : Stmt :=
  .letLocal 8 parserI32Type
    (.index (.local 0) (.constant 15))
    (.letLocal 9 parserI32Type
      (.index (.local 0) (.constant 16))
      (.letLocal 10 parserI32Type
        (.index (.local 0) (.constant 17))
        (.letLocal 11 parserI32Type
          (.index (.local 0) (.constant 18))
          (.letLocal 12 parserI32Type
            (.value (.signed .i32 0))
            (.sequence loop continuation)))))

def parserGrammarProductionLoop : Stmt :=
  match parserGrammarValidationAfterRangeGuard with
  | .letLocal _ _ _
      (.letLocal _ _ _
        (.letLocal _ _ _
          (.letLocal _ _ _
            (.letLocal _ _ _ (.sequence loop _))))) => loop
  | _ => .skip

def parserGrammarValidationAfterProductionLoop : Stmt :=
  match parserGrammarValidationAfterRangeGuard with
  | .letLocal _ _ _
      (.letLocal _ _ _
        (.letLocal _ _ _
          (.letLocal _ _ _
            (.letLocal _ _ _ (.sequence _ continuation))))) => continuation
  | _ => .skip

theorem extractedParserGrammarValid_production_scope_shape :
    parserGrammarValidationAfterRangeGuard =
      parserGrammarProductionScopes parserGrammarProductionLoop
        parserGrammarValidationAfterProductionLoop := by
  rfl

def parserIncrementLocal (id : VarId) : Stmt :=
  .sequence
    (.expression (.assign .add (.local id) (.value (.signed .i32 1))))
    .skip

def parserGrammarNonterminalScopes (loop continuation : Stmt) : Stmt :=
  .letLocal 18 parserI32Type
    (.index (.local 0) (.constant 20))
    (.letLocal 19 parserI32Type
      (.index (.local 0) (.constant 21))
      (.letLocal 20 parserI32Type
        (.index (.local 0) (.constant 22))
        (.letLocal 21 parserI32Type
          (.value (.signed .i32 0))
          (.sequence loop continuation))))

def parserGrammarNonterminalLoop : Stmt :=
  match parserGrammarValidationAfterProductionLoop with
  | .letLocal _ _ _
      (.letLocal _ _ _
        (.letLocal _ _ _
          (.letLocal _ _ _ (.sequence loop _)))) => loop
  | _ => .skip

def parserGrammarValidationSuccess : Stmt :=
  match parserGrammarValidationAfterProductionLoop with
  | .letLocal _ _ _
      (.letLocal _ _ _
        (.letLocal _ _ _
          (.letLocal _ _ _ (.sequence _ continuation)))) => continuation
  | _ => .skip

theorem extractedParserGrammarValid_nonterminal_scope_shape :
    parserGrammarValidationAfterProductionLoop =
      parserGrammarNonterminalScopes parserGrammarNonterminalLoop
        parserGrammarValidationSuccess := by
  rfl

def parserGrammarNonterminalInvalidExpr : Expr :=
  .binary .logicalOr
    (.binary .logicalOr
      (.binary .logicalOr
        (.binary .less (.local 22) (.value (.signed .i32 0)))
        (.binary .less (.local 23) (.value (.signed .i32 0))))
      (.binary .greater (.local 22) (.local 7)))
    (.binary .greater (.local 23)
      (.binary .subtract (.local 7) (.local 22)))

def parserGrammarNonterminalInvalidGuard : Stmt :=
  .ifThenElse parserGrammarNonterminalInvalidExpr parserGrammarRejectStmt .skip

def parserGrammarListedInvalidExpr : Expr :=
  .binary .logicalOr
    (.binary .logicalOr
      (.binary .less (.local 25) (.value (.signed .i32 0)))
      (.binary .greaterEqual (.local 25) (.local 3)))
    (.binary .notEqual
      (.index (.local 0)
        (.binary .add (.local 8) (.local 25)))
      (.local 21))

def parserGrammarListedInvalidGuard : Stmt :=
  .ifThenElse parserGrammarListedInvalidExpr parserGrammarRejectStmt .skip

def parserGrammarListedLoopBody : Stmt :=
  .letLocal 25 parserI32Type
    (.index (.local 0)
      (.binary .add
        (.binary .add (.local 20) (.local 22))
        (.local 24)))
    (.sequence parserGrammarListedInvalidGuard (parserIncrementLocal 24))

def parserGrammarListedLoop : Stmt :=
  .whileLoop (.binary .less (.local 24) (.local 23))
    parserGrammarListedLoopBody

def parserGrammarNonterminalLoopBody : Stmt :=
  .letLocal 22 parserI32Type
    (.index (.local 0) (.binary .add (.local 18) (.local 21)))
    (.letLocal 23 parserI32Type
      (.index (.local 0) (.binary .add (.local 19) (.local 21)))
      (.sequence parserGrammarNonterminalInvalidGuard
        (.letLocal 24 parserI32Type (.value (.signed .i32 0))
          (.sequence parserGrammarListedLoop (parserIncrementLocal 21)))))

def parserGrammarExpectedNonterminalLoop : Stmt :=
  .whileLoop (.binary .less (.local 21) (.local 4))
    parserGrammarNonterminalLoopBody

theorem extractedParserGrammarValid_nonterminal_loop_shape :
    parserGrammarNonterminalLoop = parserGrammarExpectedNonterminalLoop := by
  rfl

theorem extractedParserGrammarValid_success_shape :
    parserGrammarValidationSuccess =
      .sequence (.returnValue (some (.value (.boolean true)))) .skip := by
  rfl

def parserGrammarProductionInvalidExpr : Expr :=
  .binary .logicalOr
    (.binary .logicalOr
      (.binary .logicalOr
        (.binary .logicalOr
          (.binary .logicalOr
            (.binary .less (.local 13) (.value (.signed .i32 0)))
            (.binary .greaterEqual (.local 13) (.local 4)))
          (.binary .less (.local 14) (.value (.signed .i32 0))))
        (.binary .less (.local 15) (.value (.signed .i32 0))))
      (.binary .greater (.local 14) (.local 6)))
    (.binary .greater (.local 15)
      (.binary .subtract (.local 6) (.local 14)))

def parserGrammarProductionInvalidGuard : Stmt :=
  .ifThenElse parserGrammarProductionInvalidExpr parserGrammarRejectStmt .skip

def parserGrammarSymbolInvalidExpr : Expr :=
  .binary .logicalOr
    (.binary .less (.local 17) (.value (.signed .i32 0)))
    (.binary .greaterEqual (.local 17)
      (.binary .add (.local 2) (.local 4)))

def parserGrammarSymbolInvalidGuard : Stmt :=
  .ifThenElse parserGrammarSymbolInvalidExpr parserGrammarRejectStmt .skip

def parserGrammarSymbolLoopBody : Stmt :=
  .letLocal 17 parserI32Type
    (.index (.local 0)
      (.binary .add
        (.binary .add (.local 11) (.local 14))
        (.local 16)))
    (.sequence parserGrammarSymbolInvalidGuard (parserIncrementLocal 16))

def parserGrammarSymbolLoop : Stmt :=
  .whileLoop (.binary .less (.local 16) (.local 15))
    parserGrammarSymbolLoopBody

def parserGrammarProductionLoopBody : Stmt :=
  .letLocal 13 parserI32Type
    (.index (.local 0) (.binary .add (.local 8) (.local 12)))
    (.letLocal 14 parserI32Type
      (.index (.local 0) (.binary .add (.local 9) (.local 12)))
      (.letLocal 15 parserI32Type
        (.index (.local 0) (.binary .add (.local 10) (.local 12)))
        (.sequence parserGrammarProductionInvalidGuard
          (.letLocal 16 parserI32Type (.value (.signed .i32 0))
            (.sequence parserGrammarSymbolLoop
              (parserIncrementLocal 12))))))

def parserGrammarExpectedProductionLoop : Stmt :=
  .whileLoop (.binary .less (.local 12) (.local 3))
    parserGrammarProductionLoopBody

theorem extractedParserGrammarValid_production_loop_shape :
    parserGrammarProductionLoop = parserGrammarExpectedProductionLoop := by
  rfl

def verifiedParserGrammarValidSymbolic : DerivedFunction :=
  (verifiedParserSymbolicFunction? "grammar_is_valid").get (by native_decide)

/-- The source-linked live frame at entry to the extracted production loop.
    The unique Core-fragment lookup prevents this proof from attaching to a
    different source statement with coincidentally similar syntax. -/
def parserGrammarProductionLoopFrame :
    LocalAccessFrame :=
  verifiedParserGrammarValidSymbolic.checkedLiveFrameBeforeCore
    parserGrammarProductionLoop (by native_decide)

def parserGrammarProductionLoopFrameIds : List VarId :=
  parserGrammarProductionLoopFrame.ids

/-- The live loop frame, excluding the loop-owned counter, plus the two
    proof-only values retained by the current outer invariant.  Keeping those
    extras declaration-backed makes the remaining proof-state over-retention
    explicit instead of disguising it as the interval `id < 12`. -/
def parserGrammarProductionProtectedBindings : LocalBindingFrame :=
  LocalBindingFrame.union
    (parserGrammarProductionLoopFrame.excludingName "production").bindings [
      verifiedParserGrammarValidSymbolic.checkedUniqueBindingNamed
        "grammar_length" (by native_decide),
      verifiedParserGrammarValidSymbolic.checkedUniqueBindingNamed
        "start_nonterminal" (by native_decide)]

/-- Numeric evaluator projection of the declaration-backed production frame. -/
def parserGrammarProductionProtectedIds : List VarId :=
  parserGrammarProductionProtectedBindings.coreIds

@[simp] theorem parserGrammarProductionProtectedBindings_core_ids :
    parserGrammarProductionProtectedBindings.coreIds =
      [3, 0, 8, 9, 10, 4, 6, 11, 2, 7, 1, 5] := by
  native_decide

theorem parserGrammarProductionLoop_source_frame :
    parserGrammarProductionLoopFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("production", 12, .readWrite),
      ("production_count", 3, .read),
      ("grammar", 0, .read),
      ("production_lhs_offset", 8, .read),
      ("rhs_offsets_offset", 9, .read),
      ("rhs_lengths_offset", 10, .read),
      ("nonterminal_count", 4, .read),
      ("rhs_symbol_count", 6, .read),
      ("rhs_symbols_offset", 11, .read),
      ("kind_count", 2, .read),
      ("lhs_production_count", 7, .read)] := by
  native_decide

@[simp] theorem parserGrammarProductionProtectedIds_shape :
    parserGrammarProductionProtectedIds = [3, 0, 8, 9, 10, 4, 6, 11, 2, 7, 1, 5] := by
  native_decide

@[simp] theorem mem_parserGrammarProductionProtectedIds_iff (id : VarId) :
    id ∈ parserGrammarProductionProtectedIds ↔ id < 12 := by
  have same : List.Perm parserGrammarProductionProtectedIds
      (List.range 12) := by native_decide
  rw [same.mem_iff]
  simp

def parserGrammarSymbolLoopAccessFrame :
    LocalAccessFrame :=
  verifiedParserGrammarValidSymbolic.checkedAccessFrameForCore
    parserGrammarSymbolLoop (by native_decide)

def parserGrammarSymbolLoopLiveFrame :
    LocalAccessFrame :=
  verifiedParserGrammarValidSymbolic.checkedLiveFrameBeforeCore
    parserGrammarSymbolLoop (by native_decide)

theorem parserGrammarSymbolLoop_source_access_frame :
    parserGrammarSymbolLoopAccessFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("rhs_index", 16, .readWrite),
      ("rhs_length", 15, .read),
      ("grammar", 0, .read),
      ("rhs_symbols_offset", 11, .read),
      ("rhs_offset", 14, .read),
      ("kind_count", 2, .read),
      ("nonterminal_count", 4, .read)] := by
  native_decide

theorem parserGrammarSymbolLoop_source_live_frame :
    parserGrammarSymbolLoopLiveFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("rhs_index", 16, .readWrite),
      ("rhs_length", 15, .read),
      ("grammar", 0, .read),
      ("rhs_symbols_offset", 11, .read),
      ("rhs_offset", 14, .read),
      ("kind_count", 2, .read),
      ("nonterminal_count", 4, .read),
      ("production", 12, .readWrite)] := by
  native_decide

/-- Bindings whose cells must remain distinct from the symbol-loop index:
    the enclosing production frame, its owned counter, and the three row
    values. -/
def parserGrammarSymbolProtectedBindings : LocalBindingFrame :=
  LocalBindingFrame.union parserGrammarProductionProtectedBindings [
    verifiedParserGrammarValidSymbolic.checkedUniqueBindingNamed
      "production" (by native_decide),
    verifiedParserGrammarValidSymbolic.checkedUniqueBindingNamed
      "lhs" (by native_decide),
    verifiedParserGrammarValidSymbolic.checkedUniqueBindingNamed
      "rhs_offset" (by native_decide),
    verifiedParserGrammarValidSymbolic.checkedUniqueBindingNamed
      "rhs_length" (by native_decide)]

def parserGrammarSymbolProtectedIds : List VarId :=
  parserGrammarSymbolProtectedBindings.coreIds

@[simp] theorem parserGrammarSymbolProtectedBindings_core_ids :
    parserGrammarSymbolProtectedBindings.coreIds =
      [3, 0, 8, 9, 10, 4, 6, 11, 2, 7, 1, 5, 12, 13, 14, 15] := by
  native_decide

@[simp] theorem parserGrammarSymbolProtectedIds_shape :
    parserGrammarSymbolProtectedIds =
      [3, 0, 8, 9, 10, 4, 6, 11, 2, 7, 1, 5, 12, 13, 14, 15] := by
  native_decide

@[simp] theorem mem_parserGrammarSymbolProtectedIds_iff (id : VarId) :
    id ∈ parserGrammarSymbolProtectedIds ↔ id < 16 := by
  have same : List.Perm parserGrammarSymbolProtectedIds (List.range 16) := by
    native_decide
  rw [same.mem_iff]
  simp

theorem parserGrammarProductionProtectedIds_subset_symbol
    {id : VarId} (member : id ∈ parserGrammarProductionProtectedIds) :
    id ∈ parserGrammarSymbolProtectedIds := by
  unfold parserGrammarSymbolProtectedIds
    parserGrammarSymbolProtectedBindings LocalBindingFrame.union
  rw [LocalBindingFrame.coreIds, List.map_append, List.mem_append]
  exact Or.inl member

def parserGrammarNonterminalLoopAccessFrame :
    LocalAccessFrame :=
  verifiedParserGrammarValidSymbolic.checkedAccessFrameForCore
    parserGrammarNonterminalLoop (by native_decide)

def parserGrammarNonterminalLoopLiveFrame :
    LocalAccessFrame :=
  verifiedParserGrammarValidSymbolic.checkedLiveFrameBeforeCore
    parserGrammarNonterminalLoop (by native_decide)

theorem parserGrammarNonterminalLoop_source_frame :
    parserGrammarNonterminalLoopAccessFrame =
      parserGrammarNonterminalLoopLiveFrame := by
  native_decide

theorem parserGrammarNonterminalLoop_source_access_frame :
    parserGrammarNonterminalLoopAccessFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("nonterminal", 21, .readWrite),
      ("nonterminal_count", 4, .read),
      ("grammar", 0, .read),
      ("lhs_offsets_offset", 18, .read),
      ("lhs_counts_offset", 19, .read),
      ("lhs_production_count", 7, .read),
      ("lhs_productions_offset", 20, .read),
      ("production_count", 3, .read),
      ("production_lhs_offset", 8, .read)] := by
  native_decide

/-- The closed production-row temporaries 13 through 17 are deliberately
    absent: the nonterminal loop preserves the production frame, its counter,
    and its own three table offsets. -/
def parserGrammarNonterminalProtectedBindings : LocalBindingFrame :=
  LocalBindingFrame.union parserGrammarProductionProtectedBindings [
    verifiedParserGrammarValidSymbolic.checkedUniqueBindingNamed
      "production" (by native_decide),
    verifiedParserGrammarValidSymbolic.checkedUniqueBindingNamed
      "lhs_offsets_offset" (by native_decide),
    verifiedParserGrammarValidSymbolic.checkedUniqueBindingNamed
      "lhs_counts_offset" (by native_decide),
    verifiedParserGrammarValidSymbolic.checkedUniqueBindingNamed
      "lhs_productions_offset" (by native_decide)]

def parserGrammarNonterminalProtectedIds : List VarId :=
  parserGrammarNonterminalProtectedBindings.coreIds

@[simp] theorem parserGrammarNonterminalProtectedBindings_core_ids :
    parserGrammarNonterminalProtectedBindings.coreIds =
      [3, 0, 8, 9, 10, 4, 6, 11, 2, 7, 1, 5, 12, 18, 19, 20] := by
  native_decide

@[simp] theorem parserGrammarNonterminalProtectedIds_shape :
    parserGrammarNonterminalProtectedIds =
      [3, 0, 8, 9, 10, 4, 6, 11, 2, 7, 1, 5, 12, 18, 19, 20] := by
  native_decide

theorem mem_parserGrammarNonterminalProtectedIds_lt
    (id : VarId) (member : id ∈ parserGrammarNonterminalProtectedIds) :
    id < 21 := by
  rw [parserGrammarNonterminalProtectedIds_shape] at member
  simp only [List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
      rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide

theorem parserGrammarProductionProtectedIds_subset_nonterminal
    {id : VarId} (member : id ∈ parserGrammarProductionProtectedIds) :
    id ∈ parserGrammarNonterminalProtectedIds := by
  unfold parserGrammarNonterminalProtectedIds
    parserGrammarNonterminalProtectedBindings LocalBindingFrame.union
  rw [LocalBindingFrame.coreIds, List.map_append, List.mem_append]
  exact Or.inl member

def parserGrammarListedLoopAccessFrame :
    LocalAccessFrame :=
  verifiedParserGrammarValidSymbolic.checkedAccessFrameForCore
    parserGrammarListedLoop (by native_decide)

def parserGrammarListedLoopLiveFrame :
    LocalAccessFrame :=
  verifiedParserGrammarValidSymbolic.checkedLiveFrameBeforeCore
    parserGrammarListedLoop (by native_decide)

theorem parserGrammarListedLoop_source_access_frame :
    parserGrammarListedLoopAccessFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("index", 24, .readWrite),
      ("count", 23, .read),
      ("grammar", 0, .read),
      ("lhs_productions_offset", 20, .read),
      ("first", 22, .read),
      ("production_count", 3, .read),
      ("production_lhs_offset", 8, .read),
      ("nonterminal", 21, .read)] := by
  native_decide

theorem parserGrammarListedLoop_source_live_frame :
    parserGrammarListedLoopLiveFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("index", 24, .readWrite),
      ("count", 23, .read),
      ("grammar", 0, .read),
      ("lhs_productions_offset", 20, .read),
      ("first", 22, .read),
      ("production_count", 3, .read),
      ("production_lhs_offset", 8, .read),
      ("nonterminal", 21, .readWrite)] := by
  native_decide

def parserGrammarListedProtectedBindings : LocalBindingFrame :=
  LocalBindingFrame.union parserGrammarNonterminalProtectedBindings [
    verifiedParserGrammarValidSymbolic.checkedUniqueBindingNamed
      "nonterminal" (by native_decide),
    verifiedParserGrammarValidSymbolic.checkedUniqueBindingNamed
      "first" (by native_decide),
    verifiedParserGrammarValidSymbolic.checkedUniqueBindingNamed
      "count" (by native_decide)]

def parserGrammarListedProtectedIds : List VarId :=
  parserGrammarListedProtectedBindings.coreIds

@[simp] theorem parserGrammarListedProtectedBindings_core_ids :
    parserGrammarListedProtectedBindings.coreIds =
      [3, 0, 8, 9, 10, 4, 6, 11, 2, 7, 1, 5, 12, 18, 19, 20, 21, 22, 23] := by
  native_decide

@[simp] theorem parserGrammarListedProtectedIds_shape :
    parserGrammarListedProtectedIds =
      [3, 0, 8, 9, 10, 4, 6, 11, 2, 7, 1, 5, 12, 18, 19, 20, 21, 22, 23] := by
  native_decide

theorem mem_parserGrammarListedProtectedIds_lt
    (id : VarId) (member : id ∈ parserGrammarListedProtectedIds) : id < 24 := by
  rw [parserGrammarListedProtectedIds_shape] at member
  simp only [List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
      rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    decide

theorem parserGrammarNonterminalProtectedIds_subset_listed
    {id : VarId} (member : id ∈ parserGrammarNonterminalProtectedIds) :
    id ∈ parserGrammarListedProtectedIds := by
  unfold parserGrammarListedProtectedIds
    parserGrammarListedProtectedBindings LocalBindingFrame.union
  rw [LocalBindingFrame.coreIds, List.map_append, List.mem_append]
  exact Or.inl member

def parserGrammarProductionBindings
    (layout : PackedGrammarLayout) : List (VarId × Value) := [
  (8, .signed .i32 (Int.ofNat layout.productionLhsOffset)),
  (9, .signed .i32 (Int.ofNat layout.rhsOffsetsOffset)),
  (10, .signed .i32 (Int.ofNat layout.rhsLengthsOffset)),
  (11, .signed .i32 (Int.ofNat layout.rhsSymbolsOffset)),
  (12, .signed .i32 0)]

def parserGrammarProductionState
    (state : State) (layout : PackedGrammarLayout) : State :=
  state.bindLocals (parserGrammarProductionBindings layout)

structure GrammarProductionLoopInvariant
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (state : State) (production : Nat) where
  range : GrammarRangeInvariant layout grammar words grammarCell state
  productionLhsOffsetLocal : state.local? 8 =
    some (.signed .i32 (Int.ofNat layout.productionLhsOffset))
  rhsOffsetsOffsetLocal : state.local? 9 =
    some (.signed .i32 (Int.ofNat layout.rhsOffsetsOffset))
  rhsLengthsOffsetLocal : state.local? 10 =
    some (.signed .i32 (Int.ofNat layout.rhsLengthsOffset))
  rhsSymbolsOffsetLocal : state.local? 11 =
    some (.signed .i32 (Int.ofNat layout.rhsSymbolsOffset))
  productionCell : CellId
  productionOwned : (Assertion.localPointsTo 12 productionCell
    (some (.signed .i32 (Int.ofNat production)))).holds state
  productionSeparate : CellSet.Disjoint
    (localBindingFrameFootprint state
      parserGrammarProductionProtectedBindings)
    (CellSet.singleton productionCell)
  productionNotGrammar : productionCell ≠ grammarCell

theorem GrammarProductionLoopInvariant.condition_true
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell state production)
    (bound : production < grammar.productionCount) :
    Evaluates verifiedParserCore state
      (.binary .less (.local 12) (.local 3)) (.boolean true) state := by
  have productionResult : Evaluates verifiedParserCore state (.local 12)
      (.signed .i32 (Int.ofNat production)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 12 _
      (Assertion.localPointsTo_local 12 invariant.productionCell _ state
        invariant.productionOwned)⟩
  have countResult : Evaluates verifiedParserCore state (.local 3)
      (.signed .i32 (Int.ofNat grammar.productionCount)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 3 _
      invariant.range.productionCountLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) productionResult
    countResult
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt, bound]

theorem GrammarProductionLoopInvariant.condition_false
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell state production)
    (bound : grammar.productionCount ≤ production) :
    Evaluates verifiedParserCore state
      (.binary .less (.local 12) (.local 3)) (.boolean false) state := by
  have productionResult : Evaluates verifiedParserCore state (.local 12)
      (.signed .i32 (Int.ofNat production)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 12 _
      (Assertion.localPointsTo_local 12 invariant.productionCell _ state
        invariant.productionOwned)⟩
  have countResult : Evaluates verifiedParserCore state (.local 3)
      (.signed .i32 (Int.ofNat grammar.productionCount)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 3 _
      invariant.range.productionCountLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) productionResult
    countResult
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt]
  omega

theorem GrammarProductionLoopInvariant.production_local
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell state production) :
    Evaluates verifiedParserCore state (.local 12)
      (.signed .i32 (Int.ofNat production)) state :=
  ⟨1, evalLocal_of_local 1 verifiedParserCore state 12 _
    (Assertion.localPointsTo_local 12 invariant.productionCell _ state
      invariant.productionOwned)⟩

theorem GrammarProductionLoopInvariant.read_production_lhs
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell state production)
    (bound : production < grammar.productionCount) :
    Evaluates verifiedParserCore state
      (.index (.local 0) (.binary .add (.local 8) (.local 12)))
      (.signed .i32 (Int.ofNat
        (grammar.productionLhs.get ⟨production, by simpa using bound⟩)))
      state := by
  have rowBound : production < grammar.productionLhs.length := by
    simpa using bound
  have read := evaluatesParserDirectTableRead words grammarCell
    layout.productionLhsOffset production
    (invariant.range.validation.encoded.productionLhs.row_in_bounds rowBound)
    invariant.range.validation.wordsI32 state
    invariant.range.validation.grammarLocal (.local 8) (.local 12)
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 8 _
      invariant.productionLhsOffsetLocal⟩
    invariant.production_local invariant.range.validation.grammarBacking
  have physical := invariant.range.validation.encoded.productionLhs.get rowBound
  rw [physical] at read
  exact read

theorem GrammarProductionLoopInvariant.read_rhs_offset
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell state production)
    (bound : production < grammar.productionCount) :
    Evaluates verifiedParserCore state
      (.index (.local 0) (.binary .add (.local 9) (.local 12)))
      (.signed .i32 (Int.ofNat
        (grammar.rhsOffsets.get ⟨production, by simpa using bound⟩)))
      state := by
  have rowBound : production < grammar.rhsOffsets.length := by
    simpa using bound
  have read := evaluatesParserDirectTableRead words grammarCell
    layout.rhsOffsetsOffset production
    (invariant.range.validation.encoded.rhsOffsets.row_in_bounds rowBound)
    invariant.range.validation.wordsI32 state
    invariant.range.validation.grammarLocal (.local 9) (.local 12)
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 9 _
      invariant.rhsOffsetsOffsetLocal⟩
    invariant.production_local invariant.range.validation.grammarBacking
  have physical := invariant.range.validation.encoded.rhsOffsets.get rowBound
  rw [physical] at read
  exact read

theorem GrammarProductionLoopInvariant.read_rhs_length
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell state production)
    (bound : production < grammar.productionCount) :
    Evaluates verifiedParserCore state
      (.index (.local 0) (.binary .add (.local 10) (.local 12)))
      (.signed .i32 (Int.ofNat
        (grammar.rhsLengths.get ⟨production, by simpa using bound⟩)))
      state := by
  have rowBound : production < grammar.rhsLengths.length := by
    simpa using bound
  have read := evaluatesParserDirectTableRead words grammarCell
    layout.rhsLengthsOffset production
    (invariant.range.validation.encoded.rhsLengths.row_in_bounds rowBound)
    invariant.range.validation.wordsI32 state
    invariant.range.validation.grammarLocal (.local 10) (.local 12)
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 10 _
      invariant.rhsLengthsOffsetLocal⟩
    invariant.production_local invariant.range.validation.grammarBacking
  have physical := invariant.range.validation.encoded.rhsLengths.get rowBound
  rw [physical] at read
  exact read

def parserGrammarProductionRowState
    (state : State) (lhs rhsOffset rhsLength : Nat) : State :=
  state.bindLocals [
    (13, .signed .i32 (Int.ofNat lhs)),
    (14, .signed .i32 (Int.ofNat rhsOffset)),
    (15, .signed .i32 (Int.ofNat rhsLength))]

structure GrammarProductionRowInvariant
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (state : State) (production lhs rhsOffset rhsLength : Nat) where
  loop : GrammarProductionLoopInvariant layout grammar words grammarCell
    state production
  lhsLocal : state.local? 13 = some (.signed .i32 (Int.ofNat lhs))
  rhsOffsetLocal : state.local? 14 =
    some (.signed .i32 (Int.ofNat rhsOffset))
  rhsLengthLocal : state.local? 15 =
    some (.signed .i32 (Int.ofNat rhsLength))

theorem GrammarProductionRowInvariant.invalid_guard_evaluates_false
    (invariant : GrammarProductionRowInvariant layout grammar words
      grammarCell state production lhs rhsOffset rhsLength)
    (lhsBound : lhs < grammar.grammar.n_nonterminals)
    (rhsRange : rhsOffset + rhsLength ≤ grammar.rhsSymbols.length) :
    Evaluates verifiedParserCore state parserGrammarProductionInvalidExpr
      (.boolean false) state := by
  have zero : Evaluates verifiedParserCore state (.value (.signed .i32 0))
      (.signed .i32 0) state := ⟨1, rfl⟩
  have lhsResult : Evaluates verifiedParserCore state (.local 13)
      (.signed .i32 (Int.ofNat lhs)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 13 _
      invariant.lhsLocal⟩
  have offsetResult : Evaluates verifiedParserCore state (.local 14)
      (.signed .i32 (Int.ofNat rhsOffset)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 14 _
      invariant.rhsOffsetLocal⟩
  have lengthResult : Evaluates verifiedParserCore state (.local 15)
      (.signed .i32 (Int.ofNat rhsLength)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 15 _
      invariant.rhsLengthLocal⟩
  have nonterminalResult : Evaluates verifiedParserCore state (.local 4)
      (.signed .i32 (Int.ofNat grammar.grammar.n_nonterminals)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 4 _
      invariant.loop.range.nonterminalCountLocal⟩
  have symbolCountResult : Evaluates verifiedParserCore state (.local 6)
      (.signed .i32 (Int.ofNat grammar.rhsSymbols.length)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 6 _
      invariant.loop.range.rhsSymbolCountLocal⟩
  have lhsNonnegative : Evaluates verifiedParserCore state
      (.binary .less (.local 13) (.value (.signed .i32 0)))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) lhsResult zero
    simp [evalBinaryValue, evalSignedBinary]
  have lhsValid : Evaluates verifiedParserCore state
      (.binary .greaterEqual (.local 13) (.local 4))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) lhsResult
      nonterminalResult
    simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt, lhsBound]
  have offsetNonnegative : Evaluates verifiedParserCore state
      (.binary .less (.local 14) (.value (.signed .i32 0)))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) offsetResult zero
    simp [evalBinaryValue, evalSignedBinary]
  have lengthNonnegative : Evaluates verifiedParserCore state
      (.binary .less (.local 15) (.value (.signed .i32 0)))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) lengthResult zero
    simp [evalBinaryValue, evalSignedBinary]
  have offsetBound : rhsOffset ≤ grammar.rhsSymbols.length := by omega
  have offsetValid : Evaluates verifiedParserCore state
      (.binary .greater (.local 14) (.local 6))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) offsetResult
      symbolCountResult
    simp [evalBinaryValue, evalSignedBinary, Int.ofNat_le, offsetBound]
  have countFits : grammar.rhsSymbols.length ≤ words.length := by
    have range := (invariant.loop.range.validation.encoded.validation_facts
      invariant.loop.range.validation.grammarWellFormed).prelude.rhsSymbolsRange
    rcases range with ⟨_, fits⟩
    omega
  have remainingBound : grammar.rhsSymbols.length - rhsOffset ≤
      2147483647 :=
    Nat.le_trans (Nat.le_trans (Nat.sub_le _ _) countFits)
      invariant.loop.range.validation.wordsI32
  have remainingResult : Evaluates verifiedParserCore state
      (.binary .subtract (.local 6) (.local 14))
      (.signed .i32
        (Int.ofNat (grammar.rhsSymbols.length - rhsOffset))) state := by
    apply evaluatesEagerBinary (by decide) (by decide) symbolCountResult
      offsetResult
    simp only [evalBinaryValue, evalSignedBinary]
    simp only [show (SignedIntTy.i32 == SignedIntTy.i32) = true by decide,
      if_true]
    have normalized : wrapSigned verifiedParserCore.target .i32
        (Int.ofNat grammar.rhsSymbols.length - Int.ofNat rhsOffset) =
        Int.ofNat (grammar.rhsSymbols.length - rhsOffset) := by
      calc
        _ = wrapSigned verifiedParserCore.target .i32
              (Int.ofNat (grammar.rhsSymbols.length - rhsOffset)) :=
          congrArg (wrapSigned verifiedParserCore.target .i32)
            (Int.ofNat_sub offsetBound).symm
        _ = _ := wrapSigned_i32_ofNat verifiedParserCore.target _
          remainingBound
    exact congrArg
      (fun value =>
        (Except.ok (.signed .i32 value) : Except Trap Value)) normalized
  have lengthValid : Evaluates verifiedParserCore state
      (.binary .greater (.local 15)
        (.binary .subtract (.local 6) (.local 14)))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) lengthResult
      remainingResult
    simp [evalBinaryValue, evalSignedBinary, Int.ofNat_le]
    omega
  have firstTwo := evaluatesPureLogicalOr lhsNonnegative lhsValid
  have firstThree := evaluatesPureLogicalOr firstTwo offsetNonnegative
  have firstFour := evaluatesPureLogicalOr firstThree lengthNonnegative
  have firstFive := evaluatesPureLogicalOr firstFour offsetValid
  simpa [parserGrammarProductionInvalidExpr] using
    evaluatesPureLogicalOr firstFive lengthValid

theorem GrammarProductionRowInvariant.invalid_guard_executes
    (invariant : GrammarProductionRowInvariant layout grammar words
      grammarCell state production lhs rhsOffset rhsLength)
    (lhsBound : lhs < grammar.grammar.n_nonterminals)
    (rhsRange : rhsOffset + rhsLength ≤ grammar.rhsSymbols.length) :
    Executes verifiedParserCore state parserGrammarProductionInvalidGuard
      .next state :=
  executesIfFalse (invariant.invalid_guard_evaluates_false lhsBound rhsRange)
    (executesSkip verifiedParserCore state)

def GrammarProductionLoopInvariant.after_counter_effect
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell before production)
    (effect : ModifiesOnly (CellSet.singleton invariant.productionCell)
      before after)
    (afterWellFormed : StateWellFormed after)
    (afterOwned : (Assertion.localPointsTo 12 invariant.productionCell
      (some (.signed .i32 (Int.ofNat nextProduction)))).holds after) :
    GrammarProductionLoopInvariant layout grammar words grammarCell after
      nextProduction := by
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        parserGrammarProductionProtectedBindings)
      (CellSet.singleton invariant.productionCell) :=
    invariant.productionSeparate
  have preserve (id : VarId)
      (member : id ∈ parserGrammarProductionProtectedIds) (value : Value)
      (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint
      invariant.range.validation.stateWellFormed frameDisjoint member found
  have grammarBacking : after.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values words))
    } := by
    apply effect.preserves_entry invariant.range.validation.stateWellFormed
      invariant.range.validation.grammarBacking
    intro written
    exact invariant.productionNotGrammar written.symm
  refine {
    range := {
      validation := {
        encoded := invariant.range.validation.encoded
        grammarWellFormed := invariant.range.validation.grammarWellFormed
        wordsI32 := invariant.range.validation.wordsI32
        stateWellFormed := afterWellFormed
        grammarLocal := preserve 0 (by simp)
          (parserGrammarValue words grammarCell)
          invariant.range.validation.grammarLocal
        grammarLengthLocal := preserve 1 (by simp)
          (.signed .i32 (Int.ofNat words.length))
          invariant.range.validation.grammarLengthLocal
        grammarBacking := grammarBacking }
      kindCountLocal := preserve 2 (by simp) _
        invariant.range.kindCountLocal
      productionCountLocal := preserve 3 (by simp) _
        invariant.range.productionCountLocal
      nonterminalCountLocal := preserve 4 (by simp) _
        invariant.range.nonterminalCountLocal
      startNonterminalLocal := preserve 5 (by simp) _
        invariant.range.startNonterminalLocal
      rhsSymbolCountLocal := preserve 6 (by simp) _
        invariant.range.rhsSymbolCountLocal
      lhsProductionCountLocal := preserve 7 (by simp) _
        invariant.range.lhsProductionCountLocal }
    productionLhsOffsetLocal := preserve 8 (by simp) _
      invariant.productionLhsOffsetLocal
    rhsOffsetsOffsetLocal := preserve 9 (by simp) _
      invariant.rhsOffsetsOffsetLocal
    rhsLengthsOffsetLocal := preserve 10 (by simp) _
      invariant.rhsLengthsOffsetLocal
    rhsSymbolsOffsetLocal := preserve 11 (by simp) _
      invariant.rhsSymbolsOffsetLocal
    productionCell := invariant.productionCell
    productionOwned := afterOwned
    productionSeparate := by
      rw [effect.localBindingFrameFootprint_eq
        parserGrammarProductionProtectedBindings]
      exact invariant.productionSeparate
    productionNotGrammar := invariant.productionNotGrammar }

def GrammarProductionLoopInvariant.after_foreign_effect
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell before production)
    (written : CellId)
    (effect : ModifiesOnly (CellSet.singleton written) before after)
    (afterWellFormed : StateWellFormed after)
    (frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        parserGrammarProductionProtectedBindings)
      (CellSet.singleton written))
    (notGrammar : written ≠ grammarCell)
    (notProduction : written ≠ invariant.productionCell) :
    GrammarProductionLoopInvariant layout grammar words grammarCell after
      production := by
  have preserve (id : VarId)
      (member : id ∈ parserGrammarProductionProtectedIds) (value : Value)
      (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint
      invariant.range.validation.stateWellFormed frameDisjoint member found
  have preserveEntry (cell : CellId) (different : cell ≠ written)
      (value : Option Value)
      (found : before.cellEntry? cell = some { id := cell, value := value }) :
      after.cellEntry? cell = some { id := cell, value := value } := by
    have old := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant.range.validation.stateWellFormed found
    exact (effect.oldCells cell old different).trans found
  refine {
    range := {
      validation := {
        encoded := invariant.range.validation.encoded
        grammarWellFormed := invariant.range.validation.grammarWellFormed
        wordsI32 := invariant.range.validation.wordsI32
        stateWellFormed := afterWellFormed
        grammarLocal := preserve 0 (by simp) _
          invariant.range.validation.grammarLocal
        grammarLengthLocal := preserve 1 (by simp) _
          invariant.range.validation.grammarLengthLocal
        grammarBacking := preserveEntry grammarCell notGrammar.symm _
          invariant.range.validation.grammarBacking }
      kindCountLocal := preserve 2 (by simp) _
        invariant.range.kindCountLocal
      productionCountLocal := preserve 3 (by simp) _
        invariant.range.productionCountLocal
      nonterminalCountLocal := preserve 4 (by simp) _
        invariant.range.nonterminalCountLocal
      startNonterminalLocal := preserve 5 (by simp) _
        invariant.range.startNonterminalLocal
      rhsSymbolCountLocal := preserve 6 (by simp) _
        invariant.range.rhsSymbolCountLocal
      lhsProductionCountLocal := preserve 7 (by simp) _
        invariant.range.lhsProductionCountLocal }
    productionLhsOffsetLocal := preserve 8 (by simp) _
      invariant.productionLhsOffsetLocal
    rhsOffsetsOffsetLocal := preserve 9 (by simp) _
      invariant.rhsOffsetsOffsetLocal
    rhsLengthsOffsetLocal := preserve 10 (by simp) _
      invariant.rhsLengthsOffsetLocal
    rhsSymbolsOffsetLocal := preserve 11 (by simp) _
      invariant.rhsSymbolsOffsetLocal
    productionCell := invariant.productionCell
    productionOwned := ?_
    productionSeparate := by
      rw [effect.localBindingFrameFootprint_eq
        parserGrammarProductionProtectedBindings]
      exact invariant.productionSeparate
    productionNotGrammar := invariant.productionNotGrammar }
  · constructor
    · have beforeCell := invariant.productionOwned.1
      unfold State.cellId? at beforeCell ⊢
      rw [effect.locals]
      exact beforeCell
    · exact preserveEntry invariant.productionCell notProduction.symm _
        invariant.productionOwned.2

def GrammarProductionLoopInvariant.after_temporary_bind
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell state production)
    (id : VarId) (value : Value) (temporary : 12 < id) :
    GrammarProductionLoopInvariant layout grammar words grammarCell
      (state.bindLocal id value) production := by
  have idNe (fixed : Nat) (bound : fixed ≤ 12) : id ≠ fixed := by
    intro same
    rw [same] at temporary
    exact (Nat.not_lt_of_ge bound) temporary
  have afterWellFormed := bindLocal_preserves_well_formed state id value
    invariant.range.validation.stateWellFormed
  have rangeAfter := invariant.range.after_bind_local id value
    (idNe 0 (by decide)) (idNe 1 (by decide))
    (idNe 2 (by decide)) (idNe 3 (by decide))
    (idNe 4 (by decide)) (idNe 5 (by decide))
    (idNe 6 (by decide)) (idNe 7 (by decide))
  have counterOld : invariant.productionCell < state.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant.range.validation.stateWellFormed invariant.productionOwned.2
  refine {
    range := rangeAfter
    productionLhsOffsetLocal :=
      (bindLocal_preserves_other_local
        invariant.range.validation.stateWellFormed
          (idNe 8 (by decide))).trans
        invariant.productionLhsOffsetLocal
    rhsOffsetsOffsetLocal :=
      (bindLocal_preserves_other_local
        invariant.range.validation.stateWellFormed
          (idNe 9 (by decide))).trans
        invariant.rhsOffsetsOffsetLocal
    rhsLengthsOffsetLocal :=
      (bindLocal_preserves_other_local
        invariant.range.validation.stateWellFormed
          (idNe 10 (by decide))).trans
        invariant.rhsLengthsOffsetLocal
    rhsSymbolsOffsetLocal :=
      (bindLocal_preserves_other_local
        invariant.range.validation.stateWellFormed
          (idNe 11 (by decide))).trans
        invariant.rhsSymbolsOffsetLocal
    productionCell := invariant.productionCell
    productionOwned := ?_
    productionSeparate := ?_
    productionNotGrammar := invariant.productionNotGrammar }
  · constructor
    · simpa [State.bindLocal, State.bindCell, State.cellId?,
        idNe 12 (by decide)]
        using invariant.productionOwned.1
    · exact (bindCell_preserves_old_cell state id (some value)
        invariant.productionCell counterOld).trans invariant.productionOwned.2
  · intro cell framed written
    obtain ⟨queried, bound, same⟩ := framed
    subst cell
    apply invariant.productionSeparate.localCell_ne_of_singleton bound
    have queriedLt : queried < 12 :=
      mem_parserGrammarProductionProtectedIds_iff queried |>.1 bound
    have different : id ≠ queried := by
      intro equal
      rw [equal] at temporary
      exact (Nat.not_lt_of_ge (Nat.le_of_lt queriedLt)) temporary
    simpa [State.bindLocal, State.bindCell, State.cellId?, different] using same

noncomputable def GrammarProductionLoopInvariant.bind_row
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell state production)
    (lhs rhsOffset rhsLength : Nat) :
    GrammarProductionRowInvariant layout grammar words grammarCell
      (parserGrammarProductionRowState state lhs rhsOffset rhsLength)
      production lhs rhsOffset rhsLength := by
  let lhsValue : Value := .signed .i32 (Int.ofNat lhs)
  let offsetValue : Value := .signed .i32 (Int.ofNat rhsOffset)
  let lengthValue : Value := .signed .i32 (Int.ofNat rhsLength)
  let state13 := state.bindLocal 13 lhsValue
  let invariant13 := invariant.after_temporary_bind 13 lhsValue (by decide)
  let state14 := state13.bindLocal 14 offsetValue
  let invariant14 := invariant13.after_temporary_bind 14 offsetValue (by decide)
  let state15 := state14.bindLocal 15 lengthValue
  let invariant15 := invariant14.after_temporary_bind 15 lengthValue (by decide)
  have finalState : state15 =
      parserGrammarProductionRowState state lhs rhsOffset rhsLength := by
    rfl
  refine {
    loop := by rw [← finalState]; exact invariant15
    lhsLocal := ?_
    rhsOffsetLocal := ?_
    rhsLengthLocal := ?_ }
  · simpa [parserGrammarProductionRowState, lhsValue, offsetValue,
      lengthValue] using
      bindLocals_local_of_binding state [] [
        (14, offsetValue), (15, lengthValue)] 13 lhsValue
        invariant.range.validation.stateWellFormed (by simp)
  · simpa [parserGrammarProductionRowState, lhsValue, offsetValue,
      lengthValue] using
      bindLocals_local_of_binding state [(13, lhsValue)] [
        (15, lengthValue)] 14 offsetValue
        invariant.range.validation.stateWellFormed (by simp)
  · simpa [parserGrammarProductionRowState, lhsValue, offsetValue,
      lengthValue] using
      bindLocals_local_of_binding state [
        (13, lhsValue), (14, offsetValue)] [] 15 lengthValue
        invariant.range.validation.stateWellFormed (by simp)

def GrammarProductionRowInvariant.after_temporary_bind
    (invariant : GrammarProductionRowInvariant layout grammar words
      grammarCell state production lhs rhsOffset rhsLength)
    (id : VarId) (value : Value) (temporary : 15 < id) :
    GrammarProductionRowInvariant layout grammar words grammarCell
      (state.bindLocal id value) production lhs rhsOffset rhsLength := by
  have different (fixed : Nat) (bound : fixed ≤ 15) : id ≠ fixed := by
    intro same
    rw [same] at temporary
    exact (Nat.not_lt_of_ge bound) temporary
  exact {
    loop := invariant.loop.after_temporary_bind id value
      (Nat.lt_trans (by decide) temporary)
    lhsLocal :=
      (bindLocal_preserves_other_local
        invariant.loop.range.validation.stateWellFormed
        (different 13 (by decide))).trans invariant.lhsLocal
    rhsOffsetLocal :=
      (bindLocal_preserves_other_local
        invariant.loop.range.validation.stateWellFormed
        (different 14 (by decide))).trans invariant.rhsOffsetLocal
    rhsLengthLocal :=
      (bindLocal_preserves_other_local
        invariant.loop.range.validation.stateWellFormed
        (different 15 (by decide))).trans invariant.rhsLengthLocal }

structure GrammarSymbolLoopInvariant
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (state : State) (production lhs rhsOffset rhsLength rhsIndex : Nat) where
  row : GrammarProductionRowInvariant layout grammar words grammarCell state
    production lhs rhsOffset rhsLength
  indexCell : CellId
  indexOwned : (Assertion.localPointsTo 16 indexCell
    (some (.signed .i32 (Int.ofNat rhsIndex)))).holds state
  indexFrameSeparate : CellSet.Disjoint
    (localBindingFrameFootprint state parserGrammarSymbolProtectedBindings)
    (CellSet.singleton indexCell)
  indexNotGrammar : indexCell ≠ grammarCell

theorem GrammarSymbolLoopInvariant.indexSeparate
    (invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell
      state production lhs rhsOffset rhsLength rhsIndex)
    (id : VarId) (member : id ∈ parserGrammarSymbolProtectedIds) :
    state.cellId? id ≠ some invariant.indexCell :=
  invariant.indexFrameSeparate.localCell_ne_of_singleton member

noncomputable def GrammarProductionRowInvariant.symbol_loop_entry
    (invariant : GrammarProductionRowInvariant layout grammar words
      grammarCell state production lhs rhsOffset rhsLength) :
    GrammarSymbolLoopInvariant layout grammar words grammarCell
      (state.bindLocal 16 (.signed .i32 0))
      production lhs rhsOffset rhsLength 0 := by
  let zeroValue : Value := .signed .i32 0
  let after := state.bindLocal 16 zeroValue
  let rowAfter := invariant.after_temporary_bind 16 zeroValue (by decide)
  have owned : (Assertion.localPointsTo 16 state.nextCell
      (some zeroValue)).holds after := by
    constructor
    · simp [after, State.bindLocal, State.bindCell, State.cellId?]
    · simpa [after, State.bindLocal] using
        bindCell_finds_fresh_cell state 16 (some zeroValue)
          invariant.loop.range.validation.stateWellFormed
  refine {
    row := rowAfter
    indexCell := state.nextCell
    indexOwned := by simpa [after, zeroValue] using owned
    indexFrameSeparate := ?_
    indexNotGrammar := ?_ }
  · apply localCellFootprint_disjoint_singleton
    intro id member same
    have bound := (mem_parserGrammarSymbolProtectedIds_iff id).mp member
    have different : (16 : VarId) ≠ id := Ne.symm (Nat.ne_of_lt bound)
    have oldCell : state.cellId? id = some state.nextCell := by
      simpa [after, State.bindLocal, State.bindCell, State.cellId?, different]
        using same
    have below :=
      Lanius.Separation.StateWellFormed.cell_lt_next_of_local_binding
        id state.nextCell invariant.loop.range.validation.stateWellFormed
        oldCell
    exact (Nat.lt_irrefl state.nextCell) below
  · intro same
    have below := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant.loop.range.validation.stateWellFormed
      invariant.loop.range.validation.grammarBacking
    rw [← same] at below
    exact (Nat.lt_irrefl state.nextCell) below

theorem GrammarSymbolLoopInvariant.condition_true
    (invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell
      state production lhs rhsOffset rhsLength rhsIndex)
    (bound : rhsIndex < rhsLength) :
    Evaluates verifiedParserCore state
      (.binary .less (.local 16) (.local 15)) (.boolean true) state := by
  have indexResult : Evaluates verifiedParserCore state (.local 16)
      (.signed .i32 (Int.ofNat rhsIndex)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 16 _
      (Assertion.localPointsTo_local 16 invariant.indexCell _ state
        invariant.indexOwned)⟩
  have lengthResult : Evaluates verifiedParserCore state (.local 15)
      (.signed .i32 (Int.ofNat rhsLength)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 15 _
      invariant.row.rhsLengthLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) indexResult lengthResult
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt, bound]

theorem GrammarSymbolLoopInvariant.condition_false
    (invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell
      state production lhs rhsOffset rhsLength rhsIndex)
    (bound : rhsLength ≤ rhsIndex) :
    Evaluates verifiedParserCore state
      (.binary .less (.local 16) (.local 15)) (.boolean false) state := by
  have indexResult : Evaluates verifiedParserCore state (.local 16)
      (.signed .i32 (Int.ofNat rhsIndex)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 16 _
      (Assertion.localPointsTo_local 16 invariant.indexCell _ state
        invariant.indexOwned)⟩
  have lengthResult : Evaluates verifiedParserCore state (.local 15)
      (.signed .i32 (Int.ofNat rhsLength)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 15 _
      invariant.row.rhsLengthLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) indexResult lengthResult
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt]
  omega

theorem GrammarSymbolLoopInvariant.read_symbol
    (invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell
      state production lhs rhsOffset rhsLength rhsIndex)
    (rowRange : rhsOffset + rhsLength ≤ grammar.rhsSymbols.length)
    (indexBound : rhsIndex < rhsLength) :
    Evaluates verifiedParserCore state
      (.index (.local 0)
        (.binary .add
          (.binary .add (.local 11) (.local 14))
          (.local 16)))
      (.signed .i32 (Int.ofNat
        (grammar.rhsSymbols.get
          ⟨rhsOffset + rhsIndex, by omega⟩))) state := by
  have rowBound : rhsOffset + rhsIndex < grammar.rhsSymbols.length := by
    omega
  have physicalBound :=
    invariant.row.loop.range.validation.encoded.rhsSymbols.row_in_bounds
      rowBound
  have physicalBound' :
      layout.rhsSymbolsOffset + rhsOffset + rhsIndex < words.length := by
    simpa [Nat.add_assoc] using physicalBound
  have grammarResult : Evaluates verifiedParserCore state (.local 0)
      (parserGrammarValue words grammarCell) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 0 _
      invariant.row.loop.range.validation.grammarLocal⟩
  have symbolsOffsetResult : Evaluates verifiedParserCore state (.local 11)
      (.signed .i32 (Int.ofNat layout.rhsSymbolsOffset)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 11 _
      invariant.row.loop.rhsSymbolsOffsetLocal⟩
  have rhsOffsetResult : Evaluates verifiedParserCore state (.local 14)
      (.signed .i32 (Int.ofNat rhsOffset)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 14 _
      invariant.row.rhsOffsetLocal⟩
  have indexResult : Evaluates verifiedParserCore state (.local 16)
      (.signed .i32 (Int.ofNat rhsIndex)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 16 _
      (Assertion.localPointsTo_local 16 invariant.indexCell _ state
        invariant.indexOwned)⟩
  have partialBound : layout.rhsSymbolsOffset + rhsOffset ≤ 2147483647 :=
    Nat.le_trans (Nat.le_of_lt (Nat.lt_of_le_of_lt
      (Nat.le_add_right _ _) physicalBound'))
      invariant.row.loop.range.validation.wordsI32
  have partialResult : Evaluates verifiedParserCore state
      (.binary .add (.local 11) (.local 14))
      (.signed .i32 (Int.ofNat (layout.rhsSymbolsOffset + rhsOffset)))
      state := by
    have castAddress : Int.ofNat layout.rhsSymbolsOffset +
        Int.ofNat rhsOffset =
        Int.ofNat (layout.rhsSymbolsOffset + rhsOffset) :=
      (Int.natCast_add layout.rhsSymbolsOffset rhsOffset).symm
    have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target _
      partialBound
    apply evaluatesEagerBinary (by decide) (by decide) symbolsOffsetResult
      rhsOffsetResult
    simp only [evalBinaryValue, evalSignedBinary]
    rw [castAddress, wrapped]
    simp
  have addressBound : layout.rhsSymbolsOffset + rhsOffset + rhsIndex ≤
      2147483647 :=
    Nat.le_trans (Nat.le_of_lt physicalBound')
      invariant.row.loop.range.validation.wordsI32
  have addressResult : Evaluates verifiedParserCore state
      (.binary .add
        (.binary .add (.local 11) (.local 14))
        (.local 16))
      (.signed .i32
        (Int.ofNat (layout.rhsSymbolsOffset + rhsOffset + rhsIndex)))
      state := by
    have castAddress : Int.ofNat (layout.rhsSymbolsOffset + rhsOffset) +
        Int.ofNat rhsIndex =
        Int.ofNat (layout.rhsSymbolsOffset + rhsOffset + rhsIndex) :=
      (Int.natCast_add (layout.rhsSymbolsOffset + rhsOffset) rhsIndex).symm
    have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target _
      addressBound
    apply evaluatesEagerBinary (by decide) (by decide) partialResult indexResult
    simp only [evalBinaryValue, evalSignedBinary]
    rw [castAddress, wrapped]
    simp
  have read := evaluatesSignedI32SliceIndex verifiedParserCore state state state
    words (.local 0)
    (.binary .add
      (.binary .add (.local 11) (.local 14))
      (.local 16)) grammarCell
    (layout.rhsSymbolsOffset + rhsOffset + rhsIndex) physicalBound'
    grammarResult addressResult
    invariant.row.loop.range.validation.grammarBacking
  have physical :=
    invariant.row.loop.range.validation.encoded.rhsSymbols.get rowBound
  have physical' : words.get
      ⟨layout.rhsSymbolsOffset + rhsOffset + rhsIndex, physicalBound'⟩ =
      Int.ofNat (grammar.rhsSymbols.get ⟨rhsOffset + rhsIndex, rowBound⟩) := by
    simpa [Nat.add_assoc] using physical
  rw [physical'] at read
  exact read

def GrammarSymbolLoopInvariant.after_temporary_bind
    (invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell
      state production lhs rhsOffset rhsLength rhsIndex)
    (id : VarId) (value : Value) (temporary : 16 < id) :
    GrammarSymbolLoopInvariant layout grammar words grammarCell
      (state.bindLocal id value) production lhs rhsOffset rhsLength rhsIndex := by
  have different (fixed : Nat) (bound : fixed ≤ 16) : id ≠ fixed := by
    intro same
    rw [same] at temporary
    exact (Nat.not_lt_of_ge bound) temporary
  have indexOld : invariant.indexCell < state.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant.row.loop.range.validation.stateWellFormed
      invariant.indexOwned.2
  refine {
    row := invariant.row.after_temporary_bind id value
      (Nat.lt_trans (by decide) temporary)
    indexCell := invariant.indexCell
    indexOwned := ?_
    indexFrameSeparate := ?_
    indexNotGrammar := invariant.indexNotGrammar }
  · constructor
    · simpa [State.bindLocal, State.bindCell, State.cellId?,
        different 16 (by decide)] using invariant.indexOwned.1
    · exact (bindCell_preserves_old_cell state id (some value)
        invariant.indexCell indexOld).trans invariant.indexOwned.2
  · intro cell framed written
    obtain ⟨queried, member, cellId⟩ := framed
    have bound := (mem_parserGrammarSymbolProtectedIds_iff queried).mp member
    have notQueried : id ≠ queried := by
      intro equal
      rw [equal] at temporary
      exact (Nat.not_lt_of_ge (Nat.le_of_lt bound)) temporary
    apply invariant.indexFrameSeparate cell
    · exact ⟨queried, member, by
        simpa [State.bindLocal, State.bindCell, State.cellId?, notQueried]
          using cellId⟩
    · exact written

@[simp] theorem GrammarSymbolLoopInvariant.after_temporary_bind_indexCell
    (invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell
      state production lhs rhsOffset rhsLength rhsIndex)
    (id : VarId) (value : Value) (temporary : 16 < id) :
    (invariant.after_temporary_bind id value temporary).indexCell =
      invariant.indexCell := by
  rfl

theorem GrammarSymbolLoopInvariant.symbol_guard_evaluates_false
    (invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell
      state production lhs rhsOffset rhsLength rhsIndex)
    (symbol : Nat)
    (symbolLocal : state.local? 17 =
      some (.signed .i32 (Int.ofNat symbol)))
    (symbolBound : symbol <
      grammar.grammar.n_kinds + grammar.grammar.n_nonterminals) :
    Evaluates verifiedParserCore state parserGrammarSymbolInvalidExpr
      (.boolean false) state := by
  have zero : Evaluates verifiedParserCore state (.value (.signed .i32 0))
      (.signed .i32 0) state := ⟨1, rfl⟩
  have symbolResult : Evaluates verifiedParserCore state (.local 17)
      (.signed .i32 (Int.ofNat symbol)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 17 _ symbolLocal⟩
  have kindResult : Evaluates verifiedParserCore state (.local 2)
      (.signed .i32 (Int.ofNat grammar.grammar.n_kinds)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 2 _
      invariant.row.loop.range.kindCountLocal⟩
  have nonterminalResult : Evaluates verifiedParserCore state (.local 4)
      (.signed .i32 (Int.ofNat grammar.grammar.n_nonterminals)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 4 _
      invariant.row.loop.range.nonterminalCountLocal⟩
  have nonnegative : Evaluates verifiedParserCore state
      (.binary .less (.local 17) (.value (.signed .i32 0)))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) symbolResult zero
    simp [evalBinaryValue, evalSignedBinary]
  have domainBound := (invariant.row.loop.range.validation.encoded.validation_facts
    invariant.row.loop.range.validation.grammarWellFormed).prelude.symbolDomainFitsI32
  have domainResult : Evaluates verifiedParserCore state
      (.binary .add (.local 2) (.local 4))
      (.signed .i32 (Int.ofNat
        (grammar.grammar.n_kinds + grammar.grammar.n_nonterminals))) state := by
    have castDomain : Int.ofNat grammar.grammar.n_kinds +
        Int.ofNat grammar.grammar.n_nonterminals =
        Int.ofNat
          (grammar.grammar.n_kinds + grammar.grammar.n_nonterminals) :=
      (Int.natCast_add _ _).symm
    have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target _ domainBound
    apply evaluatesEagerBinary (by decide) (by decide) kindResult
      nonterminalResult
    simp only [evalBinaryValue, evalSignedBinary]
    rw [castDomain, wrapped]
    simp
  have upper : Evaluates verifiedParserCore state
      (.binary .greaterEqual (.local 17)
        (.binary .add (.local 2) (.local 4)))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) symbolResult domainResult
    simp [evalBinaryValue, evalSignedBinary]
    have bound : Int.ofNat symbol < Int.ofNat
        (grammar.grammar.n_kinds + grammar.grammar.n_nonterminals) :=
      Int.ofNat_lt.mpr symbolBound
    simpa using bound
  simpa [parserGrammarSymbolInvalidExpr] using
    evaluatesPureLogicalOr nonnegative upper

theorem GrammarSymbolLoopInvariant.symbol_guard_executes
    (invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell
      state production lhs rhsOffset rhsLength rhsIndex)
    (symbol : Nat)
    (symbolLocal : state.local? 17 =
      some (.signed .i32 (Int.ofNat symbol)))
    (symbolBound : symbol <
      grammar.grammar.n_kinds + grammar.grammar.n_nonterminals) :
    Executes verifiedParserCore state parserGrammarSymbolInvalidGuard
      .next state :=
  executesIfFalse
    (invariant.symbol_guard_evaluates_false symbol symbolLocal symbolBound)
    (executesSkip verifiedParserCore state)

def GrammarSymbolLoopInvariant.after_index_effect
    (invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell
      before production lhs rhsOffset rhsLength rhsIndex)
    (effect : ModifiesOnly (CellSet.singleton invariant.indexCell) before after)
    (afterWellFormed : StateWellFormed after)
    (afterOwned : (Assertion.localPointsTo 16 invariant.indexCell
      (some (.signed .i32 (Int.ofNat nextIndex)))).holds after) :
    GrammarSymbolLoopInvariant layout grammar words grammarCell after
      production lhs rhsOffset rhsLength nextIndex := by
  have notProduction : invariant.indexCell ≠
      invariant.row.loop.productionCell := by
    intro same
    apply invariant.indexSeparate 12 (by
      simp [parserGrammarSymbolProtectedIds])
    rw [same]
    exact invariant.row.loop.productionOwned.1
  have loopAfter := invariant.row.loop.after_foreign_effect
    invariant.indexCell effect afterWellFormed
    (CellSet.Disjoint.mono_left
      (localBindingFrameFootprint_mono (fun id member => by
        exact parserGrammarProductionProtectedIds_subset_symbol member))
      invariant.indexFrameSeparate)
    invariant.indexNotGrammar notProduction
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        parserGrammarSymbolProtectedBindings)
      (CellSet.singleton invariant.indexCell) :=
    invariant.indexFrameSeparate
  have preserve (id : VarId)
      (member : id ∈ parserGrammarSymbolProtectedIds) (value : Value)
      (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint
      invariant.row.loop.range.validation.stateWellFormed frameDisjoint member
      found
  refine {
    row := {
      loop := loopAfter
      lhsLocal := preserve 13 (by
        simp [parserGrammarSymbolProtectedIds]) _ invariant.row.lhsLocal
      rhsOffsetLocal := preserve 14 (by
        simp [parserGrammarSymbolProtectedIds]) _ invariant.row.rhsOffsetLocal
      rhsLengthLocal := preserve 15 (by
        simp [parserGrammarSymbolProtectedIds]) _ invariant.row.rhsLengthLocal }
    indexCell := invariant.indexCell
    indexOwned := afterOwned
    indexFrameSeparate := ?_
    indexNotGrammar := invariant.indexNotGrammar }
  rw [effect.localBindingFrameFootprint_eq
    parserGrammarSymbolProtectedBindings]
  exact invariant.indexFrameSeparate

@[simp] theorem GrammarProductionLoopInvariant.after_foreign_effect_productionCell
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell before production)
    (written : CellId)
    (effect : ModifiesOnly (CellSet.singleton written) before after)
    (afterWellFormed : StateWellFormed after)
    (frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        parserGrammarProductionProtectedBindings)
      (CellSet.singleton written))
    (notGrammar : written ≠ grammarCell)
    (notProduction : written ≠ invariant.productionCell) :
    (invariant.after_foreign_effect written effect afterWellFormed frameDisjoint
      notGrammar notProduction).productionCell = invariant.productionCell := by
  rfl

@[simp] theorem GrammarSymbolLoopInvariant.after_index_effect_indexCell
    (invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell
      before production lhs rhsOffset rhsLength rhsIndex)
    (effect : ModifiesOnly (CellSet.singleton invariant.indexCell) before after)
    (afterWellFormed : StateWellFormed after)
    (afterOwned : (Assertion.localPointsTo 16 invariant.indexCell
      (some (.signed .i32 (Int.ofNat nextIndex)))).holds after) :
    (invariant.after_index_effect effect afterWellFormed afterOwned).indexCell =
      invariant.indexCell := by
  rfl

@[simp] theorem GrammarSymbolLoopInvariant.after_index_effect_productionCell
    (invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell
      before production lhs rhsOffset rhsLength rhsIndex)
    (effect : ModifiesOnly (CellSet.singleton invariant.indexCell) before after)
    (afterWellFormed : StateWellFormed after)
    (afterOwned : (Assertion.localPointsTo 16 invariant.indexCell
      (some (.signed .i32 (Int.ofNat nextIndex)))).holds after) :
    (invariant.after_index_effect effect afterWellFormed
      afterOwned).row.loop.productionCell =
      invariant.row.loop.productionCell := by
  rfl

structure GrammarSymbolIncrement
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (before : State) (production lhs rhsOffset rhsLength rhsIndex : Nat)
    (beforeInvariant : GrammarSymbolLoopInvariant layout grammar words
      grammarCell before production lhs rhsOffset rhsLength rhsIndex) where
  after : State
  execution : Executes verifiedParserCore before (parserIncrementLocal 16)
    .next after
  effect : ModifiesOnly (CellSet.singleton beforeInvariant.indexCell)
    before after
  invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell after
    production lhs rhsOffset rhsLength (rhsIndex + 1)
  indexCell_eq : invariant.indexCell = beforeInvariant.indexCell

noncomputable def GrammarSymbolLoopInvariant.increment
    (invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell
      state production lhs rhsOffset rhsLength rhsIndex)
    (indexBound : rhsIndex < rhsLength)
    (rowRange : rhsOffset + rhsLength ≤ grammar.rhsSymbols.length) :
    GrammarSymbolIncrement layout grammar words grammarCell state production
      lhs rhsOffset rhsLength rhsIndex invariant := by
  have countFits : grammar.rhsSymbols.length ≤ words.length := by
    have range := (invariant.row.loop.range.validation.encoded.validation_facts
      invariant.row.loop.range.validation.grammarWellFormed).prelude.rhsSymbolsRange
    rcases range with ⟨_, fits⟩
    omega
  have incrementBound : rhsIndex + 1 ≤ 2147483647 := by
    exact Nat.le_trans (Nat.le_trans (Nat.succ_le_of_lt indexBound)
      (Nat.le_trans (by omega : rhsLength ≤ grammar.rhsSymbols.length)
        countFits)) invariant.row.loop.range.validation.wordsI32
  have result := executesIncrementOwnedI32Local verifiedParserCore state 16
    invariant.indexCell rhsIndex invariant.row.loop.range.validation.stateWellFormed
    invariant.indexOwned incrementBound
  let after := Classical.choose result
  have facts := Classical.choose_spec result
  exact {
    after := after
    execution := by simpa [parserIncrementLocal] using facts.1
    effect := facts.2.2.2
    invariant := invariant.after_index_effect facts.2.2.2 facts.2.1
      facts.2.2.1
    indexCell_eq := invariant.after_index_effect_indexCell facts.2.2.2
      facts.2.1 facts.2.2.1 }

structure GrammarSymbolLoopExecution
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (before : State) (production lhs rhsOffset rhsLength rhsIndex : Nat)
    (beforeInvariant : GrammarSymbolLoopInvariant layout grammar words
      grammarCell before production lhs rhsOffset rhsLength rhsIndex) where
  after : State
  execution : Executes verifiedParserCore before parserGrammarSymbolLoop
    .next after
  effect : ModifiesOnly (CellSet.singleton beforeInvariant.indexCell)
    before after
  invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell after
    production lhs rhsOffset rhsLength rhsLength
  indexCell_eq : invariant.indexCell = beforeInvariant.indexCell
  productionCell_eq : invariant.row.loop.productionCell =
    beforeInvariant.row.loop.productionCell

noncomputable def GrammarSymbolLoopInvariant.execute_loop
    (invariant : GrammarSymbolLoopInvariant layout grammar words grammarCell
      state production lhs rhsOffset rhsLength rhsIndex)
    (rowRange : rhsOffset + rhsLength ≤ grammar.rhsSymbols.length)
    (indexLe : rhsIndex ≤ rhsLength) :
    GrammarSymbolLoopExecution layout grammar words grammarCell state
      production lhs rhsOffset rhsLength rhsIndex invariant := by
  by_cases done : rhsIndex = rhsLength
  · subst rhsIndex
    exact {
      after := state
      execution := executesWhileFalse (invariant.condition_false (by omega))
      effect := ModifiesOnly.reflAny _ state
      invariant := invariant
      indexCell_eq := rfl
      productionCell_eq := rfl }
  · have indexBound : rhsIndex < rhsLength := by omega
    have rowBound : rhsOffset + rhsIndex < grammar.rhsSymbols.length := by
      omega
    let symbol := grammar.rhsSymbols.get ⟨rhsOffset + rhsIndex, rowBound⟩
    have symbolRead := invariant.read_symbol rowRange indexBound
    let symbolValue : Value := .signed .i32 (Int.ofNat symbol)
    let symbolState := state.bindLocal 17 symbolValue
    let symbolInvariant := invariant.after_temporary_bind 17 symbolValue
      (by decide)
    have symbolLocal : symbolState.local? 17 = some symbolValue := by
      exact bindLocal_finds_local state 17 symbolValue
        invariant.row.loop.range.validation.stateWellFormed
    have symbolBound : symbol <
        grammar.grammar.n_kinds + grammar.grammar.n_nonterminals := by
      have productionFacts :=
        (invariant.row.loop.range.validation.encoded.validation_facts
          invariant.row.loop.range.validation.grammarWellFormed).productions
      exact productionFacts.flattenedSymbolInBounds
        ⟨rhsOffset + rhsIndex, rowBound⟩
    have guardExecution : Executes verifiedParserCore symbolState
        parserGrammarSymbolInvalidGuard .next symbolState := by
      exact symbolInvariant.symbol_guard_executes symbol symbolLocal symbolBound
    let increment := symbolInvariant.increment indexBound rowRange
    have boundBody : Executes verifiedParserCore symbolState
        (.sequence parserGrammarSymbolInvalidGuard (parserIncrementLocal 16))
        .next increment.after :=
      executesSequence guardExecution increment.execution
    have scopedBody : Executes verifiedParserCore state
        parserGrammarSymbolLoopBody .next
        (restoreLocals state increment.after) := by
      simpa [parserGrammarSymbolLoopBody, symbolValue, symbolState, symbol]
        using executesLetLocal (type := parserI32Type) symbolRead boundBody
    let afterIteration := restoreLocals state increment.after
    have entered : StoreEffect (CellSet.singleton invariant.indexCell) state
        symbolState :=
      (bindLocal_effect state 17 symbolValue).weaken CellSet.empty_subset
    have incrementEffect : ModifiesOnly
        (CellSet.singleton invariant.indexCell) symbolState increment.after := by
      simpa [symbolInvariant, symbolState] using increment.effect
    have iterationStore : StoreEffect (CellSet.singleton invariant.indexCell)
        state increment.after := entered.trans_same incrementEffect.toStoreEffect
    have iterationEffect : ModifiesOnly
        (CellSet.singleton invariant.indexCell) state afterIteration := by
      simpa [afterIteration] using iterationStore.restoreLocals
    have afterWellFormed : StateWellFormed afterIteration := by
      exact iterationStore.restoreLocals_wellFormed
        invariant.row.loop.range.validation.stateWellFormed
        increment.invariant.row.loop.range.validation.stateWellFormed
    have afterOwned : (Assertion.localPointsTo 16 invariant.indexCell
        (some (.signed .i32 (Int.ofNat (rhsIndex + 1))))).holds
        afterIteration := by
      constructor
      · change state.cellId? 16 = some invariant.indexCell
        exact invariant.indexOwned.1
      · change increment.after.cellEntry? invariant.indexCell = some {
          id := invariant.indexCell
          value := some (.signed .i32 (Int.ofNat (rhsIndex + 1))) }
        have found := increment.invariant.indexOwned.2
        have cellEq : increment.invariant.indexCell = invariant.indexCell :=
          increment.indexCell_eq.trans (by
            simp [symbolInvariant])
        rw [cellEq] at found
        exact found
    let afterInvariant := invariant.after_index_effect iterationEffect
      afterWellFormed afterOwned
    let rest := afterInvariant.execute_loop rowRange (by omega)
    exact {
      after := rest.after
      execution := executesWhileTrueThen (invariant.condition_true indexBound)
        (by simpa [afterIteration] using scopedBody) rest.execution
      effect := iterationEffect.trans_same rest.effect
      invariant := rest.invariant
      indexCell_eq := rest.indexCell_eq.trans (by
        simp [afterInvariant])
      productionCell_eq := rest.productionCell_eq.trans (by
        simp [afterInvariant]) }
termination_by rhsLength - rhsIndex
decreasing_by omega

structure GrammarProductionIncrement
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (before : State) (production : Nat)
    (beforeInvariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell before production) where
  after : State
  execution : Executes verifiedParserCore before (parserIncrementLocal 12)
    .next after
  effect : ModifiesOnly (CellSet.singleton beforeInvariant.productionCell)
    before after
  invariant : GrammarProductionLoopInvariant layout grammar words grammarCell
    after (production + 1)
  productionCell_eq : invariant.productionCell =
    beforeInvariant.productionCell

noncomputable def GrammarProductionLoopInvariant.increment
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell state production)
    (bound : production < grammar.productionCount) :
    GrammarProductionIncrement layout grammar words grammarCell state
      production invariant := by
  have countFits : grammar.productionCount ≤ words.length := by
    have range := (invariant.range.validation.encoded.validation_facts
      invariant.range.validation.grammarWellFormed).prelude.productionLhsRange
    rcases range with ⟨_, fits⟩
    omega
  have incrementBound : production + 1 ≤ 2147483647 := by
    exact Nat.le_trans (Nat.le_trans (Nat.succ_le_of_lt bound) countFits)
      invariant.range.validation.wordsI32
  have result := executesIncrementOwnedI32Local verifiedParserCore state 12
      invariant.productionCell production
      invariant.range.validation.stateWellFormed invariant.productionOwned
      incrementBound
  let after := Classical.choose result
  have facts := Classical.choose_spec result
  exact {
    after := after
    execution := by simpa [parserIncrementLocal] using facts.1
    effect := facts.2.2.2
    invariant := invariant.after_counter_effect facts.2.2.2 facts.2.1
      facts.2.2.1
    productionCell_eq := rfl }

structure GrammarProductionIteration
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (before : State) (production : Nat)
    (beforeInvariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell before production) where
  after : State
  execution : Executes verifiedParserCore before
    parserGrammarProductionLoopBody .next after
  effect : ModifiesOnly (CellSet.singleton beforeInvariant.productionCell)
    before after
  invariant : GrammarProductionLoopInvariant layout grammar words grammarCell
    after (production + 1)
  productionCell_eq : invariant.productionCell =
    beforeInvariant.productionCell

/-- Execute one exact iteration of the extracted production validator.  The
    three row values and the RHS induction variable are lexical temporaries;
    only the enclosing production counter remains in the visible write set. -/
noncomputable def GrammarProductionLoopInvariant.execute_iteration
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell state production)
    (bound : production < grammar.productionCount) :
    GrammarProductionIteration layout grammar words grammarCell state
      production invariant := by
  let productionId : Fin grammar.productionCount := ⟨production, bound⟩
  let lhs := grammar.productionLhs.get
    ⟨production, by simpa using bound⟩
  let rhsOffset := grammar.rhsOffsets.get
    ⟨production, by simpa using bound⟩
  let rhsLength := grammar.rhsLengths.get
    ⟨production, by simpa using bound⟩
  let lhsValue : Value := .signed .i32 (Int.ofNat lhs)
  let offsetValue : Value := .signed .i32 (Int.ofNat rhsOffset)
  let lengthValue : Value := .signed .i32 (Int.ofNat rhsLength)
  let zeroValue : Value := .signed .i32 0
  let state13 := state.bindLocal 13 lhsValue
  let invariant13 := invariant.after_temporary_bind 13 lhsValue (by decide)
  let state14 := state13.bindLocal 14 offsetValue
  let invariant14 := invariant13.after_temporary_bind 14 offsetValue (by decide)
  let state15 := state14.bindLocal 15 lengthValue
  let rowInvariant := invariant.bind_row lhs rhsOffset rhsLength
  have rowState : state15 =
      parserGrammarProductionRowState state lhs rhsOffset rhsLength := by
    rfl
  have lhsBound : lhs < grammar.grammar.n_nonterminals := by
    have semantic := (invariant.range.validation.encoded.validation_facts
      invariant.range.validation.grammarWellFormed).productions.lhsInBounds
      productionId
    have lhsEq : lhs = (grammar.productionAt productionId).lhs := by
      simpa [lhs, productionId] using
        IndexedGrammar.productionLhs_get grammar productionId
    rw [lhsEq]
    exact semantic
  have rhsRange : rhsOffset + rhsLength ≤ grammar.rhsSymbols.length := by
    have semantic := (invariant.range.validation.encoded.validation_facts
      invariant.range.validation.grammarWellFormed).productions.rhsRange
      productionId
    have lengthEq : rhsLength =
        (grammar.productionAt productionId).rhs.length := by
      simpa [rhsLength, productionId] using
        IndexedGrammar.rhsLengths_get grammar productionId
    rw [lengthEq]
    simpa [rhsOffset, productionId] using semantic
  have lhsInitializer : Evaluates verifiedParserCore state
      (.index (.local 0) (.binary .add (.local 8) (.local 12)))
      lhsValue state := by
    simpa [lhsValue, lhs] using invariant.read_production_lhs bound
  have offsetInitializer : Evaluates verifiedParserCore state13
      (.index (.local 0) (.binary .add (.local 9) (.local 12)))
      offsetValue state13 := by
    simpa [state13, invariant13, offsetValue, rhsOffset] using
      invariant13.read_rhs_offset bound
  have lengthInitializer : Evaluates verifiedParserCore state14
      (.index (.local 0) (.binary .add (.local 10) (.local 12)))
      lengthValue state14 := by
    simpa [state14, invariant14, lengthValue, rhsLength] using
      invariant14.read_rhs_length bound
  have guardExecution : Executes verifiedParserCore state15
      parserGrammarProductionInvalidGuard .next state15 := by
    rw [rowState]
    exact rowInvariant.invalid_guard_executes lhsBound rhsRange
  let symbolInvariant := rowInvariant.symbol_loop_entry
  let symbolRun := symbolInvariant.execute_loop rhsRange (Nat.zero_le rhsLength)
  let increment := symbolRun.invariant.row.loop.increment bound
  have incrementEffect : ModifiesOnly
      (CellSet.singleton rowInvariant.loop.productionCell)
      symbolRun.after increment.after := by
    have sameCell : increment.invariant.productionCell =
        rowInvariant.loop.productionCell := by
      exact increment.productionCell_eq.trans
        (symbolRun.productionCell_eq.trans (by rfl))
    have beforeSame : symbolRun.invariant.row.loop.productionCell =
        rowInvariant.loop.productionCell :=
      symbolRun.productionCell_eq.trans (by rfl)
    simpa [beforeSame] using increment.effect
  have local16Body : Executes verifiedParserCore
      (state15.bindLocal 16 zeroValue)
      (.sequence parserGrammarSymbolLoop (parserIncrementLocal 12))
      .next increment.after := by
    have entryState : state15.bindLocal 16 zeroValue =
        (parserGrammarProductionRowState state lhs rhsOffset rhsLength).bindLocal
          16 (.signed .i32 0) := by
      simpa [rowState, zeroValue]
    rw [entryState]
    exact executesSequence symbolRun.execution increment.execution
  let after16 := restoreLocals state15 increment.after
  have scoped16 : Executes verifiedParserCore state15
      (.letLocal 16 parserI32Type (.value (.signed .i32 0))
        (.sequence parserGrammarSymbolLoop (parserIncrementLocal 12)))
      .next after16 := by
    simpa [after16, zeroValue] using
      executesLetLocal (type := parserI32Type)
        (show Evaluates verifiedParserCore state15
          (.value (.signed .i32 0)) zeroValue state15 from ⟨1, rfl⟩)
        local16Body
  have indexFresh : state15.nextCell ≤ symbolInvariant.indexCell := by
    exact Nat.le_refl _
  have entered16 : StoreEffect
      (CellSet.singleton symbolInvariant.indexCell) state15
      (state15.bindLocal 16 zeroValue) :=
    (bindLocal_effect state15 16 zeroValue).weaken CellSet.empty_subset
  have symbolStore : StoreEffect
      (CellSet.singleton symbolInvariant.indexCell) state15 symbolRun.after :=
    entered16.trans_same symbolRun.effect.toStoreEffect
  have combinedStore : StoreEffect
      (CellSet.union (CellSet.singleton symbolInvariant.indexCell)
        (CellSet.singleton rowInvariant.loop.productionCell))
      state15 increment.after :=
    symbolStore.trans incrementEffect.toStoreEffect
  have visibleStore : StoreEffect
      (CellSet.singleton rowInvariant.loop.productionCell)
      state15 increment.after := by
    apply combinedStore.hideFreshWritesExcept
    intro cell written
    rcases written with fresh | retained
    · exact Or.inr (by simpa [CellSet.singleton] using
        (show state15.nextCell ≤ cell from fresh ▸ indexFresh))
    · exact Or.inl retained
  have effect16 : ModifiesOnly
      (CellSet.singleton rowInvariant.loop.productionCell)
      state15 after16 := by
    simpa [after16] using visibleStore.restoreLocals
  have after16WellFormed : StateWellFormed after16 := by
    exact visibleStore.restoreLocals_wellFormed
      rowInvariant.loop.range.validation.stateWellFormed
      increment.invariant.range.validation.stateWellFormed
  let after15 := restoreLocals state14 after16
  let after14 := restoreLocals state13 after15
  let after13 := restoreLocals state after14
  have effect15 : ModifiesOnly
      (CellSet.singleton invariant.productionCell) state14 after15 := by
    have sameCell : rowInvariant.loop.productionCell =
        invariant.productionCell := by rfl
    simpa [after15, state15, lengthValue, sameCell] using
      temporaryLocal_effect 15 lengthValue effect16.toStoreEffect
  have after15WellFormed : StateWellFormed after15 := by
    have entered := (bindLocal_effect state14 15 lengthValue).weaken
      (CellSet.empty_subset : CellSet.Subset CellSet.empty
        (CellSet.singleton invariant.productionCell))
    have body : StoreEffect (CellSet.singleton invariant.productionCell)
        (state14.bindLocal 15 lengthValue) after16 := by
      have sameCell : rowInvariant.loop.productionCell =
          invariant.productionCell := by rfl
      simpa [state15, sameCell] using effect16.toStoreEffect
    exact (entered.trans_same body).restoreLocals_wellFormed
      invariant14.range.validation.stateWellFormed after16WellFormed
  have effect14 : ModifiesOnly
      (CellSet.singleton invariant.productionCell) state13 after14 := by
    simpa [after14, state14, offsetValue] using
      temporaryLocal_effect 14 offsetValue effect15.toStoreEffect
  have after14WellFormed : StateWellFormed after14 := by
    have entered := (bindLocal_effect state13 14 offsetValue).weaken
      (CellSet.empty_subset : CellSet.Subset CellSet.empty
        (CellSet.singleton invariant.productionCell))
    have body : StoreEffect (CellSet.singleton invariant.productionCell)
        (state13.bindLocal 14 offsetValue) after15 := by
      simpa [state14] using effect15.toStoreEffect
    exact (entered.trans_same body).restoreLocals_wellFormed
      invariant13.range.validation.stateWellFormed after15WellFormed
  have effect13 : ModifiesOnly
      (CellSet.singleton invariant.productionCell) state after13 := by
    simpa [after13, state13, lhsValue] using
      temporaryLocal_effect 13 lhsValue effect14.toStoreEffect
  have after13WellFormed : StateWellFormed after13 := by
    have entered := (bindLocal_effect state 13 lhsValue).weaken
      (CellSet.empty_subset : CellSet.Subset CellSet.empty
        (CellSet.singleton invariant.productionCell))
    have body : StoreEffect (CellSet.singleton invariant.productionCell)
        (state.bindLocal 13 lhsValue) after14 := by
      simpa [state13] using effect14.toStoreEffect
    exact (entered.trans_same body).restoreLocals_wellFormed
      invariant.range.validation.stateWellFormed after14WellFormed
  have afterOwned : (Assertion.localPointsTo 12 invariant.productionCell
      (some (.signed .i32 (Int.ofNat (production + 1))))).holds after13 := by
    constructor
    · change state.cellId? 12 = some invariant.productionCell
      exact invariant.productionOwned.1
    · change increment.after.cellEntry? invariant.productionCell = some {
        id := invariant.productionCell
        value := some (.signed .i32 (Int.ofNat (production + 1))) }
      have found := increment.invariant.productionOwned.2
      have cellEq : increment.invariant.productionCell =
          invariant.productionCell :=
        increment.productionCell_eq.trans
          (symbolRun.productionCell_eq.trans (by rfl))
      rw [cellEq] at found
      exact found
  let afterInvariant := invariant.after_counter_effect effect13
    after13WellFormed afterOwned
  have guardedBody : Executes verifiedParserCore state15
      (.sequence parserGrammarProductionInvalidGuard
        (.letLocal 16 parserI32Type (.value (.signed .i32 0))
          (.sequence parserGrammarSymbolLoop (parserIncrementLocal 12))))
      .next after16 :=
    executesSequence guardExecution scoped16
  have scoped15 := executesLetLocal (type := parserI32Type)
    lengthInitializer guardedBody
  have scoped14 := executesLetLocal (type := parserI32Type)
    offsetInitializer scoped15
  have scoped13 := executesLetLocal (type := parserI32Type)
    lhsInitializer scoped14
  exact {
    after := after13
    execution := by
      simpa [parserGrammarProductionLoopBody, after13, after14, after15,
        after16, state13, state14, state15, lhsValue, offsetValue,
        lengthValue, zeroValue] using scoped13
    effect := effect13
    invariant := afterInvariant
    productionCell_eq := rfl }

structure GrammarProductionLoopExecution
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (before : State) (production : Nat)
    (beforeInvariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell before production) where
  after : State
  execution : Executes verifiedParserCore before
    parserGrammarProductionLoop .next after
  effect : ModifiesOnly (CellSet.singleton beforeInvariant.productionCell)
    before after
  invariant : GrammarProductionLoopInvariant layout grammar words grammarCell
    after grammar.productionCount
  productionCell_eq : invariant.productionCell =
    beforeInvariant.productionCell

/-- The complete first validation loop from the extracted parser, with one
    semantic iteration for every dense production ID. -/
noncomputable def GrammarProductionLoopInvariant.execute_loop
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell state production)
    (productionLe : production ≤ grammar.productionCount) :
    GrammarProductionLoopExecution layout grammar words grammarCell state
      production invariant := by
  by_cases done : production = grammar.productionCount
  · subst production
    exact {
      after := state
      execution := by
        rw [extractedParserGrammarValid_production_loop_shape]
        exact executesWhileFalse (invariant.condition_false (by omega))
      effect := ModifiesOnly.reflAny _ state
      invariant := invariant
      productionCell_eq := rfl }
  · have bound : production < grammar.productionCount := by omega
    let iteration := invariant.execute_iteration bound
    let rest := iteration.invariant.execute_loop (by omega)
    have restEffect : ModifiesOnly
        (CellSet.singleton invariant.productionCell)
        iteration.after rest.after := by
      simpa [iteration.productionCell_eq] using rest.effect
    exact {
      after := rest.after
      execution := by
        rw [extractedParserGrammarValid_production_loop_shape]
        have restExpected := rest.execution
        rw [extractedParserGrammarValid_production_loop_shape] at restExpected
        exact executesWhileTrueThen (invariant.condition_true bound)
          iteration.execution restExpected
      effect := iteration.effect.trans_same restEffect
      invariant := rest.invariant
      productionCell_eq := rest.productionCell_eq.trans
        iteration.productionCell_eq }
termination_by grammar.productionCount - production
decreasing_by omega

def parserGrammarNonterminalBindings
    (layout : PackedGrammarLayout) : List (VarId × Value) := [
  (18, .signed .i32 (Int.ofNat layout.lhsOffsetsOffset)),
  (19, .signed .i32 (Int.ofNat layout.lhsCountsOffset)),
  (20, .signed .i32 (Int.ofNat layout.lhsProductionsOffset)),
  (21, .signed .i32 0)]

def parserGrammarNonterminalState
    (state : State) (layout : PackedGrammarLayout) : State :=
  state.bindLocals (parserGrammarNonterminalBindings layout)

structure GrammarNonterminalLoopInvariant
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (state : State) (nonterminal : Nat) where
  production : GrammarProductionLoopInvariant layout grammar words grammarCell
    state grammar.productionCount
  lhsOffsetsOffsetLocal : state.local? 18 =
    some (.signed .i32 (Int.ofNat layout.lhsOffsetsOffset))
  lhsCountsOffsetLocal : state.local? 19 =
    some (.signed .i32 (Int.ofNat layout.lhsCountsOffset))
  lhsProductionsOffsetLocal : state.local? 20 =
    some (.signed .i32 (Int.ofNat layout.lhsProductionsOffset))
  nonterminalCell : CellId
  nonterminalOwned : (Assertion.localPointsTo 21 nonterminalCell
    (some (.signed .i32 (Int.ofNat nonterminal)))).holds state
  nonterminalFrameSeparate : CellSet.Disjoint
    (localBindingFrameFootprint state
      parserGrammarNonterminalProtectedBindings)
    (CellSet.singleton nonterminalCell)
  nonterminalNotGrammar : nonterminalCell ≠ grammarCell
  nonterminalNotProduction : nonterminalCell ≠ production.productionCell

theorem GrammarNonterminalLoopInvariant.nonterminalSeparate
    (invariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell state nonterminal)
    (id : VarId) (member : id ∈ parserGrammarNonterminalProtectedIds) :
    state.cellId? id ≠ some invariant.nonterminalCell :=
  invariant.nonterminalFrameSeparate.localCell_ne_of_singleton member

noncomputable def GrammarProductionLoopInvariant.nonterminal_loop_entry
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell state grammar.productionCount) :
    GrammarNonterminalLoopInvariant layout grammar words grammarCell
      (parserGrammarNonterminalState state layout) 0 := by
  let offsetsValue : Value :=
    .signed .i32 (Int.ofNat layout.lhsOffsetsOffset)
  let countsValue : Value :=
    .signed .i32 (Int.ofNat layout.lhsCountsOffset)
  let productionsValue : Value :=
    .signed .i32 (Int.ofNat layout.lhsProductionsOffset)
  let zeroValue : Value := .signed .i32 0
  let state18 := state.bindLocal 18 offsetsValue
  let invariant18 := invariant.after_temporary_bind 18 offsetsValue (by decide)
  let state19 := state18.bindLocal 19 countsValue
  let invariant19 := invariant18.after_temporary_bind 19 countsValue (by decide)
  let state20 := state19.bindLocal 20 productionsValue
  let invariant20 := invariant19.after_temporary_bind 20 productionsValue
    (by decide)
  let state21 := state20.bindLocal 21 zeroValue
  let invariant21 := invariant20.after_temporary_bind 21 zeroValue (by decide)
  have finalState : state21 = parserGrammarNonterminalState state layout := by
    rfl
  let productionFinal : GrammarProductionLoopInvariant layout grammar words
      grammarCell (parserGrammarNonterminalState state layout)
      grammar.productionCount := finalState ▸ invariant21
  have owned : (Assertion.localPointsTo 21 state20.nextCell
      (some zeroValue)).holds state21 := by
    constructor
    · simp [state21, State.bindLocal, State.bindCell, State.cellId?]
    · simpa [state21, State.bindLocal] using
        bindCell_finds_fresh_cell state20 21 (some zeroValue)
          invariant20.range.validation.stateWellFormed
  refine {
    production := productionFinal
    lhsOffsetsOffsetLocal := ?_
    lhsCountsOffsetLocal := ?_
    lhsProductionsOffsetLocal := ?_
    nonterminalCell := state20.nextCell
    nonterminalOwned := by simpa [finalState, zeroValue] using owned
    nonterminalFrameSeparate := ?_
    nonterminalNotGrammar := ?_
    nonterminalNotProduction := ?_ }
  · simpa [parserGrammarNonterminalState,
      parserGrammarNonterminalBindings, offsetsValue, countsValue,
      productionsValue, zeroValue] using
      bindLocals_local_of_binding state [] [
        (19, countsValue), (20, productionsValue), (21, zeroValue)]
        18 offsetsValue invariant.range.validation.stateWellFormed (by simp)
  · simpa [parserGrammarNonterminalState,
      parserGrammarNonterminalBindings, offsetsValue, countsValue,
      productionsValue, zeroValue] using
      bindLocals_local_of_binding state [(18, offsetsValue)] [
        (20, productionsValue), (21, zeroValue)] 19 countsValue
        invariant.range.validation.stateWellFormed (by simp)
  · simpa [parserGrammarNonterminalState,
      parserGrammarNonterminalBindings, offsetsValue, countsValue,
      productionsValue, zeroValue] using
      bindLocals_local_of_binding state [
        (18, offsetsValue), (19, countsValue)] [(21, zeroValue)]
        20 productionsValue invariant.range.validation.stateWellFormed
        (by simp)
  · apply localCellFootprint_disjoint_singleton
    intro id member same
    have idBound := mem_parserGrammarNonterminalProtectedIds_lt id member
    have different : (21 : VarId) ≠ id := Ne.symm (Nat.ne_of_lt idBound)
    rw [← finalState] at same
    have oldCell : state20.cellId? id = some state20.nextCell := by
      simpa [state21, State.bindLocal, State.bindCell, State.cellId?, different]
        using same
    have below :=
      Lanius.Separation.StateWellFormed.cell_lt_next_of_local_binding
        id state20.nextCell invariant20.range.validation.stateWellFormed
        oldCell
    exact (Nat.lt_irrefl state20.nextCell) below
  · intro same
    have below := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant20.range.validation.stateWellFormed
      invariant20.range.validation.grammarBacking
    rw [← same] at below
    exact (Nat.lt_irrefl state20.nextCell) below
  · intro same
    have separate12 :
        (parserGrammarNonterminalState state layout).cellId? 12 ≠
          some state20.nextCell := by
      intro localSame
      rw [← finalState] at localSame
      have oldCell : state20.cellId? 12 = some state20.nextCell := by
        simpa [state21, State.bindLocal, State.bindCell, State.cellId?]
          using localSame
      have below :=
        Lanius.Separation.StateWellFormed.cell_lt_next_of_local_binding
          12 state20.nextCell invariant20.range.validation.stateWellFormed
          oldCell
      exact (Nat.lt_irrefl state20.nextCell) below
    apply separate12
    rw [same]
    exact productionFinal.productionOwned.1

theorem GrammarNonterminalLoopInvariant.condition_true
    (invariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell state nonterminal)
    (bound : nonterminal < grammar.grammar.n_nonterminals) :
    Evaluates verifiedParserCore state
      (.binary .less (.local 21) (.local 4)) (.boolean true) state := by
  have left : Evaluates verifiedParserCore state (.local 21)
      (.signed .i32 (Int.ofNat nonterminal)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 21 _
      (Assertion.localPointsTo_local 21 invariant.nonterminalCell _ state
        invariant.nonterminalOwned)⟩
  have right : Evaluates verifiedParserCore state (.local 4)
      (.signed .i32 (Int.ofNat grammar.grammar.n_nonterminals)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 4 _
      invariant.production.range.nonterminalCountLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt, bound]

theorem GrammarNonterminalLoopInvariant.condition_false
    (invariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell state nonterminal)
    (bound : grammar.grammar.n_nonterminals ≤ nonterminal) :
    Evaluates verifiedParserCore state
      (.binary .less (.local 21) (.local 4)) (.boolean false) state := by
  have left : Evaluates verifiedParserCore state (.local 21)
      (.signed .i32 (Int.ofNat nonterminal)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 21 _
      (Assertion.localPointsTo_local 21 invariant.nonterminalCell _ state
        invariant.nonterminalOwned)⟩
  have right : Evaluates verifiedParserCore state (.local 4)
      (.signed .i32 (Int.ofNat grammar.grammar.n_nonterminals)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 4 _
      invariant.production.range.nonterminalCountLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt]
  omega

theorem GrammarNonterminalLoopInvariant.read_first
    (invariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell state nonterminal)
    (bound : nonterminal < grammar.grammar.n_nonterminals) :
    Evaluates verifiedParserCore state
      (.index (.local 0) (.binary .add (.local 18) (.local 21)))
      (.signed .i32 (Int.ofNat
        (grammar.lhsOffsets.get ⟨nonterminal, by
          simpa [invariant.production.range.validation.grammarWellFormed.lhsIndexCount]
            using bound⟩))) state := by
  have rowBound : nonterminal < grammar.lhsOffsets.length := by
    simpa [invariant.production.range.validation.grammarWellFormed.lhsIndexCount]
      using bound
  have counter : Evaluates verifiedParserCore state (.local 21)
      (.signed .i32 (Int.ofNat nonterminal)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 21 _
      (Assertion.localPointsTo_local 21 invariant.nonterminalCell _ state
        invariant.nonterminalOwned)⟩
  have read := evaluatesParserDirectTableRead words grammarCell
    layout.lhsOffsetsOffset nonterminal
    (invariant.production.range.validation.encoded.lhsOffsets.row_in_bounds
      rowBound)
    invariant.production.range.validation.wordsI32 state
    invariant.production.range.validation.grammarLocal (.local 18) (.local 21)
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 18 _
      invariant.lhsOffsetsOffsetLocal⟩ counter
    invariant.production.range.validation.grammarBacking
  have physical := invariant.production.range.validation.encoded.lhsOffsets.get
    rowBound
  rw [physical] at read
  exact read

theorem GrammarNonterminalLoopInvariant.read_count
    (invariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell state nonterminal)
    (bound : nonterminal < grammar.grammar.n_nonterminals) :
    Evaluates verifiedParserCore state
      (.index (.local 0) (.binary .add (.local 19) (.local 21)))
      (.signed .i32 (Int.ofNat
        (grammar.lhsCounts.get ⟨nonterminal, by
          simpa [invariant.production.range.validation.grammarWellFormed.lhsIndexCount]
            using bound⟩))) state := by
  have rowBound : nonterminal < grammar.lhsCounts.length := by
    simpa [invariant.production.range.validation.grammarWellFormed.lhsIndexCount]
      using bound
  have counter : Evaluates verifiedParserCore state (.local 21)
      (.signed .i32 (Int.ofNat nonterminal)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 21 _
      (Assertion.localPointsTo_local 21 invariant.nonterminalCell _ state
        invariant.nonterminalOwned)⟩
  have read := evaluatesParserDirectTableRead words grammarCell
    layout.lhsCountsOffset nonterminal
    (invariant.production.range.validation.encoded.lhsCounts.row_in_bounds
      rowBound)
    invariant.production.range.validation.wordsI32 state
    invariant.production.range.validation.grammarLocal (.local 19) (.local 21)
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 19 _
      invariant.lhsCountsOffsetLocal⟩ counter
    invariant.production.range.validation.grammarBacking
  have physical := invariant.production.range.validation.encoded.lhsCounts.get
    rowBound
  rw [physical] at read
  exact read

def parserGrammarNonterminalRowState
    (state : State) (first count : Nat) : State :=
  state.bindLocals [
    (22, .signed .i32 (Int.ofNat first)),
    (23, .signed .i32 (Int.ofNat count))]

structure GrammarNonterminalRowInvariant
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (state : State) (nonterminal first count : Nat) where
  loop : GrammarNonterminalLoopInvariant layout grammar words grammarCell
    state nonterminal
  firstLocal : state.local? 22 = some (.signed .i32 (Int.ofNat first))
  countLocal : state.local? 23 = some (.signed .i32 (Int.ofNat count))

def GrammarNonterminalLoopInvariant.after_temporary_bind
    (invariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell state nonterminal)
    (id : VarId) (value : Value) (temporary : 21 < id) :
    GrammarNonterminalLoopInvariant layout grammar words grammarCell
      (state.bindLocal id value) nonterminal := by
  have different (fixed : Nat) (bound : fixed ≤ 21) : id ≠ fixed := by
    intro same
    rw [same] at temporary
    exact (Nat.not_lt_of_ge bound) temporary
  have cellOld : invariant.nonterminalCell < state.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant.production.range.validation.stateWellFormed
      invariant.nonterminalOwned.2
  refine {
    production := invariant.production.after_temporary_bind id value
      (Nat.lt_trans (by decide) temporary)
    lhsOffsetsOffsetLocal :=
      (bindLocal_preserves_other_local
        invariant.production.range.validation.stateWellFormed
        (different 18 (by decide))).trans invariant.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal :=
      (bindLocal_preserves_other_local
        invariant.production.range.validation.stateWellFormed
        (different 19 (by decide))).trans invariant.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal :=
      (bindLocal_preserves_other_local
        invariant.production.range.validation.stateWellFormed
        (different 20 (by decide))).trans invariant.lhsProductionsOffsetLocal
    nonterminalCell := invariant.nonterminalCell
    nonterminalOwned := ?_
    nonterminalFrameSeparate := ?_
    nonterminalNotGrammar := invariant.nonterminalNotGrammar
    nonterminalNotProduction := invariant.nonterminalNotProduction }
  · constructor
    · simpa [State.bindLocal, State.bindCell, State.cellId?,
        different 21 (by decide)] using invariant.nonterminalOwned.1
    · exact (bindCell_preserves_old_cell state id (some value)
        invariant.nonterminalCell cellOld).trans invariant.nonterminalOwned.2
  · intro cell framed written
    obtain ⟨queried, member, cellId⟩ := framed
    have bound := mem_parserGrammarNonterminalProtectedIds_lt queried member
    have notQueried : id ≠ queried := by
      intro equal
      rw [equal] at temporary
      exact (Nat.not_lt_of_ge (Nat.le_of_lt bound)) temporary
    apply invariant.nonterminalFrameSeparate cell
    · exact ⟨queried, member, by
        simpa [State.bindLocal, State.bindCell, State.cellId?, notQueried]
          using cellId⟩
    · exact written

noncomputable def GrammarNonterminalLoopInvariant.bind_row
    (invariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell state nonterminal)
    (first count : Nat) :
    GrammarNonterminalRowInvariant layout grammar words grammarCell
      (parserGrammarNonterminalRowState state first count)
      nonterminal first count := by
  let firstValue : Value := .signed .i32 (Int.ofNat first)
  let countValue : Value := .signed .i32 (Int.ofNat count)
  let state22 := state.bindLocal 22 firstValue
  let invariant22 := invariant.after_temporary_bind 22 firstValue (by decide)
  let state23 := state22.bindLocal 23 countValue
  let invariant23 := invariant22.after_temporary_bind 23 countValue (by decide)
  have finalState : state23 =
      parserGrammarNonterminalRowState state first count := by rfl
  refine {
    loop := by rw [← finalState]; exact invariant23
    firstLocal := ?_
    countLocal := ?_ }
  · simpa [parserGrammarNonterminalRowState, firstValue, countValue] using
      bindLocals_local_of_binding state [] [(23, countValue)] 22 firstValue
        invariant.production.range.validation.stateWellFormed (by simp)
  · simpa [parserGrammarNonterminalRowState, firstValue, countValue] using
      bindLocals_local_of_binding state [(22, firstValue)] [] 23 countValue
        invariant.production.range.validation.stateWellFormed (by simp)

theorem GrammarNonterminalRowInvariant.invalid_guard_evaluates_false
    (invariant : GrammarNonterminalRowInvariant layout grammar words
      grammarCell state nonterminal first count)
    (rowRange : first + count ≤ grammar.lhsProductions.length) :
    Evaluates verifiedParserCore state parserGrammarNonterminalInvalidExpr
      (.boolean false) state := by
  have zero : Evaluates verifiedParserCore state (.value (.signed .i32 0))
      (.signed .i32 0) state := ⟨1, rfl⟩
  have firstResult : Evaluates verifiedParserCore state (.local 22)
      (.signed .i32 (Int.ofNat first)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 22 _
      invariant.firstLocal⟩
  have countResult : Evaluates verifiedParserCore state (.local 23)
      (.signed .i32 (Int.ofNat count)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 23 _
      invariant.countLocal⟩
  have totalResult : Evaluates verifiedParserCore state (.local 7)
      (.signed .i32 (Int.ofNat grammar.lhsProductions.length)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 7 _
      invariant.loop.production.range.lhsProductionCountLocal⟩
  have firstNonnegative : Evaluates verifiedParserCore state
      (.binary .less (.local 22) (.value (.signed .i32 0)))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) firstResult zero
    simp [evalBinaryValue, evalSignedBinary]
  have countNonnegative : Evaluates verifiedParserCore state
      (.binary .less (.local 23) (.value (.signed .i32 0)))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) countResult zero
    simp [evalBinaryValue, evalSignedBinary]
  have firstBound : first ≤ grammar.lhsProductions.length := by omega
  have firstValid : Evaluates verifiedParserCore state
      (.binary .greater (.local 22) (.local 7))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) firstResult totalResult
    simp [evalBinaryValue, evalSignedBinary, Int.ofNat_le, firstBound]
  have totalFits : grammar.lhsProductions.length ≤ words.length := by
    have range :=
      (invariant.loop.production.range.validation.encoded.validation_facts
        invariant.loop.production.range.validation.grammarWellFormed).prelude.lhsProductionsRange
    rcases range with ⟨_, fits⟩
    omega
  have remainingBound : grammar.lhsProductions.length - first ≤
      2147483647 := Nat.le_trans (Nat.le_trans (Nat.sub_le _ _) totalFits)
        invariant.loop.production.range.validation.wordsI32
  have remainingResult : Evaluates verifiedParserCore state
      (.binary .subtract (.local 7) (.local 22))
      (.signed .i32
        (Int.ofNat (grammar.lhsProductions.length - first))) state := by
    apply evaluatesEagerBinary (by decide) (by decide) totalResult firstResult
    simp only [evalBinaryValue, evalSignedBinary]
    simp only [show (SignedIntTy.i32 == SignedIntTy.i32) = true by decide,
      if_true]
    have normalized : wrapSigned verifiedParserCore.target .i32
        (Int.ofNat grammar.lhsProductions.length - Int.ofNat first) =
        Int.ofNat (grammar.lhsProductions.length - first) := by
      calc
        _ = wrapSigned verifiedParserCore.target .i32
              (Int.ofNat (grammar.lhsProductions.length - first)) :=
          congrArg (wrapSigned verifiedParserCore.target .i32)
            (Int.ofNat_sub firstBound).symm
        _ = _ := wrapSigned_i32_ofNat verifiedParserCore.target _
          remainingBound
    exact congrArg
      (fun value =>
        (Except.ok (.signed .i32 value) : Except Trap Value)) normalized
  have countValid : Evaluates verifiedParserCore state
      (.binary .greater (.local 23)
        (.binary .subtract (.local 7) (.local 22)))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) countResult
      remainingResult
    simp [evalBinaryValue, evalSignedBinary, Int.ofNat_le]
    omega
  have firstTwo := evaluatesPureLogicalOr firstNonnegative countNonnegative
  have firstThree := evaluatesPureLogicalOr firstTwo firstValid
  simpa [parserGrammarNonterminalInvalidExpr] using
    evaluatesPureLogicalOr firstThree countValid

theorem GrammarNonterminalRowInvariant.invalid_guard_executes
    (invariant : GrammarNonterminalRowInvariant layout grammar words
      grammarCell state nonterminal first count)
    (rowRange : first + count ≤ grammar.lhsProductions.length) :
    Executes verifiedParserCore state parserGrammarNonterminalInvalidGuard
      .next state :=
  executesIfFalse (invariant.invalid_guard_evaluates_false rowRange)
    (executesSkip verifiedParserCore state)

def GrammarNonterminalRowInvariant.after_temporary_bind
    (invariant : GrammarNonterminalRowInvariant layout grammar words
      grammarCell state nonterminal first count)
    (id : VarId) (value : Value) (temporary : 23 < id) :
    GrammarNonterminalRowInvariant layout grammar words grammarCell
      (state.bindLocal id value) nonterminal first count := by
  have different (fixed : Nat) (bound : fixed ≤ 23) : id ≠ fixed := by
    intro same
    rw [same] at temporary
    exact (Nat.not_lt_of_ge bound) temporary
  exact {
    loop := invariant.loop.after_temporary_bind id value
      (Nat.lt_trans (by decide) temporary)
    firstLocal :=
      (bindLocal_preserves_other_local
        invariant.loop.production.range.validation.stateWellFormed
        (different 22 (by decide))).trans invariant.firstLocal
    countLocal :=
      (bindLocal_preserves_other_local
        invariant.loop.production.range.validation.stateWellFormed
        (different 23 (by decide))).trans invariant.countLocal }

structure GrammarListedLoopInvariant
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (state : State) (nonterminal first count index : Nat) where
  row : GrammarNonterminalRowInvariant layout grammar words grammarCell state
    nonterminal first count
  indexCell : CellId
  indexOwned : (Assertion.localPointsTo 24 indexCell
    (some (.signed .i32 (Int.ofNat index)))).holds state
  indexFrameSeparate : CellSet.Disjoint
    (localBindingFrameFootprint state parserGrammarListedProtectedBindings)
    (CellSet.singleton indexCell)
  indexNotGrammar : indexCell ≠ grammarCell

theorem GrammarListedLoopInvariant.indexSeparate
    (invariant : GrammarListedLoopInvariant layout grammar words grammarCell
      state nonterminal first count index)
    (id : VarId) (member : id ∈ parserGrammarListedProtectedIds) :
    state.cellId? id ≠ some invariant.indexCell :=
  invariant.indexFrameSeparate.localCell_ne_of_singleton member

noncomputable def GrammarNonterminalRowInvariant.listed_loop_entry
    (invariant : GrammarNonterminalRowInvariant layout grammar words
      grammarCell state nonterminal first count) :
    GrammarListedLoopInvariant layout grammar words grammarCell
      (state.bindLocal 24 (.signed .i32 0)) nonterminal first count 0 := by
  let zeroValue : Value := .signed .i32 0
  let after := state.bindLocal 24 zeroValue
  let rowAfter := invariant.after_temporary_bind 24 zeroValue (by decide)
  have owned : (Assertion.localPointsTo 24 state.nextCell
      (some zeroValue)).holds after := by
    constructor
    · simp [after, State.bindLocal, State.bindCell, State.cellId?]
    · simpa [after, State.bindLocal] using
        bindCell_finds_fresh_cell state 24 (some zeroValue)
          invariant.loop.production.range.validation.stateWellFormed
  refine {
    row := rowAfter
    indexCell := state.nextCell
    indexOwned := by simpa [after, zeroValue] using owned
    indexFrameSeparate := ?_
    indexNotGrammar := ?_ }
  · apply localCellFootprint_disjoint_singleton
    intro id member same
    have bound := mem_parserGrammarListedProtectedIds_lt id member
    have different : (24 : VarId) ≠ id := Ne.symm (Nat.ne_of_lt bound)
    have oldCell : state.cellId? id = some state.nextCell := by
      simpa [after, State.bindLocal, State.bindCell, State.cellId?, different]
        using same
    have below :=
      Lanius.Separation.StateWellFormed.cell_lt_next_of_local_binding
        id state.nextCell
        invariant.loop.production.range.validation.stateWellFormed oldCell
    exact (Nat.lt_irrefl state.nextCell) below
  · intro same
    have below := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant.loop.production.range.validation.stateWellFormed
      invariant.loop.production.range.validation.grammarBacking
    rw [← same] at below
    exact (Nat.lt_irrefl state.nextCell) below

theorem GrammarListedLoopInvariant.condition_true
    (invariant : GrammarListedLoopInvariant layout grammar words grammarCell
      state nonterminal first count index)
    (bound : index < count) :
    Evaluates verifiedParserCore state
      (.binary .less (.local 24) (.local 23)) (.boolean true) state := by
  have left : Evaluates verifiedParserCore state (.local 24)
      (.signed .i32 (Int.ofNat index)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 24 _
      (Assertion.localPointsTo_local 24 invariant.indexCell _ state
        invariant.indexOwned)⟩
  have right : Evaluates verifiedParserCore state (.local 23)
      (.signed .i32 (Int.ofNat count)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 23 _
      invariant.row.countLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt, bound]

theorem GrammarListedLoopInvariant.condition_false
    (invariant : GrammarListedLoopInvariant layout grammar words grammarCell
      state nonterminal first count index)
    (bound : count ≤ index) :
    Evaluates verifiedParserCore state
      (.binary .less (.local 24) (.local 23)) (.boolean false) state := by
  have left : Evaluates verifiedParserCore state (.local 24)
      (.signed .i32 (Int.ofNat index)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 24 _
      (Assertion.localPointsTo_local 24 invariant.indexCell _ state
        invariant.indexOwned)⟩
  have right : Evaluates verifiedParserCore state (.local 23)
      (.signed .i32 (Int.ofNat count)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 23 _
      invariant.row.countLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt]
  omega

theorem GrammarListedLoopInvariant.read_listed
    (invariant : GrammarListedLoopInvariant layout grammar words grammarCell
      state nonterminal first count index)
    (rowRange : first + count ≤ grammar.lhsProductions.length)
    (indexBound : index < count) :
    Evaluates verifiedParserCore state
      (.index (.local 0)
        (.binary .add
          (.binary .add (.local 20) (.local 22))
          (.local 24)))
      (.signed .i32 (Int.ofNat
        (grammar.lhsProductions.get ⟨first + index, by omega⟩))) state := by
  have rowBound : first + index < grammar.lhsProductions.length := by omega
  have physicalBound := invariant.row.loop.production.range.validation.encoded.lhsProductions.row_in_bounds
    rowBound
  have physicalBound' :
      layout.lhsProductionsOffset + first + index < words.length := by
    simpa [Nat.add_assoc] using physicalBound
  have grammarResult : Evaluates verifiedParserCore state (.local 0)
      (parserGrammarValue words grammarCell) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 0 _
      invariant.row.loop.production.range.validation.grammarLocal⟩
  have tableOffset : Evaluates verifiedParserCore state (.local 20)
      (.signed .i32 (Int.ofNat layout.lhsProductionsOffset)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 20 _
      invariant.row.loop.lhsProductionsOffsetLocal⟩
  have firstResult : Evaluates verifiedParserCore state (.local 22)
      (.signed .i32 (Int.ofNat first)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 22 _
      invariant.row.firstLocal⟩
  have indexResult : Evaluates verifiedParserCore state (.local 24)
      (.signed .i32 (Int.ofNat index)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 24 _
      (Assertion.localPointsTo_local 24 invariant.indexCell _ state
        invariant.indexOwned)⟩
  have partialBound : layout.lhsProductionsOffset + first ≤ 2147483647 :=
    Nat.le_trans (Nat.le_of_lt (Nat.lt_of_le_of_lt
      (Nat.le_add_right _ _) physicalBound'))
      invariant.row.loop.production.range.validation.wordsI32
  have partialResult : Evaluates verifiedParserCore state
      (.binary .add (.local 20) (.local 22))
      (.signed .i32 (Int.ofNat (layout.lhsProductionsOffset + first)))
      state := by
    have castAddress : Int.ofNat layout.lhsProductionsOffset +
        Int.ofNat first =
        Int.ofNat (layout.lhsProductionsOffset + first) :=
      (Int.natCast_add _ _).symm
    have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target _
      partialBound
    apply evaluatesEagerBinary (by decide) (by decide) tableOffset firstResult
    simp only [evalBinaryValue, evalSignedBinary]
    rw [castAddress, wrapped]
    simp
  have addressBound : layout.lhsProductionsOffset + first + index ≤
      2147483647 := Nat.le_trans (Nat.le_of_lt physicalBound')
        invariant.row.loop.production.range.validation.wordsI32
  have addressResult : Evaluates verifiedParserCore state
      (.binary .add
        (.binary .add (.local 20) (.local 22)) (.local 24))
      (.signed .i32
        (Int.ofNat (layout.lhsProductionsOffset + first + index))) state := by
    have castAddress : Int.ofNat (layout.lhsProductionsOffset + first) +
        Int.ofNat index =
        Int.ofNat (layout.lhsProductionsOffset + first + index) :=
      (Int.natCast_add _ _).symm
    have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target _
      addressBound
    apply evaluatesEagerBinary (by decide) (by decide) partialResult indexResult
    simp only [evalBinaryValue, evalSignedBinary]
    rw [castAddress, wrapped]
    simp
  have read := evaluatesSignedI32SliceIndex verifiedParserCore state state state
    words (.local 0)
    (.binary .add
      (.binary .add (.local 20) (.local 22)) (.local 24))
    grammarCell (layout.lhsProductionsOffset + first + index) physicalBound'
    grammarResult addressResult
    invariant.row.loop.production.range.validation.grammarBacking
  have physical := invariant.row.loop.production.range.validation.encoded.lhsProductions.get
    rowBound
  have physical' : words.get
      ⟨layout.lhsProductionsOffset + first + index, physicalBound'⟩ =
      Int.ofNat (grammar.lhsProductions.get ⟨first + index, rowBound⟩) := by
    simpa [Nat.add_assoc] using physical
  rw [physical'] at read
  exact read

def GrammarListedLoopInvariant.after_temporary_bind
    (invariant : GrammarListedLoopInvariant layout grammar words grammarCell
      state nonterminal first count index)
    (id : VarId) (value : Value) (temporary : 24 < id) :
    GrammarListedLoopInvariant layout grammar words grammarCell
      (state.bindLocal id value) nonterminal first count index := by
  have different (fixed : Nat) (bound : fixed ≤ 24) : id ≠ fixed := by
    intro same
    rw [same] at temporary
    exact (Nat.not_lt_of_ge bound) temporary
  have indexOld : invariant.indexCell < state.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant.row.loop.production.range.validation.stateWellFormed
      invariant.indexOwned.2
  refine {
    row := invariant.row.after_temporary_bind id value
      (Nat.lt_trans (by decide) temporary)
    indexCell := invariant.indexCell
    indexOwned := ?_
    indexFrameSeparate := ?_
    indexNotGrammar := invariant.indexNotGrammar }
  · constructor
    · simpa [State.bindLocal, State.bindCell, State.cellId?,
        different 24 (by decide)] using invariant.indexOwned.1
    · exact (bindCell_preserves_old_cell state id (some value)
        invariant.indexCell indexOld).trans invariant.indexOwned.2
  · intro cell framed written
    obtain ⟨queried, member, cellId⟩ := framed
    have bound := mem_parserGrammarListedProtectedIds_lt queried member
    have notQueried : id ≠ queried := by
      intro equal
      rw [equal] at temporary
      exact (Nat.not_lt_of_ge (Nat.le_of_lt bound)) temporary
    apply invariant.indexFrameSeparate cell
    · exact ⟨queried, member, by
        simpa [State.bindLocal, State.bindCell, State.cellId?, notQueried]
          using cellId⟩
    · exact written

@[simp] theorem GrammarListedLoopInvariant.after_temporary_bind_indexCell
    (invariant : GrammarListedLoopInvariant layout grammar words grammarCell
      state nonterminal first count index)
    (id : VarId) (value : Value) (temporary : 24 < id) :
    (invariant.after_temporary_bind id value temporary).indexCell =
      invariant.indexCell := by
  rfl

theorem GrammarListedLoopInvariant.listed_guard_executes
    (invariant : GrammarListedLoopInvariant layout grammar words grammarCell
      state nonterminal first count index)
    (listed : Nat)
    (listedLocal : state.local? 25 =
      some (.signed .i32 (Int.ofNat listed)))
    (listedBound : listed < grammar.productionCount)
    (listedLhs : (grammar.productionAt ⟨listed, listedBound⟩).lhs =
      nonterminal) :
    Executes verifiedParserCore state parserGrammarListedInvalidGuard
      .next state := by
  have zero : Evaluates verifiedParserCore state (.value (.signed .i32 0))
      (.signed .i32 0) state := ⟨1, rfl⟩
  have listedResult : Evaluates verifiedParserCore state (.local 25)
      (.signed .i32 (Int.ofNat listed)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 25 _ listedLocal⟩
  have countResult : Evaluates verifiedParserCore state (.local 3)
      (.signed .i32 (Int.ofNat grammar.productionCount)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 3 _
      invariant.row.loop.production.range.productionCountLocal⟩
  have nonterminalResult : Evaluates verifiedParserCore state (.local 21)
      (.signed .i32 (Int.ofNat nonterminal)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 21 _
      (Assertion.localPointsTo_local 21
        invariant.row.loop.nonterminalCell _ state
        invariant.row.loop.nonterminalOwned)⟩
  have nonnegative : Evaluates verifiedParserCore state
      (.binary .less (.local 25) (.value (.signed .i32 0)))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) listedResult zero
    simp [evalBinaryValue, evalSignedBinary]
  have inBounds : Evaluates verifiedParserCore state
      (.binary .greaterEqual (.local 25) (.local 3))
      (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) listedResult countResult
    simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt, listedBound]
  have rowBound : listed < grammar.productionLhs.length := by simpa
  have lhsRead := evaluatesParserDirectTableRead words grammarCell
    layout.productionLhsOffset listed
    (invariant.row.loop.production.range.validation.encoded.productionLhs.row_in_bounds
      rowBound)
    invariant.row.loop.production.range.validation.wordsI32 state
    invariant.row.loop.production.range.validation.grammarLocal
    (.local 8) (.local 25)
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 8 _
      invariant.row.loop.production.productionLhsOffsetLocal⟩
    listedResult
    invariant.row.loop.production.range.validation.grammarBacking
  have physical := invariant.row.loop.production.range.validation.encoded.productionLhs.get
    rowBound
  rw [physical] at lhsRead
  have lhsValue : grammar.productionLhs.get ⟨listed, rowBound⟩ =
      nonterminal := by
    have selected := IndexedGrammar.productionLhs_get grammar
      ⟨listed, listedBound⟩
    have selected' : grammar.productionLhs.get ⟨listed, rowBound⟩ =
        (grammar.productionAt ⟨listed, listedBound⟩).lhs := by
      simpa using selected
    exact selected'.trans listedLhs
  rw [lhsValue] at lhsRead
  have lhsMatches : Evaluates verifiedParserCore state
      (.binary .notEqual
        (.index (.local 0) (.binary .add (.local 8) (.local 25)))
        (.local 21)) (.boolean false) state := by
    apply evaluatesEagerBinary (by decide) (by decide) lhsRead
      nonterminalResult
    simp [evalBinaryValue, scalarEqual]
  have firstTwo := evaluatesPureLogicalOr nonnegative inBounds
  have invalidFalse : Evaluates verifiedParserCore state
      parserGrammarListedInvalidExpr (.boolean false) state := by
    simpa [parserGrammarListedInvalidExpr] using
      evaluatesPureLogicalOr firstTwo lhsMatches
  exact executesIfFalse invalidFalse (executesSkip verifiedParserCore state)

def GrammarNonterminalLoopInvariant.after_foreign_effect
    (invariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell before nonterminal)
    (written : CellId)
    (effect : ModifiesOnly (CellSet.singleton written) before after)
    (afterWellFormed : StateWellFormed after)
    (frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        parserGrammarNonterminalProtectedBindings)
      (CellSet.singleton written))
    (notGrammar : written ≠ grammarCell)
    (notProduction : written ≠ invariant.production.productionCell)
    (notNonterminal : written ≠ invariant.nonterminalCell) :
    GrammarNonterminalLoopInvariant layout grammar words grammarCell after
      nonterminal := by
  let productionAfter := invariant.production.after_foreign_effect written
    effect afterWellFormed
    (CellSet.Disjoint.mono_left
      (localBindingFrameFootprint_mono (fun id member => by
        exact parserGrammarProductionProtectedIds_subset_nonterminal member))
      frameDisjoint)
    notGrammar notProduction
  have preserve (id : VarId)
      (member : id ∈ parserGrammarNonterminalProtectedIds) (value : Value)
      (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint
      invariant.production.range.validation.stateWellFormed frameDisjoint
      member found
  have preserveEntry (cell : CellId) (different : cell ≠ written)
      (value : Option Value)
      (found : before.cellEntry? cell = some { id := cell, value := value }) :
      after.cellEntry? cell = some { id := cell, value := value } := by
    exact effect.preserves_entry
      invariant.production.range.validation.stateWellFormed found
      (by simpa [CellSet.singleton] using different)
  refine {
    production := productionAfter
    lhsOffsetsOffsetLocal := preserve 18 (by
      simp [parserGrammarNonterminalProtectedIds]) _
      invariant.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal := preserve 19 (by
      simp [parserGrammarNonterminalProtectedIds]) _
      invariant.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal := preserve 20 (by
      simp [parserGrammarNonterminalProtectedIds]) _
      invariant.lhsProductionsOffsetLocal
    nonterminalCell := invariant.nonterminalCell
    nonterminalOwned := ?_
    nonterminalFrameSeparate := ?_
    nonterminalNotGrammar := invariant.nonterminalNotGrammar
    nonterminalNotProduction := ?_ }
  · constructor
    · have beforeCell := invariant.nonterminalOwned.1
      unfold State.cellId? at beforeCell ⊢
      rw [effect.locals]
      exact beforeCell
    · exact preserveEntry invariant.nonterminalCell notNonterminal.symm _
        invariant.nonterminalOwned.2
  · rw [effect.localBindingFrameFootprint_eq
      parserGrammarNonterminalProtectedBindings]
    exact invariant.nonterminalFrameSeparate
  · have cellEq : productionAfter.productionCell =
        invariant.production.productionCell := by
      exact GrammarProductionLoopInvariant.after_foreign_effect_productionCell
        invariant.production written effect afterWellFormed
        (CellSet.Disjoint.mono_left
          (localBindingFrameFootprint_mono (fun id member => by
            exact parserGrammarProductionProtectedIds_subset_nonterminal
              member))
          frameDisjoint)
        notGrammar notProduction
    rw [cellEq]
    exact invariant.nonterminalNotProduction

def GrammarNonterminalLoopInvariant.after_counter_effect
    (invariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell before nonterminal)
    (effect : ModifiesOnly (CellSet.singleton invariant.nonterminalCell)
      before after)
    (afterWellFormed : StateWellFormed after)
    (afterOwned : (Assertion.localPointsTo 21 invariant.nonterminalCell
      (some (.signed .i32 (Int.ofNat nextNonterminal)))).holds after) :
    GrammarNonterminalLoopInvariant layout grammar words grammarCell after
      nextNonterminal := by
  let productionAfter := invariant.production.after_foreign_effect
    invariant.nonterminalCell effect afterWellFormed
    (CellSet.Disjoint.mono_left
      (localBindingFrameFootprint_mono (fun id member => by
        exact parserGrammarProductionProtectedIds_subset_nonterminal member))
      invariant.nonterminalFrameSeparate)
    invariant.nonterminalNotGrammar invariant.nonterminalNotProduction
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before
        parserGrammarNonterminalProtectedBindings)
      (CellSet.singleton invariant.nonterminalCell) :=
    invariant.nonterminalFrameSeparate
  have preserve (id : VarId)
      (member : id ∈ parserGrammarNonterminalProtectedIds) (value : Value)
      (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint
      invariant.production.range.validation.stateWellFormed frameDisjoint
      member found
  have productionCellEq : productionAfter.productionCell =
      invariant.production.productionCell :=
    GrammarProductionLoopInvariant.after_foreign_effect_productionCell
      invariant.production invariant.nonterminalCell effect afterWellFormed
      (CellSet.Disjoint.mono_left
        (localBindingFrameFootprint_mono (fun id member => by
          exact parserGrammarProductionProtectedIds_subset_nonterminal member))
        invariant.nonterminalFrameSeparate)
      invariant.nonterminalNotGrammar invariant.nonterminalNotProduction
  refine {
    production := productionAfter
    lhsOffsetsOffsetLocal := preserve 18 (by
      simp [parserGrammarNonterminalProtectedIds]) _
      invariant.lhsOffsetsOffsetLocal
    lhsCountsOffsetLocal := preserve 19 (by
      simp [parserGrammarNonterminalProtectedIds]) _
      invariant.lhsCountsOffsetLocal
    lhsProductionsOffsetLocal := preserve 20 (by
      simp [parserGrammarNonterminalProtectedIds]) _
      invariant.lhsProductionsOffsetLocal
    nonterminalCell := invariant.nonterminalCell
    nonterminalOwned := afterOwned
    nonterminalFrameSeparate := ?_
    nonterminalNotGrammar := invariant.nonterminalNotGrammar
    nonterminalNotProduction := ?_ }
  · rw [effect.localBindingFrameFootprint_eq
      parserGrammarNonterminalProtectedBindings]
    exact invariant.nonterminalFrameSeparate
  · rw [productionCellEq]
    exact invariant.nonterminalNotProduction

@[simp] theorem GrammarNonterminalLoopInvariant.after_counter_effect_nonterminalCell
    (invariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell before nonterminal)
    (effect : ModifiesOnly (CellSet.singleton invariant.nonterminalCell)
      before after)
    (afterWellFormed : StateWellFormed after)
    (afterOwned : (Assertion.localPointsTo 21 invariant.nonterminalCell
      (some (.signed .i32 (Int.ofNat nextNonterminal)))).holds after) :
    (invariant.after_counter_effect effect afterWellFormed
      afterOwned).nonterminalCell = invariant.nonterminalCell := by
  rfl

def GrammarListedLoopInvariant.after_index_effect
    (invariant : GrammarListedLoopInvariant layout grammar words grammarCell
      before nonterminal first count index)
    (effect : ModifiesOnly (CellSet.singleton invariant.indexCell) before after)
    (afterWellFormed : StateWellFormed after)
    (afterOwned : (Assertion.localPointsTo 24 invariant.indexCell
      (some (.signed .i32 (Int.ofNat nextIndex)))).holds after) :
    GrammarListedLoopInvariant layout grammar words grammarCell after
      nonterminal first count nextIndex := by
  have notProduction : invariant.indexCell ≠
      invariant.row.loop.production.productionCell := by
    intro same
    apply invariant.indexSeparate 12 (by
      simp [parserGrammarListedProtectedIds,
        parserGrammarNonterminalProtectedIds])
    rw [same]
    exact invariant.row.loop.production.productionOwned.1
  have notNonterminal : invariant.indexCell ≠
      invariant.row.loop.nonterminalCell := by
    intro same
    apply invariant.indexSeparate 21 (by
      simp [parserGrammarListedProtectedIds])
    rw [same]
    exact invariant.row.loop.nonterminalOwned.1
  have loopAfter := invariant.row.loop.after_foreign_effect
    invariant.indexCell effect afterWellFormed
    (CellSet.Disjoint.mono_left
      (localBindingFrameFootprint_mono (fun id member => by
        exact parserGrammarNonterminalProtectedIds_subset_listed member))
      invariant.indexFrameSeparate)
    invariant.indexNotGrammar notProduction notNonterminal
  have frameDisjoint : CellSet.Disjoint
      (localBindingFrameFootprint before parserGrammarListedProtectedBindings)
      (CellSet.singleton invariant.indexCell) :=
    invariant.indexFrameSeparate
  have preserve (id : VarId)
      (member : id ∈ parserGrammarListedProtectedIds) (value : Value)
      (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint
      invariant.row.loop.production.range.validation.stateWellFormed
      frameDisjoint member found
  refine {
    row := {
      loop := loopAfter
      firstLocal := preserve 22 (by
        simp [parserGrammarListedProtectedIds]) _ invariant.row.firstLocal
      countLocal := preserve 23 (by
        simp [parserGrammarListedProtectedIds]) _ invariant.row.countLocal }
    indexCell := invariant.indexCell
    indexOwned := afterOwned
    indexFrameSeparate := ?_
    indexNotGrammar := invariant.indexNotGrammar }
  rw [effect.localBindingFrameFootprint_eq
    parserGrammarListedProtectedBindings]
  exact invariant.indexFrameSeparate

@[simp] theorem GrammarListedLoopInvariant.after_index_effect_indexCell
    (invariant : GrammarListedLoopInvariant layout grammar words grammarCell
      before nonterminal first count index)
    (effect : ModifiesOnly (CellSet.singleton invariant.indexCell) before after)
    (afterWellFormed : StateWellFormed after)
    (afterOwned : (Assertion.localPointsTo 24 invariant.indexCell
      (some (.signed .i32 (Int.ofNat nextIndex)))).holds after) :
    (invariant.after_index_effect effect afterWellFormed
      afterOwned).indexCell = invariant.indexCell := by rfl

@[simp] theorem GrammarListedLoopInvariant.after_index_effect_nonterminalCell
    (invariant : GrammarListedLoopInvariant layout grammar words grammarCell
      before nonterminal first count index)
    (effect : ModifiesOnly (CellSet.singleton invariant.indexCell) before after)
    (afterWellFormed : StateWellFormed after)
    (afterOwned : (Assertion.localPointsTo 24 invariant.indexCell
      (some (.signed .i32 (Int.ofNat nextIndex)))).holds after) :
    (invariant.after_index_effect effect afterWellFormed
      afterOwned).row.loop.nonterminalCell =
      invariant.row.loop.nonterminalCell := by rfl

structure GrammarListedIncrement
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (before : State) (nonterminal first count index : Nat)
    (beforeInvariant : GrammarListedLoopInvariant layout grammar words
      grammarCell before nonterminal first count index) where
  after : State
  execution : Executes verifiedParserCore before (parserIncrementLocal 24)
    .next after
  effect : ModifiesOnly (CellSet.singleton beforeInvariant.indexCell)
    before after
  invariant : GrammarListedLoopInvariant layout grammar words grammarCell after
    nonterminal first count (index + 1)
  indexCell_eq : invariant.indexCell = beforeInvariant.indexCell

noncomputable def GrammarListedLoopInvariant.increment
    (invariant : GrammarListedLoopInvariant layout grammar words grammarCell
      state nonterminal first count index)
    (indexBound : index < count)
    (rowRange : first + count ≤ grammar.lhsProductions.length) :
    GrammarListedIncrement layout grammar words grammarCell state
      nonterminal first count index invariant := by
  have countFits : count ≤ words.length := by
    have tableFits : grammar.lhsProductions.length ≤ words.length := by
      have range :=
        (invariant.row.loop.production.range.validation.encoded.validation_facts
          invariant.row.loop.production.range.validation.grammarWellFormed).prelude.lhsProductionsRange
      rcases range with ⟨_, fits⟩
      omega
    omega
  have incrementBound : index + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.le_trans (Nat.succ_le_of_lt indexBound) countFits)
      invariant.row.loop.production.range.validation.wordsI32
  have result := executesIncrementOwnedI32Local verifiedParserCore state 24
    invariant.indexCell index
    invariant.row.loop.production.range.validation.stateWellFormed
    invariant.indexOwned incrementBound
  let after := Classical.choose result
  have facts := Classical.choose_spec result
  exact {
    after := after
    execution := by simpa [parserIncrementLocal] using facts.1
    effect := facts.2.2.2
    invariant := invariant.after_index_effect facts.2.2.2 facts.2.1
      facts.2.2.1
    indexCell_eq := rfl }

structure GrammarListedLoopExecution
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (before : State) (nonterminal first count index : Nat)
    (beforeInvariant : GrammarListedLoopInvariant layout grammar words
      grammarCell before nonterminal first count index) where
  after : State
  execution : Executes verifiedParserCore before parserGrammarListedLoop
    .next after
  effect : ModifiesOnly (CellSet.singleton beforeInvariant.indexCell)
    before after
  invariant : GrammarListedLoopInvariant layout grammar words grammarCell after
    nonterminal first count count
  indexCell_eq : invariant.indexCell = beforeInvariant.indexCell
  nonterminalCell_eq : invariant.row.loop.nonterminalCell =
    beforeInvariant.row.loop.nonterminalCell

noncomputable def GrammarListedLoopInvariant.execute_loop
    (invariant : GrammarListedLoopInvariant layout grammar words grammarCell
      state nonterminal first count index)
    (nonterminalBound : nonterminal < grammar.grammar.n_nonterminals)
    (firstEq : first = grammar.lhsOffsets.get
      ⟨nonterminal, by
        simpa [invariant.row.loop.production.range.validation.grammarWellFormed.lhsIndexCount]
          using nonterminalBound⟩)
    (countEq : count = (grammar.productionsByLhs.get
      ⟨nonterminal, by
        simpa [invariant.row.loop.production.range.validation.grammarWellFormed.lhsIndexCount]
          using nonterminalBound⟩).length)
    (rowRange : first + count ≤ grammar.lhsProductions.length)
    (indexLe : index ≤ count) :
    GrammarListedLoopExecution layout grammar words grammarCell state
      nonterminal first count index invariant := by
  by_cases done : index = count
  · subst index
    exact {
      after := state
      execution := executesWhileFalse (invariant.condition_false (by omega))
      effect := ModifiesOnly.reflAny _ state
      invariant := invariant
      indexCell_eq := rfl
      nonterminalCell_eq := rfl }
  · have indexBound : index < count := by omega
    have flatBound : first + index < grammar.lhsProductions.length := by omega
    let listed := grammar.lhsProductions.get ⟨first + index, flatBound⟩
    have listedRead := invariant.read_listed rowRange indexBound
    let listedValue : Value := .signed .i32 (Int.ofNat listed)
    let listedState := state.bindLocal 25 listedValue
    let listedInvariant := invariant.after_temporary_bind 25 listedValue
      (by decide)
    have listedLocal : listedState.local? 25 = some listedValue :=
      bindLocal_finds_local state 25 listedValue
        invariant.row.loop.production.range.validation.stateWellFormed
    let rowFin : Fin grammar.productionsByLhs.length :=
      ⟨nonterminal, by
        simpa [invariant.row.loop.production.range.validation.grammarWellFormed.lhsIndexCount]
          using nonterminalBound⟩
    let indexFin : Fin (grammar.productionsByLhs.get rowFin).length :=
      ⟨index, by simpa [rowFin, countEq] using indexBound⟩
    have listedRowValue : listed =
        (grammar.productionsByLhs.get rowFin).get indexFin := by
      have selected := grammar.lhsProductions_get_at_row rowFin indexFin
      simpa [listed, rowFin, indexFin, firstEq] using selected
    have rowFound : grammar.productionsByLhs[nonterminal]? =
        some (grammar.productionsByLhs.get rowFin) := by
      rw [List.getElem?_eq_getElem rowFin.isLt]
      rfl
    have listedMember : listed ∈ grammar.productionsByLhs.get rowFin := by
      rw [listedRowValue]
      exact List.get_mem _ _
    let validationFacts :=
      invariant.row.loop.production.range.validation.encoded.validation_facts
        invariant.row.loop.production.range.validation.grammarWellFormed
    have listedValidity :=
      validationFacts.nonterminals.listedProductionValid nonterminal
        (grammar.productionsByLhs.get rowFin) nonterminalBound rowFound
        listed listedMember
    let listedBound := Classical.choose listedValidity
    have listedLhs := Classical.choose_spec listedValidity
    have guardExecution : Executes verifiedParserCore listedState
        parserGrammarListedInvalidGuard .next listedState :=
      listedInvariant.listed_guard_executes listed listedLocal listedBound
        listedLhs
    let increment := listedInvariant.increment indexBound rowRange
    have body : Executes verifiedParserCore listedState
        (.sequence parserGrammarListedInvalidGuard (parserIncrementLocal 24))
        .next increment.after :=
      executesSequence guardExecution increment.execution
    let afterIteration := restoreLocals state increment.after
    have scopedBody : Executes verifiedParserCore state
        parserGrammarListedLoopBody .next afterIteration := by
      simpa [parserGrammarListedLoopBody, listedValue, listedState, listed,
        afterIteration] using
        executesLetLocal (type := parserI32Type) listedRead body
    have entered : StoreEffect (CellSet.singleton invariant.indexCell) state
        listedState :=
      (bindLocal_effect state 25 listedValue).weaken CellSet.empty_subset
    have incrementEffect : ModifiesOnly
        (CellSet.singleton invariant.indexCell) listedState increment.after := by
      simpa [listedInvariant, listedState] using increment.effect
    have iterationStore : StoreEffect (CellSet.singleton invariant.indexCell)
        state increment.after := entered.trans_same incrementEffect.toStoreEffect
    have iterationEffect : ModifiesOnly
        (CellSet.singleton invariant.indexCell) state afterIteration := by
      simpa [afterIteration] using iterationStore.restoreLocals
    have afterWellFormed : StateWellFormed afterIteration :=
      iterationStore.restoreLocals_wellFormed
        invariant.row.loop.production.range.validation.stateWellFormed
        increment.invariant.row.loop.production.range.validation.stateWellFormed
    have afterOwned : (Assertion.localPointsTo 24 invariant.indexCell
        (some (.signed .i32 (Int.ofNat (index + 1))))).holds
        afterIteration := by
      constructor
      · change state.cellId? 24 = some invariant.indexCell
        exact invariant.indexOwned.1
      · change increment.after.cellEntry? invariant.indexCell = some {
          id := invariant.indexCell
          value := some (.signed .i32 (Int.ofNat (index + 1))) }
        have found := increment.invariant.indexOwned.2
        have cellEq : increment.invariant.indexCell = invariant.indexCell :=
          increment.indexCell_eq.trans (by simp [listedInvariant])
        rw [cellEq] at found
        exact found
    let afterInvariant := invariant.after_index_effect iterationEffect
      afterWellFormed afterOwned
    let rest := afterInvariant.execute_loop nonterminalBound firstEq countEq
      rowRange (by omega)
    exact {
      after := rest.after
      execution := executesWhileTrueThen (invariant.condition_true indexBound)
        scopedBody rest.execution
      effect := iterationEffect.trans_same rest.effect
      invariant := rest.invariant
      indexCell_eq := rest.indexCell_eq.trans (by simp [afterInvariant])
      nonterminalCell_eq := rest.nonterminalCell_eq.trans
        (by simp [afterInvariant]) }
termination_by count - index
decreasing_by omega

structure GrammarNonterminalIncrement
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (before : State) (nonterminal : Nat)
    (beforeInvariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell before nonterminal) where
  after : State
  execution : Executes verifiedParserCore before (parserIncrementLocal 21)
    .next after
  effect : ModifiesOnly (CellSet.singleton beforeInvariant.nonterminalCell)
    before after
  invariant : GrammarNonterminalLoopInvariant layout grammar words grammarCell
    after (nonterminal + 1)
  nonterminalCell_eq : invariant.nonterminalCell =
    beforeInvariant.nonterminalCell

noncomputable def GrammarNonterminalLoopInvariant.increment
    (invariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell state nonterminal)
    (bound : nonterminal < grammar.grammar.n_nonterminals) :
    GrammarNonterminalIncrement layout grammar words grammarCell state
      nonterminal invariant := by
  have countFits : grammar.grammar.n_nonterminals ≤ words.length := by
    have range :=
      (invariant.production.range.validation.encoded.validation_facts
        invariant.production.range.validation.grammarWellFormed).prelude.lhsOffsetsRange
    rcases range with ⟨_, offsetFits, remainingFits⟩
    omega
  have incrementBound : nonterminal + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.le_trans (Nat.succ_le_of_lt bound) countFits)
      invariant.production.range.validation.wordsI32
  have result := executesIncrementOwnedI32Local verifiedParserCore state 21
    invariant.nonterminalCell nonterminal
    invariant.production.range.validation.stateWellFormed
    invariant.nonterminalOwned incrementBound
  let after := Classical.choose result
  have facts := Classical.choose_spec result
  exact {
    after := after
    execution := by simpa [parserIncrementLocal] using facts.1
    effect := facts.2.2.2
    invariant := invariant.after_counter_effect facts.2.2.2 facts.2.1
      facts.2.2.1
    nonterminalCell_eq := rfl }

structure GrammarNonterminalIteration
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (before : State) (nonterminal : Nat)
    (beforeInvariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell before nonterminal) where
  after : State
  execution : Executes verifiedParserCore before
    parserGrammarNonterminalLoopBody .next after
  effect : ModifiesOnly (CellSet.singleton beforeInvariant.nonterminalCell)
    before after
  invariant : GrammarNonterminalLoopInvariant layout grammar words grammarCell
    after (nonterminal + 1)
  nonterminalCell_eq : invariant.nonterminalCell =
    beforeInvariant.nonterminalCell

/-- Execute one exact row of the extracted nonterminal validator.  The row
    metadata and listed-production counter are scoped temporaries; only the
    enclosing nonterminal counter is caller-visible. -/
noncomputable def GrammarNonterminalLoopInvariant.execute_iteration
    (invariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell state nonterminal)
    (bound : nonterminal < grammar.grammar.n_nonterminals) :
    GrammarNonterminalIteration layout grammar words grammarCell state
      nonterminal invariant := by
  let rowFin : Fin grammar.productionsByLhs.length :=
    ⟨nonterminal, by
      simpa [invariant.production.range.validation.grammarWellFormed.lhsIndexCount]
        using bound⟩
  have rowBound : nonterminal < grammar.productionsByLhs.length :=
    rowFin.isLt
  let first := grammar.lhsOffsets.get
    ⟨nonterminal, by simpa only [IndexedGrammar.lhsOffsets_length] using rowBound⟩
  let count := grammar.lhsCounts.get
    ⟨nonterminal, by simpa only [IndexedGrammar.lhsCounts_length] using rowBound⟩
  let firstValue : Value := .signed .i32 (Int.ofNat first)
  let countValue : Value := .signed .i32 (Int.ofNat count)
  let zeroValue : Value := .signed .i32 0
  let state22 := state.bindLocal 22 firstValue
  let invariant22 := invariant.after_temporary_bind 22 firstValue (by decide)
  let state23 := state22.bindLocal 23 countValue
  let rowInvariant := invariant.bind_row first count
  have rowState : state23 =
      parserGrammarNonterminalRowState state first count := by rfl
  have firstInitializer : Evaluates verifiedParserCore state
      (.index (.local 0) (.binary .add (.local 18) (.local 21)))
      firstValue state := by
    simpa [firstValue, first, rowFin] using invariant.read_first bound
  have countInitializer : Evaluates verifiedParserCore state22
      (.index (.local 0) (.binary .add (.local 19) (.local 21)))
      countValue state22 := by
    simpa [state22, invariant22, countValue, count, rowFin] using
      invariant22.read_count bound
  have countEq : count = (grammar.productionsByLhs.get rowFin).length := by
    simpa [count, rowFin] using IndexedGrammar.lhsCounts_get grammar rowFin
  have rowRange : first + count ≤ grammar.lhsProductions.length := by
    rw [countEq]
    have fits := offsetsFrom_row_fits 0 grammar.productionsByLhs rowFin
    simpa [first, IndexedGrammar.lhsOffsets,
      IndexedGrammar.lhsProductions, rowFin] using fits
  have guardExecution : Executes verifiedParserCore state23
      parserGrammarNonterminalInvalidGuard .next state23 := by
    rw [rowState]
    exact rowInvariant.invalid_guard_executes rowRange
  let listedInvariant := rowInvariant.listed_loop_entry
  let listedRun := listedInvariant.execute_loop bound
    (by simp [first, rowFin]) countEq rowRange (Nat.zero_le count)
  let increment := listedRun.invariant.row.loop.increment bound
  have incrementEffect : ModifiesOnly
      (CellSet.singleton rowInvariant.loop.nonterminalCell)
      listedRun.after increment.after := by
    have beforeSame : listedRun.invariant.row.loop.nonterminalCell =
        rowInvariant.loop.nonterminalCell :=
      listedRun.nonterminalCell_eq.trans (by rfl)
    simpa [beforeSame] using increment.effect
  have local24Body : Executes verifiedParserCore
      (state23.bindLocal 24 zeroValue)
      (.sequence parserGrammarListedLoop (parserIncrementLocal 21))
      .next increment.after := by
    have entryState : state23.bindLocal 24 zeroValue =
        (parserGrammarNonterminalRowState state first count).bindLocal 24
          (.signed .i32 0) := by
      simpa [rowState, zeroValue]
    rw [entryState]
    exact executesSequence listedRun.execution increment.execution
  let after24 := restoreLocals state23 increment.after
  have scoped24 : Executes verifiedParserCore state23
      (.letLocal 24 parserI32Type (.value (.signed .i32 0))
        (.sequence parserGrammarListedLoop (parserIncrementLocal 21)))
      .next after24 := by
    simpa [after24, zeroValue] using
      executesLetLocal (type := parserI32Type)
        (show Evaluates verifiedParserCore state23
          (.value (.signed .i32 0)) zeroValue state23 from ⟨1, rfl⟩)
        local24Body
  have entered24 : StoreEffect
      (CellSet.singleton listedInvariant.indexCell) state23
      (state23.bindLocal 24 zeroValue) :=
    (bindLocal_effect state23 24 zeroValue).weaken CellSet.empty_subset
  have listedStore : StoreEffect
      (CellSet.singleton listedInvariant.indexCell) state23 listedRun.after :=
    entered24.trans_same listedRun.effect.toStoreEffect
  have combinedStore : StoreEffect
      (CellSet.union (CellSet.singleton listedInvariant.indexCell)
        (CellSet.singleton rowInvariant.loop.nonterminalCell))
      state23 increment.after :=
    listedStore.trans incrementEffect.toStoreEffect
  have visibleStore : StoreEffect
      (CellSet.singleton rowInvariant.loop.nonterminalCell)
      state23 increment.after := by
    apply combinedStore.hideFreshWritesExcept
    intro cell written
    rcases written with fresh | retained
    · exact Or.inr (by simpa [CellSet.singleton] using
        (show state23.nextCell ≤ cell from fresh ▸ Nat.le_refl _))
    · exact Or.inl retained
  have effect24 : ModifiesOnly
      (CellSet.singleton rowInvariant.loop.nonterminalCell)
      state23 after24 := by
    simpa [after24] using visibleStore.restoreLocals
  have after24WellFormed : StateWellFormed after24 :=
    visibleStore.restoreLocals_wellFormed
      rowInvariant.loop.production.range.validation.stateWellFormed
      increment.invariant.production.range.validation.stateWellFormed
  let after23 := restoreLocals state22 after24
  let after22 := restoreLocals state after23
  have effect23 : ModifiesOnly
      (CellSet.singleton invariant.nonterminalCell) state22 after23 := by
    have sameCell : rowInvariant.loop.nonterminalCell =
        invariant.nonterminalCell := by rfl
    simpa [after23, state23, countValue, sameCell] using
      temporaryLocal_effect 23 countValue effect24.toStoreEffect
  have after23WellFormed : StateWellFormed after23 := by
    have entered := (bindLocal_effect state22 23 countValue).weaken
      (CellSet.empty_subset : CellSet.Subset CellSet.empty
        (CellSet.singleton invariant.nonterminalCell))
    have body : StoreEffect (CellSet.singleton invariant.nonterminalCell)
        (state22.bindLocal 23 countValue) after24 := by
      have sameCell : rowInvariant.loop.nonterminalCell =
          invariant.nonterminalCell := by rfl
      simpa [state23, sameCell] using effect24.toStoreEffect
    exact (entered.trans_same body).restoreLocals_wellFormed
      invariant22.production.range.validation.stateWellFormed
      after24WellFormed
  have effect22 : ModifiesOnly
      (CellSet.singleton invariant.nonterminalCell) state after22 := by
    simpa [after22, state22, firstValue] using
      temporaryLocal_effect 22 firstValue effect23.toStoreEffect
  have after22WellFormed : StateWellFormed after22 := by
    have entered := (bindLocal_effect state 22 firstValue).weaken
      (CellSet.empty_subset : CellSet.Subset CellSet.empty
        (CellSet.singleton invariant.nonterminalCell))
    have body : StoreEffect (CellSet.singleton invariant.nonterminalCell)
        (state.bindLocal 22 firstValue) after23 := by
      simpa [state22] using effect23.toStoreEffect
    exact (entered.trans_same body).restoreLocals_wellFormed
      invariant.production.range.validation.stateWellFormed
      after23WellFormed
  have afterOwned : (Assertion.localPointsTo 21 invariant.nonterminalCell
      (some (.signed .i32 (Int.ofNat (nonterminal + 1))))).holds after22 := by
    constructor
    · change state.cellId? 21 = some invariant.nonterminalCell
      exact invariant.nonterminalOwned.1
    · change increment.after.cellEntry? invariant.nonterminalCell = some {
        id := invariant.nonterminalCell
        value := some (.signed .i32 (Int.ofNat (nonterminal + 1))) }
      have found := increment.invariant.nonterminalOwned.2
      have cellEq : increment.invariant.nonterminalCell =
          invariant.nonterminalCell :=
        increment.nonterminalCell_eq.trans
          (listedRun.nonterminalCell_eq.trans (by rfl))
      rw [cellEq] at found
      exact found
  let afterInvariant := invariant.after_counter_effect effect22
    after22WellFormed afterOwned
  have guardedBody : Executes verifiedParserCore state23
      (.sequence parserGrammarNonterminalInvalidGuard
        (.letLocal 24 parserI32Type (.value (.signed .i32 0))
          (.sequence parserGrammarListedLoop (parserIncrementLocal 21))))
      .next after24 :=
    executesSequence guardExecution scoped24
  have scoped23 := executesLetLocal (type := parserI32Type)
    countInitializer guardedBody
  have scoped22 := executesLetLocal (type := parserI32Type)
    firstInitializer scoped23
  exact {
    after := after22
    execution := by
      simpa [parserGrammarNonterminalLoopBody, after22, after23, after24,
        state22, state23, firstValue, countValue, zeroValue] using scoped22
    effect := effect22
    invariant := afterInvariant
    nonterminalCell_eq := rfl }

structure GrammarNonterminalLoopExecution
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (grammarCell : CellId)
    (before : State) (nonterminal : Nat)
    (beforeInvariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell before nonterminal) where
  after : State
  execution : Executes verifiedParserCore before
    parserGrammarNonterminalLoop .next after
  effect : ModifiesOnly (CellSet.singleton beforeInvariant.nonterminalCell)
    before after
  invariant : GrammarNonterminalLoopInvariant layout grammar words grammarCell
    after grammar.grammar.n_nonterminals
  nonterminalCell_eq : invariant.nonterminalCell =
    beforeInvariant.nonterminalCell

/-- The complete second validation loop from the extracted parser, with one
    semantic iteration for every dense nonterminal row. -/
noncomputable def GrammarNonterminalLoopInvariant.execute_loop
    (invariant : GrammarNonterminalLoopInvariant layout grammar words
      grammarCell state nonterminal)
    (nonterminalLe : nonterminal ≤ grammar.grammar.n_nonterminals) :
    GrammarNonterminalLoopExecution layout grammar words grammarCell state
      nonterminal invariant := by
  by_cases done : nonterminal = grammar.grammar.n_nonterminals
  · subst nonterminal
    exact {
      after := state
      execution := by
        rw [extractedParserGrammarValid_nonterminal_loop_shape]
        exact executesWhileFalse (invariant.condition_false (by omega))
      effect := ModifiesOnly.reflAny _ state
      invariant := invariant
      nonterminalCell_eq := rfl }
  · have bound : nonterminal < grammar.grammar.n_nonterminals := by omega
    let iteration := invariant.execute_iteration bound
    let rest := iteration.invariant.execute_loop (by omega)
    have restEffect : ModifiesOnly
        (CellSet.singleton invariant.nonterminalCell)
        iteration.after rest.after := by
      simpa [iteration.nonterminalCell_eq] using rest.effect
    exact {
      after := rest.after
      execution := by
        rw [extractedParserGrammarValid_nonterminal_loop_shape]
        have restExpected := rest.execution
        rw [extractedParserGrammarValid_nonterminal_loop_shape] at restExpected
        exact executesWhileTrueThen (invariant.condition_true bound)
          iteration.execution restExpected
      effect := iteration.effect.trans_same restEffect
      invariant := rest.invariant
      nonterminalCell_eq := rest.nonterminalCell_eq.trans
        iteration.nonterminalCell_eq }
termination_by grammar.grammar.n_nonterminals - nonterminal
decreasing_by omega

noncomputable def GrammarRangeInvariant.production_loop_entry
    (invariant : GrammarRangeInvariant layout grammar words grammarCell state) :
    GrammarProductionLoopInvariant layout grammar words grammarCell
      (parserGrammarProductionState state layout) 0 := by
  let lhsValue : Value :=
    .signed .i32 (Int.ofNat layout.productionLhsOffset)
  let offsetsValue : Value :=
    .signed .i32 (Int.ofNat layout.rhsOffsetsOffset)
  let lengthsValue : Value :=
    .signed .i32 (Int.ofNat layout.rhsLengthsOffset)
  let symbolsValue : Value :=
    .signed .i32 (Int.ofNat layout.rhsSymbolsOffset)
  let zeroValue : Value := .signed .i32 0
  let state8 := state.bindLocal 8 lhsValue
  let invariant8 := invariant.after_bind_local 8 lhsValue
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide)
  let state9 := state8.bindLocal 9 offsetsValue
  let invariant9 := invariant8.after_bind_local 9 offsetsValue
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide)
  let state10 := state9.bindLocal 10 lengthsValue
  let invariant10 := invariant9.after_bind_local 10 lengthsValue
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide)
  let state11 := state10.bindLocal 11 symbolsValue
  let invariant11 := invariant10.after_bind_local 11 symbolsValue
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide)
  let state12 := state11.bindLocal 12 zeroValue
  let invariant12 := invariant11.after_bind_local 12 zeroValue
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide)
  have finalState : state12 = parserGrammarProductionState state layout := by
    rfl
  have counterOwned : (Assertion.localPointsTo 12 state11.nextCell
      (some zeroValue)).holds state12 := by
    constructor
    · simp [state12, State.bindLocal, State.bindCell, State.cellId?]
    · simpa [state12, State.bindLocal] using
        bindCell_finds_fresh_cell state11 12 (some zeroValue)
          invariant11.validation.stateWellFormed
  refine {
    range := ?_
    productionLhsOffsetLocal := ?_
    rhsOffsetsOffsetLocal := ?_
    rhsLengthsOffsetLocal := ?_
    rhsSymbolsOffsetLocal := ?_
    productionCell := state11.nextCell
    productionOwned := ?_
    productionSeparate := ?_
    productionNotGrammar := ?_ }
  · rw [← finalState]
    exact invariant12
  · simpa [parserGrammarProductionState, parserGrammarProductionBindings,
      lhsValue, offsetsValue, lengthsValue, symbolsValue, zeroValue] using
      bindLocals_local_of_binding state [] [
        (9, offsetsValue), (10, lengthsValue), (11, symbolsValue),
        (12, zeroValue)] 8 lhsValue invariant.validation.stateWellFormed
        (by simp)
  · simpa [parserGrammarProductionState, parserGrammarProductionBindings,
      lhsValue, offsetsValue, lengthsValue, symbolsValue, zeroValue] using
      bindLocals_local_of_binding state [(8, lhsValue)] [
        (10, lengthsValue), (11, symbolsValue), (12, zeroValue)]
        9 offsetsValue invariant.validation.stateWellFormed (by simp)
  · simpa [parserGrammarProductionState, parserGrammarProductionBindings,
      lhsValue, offsetsValue, lengthsValue, symbolsValue, zeroValue] using
      bindLocals_local_of_binding state [(8, lhsValue), (9, offsetsValue)] [
        (11, symbolsValue), (12, zeroValue)] 10 lengthsValue
        invariant.validation.stateWellFormed (by simp)
  · simpa [parserGrammarProductionState, parserGrammarProductionBindings,
      lhsValue, offsetsValue, lengthsValue, symbolsValue, zeroValue] using
      bindLocals_local_of_binding state [
        (8, lhsValue), (9, offsetsValue), (10, lengthsValue)] [
        (12, zeroValue)] 11 symbolsValue
        invariant.validation.stateWellFormed (by simp)
  · simpa [finalState, zeroValue] using counterOwned
  · intro cell framed written
    obtain ⟨id, idBound, same⟩ := framed
    subst cell
    have idLt : id < 12 :=
      mem_parserGrammarProductionProtectedIds_iff id |>.1 idBound
    have different : (12 : VarId) ≠ id := Ne.symm (Nat.ne_of_lt idLt)
    rw [← finalState] at same
    have oldCell : state11.cellId? id = some state11.nextCell := by
      simpa [state12, State.bindLocal, State.bindCell,
        State.cellId?, different] using same
    have below :=
      Lanius.Separation.StateWellFormed.cell_lt_next_of_local_binding
        id state11.nextCell invariant11.validation.stateWellFormed oldCell
    exact (Nat.lt_irrefl state11.nextCell) below
  · intro same
    have below := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant11.validation.stateWellFormed
      invariant11.validation.grammarBacking
    rw [← same] at below
    exact (Nat.lt_irrefl state11.nextCell) below

/-- Close the five hoisted-offset/counter scopes around a proved production
    loop and its continuation. The implication exposes the exact loop-entry
    state and its ownership invariant to the algorithm proof. -/
noncomputable def GrammarRangeInvariant.execute_production_scopes
    (invariant : GrammarRangeInvariant layout grammar words grammarCell state)
    (bodyResult : Executes verifiedParserCore
      (parserGrammarProductionState state layout)
        (.sequence parserGrammarProductionLoop
          parserGrammarValidationAfterProductionLoop)
        completion completed)
    (bodyEffect : ModifiesOnly (CellSet.singleton (state.nextCell + 4))
      (parserGrammarProductionState state layout) completed)
    (completedWellFormed : StateWellFormed completed) :
    ExecutionWithEffect verifiedParserCore state
      parserGrammarValidationAfterRangeGuard completion CellSet.empty := by
  let lhsValue : Value :=
    .signed .i32 (Int.ofNat layout.productionLhsOffset)
  let offsetsValue : Value :=
    .signed .i32 (Int.ofNat layout.rhsOffsetsOffset)
  let lengthsValue : Value :=
    .signed .i32 (Int.ofNat layout.rhsLengthsOffset)
  let symbolsValue : Value :=
    .signed .i32 (Int.ofNat layout.rhsSymbolsOffset)
  let zeroValue : Value := .signed .i32 0
  let state8 := state.bindLocal 8 lhsValue
  let invariant8 := invariant.after_bind_local 8 lhsValue
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide)
  let state9 := state8.bindLocal 9 offsetsValue
  let invariant9 := invariant8.after_bind_local 9 offsetsValue
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide)
  let state10 := state9.bindLocal 10 lengthsValue
  let invariant10 := invariant9.after_bind_local 10 lengthsValue
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide)
  let state11 := state10.bindLocal 11 symbolsValue
  let invariant11 := invariant10.after_bind_local 11 symbolsValue
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by decide) (by decide)
  let state12 := state11.bindLocal 12 zeroValue
  have entryState : state12 = parserGrammarProductionState state layout := by
    rfl
  have lhsInitializer : Evaluates verifiedParserCore state
      (.index (.local 0) (.constant 15)) lhsValue state := by
    simpa [lhsValue] using invariant.validation.evaluates_header 15 8
      layout.productionLhsOffset invariant.validation.encoded.productionLhsOffset
      verifiedParser_range_header_constants.2.1
  have offsetsInitializer : Evaluates verifiedParserCore state8
      (.index (.local 0) (.constant 16)) offsetsValue state8 := by
    simpa [offsetsValue] using invariant8.validation.evaluates_header 16 9
      layout.rhsOffsetsOffset invariant8.validation.encoded.rhsOffsetsOffset
      verifiedParser_range_header_constants.2.2.1
  have lengthsInitializer : Evaluates verifiedParserCore state9
      (.index (.local 0) (.constant 17)) lengthsValue state9 := by
    simpa [lengthsValue] using invariant9.validation.evaluates_header 17 10
      layout.rhsLengthsOffset invariant9.validation.encoded.rhsLengthsOffset
      verifiedParser_range_header_constants.2.2.2.1
  have symbolsInitializer : Evaluates verifiedParserCore state10
      (.index (.local 0) (.constant 18)) symbolsValue state10 := by
    simpa [symbolsValue] using invariant10.validation.evaluates_header 18 11
      layout.rhsSymbolsOffset invariant10.validation.encoded.rhsSymbolsOffset
      verifiedParser_range_header_constants.2.2.2.2.1
  have zeroInitializer : Evaluates verifiedParserCore state11
      (.value (.signed .i32 0)) zeroValue state11 := ⟨1, rfl⟩
  have effect12 : ModifiesOnly (CellSet.singleton state11.nextCell)
      state12 completed := by
    have next11 : state11.nextCell = state.nextCell + 4 := by
      simp [state11, state10, state9, state8, State.bindLocal,
        State.bindCell]
    rw [entryState, next11]
    exact bodyEffect
  let closed12 := closesFreshLocal (type := parserI32Type)
    invariant11.validation.stateWellFormed
    zeroInitializer (entryState ▸ bodyResult) effect12 completedWellFormed
  let closed11 := closesFreshLocal (type := parserI32Type)
    invariant10.validation.stateWellFormed
    symbolsInitializer closed12.execution
      (closed12.effect.weaken CellSet.empty_subset) closed12.wellFormed
  let closed10 := closesFreshLocal (type := parserI32Type)
    invariant9.validation.stateWellFormed
    lengthsInitializer closed11.execution
      (closed11.effect.weaken CellSet.empty_subset) closed11.wellFormed
  let closed9 := closesFreshLocal (type := parserI32Type)
    invariant8.validation.stateWellFormed
    offsetsInitializer closed10.execution
      (closed10.effect.weaken CellSet.empty_subset) closed10.wellFormed
  let closed8 := closesFreshLocal (type := parserI32Type)
    invariant.validation.stateWellFormed
    lhsInitializer closed9.execution
      (closed9.effect.weaken CellSet.empty_subset) closed9.wellFormed
  exact {
    after := closed8.after
    execution := by
      rw [extractedParserGrammarValid_production_scope_shape]
      simpa [parserGrammarProductionScopes, state8, state9, state10, state11,
        state12, lhsValue, offsetsValue, lengthsValue, symbolsValue, zeroValue,
        closed12, closed11, closed10, closed9, closed8] using closed8.execution
    effect := closed8.effect
    wellFormed := closed8.wellFormed
  }

/-- Close the three hoisted row-table offsets and nonterminal counter around
    the proved nonterminal loop and successful return. -/
noncomputable def GrammarProductionLoopInvariant.execute_nonterminal_scopes
    (invariant : GrammarProductionLoopInvariant layout grammar words
      grammarCell state grammar.productionCount)
    (bodyResult : Executes verifiedParserCore
      (parserGrammarNonterminalState state layout)
        (.sequence parserGrammarNonterminalLoop
          parserGrammarValidationSuccess)
        completion completed)
    (bodyEffect : ModifiesOnly (CellSet.singleton (state.nextCell + 3))
      (parserGrammarNonterminalState state layout) completed)
    (completedWellFormed : StateWellFormed completed) :
    ExecutionWithEffect verifiedParserCore state
      parserGrammarValidationAfterProductionLoop completion CellSet.empty := by
  let offsetsValue : Value :=
    .signed .i32 (Int.ofNat layout.lhsOffsetsOffset)
  let countsValue : Value :=
    .signed .i32 (Int.ofNat layout.lhsCountsOffset)
  let productionsValue : Value :=
    .signed .i32 (Int.ofNat layout.lhsProductionsOffset)
  let zeroValue : Value := .signed .i32 0
  let state18 := state.bindLocal 18 offsetsValue
  let invariant18 := invariant.after_temporary_bind 18 offsetsValue (by decide)
  let state19 := state18.bindLocal 19 countsValue
  let invariant19 := invariant18.after_temporary_bind 19 countsValue
    (by decide)
  let state20 := state19.bindLocal 20 productionsValue
  let invariant20 := invariant19.after_temporary_bind 20 productionsValue
    (by decide)
  let state21 := state20.bindLocal 21 zeroValue
  have entryState : state21 = parserGrammarNonterminalState state layout := by
    rfl
  have offsetsInitializer : Evaluates verifiedParserCore state
      (.index (.local 0) (.constant 20)) offsetsValue state := by
    simpa [offsetsValue] using invariant.range.validation.evaluates_header
      20 13 layout.lhsOffsetsOffset
      invariant.range.validation.encoded.lhsOffsetsOffset
      verifiedParser_range_header_constants.2.2.2.2.2.1
  have countsInitializer : Evaluates verifiedParserCore state18
      (.index (.local 0) (.constant 21)) countsValue state18 := by
    simpa [countsValue] using invariant18.range.validation.evaluates_header
      21 14 layout.lhsCountsOffset
      invariant18.range.validation.encoded.lhsCountsOffset
      verifiedParser_range_header_constants.2.2.2.2.2.2.1
  have productionsInitializer : Evaluates verifiedParserCore state19
      (.index (.local 0) (.constant 22)) productionsValue state19 := by
    simpa [productionsValue] using
      invariant19.range.validation.evaluates_header
        22 15 layout.lhsProductionsOffset
        invariant19.range.validation.encoded.lhsProductionsOffset
        verifiedParser_range_header_constants.2.2.2.2.2.2.2
  have zeroInitializer : Evaluates verifiedParserCore state20
      (.value (.signed .i32 0)) zeroValue state20 := ⟨1, rfl⟩
  have effect21 : ModifiesOnly (CellSet.singleton state20.nextCell)
      state21 completed := by
    have next20 : state20.nextCell = state.nextCell + 3 := by
      simp [state20, state19, state18, State.bindLocal, State.bindCell]
    rw [entryState, next20]
    exact bodyEffect
  let closed21 := closesFreshLocal (type := parserI32Type)
    invariant20.range.validation.stateWellFormed
    zeroInitializer (entryState ▸ bodyResult) effect21 completedWellFormed
  let closed20 := closesFreshLocal (type := parserI32Type)
    invariant19.range.validation.stateWellFormed
    productionsInitializer closed21.execution
      (closed21.effect.weaken CellSet.empty_subset) closed21.wellFormed
  let closed19 := closesFreshLocal (type := parserI32Type)
    invariant18.range.validation.stateWellFormed
    countsInitializer closed20.execution
      (closed20.effect.weaken CellSet.empty_subset) closed20.wellFormed
  let closed18 := closesFreshLocal (type := parserI32Type)
    invariant.range.validation.stateWellFormed
    offsetsInitializer closed19.execution
      (closed19.effect.weaken CellSet.empty_subset) closed19.wellFormed
  exact {
    after := closed18.after
    execution := by
      rw [extractedParserGrammarValid_nonterminal_scope_shape]
      simpa [parserGrammarNonterminalScopes, state18, state19, state20,
        state21, offsetsValue, countsValue, productionsValue, zeroValue,
        closed21, closed20, closed19, closed18] using closed18.execution
    effect := closed18.effect
    wellFormed := closed18.wellFormed
  }

/-- Execute the extracted validator through its header loads and complete
    packed-table range guard. The continuation starts in the state produced by
    the eight helper calls; the enclosing lexical scopes are restored exactly
    as the Core semantics requires. -/
noncomputable def GrammarValidationInvariant.execute_count_scopes
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell state)
    (continuationResult :
      let rangeInvariant := invariant.range_state_invariant
      let guard := rangeInvariant.execute_invalid_ranges_guard
      Executes verifiedParserCore guard.after
        parserGrammarValidationAfterRangeGuard completion completed)
    (continuationEffect :
      let rangeInvariant := invariant.range_state_invariant
      let guard := rangeInvariant.execute_invalid_ranges_guard
      ModifiesOnly CellSet.empty guard.after completed)
    (completedWellFormed : StateWellFormed completed) :
    ExecutionWithEffect verifiedParserCore state
      parserGrammarValidationAfterPreludeGuards completion CellSet.empty := by
  let kindValue : Value :=
    .signed .i32 (Int.ofNat grammar.grammar.n_kinds)
  let productionValue : Value :=
    .signed .i32 (Int.ofNat grammar.productionCount)
  let nonterminalValue : Value :=
    .signed .i32 (Int.ofNat grammar.grammar.n_nonterminals)
  let startValue : Value :=
    .signed .i32 (Int.ofNat grammar.grammar.start_nonterminal)
  let rhsSymbolValue : Value :=
    .signed .i32 (Int.ofNat grammar.rhsSymbols.length)
  let lhsProductionValue : Value :=
    .signed .i32 (Int.ofNat grammar.lhsProductions.length)
  let state2 := state.bindLocal 2 kindValue
  let invariant2 := invariant.after_bind_local 2 kindValue (by decide)
    (by decide)
  let state3 := state2.bindLocal 3 productionValue
  let invariant3 := invariant2.after_bind_local 3 productionValue (by decide)
    (by decide)
  let state4 := state3.bindLocal 4 nonterminalValue
  let invariant4 := invariant3.after_bind_local 4 nonterminalValue (by decide)
    (by decide)
  let state5 := state4.bindLocal 5 startValue
  let invariant5 := invariant4.after_bind_local 5 startValue (by decide)
    (by decide)
  let state6 := state5.bindLocal 6 rhsSymbolValue
  let invariant6 := invariant5.after_bind_local 6 rhsSymbolValue (by decide)
    (by decide)
  let state7 := state6.bindLocal 7 lhsProductionValue
  let rangeInvariant := invariant.range_state_invariant
  have rangeState : state7 = parserGrammarRangeState state grammar := by rfl
  let guard := rangeInvariant.execute_invalid_ranges_guard
  have kindInitializer : Evaluates verifiedParserCore state
      (.index (.local 0) (.constant 8)) kindValue state := by
    simpa [kindValue] using invariant.evaluates_header 8 1
      grammar.grammar.n_kinds invariant.encoded.kindCount
      verifiedParser_count_header_constants.1
  have productionInitializer : Evaluates verifiedParserCore state2
      (.index (.local 0) (.constant 9)) productionValue state2 := by
    simpa [productionValue] using invariant2.evaluates_header 9 2
      grammar.productionCount invariant.encoded.productionCount
      verifiedParser_count_header_constants.2.1
  have nonterminalInitializer : Evaluates verifiedParserCore state3
      (.index (.local 0) (.constant 10)) nonterminalValue state3 := by
    simpa [nonterminalValue] using invariant3.evaluates_header 10 3
      grammar.grammar.n_nonterminals invariant.encoded.nonterminalCount
      verifiedParser_count_header_constants.2.2.1
  have startInitializer : Evaluates verifiedParserCore state4
      (.index (.local 0) (.constant 11)) startValue state4 := by
    simpa [startValue] using invariant4.evaluates_header 11 4
      grammar.grammar.start_nonterminal invariant.encoded.startNonterminal
      verifiedParser_count_header_constants.2.2.2.1
  have rhsSymbolInitializer : Evaluates verifiedParserCore state5
      (.index (.local 0) (.constant 19)) rhsSymbolValue state5 := by
    simpa [rhsSymbolValue] using invariant5.evaluates_header 19 12
      grammar.rhsSymbols.length invariant.encoded.rhsSymbolCount
      verifiedParser_count_header_constants.2.2.2.2.1
  have lhsProductionInitializer : Evaluates verifiedParserCore state6
      (.index (.local 0) (.constant 23)) lhsProductionValue state6 := by
    simpa [lhsProductionValue] using invariant6.evaluates_header 23 16
      grammar.lhsProductions.length invariant.encoded.lhsProductionCount
      verifiedParser_count_header_constants.2.2.2.2.2
  have rangeBody : Executes verifiedParserCore state7
      parserGrammarValidationAfterCountGuard completion completed := by
    rw [rangeState]
    rw [extractedParserGrammarValid_range_guard_shape]
    exact executesSequence guard.execution continuationResult
  have checkedBody : Executes verifiedParserCore state7
      (.sequence parserGrammarCountsGuardStmt
        parserGrammarValidationAfterCountGuard) completion completed :=
    executesSequence rangeInvariant.counts_guard_executes rangeBody
  have checkedEffect : ModifiesOnly CellSet.empty state7 completed := by
    rw [rangeState]
    exact guard.effect.trans_same continuationEffect
  let closed7 := closesFreshLocal (type := parserI32Type)
    invariant6.stateWellFormed
    lhsProductionInitializer checkedBody
      (checkedEffect.weaken CellSet.empty_subset) completedWellFormed
  let closed6 := closesFreshLocal (type := parserI32Type)
    invariant5.stateWellFormed
    rhsSymbolInitializer closed7.execution
      (closed7.effect.weaken CellSet.empty_subset) closed7.wellFormed
  let closed5 := closesFreshLocal (type := parserI32Type)
    invariant4.stateWellFormed
    startInitializer closed6.execution
      (closed6.effect.weaken CellSet.empty_subset) closed6.wellFormed
  let closed4 := closesFreshLocal (type := parserI32Type)
    invariant3.stateWellFormed
    nonterminalInitializer closed5.execution
      (closed5.effect.weaken CellSet.empty_subset) closed5.wellFormed
  let closed3 := closesFreshLocal (type := parserI32Type)
    invariant2.stateWellFormed
    productionInitializer closed4.execution
      (closed4.effect.weaken CellSet.empty_subset) closed4.wellFormed
  let closed2 := closesFreshLocal (type := parserI32Type)
    invariant.stateWellFormed
    kindInitializer closed3.execution
      (closed3.effect.weaken CellSet.empty_subset) closed3.wellFormed
  exact {
    after := closed2.after
    execution := by
      rw [extractedParserGrammarValid_count_scope_shape]
      simpa [parserGrammarCountScopes, state2, state3, state4, state5, state6,
        state7, kindValue, productionValue, nonterminalValue, startValue,
        rhsSymbolValue, lhsProductionValue, closed7, closed6, closed5,
        closed4, closed3, closed2] using closed2.execution
    effect := closed2.effect
    wellFormed := closed2.wellFormed
  }

theorem GrammarValidationInvariant.length_guard_evaluates_false
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell state) :
    Evaluates verifiedParserCore state parserGrammarLengthGuardExpr
      (.boolean false) state := by
  have left : Evaluates verifiedParserCore state (.local 1)
      (.signed .i32 (Int.ofNat words.length)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 1
      (.signed .i32 (Int.ofNat words.length))
      invariant.grammarLengthLocal⟩
  have right : Evaluates verifiedParserCore state (.constant 6)
      (.signed .i32 17) state :=
    evaluatesConstant verifiedParser_range_valid_constant
  apply evaluatesEagerBinary (op := .less) (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]
  exact Int.ofNat_le.mpr invariant.encoded.headerPresent

theorem GrammarValidationInvariant.length_guard_executes
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell state) :
    Executes verifiedParserCore state parserGrammarLengthGuardStmt
      .next state := by
  exact executesIfFalse invariant.length_guard_evaluates_false
    (executesSkip verifiedParserCore state)

theorem GrammarValidationInvariant.version_guard_evaluates_false
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell state) :
    Evaluates verifiedParserCore state parserGrammarVersionGuardExpr
      (.boolean false) state := by
  have headerBound : 0 < words.length := by
    exact Nat.lt_of_lt_of_le (by decide) invariant.encoded.headerPresent
  have left := evaluatesParserHeaderRead words grammarCell 7 0 headerBound
    state invariant.grammarLocal invariant.grammarBacking
    verifiedParser_grammar_guard_constants.1
  have headerValue : words.get ⟨0, headerBound⟩ = 1 := by
    simpa [grammarVersion] using invariant.encoded.version.get
  rw [headerValue] at left
  have right : Evaluates verifiedParserCore state (.constant 5)
      (.signed .i32 1) state :=
    evaluatesConstant verifiedParser_grammar_guard_constants.2
  apply evaluatesEagerBinary (op := .notEqual) (by decide) (by decide)
    left right
  simp [evalBinaryValue, scalarEqual]

theorem GrammarValidationInvariant.version_guard_executes
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell state) :
    Executes verifiedParserCore state parserGrammarVersionGuardStmt
      .next state := by
  exact executesIfFalse invariant.version_guard_evaluates_false
    (executesSkip verifiedParserCore state)

/-- The two early rejection guards in the extracted validator are proved to
    fall through for every semantically encoded grammar. -/
theorem GrammarValidationInvariant.initial_guards_execute
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell state) :
    Executes verifiedParserCore state
      (.sequence parserGrammarLengthGuardStmt parserGrammarVersionGuardStmt)
      .next state := by
  exact executesSequence invariant.length_guard_executes
    invariant.version_guard_executes

theorem GrammarValidationInvariant.body_executes_of_after_guards
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell state)
    (remainderResult : Executes verifiedParserCore state
      parserGrammarValidationAfterPreludeGuards completion finalState) :
    Executes verifiedParserCore state extractedParserGrammarValidBody
      completion finalState := by
  rw [extractedParserGrammarValid_initial_shape]
  exact executesSequence invariant.length_guard_executes
    (executesSequence invariant.version_guard_executes remainderResult)

/-- Every semantically encoded, well-formed packed grammar follows the exact
    extracted `grammar_is_valid` implementation to its successful return.
    This composes both validator loops with all header, range, and scope
    proofs; the theorem is about the artifact-derived Core body rather than a
    handwritten approximation. -/
noncomputable def GrammarValidationInvariant.execute_success
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell state) :
    ExecutionWithEffect verifiedParserCore state
      extractedParserGrammarValidBody (.returned (some (.boolean true)))
      CellSet.empty := by
  let rangeInvariant := invariant.range_state_invariant
  let guard := rangeInvariant.execute_invalid_ranges_guard
  let productionInvariant := guard.invariant.production_loop_entry
  let productionRun := productionInvariant.execute_loop
    (Nat.zero_le grammar.productionCount)
  let nonterminalInvariant := productionRun.invariant.nonterminal_loop_entry
  let nonterminalRun := nonterminalInvariant.execute_loop
    (Nat.zero_le grammar.grammar.n_nonterminals)
  have success : Executes verifiedParserCore nonterminalRun.after
      parserGrammarValidationSuccess
      (.returned (some (.boolean true))) nonterminalRun.after := by
    rw [extractedParserGrammarValid_success_shape]
    exact executesSequenceReturned
      (executesReturnValue
        (show Evaluates verifiedParserCore nonterminalRun.after
          (.value (.boolean true)) (.boolean true) nonterminalRun.after from
          ⟨1, rfl⟩))
  have nonterminalBody : Executes verifiedParserCore
      (parserGrammarNonterminalState productionRun.after layout)
      (.sequence parserGrammarNonterminalLoop
        parserGrammarValidationSuccess)
      (.returned (some (.boolean true))) nonterminalRun.after := by
    exact executesSequence nonterminalRun.execution success
  have nonterminalBodyEffect : ModifiesOnly
      (CellSet.singleton (productionRun.after.nextCell + 3))
      (parserGrammarNonterminalState productionRun.after layout)
      nonterminalRun.after := by
    simpa [nonterminalInvariant, GrammarProductionLoopInvariant.nonterminal_loop_entry,
      parserGrammarNonterminalState, parserGrammarNonterminalBindings,
      State.bindLocals, State.bindLocal, State.bindCell] using
      nonterminalRun.effect
  let nonterminalScopes :=
    productionRun.invariant.execute_nonterminal_scopes nonterminalBody
      nonterminalBodyEffect
      nonterminalRun.invariant.production.range.validation.stateWellFormed
  have productionBody : Executes verifiedParserCore
      (parserGrammarProductionState guard.after layout)
      (.sequence parserGrammarProductionLoop
        parserGrammarValidationAfterProductionLoop)
      (.returned (some (.boolean true))) nonterminalScopes.after := by
    exact executesSequence productionRun.execution nonterminalScopes.execution
  have productionBodyEffect : ModifiesOnly
      (CellSet.singleton (guard.after.nextCell + 4))
      (parserGrammarProductionState guard.after layout)
      nonterminalScopes.after := by
    have loopEffect : ModifiesOnly
        (CellSet.singleton (guard.after.nextCell + 4))
        (parserGrammarProductionState guard.after layout)
        productionRun.after := by
      simpa [productionInvariant, GrammarRangeInvariant.production_loop_entry,
        parserGrammarProductionState, parserGrammarProductionBindings,
        State.bindLocals, State.bindLocal, State.bindCell] using
        productionRun.effect
    exact loopEffect.trans_same
      (nonterminalScopes.effect.weaken CellSet.empty_subset)
  let productionScopes := guard.invariant.execute_production_scopes
    productionBody productionBodyEffect nonterminalScopes.wellFormed
  have countContinuation : Executes verifiedParserCore guard.after
      parserGrammarValidationAfterRangeGuard
      (.returned (some (.boolean true))) productionScopes.after :=
    productionScopes.execution
  let countScopes := invariant.execute_count_scopes countContinuation
    productionScopes.effect productionScopes.wellFormed
  exact {
    after := countScopes.after
    execution := invariant.body_executes_of_after_guards countScopes.execution
    effect := countScopes.effect
    wellFormed := countScopes.wellFormed
  }

def parserGrammarValidBindings
    (words : List Int) (grammarCell : CellId) : List (VarId × Value) := [
  (0, parserGrammarValue words grammarCell),
  (1, .signed .i32 (Int.ofNat words.length))]

def parserGrammarValidCallee
    (caller : State) (words : List Int) (grammarCell : CellId) : State :=
  enterCall caller (parserGrammarValidBindings words grammarCell)

/-- Full internal-call rule for the extracted validator.  The untrusted caller
    supplies ordinary argument evaluation and a semantic invariant over the
    entered call frame; the proved body then returns `true`, with its scoped
    locals restored according to the Core call semantics. -/
theorem extractedParserGrammarValidCall_accepts_encoded
    (before afterArguments : State) (arguments : List Expr)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      parserGrammarValue words grammarCell,
      .signed .i32 (Int.ofNat words.length)] afterArguments)
    (invariant : GrammarValidationInvariant layout grammar words grammarCell
      (parserGrammarValidCallee afterArguments words grammarCell))
    (afterArgumentsWellFormed : StateWellFormed afterArguments) :
    ∃ after,
      Evaluates verifiedParserCore before
        (.call extractedParserGrammarValidFunction.id arguments)
        (.boolean true) after ∧
      ModifiesOnly CellSet.empty afterArguments after ∧
      StateWellFormed after := by
  let callee := parserGrammarValidCallee afterArguments words grammarCell
  let body := invariant.execute_success
  let completed := body.after
  let after := restoreLocals afterArguments completed
  have evaluation : Evaluates verifiedParserCore before
      (.call extractedParserGrammarValidFunction.id arguments)
      (.boolean true) after := by
    apply evaluatesCallReturned argumentsResult
      verifiedParserCore_finds_grammarValid
    · rw [extractedParserGrammarValid_function_shape.2.1]
      rfl
    · exact extractedParserGrammarValid_function_shape.2.2.2.1
    · simpa [callee, after, completed, parserGrammarValidCallee,
        parserGrammarValidBindings] using body.execution
  have entered : StoreEffect CellSet.empty afterArguments callee := by
    simpa [callee, parserGrammarValidCallee] using
      enterCall_effect afterArguments (parserGrammarValidBindings words grammarCell)
  have complete : StoreEffect CellSet.empty afterArguments completed :=
    entered.trans_same body.effect.toStoreEffect
  have effect : ModifiesOnly CellSet.empty afterArguments after := by
    simpa [after] using complete.restoreLocals
  have afterWellFormed : StateWellFormed after := by
    exact complete.restoreLocals_wellFormed afterArgumentsWellFormed
      body.wellFormed
  exact ⟨after, evaluation, effect, afterWellFormed⟩

theorem GrammarValidationInvariant.validation_facts
    (invariant : GrammarValidationInvariant layout grammar words
      grammarCell state) :
    GrammarValidationFacts layout grammar words :=
  invariant.encoded.validation_facts invariant.grammarWellFormed

end Lanius.Extraction.ParserValidation
