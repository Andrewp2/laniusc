import Lanius.Extraction.VerifiedFrontend.Parser.Accessors
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
    (include_str ".." / ".." / "Artifacts" / "parser.json"),
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

end Lanius.Extraction.ParserScan
