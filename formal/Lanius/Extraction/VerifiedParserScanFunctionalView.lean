import Lanius.Extraction.VerifiedParserScan
import Lanius.FunctionalViewCoreReadOnly
import Lanius.FunctionalViewCoreReification

namespace Lanius.Extraction.ParserScan.Proof

open Lanius.Core
open Lanius.Typing
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Reification
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.Extraction.ParserScan
open Lanius.Extraction.ParserAccessors
open Lanius.Compiler.Parser

/-! # Functional View representation of `scan_terminal`

This is the proof-facing program. Its slots are lexically scoped `Fin`
indices; the physical Core locals 5, 6, and 7 are introduced only by
`toCoreStmt`. The exact-conversion theorem below prevents this representation
from drifting away from the extracted compiler artifact.
-/

private abbrev ScanBlock (arity : Nat) := Block signature arity
private abbrev ScanTerm (arity : Nat) := Term signature arity

private def slot {arity : Nat} (index : Nat)
    (bound : index < arity := by omega) : ScanTerm arity :=
  reference ⟨index, bound⟩

private def i32 (value : Int) : ScanTerm arity :=
  literal (.signed .i32 value)

private def constant (id : ConstantId) : ScanTerm arity :=
  apply (.constant id parserI32Type) []

private def unaryI32 (operation : UnaryOp) (operand : ScanTerm arity) :
    ScanTerm arity :=
  apply (.unary operation parserI32Type parserI32Type) [operand]

private def binaryI32 (operation : BinaryOp)
    (left right : ScanTerm arity) : ScanTerm arity :=
  apply (.binary operation parserI32Type parserI32Type parserI32Type)
    [left, right]

private def compareI32 (operation : BinaryOp)
    (left right : ScanTerm arity) : ScanTerm arity :=
  apply (.binary operation parserI32Type parserI32Type (.scalar .bool))
    [left, right]

private def logicalAnd (left right : ScanTerm arity) : ScanTerm arity :=
  Lanius.FunctionalView.Core.logicalAnd left right

private def indexI32 (base index : ScanTerm arity) : ScanTerm arity :=
  apply (.index (.slice parserI32Type) parserI32Type parserI32Type)
    [base, index]

private def reject : ScanBlock arity :=
  .sequence (.returnValue (some (unaryI32 .negate (i32 1)))) .skip

private def advance (amount : Int) : ScanBlock 8 :=
  .sequence
    (.returnValue (some (binaryI32 .add (slot 3) (i32 amount))))
    .skip

private def splitMatch : ScanTerm 8 :=
  logicalAnd
    (compareI32 .equal (slot 6) (indexI32 (slot 0) (constant 12)))
    (compareI32 .equal (slot 7) (indexI32 (slot 0) (constant 13)))

private def splitMatchBlock : ScanBlock 8 :=
  .ifThenElse splitMatch (advance 1) .skip

private def oddPosition : ScanBlock 8 :=
  .sequence splitMatchBlock reject

private def canonicalMatch : ScanBlock 8 :=
  .ifThenElse (compareI32 .equal (slot 6) (slot 7)) (advance 2) .skip

private def evenPosition : ScanBlock 8 :=
  .sequence canonicalMatch (.sequence splitMatchBlock reject)

private def dispatch : ScanBlock 8 :=
  .sequence
    (.ifThenElse
      (compareI32 .equal (binaryI32 .remainder (slot 3) (i32 2)) (i32 1))
      oddPosition .skip)
    evenPosition

private def canonicalKind : ScanTerm 7 :=
  indexI32 (slot 0)
    (binaryI32 .add (indexI32 (slot 0) (constant 14)) (slot 4))

private def scanTerminalReification? :=
  reifyBlock? verifiedParserCore extractedParserScanTerminalFunction.returnType
    (parameterContext extractedParserScanTerminalFunction.parameters) false
    (identityLayout (arity := 5)) 5 extractedParserScanTerminalBody

private theorem scanTerminalReification_exists :
    scanTerminalReification?.isSome := by
  native_decide

/-- The terminal scan's functional view, mechanically recovered from the
    checked Core artifact. -/
def scanTerminalView :=
  scanTerminalReification?.get scanTerminalReification_exists

def scanTerminal : ScanBlock 5 :=
    .letValue parserI32Type (binaryI32 .divide (slot 3) (i32 2))
      (.sequence
        (.ifThenElse
          (compareI32 .greaterEqual (slot 5) (slot 2))
          reject .skip)
        (.letValue parserI32Type (indexI32 (slot 1) (slot 5))
          (.letValue parserI32Type canonicalKind dispatch)))

