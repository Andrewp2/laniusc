import Lanius.Extraction.VerifiedParserAccessors
import Lanius.Compiler.ParserLanguage

namespace Lanius.Extraction.ParserScan

open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction
open Lanius.Compiler.Parser
open Lanius.Extraction.ParserAccessors

def extractedParserScanTerminalWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "scan_terminal"

def extractedParserScanTerminalFunction : Function :=
  CoreDecode.function extractedParserScanTerminalWire

def parserRejectExpr : Expr :=
  .unary .negate (.value (.signed .i32 1))

def parserRejectStmt : Stmt :=
  .sequence (.returnValue (some parserRejectExpr)) .skip

def parserPositionAdvanceExpr (amount : Int) : Expr :=
  .binary .add (.local 3) (.value (.signed .i32 amount))

def parserPositionAdvanceStmt (amount : Int) : Stmt :=
  .sequence (.returnValue (some (parserPositionAdvanceExpr amount))) .skip

def parserSplitMatchExpr : Expr :=
  .binary .logicalAnd
    (.binary .equal (.local 6)
      (.index (.local 0) (.constant 12)))
    (.binary .equal (.local 7)
      (.index (.local 0) (.constant 13)))

def parserSplitMatchStmt : Stmt :=
  .ifThenElse parserSplitMatchExpr (parserPositionAdvanceStmt 1) .skip

def parserOddPositionStmt : Stmt :=
  .sequence parserSplitMatchStmt parserRejectStmt

def parserCanonicalMatchStmt : Stmt :=
  .ifThenElse
    (.binary .equal (.local 6) (.local 7))
    (parserPositionAdvanceStmt 2) .skip

def parserEvenPositionStmt : Stmt :=
  .sequence parserCanonicalMatchStmt
    (.sequence parserSplitMatchStmt parserRejectStmt)

def parserScanTerminalDispatch : Stmt :=
  .sequence
    (.ifThenElse
      (.binary .equal
        (.binary .remainder (.local 3) (.value (.signed .i32 2)))
        (.value (.signed .i32 1)))
      parserOddPositionStmt .skip)
    parserEvenPositionStmt

def parserCanonicalKindExpr : Expr :=
  .index (.local 0)
    (.binary .add
      (.index (.local 0) (.constant 14))
      (.local 4))

def parserScanTerminalBody : Stmt :=
  .letLocal 5 parserI32Type
    (.binary .divide (.local 3) (.value (.signed .i32 2)))
    (.sequence
      (.ifThenElse
        (.binary .greaterEqual (.local 5) (.local 2))
        parserRejectStmt .skip)
      (.letLocal 6 parserI32Type
        (.index (.local 1) (.local 5))
        (.letLocal 7 parserI32Type parserCanonicalKindExpr
          parserScanTerminalDispatch)))

def extractedParserScanTerminalBody : Stmt :=
  extractedParserScanTerminalFunction.body.getD .skip

theorem extractedParserScanTerminal_function_shape :
    extractedParserScanTerminalFunction.id = 17 ∧
      extractedParserScanTerminalFunction.parameters = [
        (0, .slice parserI32Type),
        (1, .slice parserI32Type),
        (2, parserI32Type),
        (3, parserI32Type),
        (4, parserI32Type)] ∧
      extractedParserScanTerminalFunction.returnType = parserI32Type ∧
      extractedParserScanTerminalFunction.body = some parserScanTerminalBody ∧
      extractedParserScanTerminalFunction.external = none := by
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem extractedParserScanTerminalBody_eq :
    extractedParserScanTerminalBody = parserScanTerminalBody := by
  rfl

theorem verifiedParser_scan_terminal_constants :
    verifiedParserCore.constant? 12 = some {
        id := 12
        type := parserI32Type
        value := .signed .i32 5
      } ∧
      verifiedParserCore.constant? 13 = some {
        id := 13
        type := parserI32Type
        value := .signed .i32 6
      } ∧
      verifiedParserCore.constant? 14 = some {
        id := 14
        type := parserI32Type
        value := .signed .i32 7
      } := by
  have evidence :
      (verifiedParserCore.constant? 12).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (12, parserI32Type, some 5) ∧
      (verifiedParserCore.constant? 13).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (13, parserI32Type, some 6) ∧
      (verifiedParserCore.constant? 14).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (14, parserI32Type, some 7) := by
    native_decide
  exact ⟨
    constant_eq_of_signed_i32_evidence verifiedParserCore 12 5 evidence.1,
    constant_eq_of_signed_i32_evidence verifiedParserCore 13 6 evidence.2.1,
    constant_eq_of_signed_i32_evidence verifiedParserCore 14 7 evidence.2.2⟩

def scanTerminalValue (result : Option Nat) : Value :=
  match result with
  | some position => .signed .i32 (Int.ofNat position)
  | none => .signed .i32 (-1)

theorem verifiedParserCore_finds_scanTerminal :
    verifiedParserCore.function? extractedParserScanTerminalFunction.id =
      some extractedParserScanTerminalFunction := by
  unfold verifiedParserCore extractedParserScanTerminalFunction
    extractedParserScanTerminalWire
  rfl

private theorem evaluatesI32Local
    (state : State) (localId : VarId) (value : Nat)
    (found : state.local? localId = some (.signed .i32 (Int.ofNat value))) :
    Evaluates verifiedParserCore state (.local localId)
      (.signed .i32 (Int.ofNat value)) state :=
  ⟨1, evalLocal_of_local 1 verifiedParserCore state localId
    (.signed .i32 (Int.ofNat value)) found⟩

private theorem evaluatesReject (state : State) :
    Evaluates verifiedParserCore state parserRejectExpr
      (.signed .i32 (-1)) state := by
  apply evaluatesUnary (before := state) (afterOperand := state)
    (operandValue := .signed .i32 1)
  · exact ⟨1, rfl⟩
  · simp [evalUnaryValue, wrapSigned_i32_neg_one]

private theorem executesReject (state : State) :
    Executes verifiedParserCore state parserRejectStmt
      (.returned (some (.signed .i32 (-1)))) state := by
  apply executesSequenceReturned
  exact executesReturnValue (evaluatesReject state)

private theorem evaluatesPositionAdvance
    (state : State) (position amount : Nat)
    (positionLocal : state.local? 3 =
      some (.signed .i32 (Int.ofNat position)))
    (resultI32 : position + amount ≤ 2147483647) :
    Evaluates verifiedParserCore state
      (parserPositionAdvanceExpr (Int.ofNat amount))
      (.signed .i32 (Int.ofNat (position + amount))) state := by
  have positionResult := evaluatesI32Local state 3 position positionLocal
  have amountResult : Evaluates verifiedParserCore state
      (.value (.signed .i32 (Int.ofNat amount)))
      (.signed .i32 (Int.ofNat amount)) state := ⟨1, rfl⟩
  have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target
    (position + amount) resultI32
  apply evaluatesEagerBinary (by decide) (by decide) positionResult amountResult
  simp only [evalBinaryValue, evalSignedBinary]
  simp only [beq_self_eq_true, if_true]
  have cast : Int.ofNat position + Int.ofNat amount =
      Int.ofNat (position + amount) :=
    (Int.natCast_add position amount).symm
  rw [cast, wrapped]

private theorem executesPositionAdvance
    (state : State) (position amount : Nat)
    (positionLocal : state.local? 3 =
      some (.signed .i32 (Int.ofNat position)))
    (resultI32 : position + amount ≤ 2147483647) :
    Executes verifiedParserCore state
      (parserPositionAdvanceStmt (Int.ofNat amount))
      (.returned (some (.signed .i32 (Int.ofNat (position + amount)))))
      state := by
  apply executesSequenceReturned
  exact executesReturnValue
    (evaluatesPositionAdvance state position amount positionLocal resultI32)

private theorem evaluatesNatEquality
    (state : State) (left right : Expr) (leftValue rightValue : Nat)
    (leftResult : Evaluates verifiedParserCore state left
      (.signed .i32 (Int.ofNat leftValue)) state)
    (rightResult : Evaluates verifiedParserCore state right
      (.signed .i32 (Int.ofNat rightValue)) state) :
    Evaluates verifiedParserCore state (.binary .equal left right)
      (.boolean (decide (leftValue = rightValue))) state := by
  apply evaluatesEagerBinary (by decide) (by decide) leftResult rightResult
  by_cases same : leftValue = rightValue
  · subst rightValue
    simp [evalBinaryValue, scalarEqual]
  · have different : Int.ofNat leftValue ≠ Int.ofNat rightValue := by
      intro equal
      exact same (Int.ofNat_inj.mp equal)
    simp [evalBinaryValue, scalarEqual, same]
    exact different

private theorem evaluatesSplitMatch
    (state : State) (rawKind canonicalKind splitTokenKind
      splitComponentKind : Nat)
    (rawLocal : state.local? 6 =
      some (.signed .i32 (Int.ofNat rawKind)))
    (canonicalLocal : state.local? 7 =
      some (.signed .i32 (Int.ofNat canonicalKind)))
    (splitTokenRead : Evaluates verifiedParserCore state
      (.index (.local 0) (.constant 12))
      (.signed .i32 (Int.ofNat splitTokenKind)) state)
    (splitComponentRead : Evaluates verifiedParserCore state
      (.index (.local 0) (.constant 13))
      (.signed .i32 (Int.ofNat splitComponentKind)) state) :
    Evaluates verifiedParserCore state parserSplitMatchExpr
      (.boolean (decide
        (rawKind = splitTokenKind ∧ canonicalKind = splitComponentKind)))
      state := by
  have rawResult := evaluatesI32Local state 6 rawKind rawLocal
  have canonicalResult := evaluatesI32Local state 7 canonicalKind canonicalLocal
  have left := evaluatesNatEquality state (.local 6)
    (.index (.local 0) (.constant 12)) rawKind splitTokenKind rawResult
    splitTokenRead
  have right := evaluatesNatEquality state (.local 7)
    (.index (.local 0) (.constant 13)) canonicalKind splitComponentKind
    canonicalResult splitComponentRead
  simpa [parserSplitMatchExpr] using evaluatesPureLogicalAnd left right

private theorem evaluatesPositionParity
    (state : State) (position : Nat)
    (positionLocal : state.local? 3 =
      some (.signed .i32 (Int.ofNat position))) :
    Evaluates verifiedParserCore state
      (.binary .equal
        (.binary .remainder (.local 3) (.value (.signed .i32 2)))
        (.value (.signed .i32 1)))
      (.boolean (decide (position % 2 = 1))) state := by
  have positionResult := evaluatesI32Local state 3 position positionLocal
  have twoResult : Evaluates verifiedParserCore state
      (.value (.signed .i32 2)) (.signed .i32 2) state := ⟨1, rfl⟩
  have remainderResult : Evaluates verifiedParserCore state
      (.binary .remainder (.local 3) (.value (.signed .i32 2)))
      (.signed .i32 (Int.ofNat (position % 2))) state := by
    have remainderI32 : position % 2 ≤ 2147483647 := by omega
    have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target
      (position % 2) remainderI32
    have remainderCast :
        Int.ofNat position - truncDiv (Int.ofNat position) 2 * 2 =
          Int.ofNat (position % 2) := by
      have quotient : truncDiv (Int.ofNat position) 2 =
          Int.ofNat (position / 2) := by
        simp [truncDiv]
      have sameDivision : truncDiv (Int.ofNat position) 2 =
          (Int.ofNat position).tdiv 2 := by
        rw [quotient]
        exact Int.ofNat_tdiv position 2
      calc
        Int.ofNat position - truncDiv (Int.ofNat position) 2 * 2 =
            Int.ofNat position - 2 * (Int.ofNat position).tdiv 2 := by
              rw [sameDivision, Int.mul_comm]
        _ = (Int.ofNat position).tmod 2 :=
          (Int.tmod_def (Int.ofNat position) 2).symm
        _ = Int.ofNat (position % 2) :=
          (Int.ofNat_tmod position 2).symm
    apply evaluatesEagerBinary (by decide) (by decide) positionResult twoResult
    simp only [evalBinaryValue, evalSignedBinary]
    simp only [show (SignedIntTy.i32 == SignedIntTy.i32) = true by decide,
      if_true]
    rw [remainderCast, wrapped]
    simp
  have oneResult : Evaluates verifiedParserCore state
      (.value (.signed .i32 1)) (.signed .i32 1) state := ⟨1, rfl⟩
  exact evaluatesNatEquality state
    (.binary .remainder (.local 3) (.value (.signed .i32 2)))
    (.value (.signed .i32 1)) (position % 2) 1 remainderResult oneResult

private theorem evaluatesRawCanonicalEquality
    (state : State) (rawKind canonicalKind : Nat)
    (rawLocal : state.local? 6 =
      some (.signed .i32 (Int.ofNat rawKind)))
    (canonicalLocal : state.local? 7 =
      some (.signed .i32 (Int.ofNat canonicalKind))) :
    Evaluates verifiedParserCore state
      (.binary .equal (.local 6) (.local 7))
      (.boolean (decide (rawKind = canonicalKind))) state :=
  evaluatesNatEquality state (.local 6) (.local 7) rawKind canonicalKind
    (evaluatesI32Local state 6 rawKind rawLocal)
    (evaluatesI32Local state 7 canonicalKind canonicalLocal)

/-- Exact control-flow proof for the terminal lattice decision after the raw
    and canonical token kinds have been loaded. Every branch returns the
    mathematical `scanTerminalStep` result and leaves memory unchanged. -/