private theorem scanTerminal_shape : scanTerminal =
    .letValue parserI32Type (binaryI32 .divide (slot 3) (i32 2))
      (.sequence
        (.ifThenElse
          (compareI32 .greaterEqual (slot 5) (slot 2))
          reject .skip)
        (.letValue parserI32Type (indexI32 (slot 1) (slot 5))
          (.letValue parserI32Type canonicalKind dispatch))) := by
  rfl

def scanWorld (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId) : ReadOnly.World := {
  i32Slice? := fun cell =>
    if cell = grammarCell then
      some words
    else if cell = tokensCell then
      some (tokens.map Int.ofNat)
    else
      none
}

def scanEnvironment (words : List Int) (tokens : List Nat)
    (grammarCell tokensCell : CellId) (position semanticKind : Nat) : Env 5 :=
  fun index => match index.val with
    | 0 => parserGrammarValue words grammarCell
    | 1 => parserTokensValue tokens tokensCell
    | 2 => .signed .i32 (Int.ofNat tokens.length)
    | 3 => .signed .i32 (Int.ofNat position)
    | _ => .signed .i32 (Int.ofNat semanticKind)

@[simp] theorem scanWorld_finds_grammar :
    (scanWorld words tokens grammarCell tokensCell).i32Slice? grammarCell =
      some words := by
  simp [scanWorld]

private theorem scanBacking_values_agree
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      grammarCell position semanticKind state) :
    words = tokens.map Int.ofNat := by
  have encodedValues : signedI32Values words =
      signedI32Values (tokens.map Int.ofNat) := by
    have backing := invariant.grammarBacking.symm.trans invariant.tokensBacking
    have cellEquality := Option.some.inj backing
    have valueEquality := congrArg Cell.value cellEquality
    have arrayEquality := Option.some.inj valueEquality
    injection arrayEquality
  exact (List.map_inj_right (fun left right same => by
    injection same)).mp encodedValues

@[simp] theorem scanWorld_finds_tokens
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state) :
    (scanWorld words tokens grammarCell tokensCell).i32Slice? tokensCell =
      some (tokens.map Int.ofNat) := by
  by_cases sameCell : tokensCell = grammarCell
  · subst tokensCell
    rw [scanWorld_finds_grammar, scanBacking_values_agree invariant]
  · simp [scanWorld, sameCell]

theorem scanWorld_represents
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state) :
    ReadOnly.World.Represents
      (scanWorld words tokens grammarCell tokensCell) state := by
  intro cell values found
  by_cases grammar : cell = grammarCell
  · subst cell
    have sameValues : values = words := by
      symm
      simpa [scanWorld] using found
    subst values
    exact ⟨invariant.grammarBacking,
      StateWellFormed.cell_lt_next_of_entry invariant.wellFormed
        invariant.grammarBacking⟩
  · by_cases token : cell = tokensCell
    · subst cell
      have sameValues : values = tokens.map Int.ofNat := by
        symm
        simpa [scanWorld, grammar] using found
      subst values
      exact ⟨invariant.tokensBacking,
        StateWellFormed.cell_lt_next_of_entry invariant.wellFormed
          invariant.tokensBacking⟩
    · simp [scanWorld, grammar, token] at found

theorem scanEnvironment_matches
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state) :
    EnvironmentMatches (identityLayout (arity := 5))
      (scanEnvironment words tokens grammarCell tokensCell position semanticKind)
      state := by
  rintro ⟨index, bound⟩
  have alternatives : index = 0 ∨ index = 1 ∨ index = 2 ∨
      index = 3 ∨ index = 4 := by omega
  rcases alternatives with rfl | rfl | rfl | rfl | rfl
  · simpa [identityLayout, scanEnvironment] using invariant.grammarLocal
  · simpa [identityLayout, scanEnvironment] using invariant.tokensLocal
  · simpa [identityLayout, scanEnvironment] using invariant.tokenCountLocal
  · change state.local? 3 = some (.signed .i32 (Int.ofNat position))
    exact invariant.positionLocal
  · change state.local? 4 = some (.signed .i32 (Int.ofNat semanticKind))
    exact invariant.semanticKindLocal

private theorem reject_evaluates (world : ReadOnly.World)
    (environment : Env arity) :
    Block.evaluate (ReadOnly.machine verifiedParserCore) world environment
        (reject : ScanBlock arity) =
      .done (.returned (some (.signed .i32 (-1)))) world := by
  unfold reject
  apply Block.evaluate_sequence_returned
  apply Block.evaluate_returnValue
  exact ReadOnly.Term.evaluate_i32_negate_one