theorem parserScanTerminalDispatch_executes
    (state : State) (position rawKind canonicalKind splitTokenKind
      splitComponentKind : Nat)
    (positionLocal : state.local? 3 =
      some (.signed .i32 (Int.ofNat position)))
    (rawLocal : state.local? 6 =
      some (.signed .i32 (Int.ofNat rawKind)))
    (canonicalLocal : state.local? 7 =
      some (.signed .i32 (Int.ofNat canonicalKind)))
    (splitTokenRead : Evaluates verifiedParserCore state
      (.index (.local 0) (.constant 12))
      (.signed .i32 (Int.ofNat splitTokenKind)) state)
    (splitComponentRead : Evaluates verifiedParserCore state
      (.index (.local 0) (.constant 13))
      (.signed .i32 (Int.ofNat splitComponentKind)) state)
    (positionAdvanceI32 : position + 2 ≤ 2147483647) :
    Executes verifiedParserCore state parserScanTerminalDispatch
      (.returned (some (scanTerminalValue
        (scanTerminalStep splitTokenKind splitComponentKind rawKind
          canonicalKind position)))) state := by
  have parity := evaluatesPositionParity state position positionLocal
  have splitMatch := evaluatesSplitMatch state rawKind canonicalKind
    splitTokenKind splitComponentKind rawLocal canonicalLocal splitTokenRead
    splitComponentRead
  have advanceOne := executesPositionAdvance state position 1 positionLocal
    (by omega)
  have advanceTwo := executesPositionAdvance state position 2 positionLocal
    positionAdvanceI32
  by_cases odd : position % 2 = 1
  · have parityTrue : Evaluates verifiedParserCore state
        (.binary .equal
          (.binary .remainder (.local 3) (.value (.signed .i32 2)))
          (.value (.signed .i32 1))) (.boolean true) state := by
      simpa [odd] using parity
    by_cases split :
        rawKind = splitTokenKind ∧ canonicalKind = splitComponentKind
    · have splitTrue : Evaluates verifiedParserCore state parserSplitMatchExpr
          (.boolean true) state := by
        simpa [split] using splitMatch
      have selected := executesIfTrue (elseBranch := .skip) splitTrue advanceOne
      have oddResult : Executes verifiedParserCore state parserOddPositionStmt
          (.returned (some (.signed .i32 (Int.ofNat (position + 1)))))
          state := by
        exact executesSequenceReturned selected
      have paritySelected := executesIfTrue (elseBranch := .skip) parityTrue
        oddResult
      simpa [parserScanTerminalDispatch, scanTerminalStep, odd, split,
        scanTerminalValue] using
        (executesSequenceReturned paritySelected)
    · have splitFalse : Evaluates verifiedParserCore state parserSplitMatchExpr
          (.boolean false) state := by
        simpa [split] using splitMatch
      have skipped := executesIfFalse (thenBranch := parserPositionAdvanceStmt 1)
        splitFalse (executesSkip verifiedParserCore state)
      have oddResult : Executes verifiedParserCore state parserOddPositionStmt
          (.returned (some (.signed .i32 (-1)))) state := by
        exact executesSequence skipped (executesReject state)
      have paritySelected := executesIfTrue (elseBranch := .skip) parityTrue
        oddResult
      simpa [parserScanTerminalDispatch, scanTerminalStep, odd, split,
        scanTerminalValue] using
        (executesSequenceReturned paritySelected)
  · have parityFalse : Evaluates verifiedParserCore state
        (.binary .equal
          (.binary .remainder (.local 3) (.value (.signed .i32 2)))
          (.value (.signed .i32 1))) (.boolean false) state := by
      simpa [odd] using parity
    have paritySkipped := executesIfFalse (thenBranch := parserOddPositionStmt)
      parityFalse (executesSkip verifiedParserCore state)
    have rawCanonical := evaluatesRawCanonicalEquality state rawKind
      canonicalKind rawLocal canonicalLocal
    by_cases direct : rawKind = canonicalKind
    · have directTrue : Evaluates verifiedParserCore state
          (.binary .equal (.local 6) (.local 7)) (.boolean true) state := by
        simpa [direct] using rawCanonical
      have selected := executesIfTrue (elseBranch := .skip) directTrue
        advanceTwo
      have evenResult : Executes verifiedParserCore state parserEvenPositionStmt
          (.returned (some (.signed .i32 (Int.ofNat (position + 2)))))
          state := executesSequenceReturned selected
      simpa [parserScanTerminalDispatch, scanTerminalStep, odd, direct,
        scanTerminalValue] using
        (executesSequence paritySkipped evenResult)
    · have directFalse : Evaluates verifiedParserCore state
          (.binary .equal (.local 6) (.local 7)) (.boolean false) state := by
        simpa [direct] using rawCanonical
      have directSkipped := executesIfFalse
        (thenBranch := parserPositionAdvanceStmt 2) directFalse
        (executesSkip verifiedParserCore state)
      by_cases split :
          rawKind = splitTokenKind ∧ canonicalKind = splitComponentKind
      · have splitTrue : Evaluates verifiedParserCore state parserSplitMatchExpr
            (.boolean true) state := by
          simpa [split] using splitMatch
        have selected := executesIfTrue (elseBranch := .skip) splitTrue
          advanceOne
        have tail : Executes verifiedParserCore state
            (.sequence parserSplitMatchStmt parserRejectStmt)
            (.returned (some (.signed .i32 (Int.ofNat (position + 1)))))
            state := executesSequenceReturned selected
        have evenResult : Executes verifiedParserCore state
            parserEvenPositionStmt
            (.returned (some (.signed .i32 (Int.ofNat (position + 1)))))
            state := executesSequence directSkipped tail
        simpa only [parserScanTerminalDispatch, scanTerminalStep, if_neg odd,
          if_neg direct, if_pos split, scanTerminalValue] using
          (executesSequence paritySkipped evenResult)
      · have splitFalse : Evaluates verifiedParserCore state
            parserSplitMatchExpr (.boolean false) state := by
          simpa [split] using splitMatch
        have splitSkipped := executesIfFalse
          (thenBranch := parserPositionAdvanceStmt 1) splitFalse
          (executesSkip verifiedParserCore state)
        have tail : Executes verifiedParserCore state
            (.sequence parserSplitMatchStmt parserRejectStmt)
            (.returned (some (.signed .i32 (-1)))) state :=
          executesSequence splitSkipped (executesReject state)
        have evenResult : Executes verifiedParserCore state
            parserEvenPositionStmt (.returned (some (.signed .i32 (-1))))
            state := executesSequence directSkipped tail
        simpa [parserScanTerminalDispatch, scanTerminalStep, odd, direct,
          split, scanTerminalValue] using
          (executesSequence paritySkipped evenResult)

def parserTokensValue (tokens : List Nat) (cell : CellId) : Value :=
  parserGrammarValue (tokens.map Int.ofNat) cell

structure ScanTerminalInvariant
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId) (position semanticKind : Nat)
    (runtime : State) : Prop where
  encoded : EncodesGrammar layout grammar words
  wordsI32 : words.length ≤ 2147483647
  tokensI32 : tokens.length ≤ 2147483647
  positionAdvanceI32 : position + 2 ≤ 2147483647
  semanticKindBound : semanticKind < grammar.grammar.canonical_kinds.length
  wellFormed : StateWellFormed runtime
  grammarLocal : runtime.local? 0 =
    some (parserGrammarValue words grammarCell)
  tokensLocal : runtime.local? 1 = some (parserTokensValue tokens tokensCell)
  tokenCountLocal : runtime.local? 2 =
    some (.signed .i32 (Int.ofNat tokens.length))
  positionLocal : runtime.local? 3 =
    some (.signed .i32 (Int.ofNat position))
  semanticKindLocal : runtime.local? 4 =
    some (.signed .i32 (Int.ofNat semanticKind))
  grammarBacking : runtime.cellEntry? grammarCell = some {
    id := grammarCell
    value := some (.array (signedI32Values words))
  }
  tokensBacking : runtime.cellEntry? tokensCell = some {
    id := tokensCell
    value := some (.array (signedI32Values (tokens.map Int.ofNat)))
  }

theorem ScanTerminalInvariant.after_bind_local
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind runtime)
    (id : VarId) (value : Value)
    (notInCallerFrame : id ∉ verifiedParserScanTerminalCallerFrameIds) :
    ScanTerminalInvariant layout grammar words tokens grammarCell tokensCell
      position semanticKind (runtime.bindLocal id value) := by
  have not0 : id ≠ 0 := by
    intro equal
    subst id
    apply notInCallerFrame
    simp [verifiedParserScanTerminal_caller_frame_ids]
  have not1 : id ≠ 1 := by
    intro equal
    subst id
    apply notInCallerFrame
    simp [verifiedParserScanTerminal_caller_frame_ids]
  have not2 : id ≠ 2 := by
    intro equal
    subst id
    apply notInCallerFrame
    simp [verifiedParserScanTerminal_caller_frame_ids]
  have not3 : id ≠ 3 := by
    intro equal
    subst id
    apply notInCallerFrame
    simp [verifiedParserScanTerminal_caller_frame_ids]
  have not4 : id ≠ 4 := by
    intro equal
    subst id
    apply notInCallerFrame
    simp [verifiedParserScanTerminal_caller_frame_ids]
  exact {
  encoded := invariant.encoded
  wordsI32 := invariant.wordsI32
  tokensI32 := invariant.tokensI32
  positionAdvanceI32 := invariant.positionAdvanceI32
  semanticKindBound := invariant.semanticKindBound
  wellFormed := bindLocal_preserves_well_formed runtime id value
    invariant.wellFormed
  grammarLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not0).trans
      invariant.grammarLocal
  tokensLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not1).trans
      invariant.tokensLocal
  tokenCountLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not2).trans
      invariant.tokenCountLocal
  positionLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not3).trans
      invariant.positionLocal
  semanticKindLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not4).trans
      invariant.semanticKindLocal
  grammarBacking := by
    have old := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant.wellFormed invariant.grammarBacking
    exact ((bindLocal_effect runtime id value).oldCells grammarCell old
      (by simp [CellSet.empty])).trans invariant.grammarBacking
  tokensBacking := by
    have old := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant.wellFormed invariant.tokensBacking
    exact ((bindLocal_effect runtime id value).oldCells tokensCell old
      (by simp [CellSet.empty])).trans invariant.tokensBacking
  }

private theorem evaluatesTokenIndex
    (state : State) (position : Nat)
    (positionLocal : state.local? 3 =
      some (.signed .i32 (Int.ofNat position)))
    (positionI32 : position ≤ 2147483647) :
    Evaluates verifiedParserCore state
      (.binary .divide (.local 3) (.value (.signed .i32 2)))
      (.signed .i32 (Int.ofNat (position / 2))) state := by
  have positionResult := evaluatesI32Local state 3 position positionLocal
  have twoResult : Evaluates verifiedParserCore state
      (.value (.signed .i32 2)) (.signed .i32 2) state := ⟨1, rfl⟩
  have quotient : truncDiv (Int.ofNat position) 2 =
      Int.ofNat (position / 2) := by
    simp [truncDiv]
  have quotientI32 : position / 2 ≤ 2147483647 := by omega
  have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target
    (position / 2) quotientI32
  apply evaluatesEagerBinary (by decide) (by decide) positionResult twoResult
  simp only [evalBinaryValue, evalSignedBinary]
  simp only [show (SignedIntTy.i32 == SignedIntTy.i32) = true by decide,
    if_true]
  rw [quotient, wrapped]
  simp

private theorem evaluatesTokenEndGuard
    (state : State) (tokenIndex tokenCount : Nat)
    (tokenIndexLocal : state.local? 5 =
      some (.signed .i32 (Int.ofNat tokenIndex)))
    (tokenCountLocal : state.local? 2 =
      some (.signed .i32 (Int.ofNat tokenCount))) :
    Evaluates verifiedParserCore state
      (.binary .greaterEqual (.local 5) (.local 2))
      (.boolean (decide (tokenIndex ≥ tokenCount))) state := by
  have left := evaluatesI32Local state 5 tokenIndex tokenIndexLocal
  have right := evaluatesI32Local state 2 tokenCount tokenCountLocal
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

private theorem evaluatesCanonicalKind
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state) :
    Evaluates verifiedParserCore state parserCanonicalKindExpr
      (.signed .i32 (Int.ofNat (grammar.grammar.canonical_kinds.get
        ⟨semanticKind, invariant.semanticKindBound⟩))) state := by
  have headerBound := invariant.encoded.canonicalKindsOffset.index_in_bounds
  have headerValue := invariant.encoded.canonicalKindsOffset.get
  have addressBound := invariant.encoded.canonicalKinds.row_in_bounds
    invariant.semanticKindBound
  have rowResult := evaluatesI32Local state 4 semanticKind
    invariant.semanticKindLocal
  have physical := evaluatesParserTableReadFrom words grammarCell 14 7
    layout.canonicalKindsOffset semanticKind headerBound headerValue
    addressBound invariant.wordsI32 state invariant.grammarLocal (.local 4)
    rowResult invariant.grammarBacking verifiedParser_scan_terminal_constants.2.2
  have semanticValue := invariant.encoded.canonicalKinds.get
    invariant.semanticKindBound
  rw [semanticValue] at physical
  exact physical