private theorem tokenEndGuard_evaluates
    (world : ReadOnly.World) (environment : Env 6)
    (tokenIndex tokenCount : Nat)
    (tokenIndexValue : environment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat tokenIndex))
    (tokenCountValue : environment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat tokenCount)) :
    Term.evaluate (ReadOnly.machine verifiedParserCore) world environment
        (compareI32 .greaterEqual (slot 5) (slot 2)) =
      .ok (.boolean (decide (tokenIndex ≥ tokenCount)), world) := by
  simp only [compareI32, slot, apply, reference]
  functional_eval

private theorem rawKind_evaluates
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state)
    (environment : Env 6) (tokenBound : position / 2 < tokens.length)
    (tokensValue : environment ⟨1, by omega⟩ =
      parserTokensValue tokens tokensCell)
    (tokenIndexValue : environment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat (position / 2))) :
    Term.evaluate (ReadOnly.machine verifiedParserCore)
        (scanWorld words tokens grammarCell tokensCell) environment
        (indexI32 (slot 1) (slot 5)) =
      .ok (.signed .i32 (Int.ofNat
        (tokens.get ⟨position / 2, tokenBound⟩)),
        scanWorld words tokens grammarCell tokensCell) := by
  have baseValue : environment ⟨1, by omega⟩ =
      .slice parserI32Type tokensCell [] 0 (tokens.map Int.ofNat).length := by
    simpa [parserTokensValue, parserGrammarValue, parserI32Type] using tokensValue
  have found := scanWorld_finds_tokens invariant
  have inBounds : position / 2 < (tokens.map Int.ofNat).length := by
    simpa using tokenBound
  simpa using (show
    Term.evaluate (ReadOnly.machine verifiedParserCore)
        (scanWorld words tokens grammarCell tokensCell) environment
        (indexI32 (slot 1) (slot 5)) =
      .ok (.signed .i32 ((tokens.map Int.ofNat).get ⟨position / 2, inBounds⟩),
        scanWorld words tokens grammarCell tokensCell) by
    simp only [indexI32, slot, apply, reference]
    functional_eval)

private theorem canonicalKind_evaluates
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state)
    (environment : Env 7)
    (grammarValue : environment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell)
    (semanticValue : environment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat semanticKind)) :
    Term.evaluate (ReadOnly.machine verifiedParserCore)
        (scanWorld words tokens grammarCell tokensCell) environment
        canonicalKind =
      .ok (.signed .i32 (Int.ofNat
        (grammar.grammar.canonical_kinds.get
          ⟨semanticKind, invariant.semanticKindBound⟩)),
        scanWorld words tokens grammarCell tokensCell) := by
  let world := scanWorld words tokens grammarCell tokensCell
  have baseValue : environment ⟨0, by omega⟩ =
      .slice parserI32Type grammarCell [] 0 words.length := by
    simpa [parserGrammarValue] using grammarValue
  have found : world.i32Slice? grammarCell = some words := by
    simp [world]
  have constantFound := verifiedParser_scan_terminal_constants.2.2
  have headerBound := invariant.encoded.canonicalKindsOffset.index_in_bounds
  have headerValue := invariant.encoded.canonicalKindsOffset.get
  have addressBound : layout.canonicalKindsOffset + semanticKind ≤
      2147483647 := by
    have rowBound := invariant.encoded.canonicalKinds.row_in_bounds
      invariant.semanticKindBound
    have wordsBound := invariant.wordsI32
    omega
  have rowBound := invariant.encoded.canonicalKinds.row_in_bounds
    invariant.semanticKindBound
  have rowValue := invariant.encoded.canonicalKinds.get
    invariant.semanticKindBound
  simp only [canonicalKind, indexI32, binaryI32, constant, slot, apply,
    reference]
  functional_eval

private theorem grammarHeader_evaluates
    (world : ReadOnly.World) (environment : Env arity)
    (words : List Int) (grammarCell : CellId)
    (grammarValue : environment ⟨0, firstBound⟩ =
      parserGrammarValue words grammarCell)
    (constantResult : Term.evaluate (ReadOnly.machine verifiedParserCore)
      world environment (constant constantId) =
      .ok (.signed .i32 (Int.ofNat index), world))
    (found : world.i32Slice? grammarCell = some words)
    (header : HeaderWord words index value) :
    Term.evaluate (ReadOnly.machine verifiedParserCore) world environment
        (indexI32 (slot 0 firstBound) (constant constantId)) =
      .ok (.signed .i32 (Int.ofNat value), world) := by
  have baseValue : environment ⟨0, firstBound⟩ =
      .slice parserI32Type grammarCell [] 0 words.length := by
    simpa [parserGrammarValue, parserI32Type] using grammarValue
  have inBounds := header.index_in_bounds
  have headerValue := header.get
  simp only [indexI32, slot, apply, reference]
  functional_eval