private theorem evaluatesRawToken
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state)
    (tokenIndex : Nat) (tokenBound : tokenIndex < tokens.length)
    (tokenIndexLocal : state.local? 5 =
      some (.signed .i32 (Int.ofNat tokenIndex))) :
    Evaluates verifiedParserCore state
      (.index (.local 1) (.local 5))
      (.signed .i32 (Int.ofNat (tokens.get ⟨tokenIndex, tokenBound⟩))) state := by
  have tokensResult : Evaluates verifiedParserCore state (.local 1)
      (parserTokensValue tokens tokensCell) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 1
      (parserTokensValue tokens tokensCell) invariant.tokensLocal⟩
  have indexResult := evaluatesI32Local state 5 tokenIndex tokenIndexLocal
  have indexed := evaluatesSignedI32SliceIndex verifiedParserCore state state
    state (tokens.map Int.ofNat) (.local 1) (.local 5) tokensCell tokenIndex
    (by simpa using tokenBound) tokensResult indexResult invariant.tokensBacking
  simpa [parserTokensValue] using indexed

private theorem evaluatesSplitTokenHeader
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state) :
    Evaluates verifiedParserCore state
      (.index (.local 0) (.constant 12))
      (.signed .i32 (Int.ofNat grammar.grammar.split_token_kind)) state := by
  have result := evaluatesParserHeaderRead words grammarCell 12 5
    invariant.encoded.splitTokenKind.index_in_bounds state
    invariant.grammarLocal invariant.grammarBacking
    verifiedParser_scan_terminal_constants.1
  rw [invariant.encoded.splitTokenKind.get] at result
  exact result

private theorem evaluatesSplitComponentHeader
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state) :
    Evaluates verifiedParserCore state
      (.index (.local 0) (.constant 13))
      (.signed .i32 (Int.ofNat grammar.grammar.split_component_kind)) state := by
  have result := evaluatesParserHeaderRead words grammarCell 13 6
    invariant.encoded.splitComponentKind.index_in_bounds state
    invariant.grammarLocal invariant.grammarBacking
    verifiedParser_scan_terminal_constants.2.1
  rw [invariant.encoded.splitComponentKind.get] at result
  exact result

/-- When the lattice position is beyond the physical token stream, the
    extracted function takes its early-return path before either slice is
    indexed. The only allocation is the scoped `token_index` local. -/
theorem extractedParserScanTerminalBody_rejects_past_end
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state)
    (pastEnd : tokens.length ≤ position / 2) :
    let tokenIndexState := state.bindLocal 5
      (.signed .i32 (Int.ofNat (position / 2)))
    Executes verifiedParserCore state extractedParserScanTerminalBody
      (.returned (some (scanTerminalValue none)))
      (restoreLocals state tokenIndexState) := by
  dsimp only
  let tokenIndexState := state.bindLocal 5
    (.signed .i32 (Int.ofNat (position / 2)))
  have positionBound := invariant.positionAdvanceI32
  have initializer := evaluatesTokenIndex state position
    invariant.positionLocal (by omega)
  have tokenIndexInvariant := invariant.after_bind_local 5
    (.signed .i32 (Int.ofNat (position / 2)))
    (by simp [verifiedParserScanTerminal_caller_frame_ids])
  have tokenIndexLocal : tokenIndexState.local? 5 =
      some (.signed .i32 (Int.ofNat (position / 2))) := by
    exact bindLocal_finds_local state 5
      (.signed .i32 (Int.ofNat (position / 2))) invariant.wellFormed
  have guard := evaluatesTokenEndGuard tokenIndexState (position / 2)
    tokens.length tokenIndexLocal tokenIndexInvariant.tokenCountLocal
  have guardTrue : Evaluates verifiedParserCore tokenIndexState
      (.binary .greaterEqual (.local 5) (.local 2)) (.boolean true)
      tokenIndexState := by
    simpa [pastEnd] using guard
  have returned := executesIfTrue (elseBranch := .skip) guardTrue
    (executesReject tokenIndexState)
  have guarded : Executes verifiedParserCore tokenIndexState
      (.sequence
        (.ifThenElse
          (.binary .greaterEqual (.local 5) (.local 2))
          parserRejectStmt .skip)
        (.letLocal 6 parserI32Type
          (.index (.local 1) (.local 5))
          (.letLocal 7 parserI32Type parserCanonicalKindExpr
            parserScanTerminalDispatch)))
      (.returned (some (scanTerminalValue none))) tokenIndexState := by
    simpa [scanTerminalValue] using executesSequenceReturned returned
  rw [extractedParserScanTerminalBody_eq]
  simpa [parserScanTerminalBody, tokenIndexState] using
    (executesLetLocal (type := parserI32Type) initializer guarded)

/-- In-bounds execution of the complete extracted body. It reads one token
    and one canonical grammar row, executes the verified lattice dispatch,
    and restores all three temporary lexical scopes. -/