private theorem splitMatch_evaluates
    (world : ReadOnly.World) (environment : Env 8)
    (rawKind canonicalKind splitTokenKind splitComponentKind : Nat)
    (rawValue : environment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat rawKind))
    (canonicalValue : environment ⟨7, by omega⟩ =
      .signed .i32 (Int.ofNat canonicalKind))
    (splitTokenResult : Term.evaluate (ReadOnly.machine verifiedParserCore)
      world environment (indexI32 (slot 0) (constant 12)) =
      .ok (.signed .i32 (Int.ofNat splitTokenKind), world))
    (splitComponentResult : Term.evaluate
      (ReadOnly.machine verifiedParserCore) world environment
      (indexI32 (slot 0) (constant 13)) =
      .ok (.signed .i32 (Int.ofNat splitComponentKind), world)) :
    Term.evaluate (ReadOnly.machine verifiedParserCore) world environment
        splitMatch =
      .ok (.boolean (decide
        (rawKind = splitTokenKind ∧ canonicalKind = splitComponentKind)),
        world) := by
  simpa using (show
    Term.evaluate (ReadOnly.machine verifiedParserCore) world environment
        splitMatch =
      .ok (.boolean
        (decide (rawKind = splitTokenKind) &&
          decide (canonicalKind = splitComponentKind)), world) by
    simp only [splitMatch, logicalAnd, compareI32, slot, apply, reference]
    functional_eval)

private theorem parity_evaluates
    (world : ReadOnly.World) (environment : Env 8) (position : Nat)
    (positionValue : environment ⟨3, by omega⟩ =
      .signed .i32 (Int.ofNat position)) :
    Term.evaluate (ReadOnly.machine verifiedParserCore) world environment
        (compareI32 .equal (binaryI32 .remainder (slot 3) (i32 2))
          (i32 1)) =
      .ok (.boolean (decide (position % 2 = 1)), world) := by
  simp only [compareI32, binaryI32, i32, slot, literal, apply, reference]
  functional_eval

private theorem directMatch_evaluates
    (world : ReadOnly.World) (environment : Env 8)
    (rawKind canonicalKind : Nat)
    (rawValue : environment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat rawKind))
    (canonicalValue : environment ⟨7, by omega⟩ =
      .signed .i32 (Int.ofNat canonicalKind)) :
    Term.evaluate (ReadOnly.machine verifiedParserCore) world environment
        (compareI32 .equal (slot 6) (slot 7)) =
      .ok (.boolean (decide (rawKind = canonicalKind)), world) := by
  simp only [compareI32, slot, apply, reference]
  functional_eval

private theorem advance_evaluates
    (world : ReadOnly.World) (environment : Env 8)
    (position amount : Nat)
    (positionValue : environment ⟨3, by omega⟩ =
      .signed .i32 (Int.ofNat position))
    (bounded : position + amount ≤ 2147483647) :
    Block.evaluate (ReadOnly.machine verifiedParserCore) world environment
        (advance (Int.ofNat amount)) =
      .done (.returned (some
        (.signed .i32 (Int.ofNat (position + amount))))) world := by
  unfold advance
  apply Block.evaluate_sequence_returned
  apply Block.evaluate_returnValue
  simp only [binaryI32, slot, i32, literal, apply, reference]
  functional_eval

private theorem dispatch_evaluates
    (world : ReadOnly.World) (environment : Env 8)
    (position rawKind canonicalKind splitTokenKind splitComponentKind : Nat)
    (positionValue : environment ⟨3, by omega⟩ =
      .signed .i32 (Int.ofNat position))
    (rawValue : environment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat rawKind))
    (canonicalValue : environment ⟨7, by omega⟩ =
      .signed .i32 (Int.ofNat canonicalKind))
    (splitTokenResult : Term.evaluate (ReadOnly.machine verifiedParserCore)
      world environment (indexI32 (slot 0) (constant 12)) =
      .ok (.signed .i32 (Int.ofNat splitTokenKind), world))
    (splitComponentResult : Term.evaluate
      (ReadOnly.machine verifiedParserCore) world environment
      (indexI32 (slot 0) (constant 13)) =
      .ok (.signed .i32 (Int.ofNat splitComponentKind), world))
    (positionAdvanceI32 : position + 2 ≤ 2147483647) :
    Block.evaluate (ReadOnly.machine verifiedParserCore) world environment
        dispatch =
      .done (.returned (some (scanTerminalValue
        (scanTerminalStep splitTokenKind splitComponentKind rawKind
          canonicalKind position)))) world := by
  have parity := parity_evaluates world environment position positionValue
  have splitMatchResult := splitMatch_evaluates world environment rawKind
    canonicalKind splitTokenKind splitComponentKind rawValue canonicalValue
    splitTokenResult splitComponentResult
  have directMatch := directMatch_evaluates world environment rawKind
    canonicalKind rawValue canonicalValue
  have advanceOne := advance_evaluates world environment position 1
    positionValue (by omega)
  have advanceTwo := advance_evaluates world environment position 2
    positionValue positionAdvanceI32
  have rejected := reject_evaluates world environment
  by_cases odd : position % 2 = 1
  · by_cases split :
        rawKind = splitTokenKind ∧ canonicalKind = splitComponentKind
    · simp_all [dispatch, oddPosition, evenPosition, canonicalMatch,
        splitMatchBlock, Block.evaluate, scanTerminalStep, scanTerminalValue]
    · have splitStep :
          (if rawKind = splitTokenKind ∧ canonicalKind = splitComponentKind
            then some (position + 1) else none) = none := if_neg split
      simp_all [dispatch, oddPosition, evenPosition, canonicalMatch,
        splitMatchBlock, Block.evaluate, scanTerminalStep, scanTerminalValue]
      split <;> simp_all
  · by_cases direct : rawKind = canonicalKind
    · simp_all [dispatch, oddPosition, evenPosition, canonicalMatch,
        splitMatchBlock, Block.evaluate, scanTerminalStep, scanTerminalValue]
    · by_cases split :
          rawKind = splitTokenKind ∧ canonicalKind = splitComponentKind
      · simp_all [dispatch, oddPosition, evenPosition, canonicalMatch,
          splitMatchBlock, Block.evaluate, scanTerminalStep, scanTerminalValue]
      · have splitStep :
            (if rawKind = splitTokenKind ∧ canonicalKind = splitComponentKind
              then some (position + 1) else none) = none := if_neg split
        simp_all [dispatch, oddPosition, evenPosition, canonicalMatch,
          splitMatchBlock, Block.evaluate, scanTerminalStep, scanTerminalValue]
        split <;> simp_all

private theorem tokenIndex_evaluates
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state) :
    Term.evaluate (ReadOnly.machine verifiedParserCore)
        (scanWorld words tokens grammarCell tokensCell)
        (scanEnvironment words tokens grammarCell tokensCell position semanticKind)
        (binaryI32 .divide (slot 3) (i32 2)) =
      .ok (.signed .i32 (Int.ofNat (position / 2)),
        scanWorld words tokens grammarCell tokensCell) := by
  have positionBound : position ≤ 2147483647 := by
    have positionAdvance := invariant.positionAdvanceI32
    omega
  simp only [binaryI32, slot, i32, literal, apply, reference]
  functional_eval