theorem extractedParserScanTerminalBody_scans
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state)
    (tokenBound : position / 2 < tokens.length) :
    let tokenIndex := position / 2
    let rawKind := tokens.get ⟨tokenIndex, tokenBound⟩
    let canonicalKind := grammar.grammar.canonical_kinds.get
      ⟨semanticKind, invariant.semanticKindBound⟩
    let tokenIndexState := state.bindLocal 5
      (.signed .i32 (Int.ofNat tokenIndex))
    let rawState := tokenIndexState.bindLocal 6
      (.signed .i32 (Int.ofNat rawKind))
    let canonicalState := rawState.bindLocal 7
      (.signed .i32 (Int.ofNat canonicalKind))
    let afterCanonical := restoreLocals rawState canonicalState
    let afterRaw := restoreLocals tokenIndexState afterCanonical
    let after := restoreLocals state afterRaw
    Executes verifiedParserCore state extractedParserScanTerminalBody
      (.returned (some (scanTerminalValue
        (scanTerminalStep grammar.grammar.split_token_kind
          grammar.grammar.split_component_kind rawKind canonicalKind
          position)))) after := by
  dsimp only
  let tokenIndex := position / 2
  let rawKind := tokens.get ⟨tokenIndex, tokenBound⟩
  let canonicalKind := grammar.grammar.canonical_kinds.get
    ⟨semanticKind, invariant.semanticKindBound⟩
  let tokenIndexState := state.bindLocal 5
    (.signed .i32 (Int.ofNat tokenIndex))
  let rawState := tokenIndexState.bindLocal 6
    (.signed .i32 (Int.ofNat rawKind))
  let canonicalState := rawState.bindLocal 7
    (.signed .i32 (Int.ofNat canonicalKind))
  let afterCanonical := restoreLocals rawState canonicalState
  let afterRaw := restoreLocals tokenIndexState afterCanonical
  let after := restoreLocals state afterRaw
  have positionBound := invariant.positionAdvanceI32
  have tokenIndexInitializer := evaluatesTokenIndex state position
    invariant.positionLocal (by omega)
  have tokenIndexInvariant := invariant.after_bind_local 5
    (.signed .i32 (Int.ofNat tokenIndex))
    (by simp [verifiedParserScanTerminal_caller_frame_ids])
  have tokenIndexLocal : tokenIndexState.local? 5 =
      some (.signed .i32 (Int.ofNat tokenIndex)) := by
    exact bindLocal_finds_local state 5
      (.signed .i32 (Int.ofNat tokenIndex)) invariant.wellFormed
  have guard := evaluatesTokenEndGuard tokenIndexState tokenIndex tokens.length
    tokenIndexLocal tokenIndexInvariant.tokenCountLocal
  have guardFalse : Evaluates verifiedParserCore tokenIndexState
      (.binary .greaterEqual (.local 5) (.local 2)) (.boolean false)
      tokenIndexState := by
    have notEnd : ¬tokens.length ≤ tokenIndex := by
      simpa [tokenIndex] using (Nat.not_le.mpr tokenBound)
    simpa [notEnd] using guard
  have guardSkipped := executesIfFalse (thenBranch := parserRejectStmt)
    guardFalse (executesSkip verifiedParserCore tokenIndexState)
  have rawInitializer : Evaluates verifiedParserCore tokenIndexState
      (.index (.local 1) (.local 5))
      (.signed .i32 (Int.ofNat rawKind)) tokenIndexState := by
    simpa [tokenIndexState, tokenIndex, rawKind] using
      (evaluatesRawToken tokenIndexInvariant tokenIndex tokenBound
        tokenIndexLocal)
  have rawInvariant := tokenIndexInvariant.after_bind_local 6
    (.signed .i32 (Int.ofNat rawKind))
    (by simp [verifiedParserScanTerminal_caller_frame_ids])
  have rawLocalBefore : rawState.local? 6 =
      some (.signed .i32 (Int.ofNat rawKind)) := by
    exact bindLocal_finds_local tokenIndexState 6
      (.signed .i32 (Int.ofNat rawKind)) tokenIndexInvariant.wellFormed
  have canonicalInitializer : Evaluates verifiedParserCore rawState
      parserCanonicalKindExpr (.signed .i32 (Int.ofNat canonicalKind))
      rawState := by
    simpa [rawState, tokenIndexState, tokenIndex, rawKind, canonicalKind] using
      evaluatesCanonicalKind rawInvariant
  have canonicalInvariant := rawInvariant.after_bind_local 7
    (.signed .i32 (Int.ofNat canonicalKind))
    (by simp [verifiedParserScanTerminal_caller_frame_ids])
  have rawLocal : canonicalState.local? 6 =
      some (.signed .i32 (Int.ofNat rawKind)) := by
    exact (bindLocal_preserves_other_local rawInvariant.wellFormed
      (by decide : 7 ≠ 6)).trans rawLocalBefore
  have canonicalLocal : canonicalState.local? 7 =
      some (.signed .i32 (Int.ofNat canonicalKind)) := by
    exact bindLocal_finds_local rawState 7
      (.signed .i32 (Int.ofNat canonicalKind)) rawInvariant.wellFormed
  have dispatch := parserScanTerminalDispatch_executes canonicalState position
    rawKind canonicalKind grammar.grammar.split_token_kind
    grammar.grammar.split_component_kind canonicalInvariant.positionLocal
    rawLocal canonicalLocal (evaluatesSplitTokenHeader canonicalInvariant)
    (evaluatesSplitComponentHeader canonicalInvariant)
    invariant.positionAdvanceI32
  have canonicalScope : Executes verifiedParserCore rawState
      (.letLocal 7 parserI32Type parserCanonicalKindExpr
        parserScanTerminalDispatch)
      (.returned (some (scanTerminalValue
        (scanTerminalStep grammar.grammar.split_token_kind
          grammar.grammar.split_component_kind rawKind canonicalKind
          position)))) afterCanonical := by
    simpa [canonicalState, afterCanonical] using
      (executesLetLocal (type := parserI32Type) canonicalInitializer dispatch)
  have rawScope : Executes verifiedParserCore tokenIndexState
      (.letLocal 6 parserI32Type
        (.index (.local 1) (.local 5))
        (.letLocal 7 parserI32Type parserCanonicalKindExpr
          parserScanTerminalDispatch))
      (.returned (some (scanTerminalValue
        (scanTerminalStep grammar.grammar.split_token_kind
          grammar.grammar.split_component_kind rawKind canonicalKind
          position)))) afterRaw := by
    simpa [rawState, afterRaw] using
      (executesLetLocal (type := parserI32Type) rawInitializer canonicalScope)
  have guarded : Executes verifiedParserCore tokenIndexState
      (.sequence
        (.ifThenElse
          (.binary .greaterEqual (.local 5) (.local 2))
          parserRejectStmt .skip)
        (.letLocal 6 parserI32Type
          (.index (.local 1) (.local 5))
          (.letLocal 7 parserI32Type parserCanonicalKindExpr
            parserScanTerminalDispatch)))
      (.returned (some (scanTerminalValue
        (scanTerminalStep grammar.grammar.split_token_kind
          grammar.grammar.split_component_kind rawKind canonicalKind
          position)))) afterRaw :=
    executesSequence guardSkipped rawScope
  rw [extractedParserScanTerminalBody_eq]
  simpa [parserScanTerminalBody, tokenIndexState, rawState, canonicalState,
    afterCanonical, afterRaw, after, tokenIndex, rawKind, canonicalKind] using
    (executesLetLocal (type := parserI32Type) tokenIndexInitializer guarded)

theorem extractedParserScanTerminalBody_scans_model
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state)
    (tokenBound : position / 2 < tokens.length) :
    let tokenIndex := position / 2
    let rawKind := tokens.get ⟨tokenIndex, tokenBound⟩
    let canonicalKind := grammar.grammar.canonical_kinds.get
      ⟨semanticKind, invariant.semanticKindBound⟩
    let tokenIndexState := state.bindLocal 5
      (.signed .i32 (Int.ofNat tokenIndex))
    let rawState := tokenIndexState.bindLocal 6
      (.signed .i32 (Int.ofNat rawKind))
    let canonicalState := rawState.bindLocal 7
      (.signed .i32 (Int.ofNat canonicalKind))
    let after := restoreLocals state
      (restoreLocals tokenIndexState (restoreLocals rawState canonicalState))
    Executes verifiedParserCore state extractedParserScanTerminalBody
      (.returned (some (scanTerminalValue
        (scanTerminal grammar tokens position semanticKind)))) after := by
  dsimp only
  have tokenFound : tokens[position / 2]? = some
      (tokens.get ⟨position / 2, tokenBound⟩) := by
    exact List.getElem?_eq_getElem tokenBound
  have canonicalFound : grammar.grammar.canonical_kinds[semanticKind]? = some
      (grammar.grammar.canonical_kinds.get
        ⟨semanticKind, invariant.semanticKindBound⟩) := by
    exact List.getElem?_eq_getElem invariant.semanticKindBound
  have execution := extractedParserScanTerminalBody_scans invariant tokenBound
  simpa [scanTerminal, tokenFound, canonicalFound] using execution