theorem scanTerminal_evaluates
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state)
    (tokenBound : position / 2 < tokens.length) :
    Block.evaluate (ReadOnly.machine verifiedParserCore)
        (scanWorld words tokens grammarCell tokensCell)
        (scanEnvironment words tokens grammarCell tokensCell position semanticKind)
        scanTerminal =
      .done (.returned (some (scanTerminalValue
        (scanTerminalStep grammar.grammar.split_token_kind
          grammar.grammar.split_component_kind
          (tokens.get ⟨position / 2, tokenBound⟩)
          (grammar.grammar.canonical_kinds.get
            ⟨semanticKind, invariant.semanticKindBound⟩)
          position))))
        (scanWorld words tokens grammarCell tokensCell) := by
  let world := scanWorld words tokens grammarCell tokensCell
  let environment := scanEnvironment words tokens grammarCell tokensCell
    position semanticKind
  let tokenIndex := position / 2
  let rawKind := tokens.get ⟨tokenIndex, tokenBound⟩
  let canonicalKindValue := grammar.grammar.canonical_kinds.get
    ⟨semanticKind, invariant.semanticKindBound⟩
  let tokenEnvironment := environment.push
    (.signed .i32 (Int.ofNat tokenIndex))
  let rawEnvironment := tokenEnvironment.push
    (.signed .i32 (Int.ofNat rawKind))
  let canonicalEnvironment := rawEnvironment.push
    (.signed .i32 (Int.ofNat canonicalKindValue))
  have tokenIndexResult := tokenIndex_evaluates invariant
  have tokenIndexValue : tokenEnvironment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat tokenIndex) := by
    rfl
  have tokenCountValue : tokenEnvironment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat tokens.length) := by
    rfl
  have guard := tokenEndGuard_evaluates world tokenEnvironment tokenIndex
    tokens.length tokenIndexValue tokenCountValue
  have guardFalse : Term.evaluate (ReadOnly.machine verifiedParserCore)
      world tokenEnvironment
      (compareI32 .greaterEqual (slot 5) (slot 2)) =
      .ok (.boolean false, world) := by
    have notPastEnd : ¬ tokenIndex ≥ tokens.length := by
      simpa [tokenIndex] using (Nat.not_le.mpr tokenBound)
    simpa [notPastEnd] using guard
  have tokensValue : tokenEnvironment ⟨1, by omega⟩ =
      parserTokensValue tokens tokensCell := by
    rfl
  have rawResult : Term.evaluate (ReadOnly.machine verifiedParserCore)
      world tokenEnvironment (indexI32 (slot 1) (slot 5)) =
      .ok (.signed .i32 (Int.ofNat rawKind), world) := by
    simpa [world, tokenIndex, rawKind] using
      rawKind_evaluates invariant tokenEnvironment tokenBound tokensValue
        tokenIndexValue
  have grammarValueAtRaw : rawEnvironment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell := by
    rfl
  have semanticValueAtRaw : rawEnvironment ⟨4, by omega⟩ =
      .signed .i32 (Int.ofNat semanticKind) := by
    rfl
  have canonicalResult : Term.evaluate (ReadOnly.machine verifiedParserCore)
      world rawEnvironment canonicalKind =
      .ok (.signed .i32 (Int.ofNat canonicalKindValue), world) := by
    simpa [world, canonicalKindValue] using canonicalKind_evaluates invariant
      rawEnvironment grammarValueAtRaw semanticValueAtRaw
  have positionValue : canonicalEnvironment ⟨3, by omega⟩ =
      .signed .i32 (Int.ofNat position) := by
    rfl
  have rawValue : canonicalEnvironment ⟨6, by omega⟩ =
      .signed .i32 (Int.ofNat rawKind) := by
    rfl
  have canonicalValue : canonicalEnvironment ⟨7, by omega⟩ =
      .signed .i32 (Int.ofNat canonicalKindValue) := by
    rfl
  have grammarValue : canonicalEnvironment ⟨0, by omega⟩ =
      parserGrammarValue words grammarCell := by
    rfl
  have splitTokenConstant : Term.evaluate
      (ReadOnly.machine verifiedParserCore) world canonicalEnvironment
      (constant 12) = .ok (.signed .i32 5, world) := by
    simpa [constant, apply] using ReadOnly.Term.evaluate_constant
      (world := world) (environment := canonicalEnvironment)
      verifiedParser_scan_terminal_constants.1
  have splitComponentConstant : Term.evaluate
      (ReadOnly.machine verifiedParserCore) world canonicalEnvironment
      (constant 13) = .ok (.signed .i32 6, world) := by
    simpa [constant, apply] using ReadOnly.Term.evaluate_constant
      (world := world) (environment := canonicalEnvironment)
      verifiedParser_scan_terminal_constants.2.1
  have splitTokenResult := grammarHeader_evaluates world canonicalEnvironment
    words grammarCell grammarValue splitTokenConstant scanWorld_finds_grammar
    invariant.encoded.splitTokenKind
  have splitComponentResult := grammarHeader_evaluates world
    canonicalEnvironment words grammarCell grammarValue splitComponentConstant
    scanWorld_finds_grammar invariant.encoded.splitComponentKind
  have dispatchResult := dispatch_evaluates world canonicalEnvironment position
    rawKind canonicalKindValue grammar.grammar.split_token_kind
    grammar.grammar.split_component_kind positionValue rawValue canonicalValue
    splitTokenResult splitComponentResult invariant.positionAdvanceI32
  rw [scanTerminal_shape]
  apply Block.evaluate_letValue tokenIndexResult
  apply Block.evaluate_sequence_next
  · exact Block.evaluate_if_false guardFalse (Block.evaluate_skip _ _ _)
  apply Block.evaluate_letValue rawResult
  apply Block.evaluate_letValue canonicalResult
  exact dispatchResult