theorem extractedParserScanTerminalBody_rejects_model
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state)
    (pastEnd : tokens.length ≤ position / 2) :
    let tokenIndexState := state.bindLocal 5
      (.signed .i32 (Int.ofNat (position / 2)))
    Executes verifiedParserCore state extractedParserScanTerminalBody
      (.returned (some (scanTerminalValue
        (scanTerminal grammar tokens position semanticKind))))
      (restoreLocals state tokenIndexState) := by
  dsimp only
  have tokenMissing : tokens[position / 2]? = none := by
    exact List.getElem?_eq_none (by omega)
  have execution := extractedParserScanTerminalBody_rejects_past_end invariant
    pastEnd
  simpa [scanTerminal, tokenMissing] using execution

/-- Complete body-level correctness statement. For every validated input,
    there is an exact Core execution returning the mathematical terminal-scan
    result; the witness state records the branch-dependent number of scoped
    temporary cells allocated by the source function. -/
theorem extractedParserScanTerminalBody_implements_model
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state) :
    ∃ after,
      Executes verifiedParserCore state extractedParserScanTerminalBody
        (.returned (some (scanTerminalValue
          (scanTerminal grammar tokens position semanticKind)))) after ∧
      ModifiesOnly CellSet.empty state after ∧
      StateWellFormed after := by
  by_cases tokenBound : position / 2 < tokens.length
  · let tokenIndex := position / 2
    let rawKind := tokens.get ⟨tokenIndex, tokenBound⟩
    let canonicalKind := grammar.grammar.canonical_kinds.get
      ⟨semanticKind, invariant.semanticKindBound⟩
    let tokenIndexState := state.bindLocal 5
      (.signed .i32 (Int.ofNat tokenIndex))
    let rawState := tokenIndexState.bindLocal 6
      (.signed .i32 (Int.ofNat rawKind))
    let canonicalState := rawState.bindLocal 7
      (.signed .i32 (Int.ofNat canonicalKind))
    let after := restoreLocals state
      (restoreLocals tokenIndexState (restoreLocals rawState canonicalState))
    have execution : Executes verifiedParserCore state
        extractedParserScanTerminalBody
        (.returned (some (scanTerminalValue
          (scanTerminal grammar tokens position semanticKind)))) after := by
      simpa [tokenIndex, rawKind, canonicalKind, tokenIndexState, rawState,
        canonicalState, after] using
        (extractedParserScanTerminalBody_scans_model invariant tokenBound)
    have entered5 := bindLocal_effect state 5
      (.signed .i32 (Int.ofNat tokenIndex))
    have entered6 := bindLocal_effect tokenIndexState 6
      (.signed .i32 (Int.ofNat rawKind))
    have entered7 := bindLocal_effect rawState 7
      (.signed .i32 (Int.ofNat canonicalKind))
    have entered : StoreEffect CellSet.empty state canonicalState := by
      exact entered5.trans_same (entered6.trans_same entered7)
    have effect : ModifiesOnly CellSet.empty state after := by
      simpa [after, tokenIndexState, rawState, canonicalState, restoreLocals]
        using entered.restoreLocals
    have completedWellFormed : StateWellFormed canonicalState := by
      exact bindLocal_preserves_well_formed rawState 7
        (.signed .i32 (Int.ofNat canonicalKind))
        (bindLocal_preserves_well_formed tokenIndexState 6
          (.signed .i32 (Int.ofNat rawKind))
          (bindLocal_preserves_well_formed state 5
            (.signed .i32 (Int.ofNat tokenIndex)) invariant.wellFormed))
    have afterWellFormed : StateWellFormed after := by
      simpa [after, tokenIndexState, rawState, canonicalState, restoreLocals]
        using entered.restoreLocals_wellFormed invariant.wellFormed
          completedWellFormed
    exact ⟨after, execution, effect, afterWellFormed⟩
  · have pastEnd : tokens.length ≤ position / 2 := Nat.le_of_not_gt tokenBound
    let tokenIndexState := state.bindLocal 5
      (.signed .i32 (Int.ofNat (position / 2)))
    let after := restoreLocals state tokenIndexState
    have execution : Executes verifiedParserCore state
        extractedParserScanTerminalBody
        (.returned (some (scanTerminalValue
          (scanTerminal grammar tokens position semanticKind)))) after := by
      simpa [after, tokenIndexState] using
        (extractedParserScanTerminalBody_rejects_model invariant pastEnd)
    have entered := bindLocal_effect state 5
      (.signed .i32 (Int.ofNat (position / 2)))
    have effect : ModifiesOnly CellSet.empty state after := by
      simpa [after, tokenIndexState] using entered.restoreLocals
    have completedWellFormed : StateWellFormed tokenIndexState :=
      bindLocal_preserves_well_formed state 5
        (.signed .i32 (Int.ofNat (position / 2))) invariant.wellFormed
    have afterWellFormed : StateWellFormed after :=
      entered.restoreLocals_wellFormed invariant.wellFormed
        completedWellFormed
    exact ⟨after, execution, effect, afterWellFormed⟩

def parserScanTerminalBindings
    (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId) (position semanticKind : Nat) :
    List (VarId × Value) := [
  (0, parserGrammarValue words grammarCell),
  (1, parserTokensValue tokens tokensCell),
  (2, .signed .i32 (Int.ofNat tokens.length)),
  (3, .signed .i32 (Int.ofNat position)),
  (4, .signed .i32 (Int.ofNat semanticKind))]

def parserScanTerminalCallee
    (caller : State) (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId) (position semanticKind : Nat) : State :=
  enterCall caller (parserScanTerminalBindings words tokens grammarCell
    tokensCell position semanticKind)

theorem parserScanTerminalCallee_entry
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId) (position semanticKind : Nat)
    (caller : State)
    (encoded : EncodesGrammar layout grammar words)
    (wordsI32 : words.length ≤ 2147483647)
    (tokensI32 : tokens.length ≤ 2147483647)
    (positionAdvanceI32 : position + 2 ≤ 2147483647)
    (semanticKindBound : semanticKind <
      grammar.grammar.canonical_kinds.length)
    (wellFormed : StateWellFormed caller)
    (grammarBacking : caller.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values words))
    })
    (tokensBacking : caller.cellEntry? tokensCell = some {
      id := tokensCell
      value := some (.array
        (signedI32Values (tokens.map Int.ofNat)))
    }) :
    ScanTerminalInvariant layout grammar words tokens grammarCell tokensCell
      position semanticKind
      (parserScanTerminalCallee caller words tokens grammarCell tokensCell
        position semanticKind) := by
  let bindings := parserScanTerminalBindings words tokens grammarCell
    tokensCell position semanticKind
  let callee := enterCall caller bindings
  have calleeWellFormed : StateWellFormed callee :=
    enterCall_preserves_wellFormed wellFormed
  have grammarOld : grammarCell < caller.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry wellFormed
      grammarBacking
  have tokensOld : tokensCell < caller.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry wellFormed
      tokensBacking
  have calleeGrammarBacking : callee.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values words))
    } := ((enterCall_effect caller bindings).oldCells grammarCell grammarOld
      (by simp [CellSet.empty])).trans grammarBacking
  have calleeTokensBacking : callee.cellEntry? tokensCell = some {
      id := tokensCell
      value := some (.array
        (signedI32Values (tokens.map Int.ofNat)))
    } := ((enterCall_effect caller bindings).oldCells tokensCell tokensOld
      (by simp [CellSet.empty])).trans tokensBacking
  have local0 : callee.local? 0 =
      some (parserGrammarValue words grammarCell) := by
    simpa [callee, bindings, parserScanTerminalBindings] using
      (enterCall_local_of_binding caller [] [
        (1, parserTokensValue tokens tokensCell),
        (2, .signed .i32 (Int.ofNat tokens.length)),
        (3, .signed .i32 (Int.ofNat position)),
        (4, .signed .i32 (Int.ofNat semanticKind))]
        0 (parserGrammarValue words grammarCell) wellFormed (by simp))
  have local1 : callee.local? 1 =
      some (parserTokensValue tokens tokensCell) := by
    simpa [callee, bindings, parserScanTerminalBindings] using
      (enterCall_local_of_binding caller [
        (0, parserGrammarValue words grammarCell)] [
        (2, .signed .i32 (Int.ofNat tokens.length)),
        (3, .signed .i32 (Int.ofNat position)),
        (4, .signed .i32 (Int.ofNat semanticKind))]
        1 (parserTokensValue tokens tokensCell) wellFormed (by simp))
  have local2 : callee.local? 2 =
      some (.signed .i32 (Int.ofNat tokens.length)) := by
    simpa [callee, bindings, parserScanTerminalBindings] using
      (enterCall_local_of_binding caller [
        (0, parserGrammarValue words grammarCell),
        (1, parserTokensValue tokens tokensCell)] [
        (3, .signed .i32 (Int.ofNat position)),
        (4, .signed .i32 (Int.ofNat semanticKind))]
        2 (.signed .i32 (Int.ofNat tokens.length)) wellFormed (by simp))
  have local3 : callee.local? 3 =
      some (.signed .i32 (Int.ofNat position)) := by
    simpa [callee, bindings, parserScanTerminalBindings] using
      (enterCall_local_of_binding caller [
        (0, parserGrammarValue words grammarCell),
        (1, parserTokensValue tokens tokensCell),
        (2, .signed .i32 (Int.ofNat tokens.length))] [
        (4, .signed .i32 (Int.ofNat semanticKind))]
        3 (.signed .i32 (Int.ofNat position)) wellFormed (by simp))
  have local4 : callee.local? 4 =
      some (.signed .i32 (Int.ofNat semanticKind)) := by
    simpa [callee, bindings, parserScanTerminalBindings] using
      (enterCall_local_of_binding caller [
        (0, parserGrammarValue words grammarCell),
        (1, parserTokensValue tokens tokensCell),
        (2, .signed .i32 (Int.ofNat tokens.length)),
        (3, .signed .i32 (Int.ofNat position))] []
        4 (.signed .i32 (Int.ofNat semanticKind)) wellFormed (by simp))
  simpa [parserScanTerminalCallee, bindings, callee] using
    (show ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind callee from {
        encoded := encoded
        wordsI32 := wordsI32
        tokensI32 := tokensI32
        positionAdvanceI32 := positionAdvanceI32
        semanticKindBound := semanticKindBound
        wellFormed := calleeWellFormed
        grammarLocal := local0
        tokensLocal := local1
        tokenCountLocal := local2
        positionLocal := local3
        semanticKindLocal := local4
        grammarBacking := calleeGrammarBacking
        tokensBacking := calleeTokensBacking })

/-- Full extracted call evaluation. The premises expose the same
    `ScanTerminalInvariant` used by the body proof, so later recognizer proofs
    can establish ownership and packed-layout facts once at the call site. -/
theorem extractedParserScanTerminalCall_implements_model
    (before afterArguments : State) (arguments : List Expr)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      parserGrammarValue words grammarCell,
      parserTokensValue tokens tokensCell,
      .signed .i32 (Int.ofNat tokens.length),
      .signed .i32 (Int.ofNat position),
      .signed .i32 (Int.ofNat semanticKind)] afterArguments)
    (grammarBacking : afterArguments.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values words))
    })
    (tokensBacking : afterArguments.cellEntry? tokensCell = some {
      id := tokensCell
      value := some (.array
        (signedI32Values (tokens.map Int.ofNat)))
    })
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind
      (parserScanTerminalCallee afterArguments words tokens grammarCell
        tokensCell position semanticKind)) :
    ∃ after,
      Evaluates verifiedParserCore before
        (.call extractedParserScanTerminalFunction.id arguments)
        (scanTerminalValue (scanTerminal grammar tokens position semanticKind))
        after ∧
      ModifiesOnly CellSet.empty afterArguments after ∧
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
  let callee := parserScanTerminalCallee afterArguments words tokens grammarCell
    tokensCell position semanticKind
  obtain ⟨completed, body, bodyEffect, completedWellFormed⟩ :=
    extractedParserScanTerminalBody_implements_model invariant
  rw [extractedParserScanTerminalBody_eq] at body
  let after := restoreLocals afterArguments completed
  have evaluation : Evaluates verifiedParserCore before
      (.call extractedParserScanTerminalFunction.id arguments)
      (scanTerminalValue (scanTerminal grammar tokens position semanticKind))
      after := by
    apply evaluatesCallReturned argumentsResult
      verifiedParserCore_finds_scanTerminal
    · rw [extractedParserScanTerminal_function_shape.2.1]
      rfl
    · exact extractedParserScanTerminal_function_shape.2.2.2.1
    · simpa [callee, after, parserScanTerminalCallee,
        parserScanTerminalBindings] using body
  let bindings := parserScanTerminalBindings words tokens grammarCell
    tokensCell position semanticKind
  have entered : StoreEffect CellSet.empty afterArguments callee := by
    simpa [callee, parserScanTerminalCallee, bindings,
      parserScanTerminalBindings] using
      enterCall_effect afterArguments bindings
  have callStore : StoreEffect CellSet.empty afterArguments completed := by
    exact entered.trans_same bodyEffect.toStoreEffect
  have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
    simpa [after] using callStore.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    callStore.restoreLocals_wellFormed
      afterArgumentsWellFormed
      completedWellFormed
  have grammarBacking := callEffect.empty_preserves_entry
    afterArgumentsWellFormed grammarBacking
  have tokensBacking := callEffect.empty_preserves_entry
    afterArgumentsWellFormed tokensBacking
  exact ⟨after, evaluation, callEffect, afterWellFormed,
    grammarBacking, tokensBacking⟩

end Lanius.Extraction.ParserScan