theorem scanTerminal_rejects_past_end_evaluates
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state)
    (pastEnd : tokens.length ≤ position / 2) :
    Block.evaluate (ReadOnly.machine verifiedParserCore)
        (scanWorld words tokens grammarCell tokensCell)
        (scanEnvironment words tokens grammarCell tokensCell position semanticKind)
        scanTerminal =
      .done (.returned (some (scanTerminalValue none)))
        (scanWorld words tokens grammarCell tokensCell) := by
  let world := scanWorld words tokens grammarCell tokensCell
  let environment := scanEnvironment words tokens grammarCell tokensCell
    position semanticKind
  let tokenIndex := position / 2
  let tokenEnvironment := environment.push
    (.signed .i32 (Int.ofNat tokenIndex))
  have tokenIndexResult := tokenIndex_evaluates invariant
  have tokenIndexValue : tokenEnvironment ⟨5, by omega⟩ =
      .signed .i32 (Int.ofNat tokenIndex) := by
    rfl
  have tokenCountValue : tokenEnvironment ⟨2, by omega⟩ =
      .signed .i32 (Int.ofNat tokens.length) := by
    rfl
  have guard := tokenEndGuard_evaluates world tokenEnvironment tokenIndex
    tokens.length tokenIndexValue tokenCountValue
  have guardTrue : Term.evaluate (ReadOnly.machine verifiedParserCore)
      world tokenEnvironment
      (compareI32 .greaterEqual (slot 5) (slot 2)) =
      .ok (.boolean true, world) := by
    simpa [pastEnd, tokenIndex] using guard
  rw [scanTerminal_shape]
  apply Block.evaluate_letValue tokenIndexResult
  simpa [scanTerminalValue, world, environment, tokenIndex,
    tokenEnvironment] using Block.evaluate_sequence_returned
    (Block.evaluate_if_true guardTrue
      (reject_evaluates world tokenEnvironment))

/-- The Functional View is not a second, manually trusted parser model. Deterministic
    conversion recreates the body decoded from the checked compiler artifact. -/
theorem scanTerminalView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 5)) 5 scanTerminalView.block =
      extractedParserScanTerminalBody := by
  exact scanTerminalView.toCoreExactly

/-- The readable proof program and the mechanically reified view denote the
    same checked Core statement. -/
theorem scanTerminal_agrees_with_reification :
    toCoreStmt (identityLayout (arity := 5)) 5 scanTerminal =
      toCoreStmt (identityLayout (arity := 5)) 5 scanTerminalView.block := by
  rw [scanTerminalView_toCore_exactly]
  rfl

/-- Reusable correctness boundary for the extracted function. A parser model
    now proves only that `scanTerminal` evaluates to the desired result under
    its primitive-operation bridge. Cell allocation, restoration, branching,
    returns, and preservation of caller state are discharged here once. -/
theorem extractedScanTerminal_executes_of_evaluation
    {abstractMachine : Machine signature}
    {world afterWorld : abstractMachine.World}
    {state : State} {completion : FunctionalView.Completion}
    (bridge : ReadOnlyBridge abstractMachine verifiedParserCore)
    (represented : bridge.Represents world state)
    (environment : Env 5)
    (environmentMatches : EnvironmentMatches
      (identityLayout (arity := 5)) environment state)
    (wellFormed : StateWellFormed state)
    (evaluated : Block.evaluate abstractMachine world environment scanTerminal =
      .done completion afterWorld) :
    ∃ after,
      Executes verifiedParserCore state extractedParserScanTerminalBody
        (toCoreCompletion completion) after ∧
      ModifiesOnly CellSet.empty state after ∧
      StateWellFormed after ∧
      bridge.Represents afterWorld after ∧
      EnvironmentMatches (identityLayout (arity := 5)) environment after := by
  have below := LayoutBelow.identity (arity := 5)
  obtain ⟨after, execution, effect, afterWellFormed, afterRepresented,
    afterMatches⟩ := block_executes bridge represented environmentMatches below
      wellFormed evaluated
  rw [scanTerminal_agrees_with_reification,
    scanTerminalView_toCore_exactly] at execution
  exact ⟨after, execution, effect, afterWellFormed, afterRepresented,
    afterMatches⟩

/-- The extracted parser scan theorem through Functional View. Compared with the
    structural proof, the function-level argument states the abstract
    evaluation result and delegates lexical allocation, restoration, and
    caller-state preservation to the generic simulation theorem. -/
theorem extractedParserScanTerminalBody_scans
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state)
    (tokenBound : position / 2 < tokens.length) :
    ∃ after,
      Executes verifiedParserCore state extractedParserScanTerminalBody
        (.returned (some (scanTerminalValue
          (scanTerminalStep grammar.grammar.split_token_kind
            grammar.grammar.split_component_kind
            (tokens.get ⟨position / 2, tokenBound⟩)
            (grammar.grammar.canonical_kinds.get
              ⟨semanticKind, invariant.semanticKindBound⟩)
            position)))) after ∧
      ModifiesOnly CellSet.empty state after ∧
      StateWellFormed after := by
  obtain ⟨after, execution, effect, wellFormed, _, _⟩ :=
    extractedScanTerminal_executes_of_evaluation
      (ReadOnly.bridge verifiedParserCore)
      (scanWorld_represents invariant)
      (scanEnvironment words tokens grammarCell tokensCell position semanticKind)
      (scanEnvironment_matches invariant) invariant.wellFormed
      (scanTerminal_evaluates invariant tokenBound)
  exact ⟨after, execution, effect, wellFormed⟩

theorem extractedParserScanTerminalBody_rejects_past_end
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state)
    (pastEnd : tokens.length ≤ position / 2) :
    ∃ after,
      Executes verifiedParserCore state extractedParserScanTerminalBody
        (.returned (some (scanTerminalValue none))) after ∧
      ModifiesOnly CellSet.empty state after ∧
      StateWellFormed after := by
  obtain ⟨after, execution, effect, wellFormed, _, _⟩ :=
    extractedScanTerminal_executes_of_evaluation
      (ReadOnly.bridge verifiedParserCore)
      (scanWorld_represents invariant)
      (scanEnvironment words tokens grammarCell tokensCell position semanticKind)
      (scanEnvironment_matches invariant) invariant.wellFormed
      (scanTerminal_rejects_past_end_evaluates invariant pastEnd)
  exact ⟨after, execution, effect, wellFormed⟩

/-- Authoritative body theorem. The branch-specific functional evaluations
    above are the only scan proofs; structural Core allocation and restoration
    are inherited from the generic Functional View simulation. -/
theorem extractedParserScanTerminalBody_implements_model
    (invariant : ScanTerminalInvariant layout grammar words tokens grammarCell
      tokensCell position semanticKind state) :
    ∃ after,
      Executes verifiedParserCore state extractedParserScanTerminalBody
        (.returned (some (scanTerminalValue
          (Lanius.Compiler.Parser.scanTerminal grammar tokens position
            semanticKind)))) after ∧
      ModifiesOnly CellSet.empty state after ∧
      StateWellFormed after := by
  by_cases tokenBound : position / 2 < tokens.length
  · obtain ⟨after, execution, effect, wellFormed⟩ :=
      extractedParserScanTerminalBody_scans invariant tokenBound
    have tokenFound : tokens[position / 2]? = some
        (tokens.get ⟨position / 2, tokenBound⟩) :=
      List.getElem?_eq_getElem tokenBound
    have canonicalFound : grammar.grammar.canonical_kinds[semanticKind]? = some
        (grammar.grammar.canonical_kinds.get
          ⟨semanticKind, invariant.semanticKindBound⟩) :=
      List.getElem?_eq_getElem invariant.semanticKindBound
    exact ⟨after, by
      simpa [Lanius.Compiler.Parser.scanTerminal, tokenFound, canonicalFound]
        using execution, effect, wellFormed⟩
  · have pastEnd : tokens.length ≤ position / 2 := Nat.le_of_not_gt tokenBound
    obtain ⟨after, execution, effect, wellFormed⟩ :=
      extractedParserScanTerminalBody_rejects_past_end invariant pastEnd
    have tokenMissing : tokens[position / 2]? = none :=
      List.getElem?_eq_none (by omega)
    exact ⟨after, by
      simpa [Lanius.Compiler.Parser.scanTerminal, tokenMissing]
        using execution, effect, wellFormed⟩

end Lanius.Extraction.ParserScan.Proof

namespace Lanius.Extraction.ParserScan

open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Compiler.Parser
open Lanius.Extraction.ParserAccessors

/-- Full extracted call evaluation, now rooted in the Functional View body theorem. -/
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
    Proof.extractedParserScanTerminalBody_implements_model invariant
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
  have callStore : StoreEffect CellSet.empty afterArguments completed :=
    entered.trans_same bodyEffect.toStoreEffect
  have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
    simpa [after] using callStore.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    callStore.restoreLocals_wellFormed afterArgumentsWellFormed
      completedWellFormed
  exact ⟨after, evaluation, callEffect, afterWellFormed,
    callEffect.empty_preserves_entry afterArgumentsWellFormed grammarBacking,
    callEffect.empty_preserves_entry afterArgumentsWellFormed tokensBacking⟩

end Lanius.Extraction.ParserScan
