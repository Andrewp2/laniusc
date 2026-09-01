import Lanius.Extraction.VerifiedFrontendPack
import Lanius.Extraction.ArtifactQuote
import Lanius.Extraction.ArtifactPackChecker
import Lanius.Extraction.StatementNormalization
import Lanius.Compiler.LexerProgramNumbers
import Lanius.CallContracts
import Lanius.FunctionalViewCoreReadOnly

namespace Lanius.Extraction

set_option maxRecDepth 100000

open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Separation

/-- The complete Core program decoded from the checked frontend source pack. -/
def verifiedFrontendCore : Core.Program :=
  match ArtifactPackChecker.mergeCorePrograms? verifiedFrontendPack.units with
  | some wire => CoreDecode.program wire
  | none => {}

def verifiedFrontendLexerSourceText : String :=
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "lexer.lani"

def verifiedFrontendLexerCore : Core.Program :=
  match verifiedFrontendLexerArtifact.core_program with
  | some wire => CoreDecode.program wire
  | none => {}

def extractedIsWhitespaceWire : CoreFunction :=
  artifact_pack_function%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "is_whitespace"

def extractedIsIdentifierStartWire : CoreFunction :=
  artifact_pack_function%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "is_identifier_start"

def extractedIsIdentifierContinueWire : CoreFunction :=
  artifact_pack_function%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "is_identifier_continue"

def extractedIsDecimalDigitWire : CoreFunction :=
  artifact_pack_function%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "is_decimal_digit"

def extractedScanWhitespaceEndWire : CoreFunction :=
  artifact_pack_function%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "scan_whitespace_end"

def extractedScanIdentifierEndWire : CoreFunction :=
  artifact_pack_function%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "scan_identifier_end"

def extractedIsWhitespaceFunction : Function :=
  CoreDecode.function extractedIsWhitespaceWire

def extractedIsIdentifierStartFunction : Function :=
  CoreDecode.function extractedIsIdentifierStartWire

def extractedIsIdentifierContinueFunction : Function :=
  CoreDecode.function extractedIsIdentifierContinueWire

def extractedIsDecimalDigitFunction : Function :=
  CoreDecode.function extractedIsDecimalDigitWire

def extractedScanWhitespaceEndFunction : Function :=
  CoreDecode.function extractedScanWhitespaceEndWire

def extractedScanIdentifierEndFunction : Function :=
  CoreDecode.function extractedScanIdentifierEndWire

def extractedIsWhitespaceBody : Stmt :=
  match extractedIsWhitespaceFunction.body with
  | some body => body
  | none => .skip

def extractedIsIdentifierStartBody : Stmt :=
  match extractedIsIdentifierStartFunction.body with
  | some body => body
  | none => .skip

def extractedIsIdentifierContinueBody : Stmt :=
  match extractedIsIdentifierContinueFunction.body with
  | some body => body
  | none => .skip

def extractedIsDecimalDigitBody : Stmt :=
  match extractedIsDecimalDigitFunction.body with
  | some body => body
  | none => .skip

def extractedScanWhitespaceEndBody : Stmt :=
  match extractedScanWhitespaceEndFunction.body with
  | some body => body
  | none => .skip

def extractedScanIdentifierEndBody : Stmt :=
  match extractedScanIdentifierEndFunction.body with
  | some body => body
  | none => .skip

def extractedIdentifierContinueExpr : Expr :=
  orExpr
    (.call extractedIsIdentifierStartFunction.id [byteLocal])
    (.call extractedIsDecimalDigitFunction.id [byteLocal])

def verifiedFrontendDigitsSourceText : String :=
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "digits.lani"

def verifiedFrontendDigitsCore : Core.Program :=
  match verifiedFrontendDigitsArtifact.core_program with
  | some wire => CoreDecode.program wire
  | none => {}

/-- The raw Core function and body emitted for `scan_digit_run`. The fallback
    branches are ruled out below by definitional theorems over the quoted
    artifact. -/
def extractedScanDigitRunWire : CoreFunction :=
  artifact_pack_function%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani",
    "scan_digit_run"

def extractedIsDigitForBaseWire : CoreFunction :=
  artifact_pack_function%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani",
    "is_digit_for_base"

def extractedSuccessfulDigitsWire : CoreFunction :=
  artifact_pack_function%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani",
    "successful_digits"

def extractedFailedDigitsWire : CoreFunction :=
  artifact_pack_function%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani",
    "failed_digits"

def extractedIsDigitForBaseFunction : Function :=
  CoreDecode.function extractedIsDigitForBaseWire

def extractedSuccessfulDigitsFunction : Function :=
  CoreDecode.function extractedSuccessfulDigitsWire

def extractedFailedDigitsFunction : Function :=
  CoreDecode.function extractedFailedDigitsWire

def extractedIsDigitForBaseBody : Stmt :=
  match extractedIsDigitForBaseFunction.body with
  | some body => body
  | none => .skip

def extractedSuccessfulDigitsBody : Stmt :=
  match extractedSuccessfulDigitsFunction.body with
  | some body => body
  | none => .skip

def extractedFailedDigitsBody : Stmt :=
  match extractedFailedDigitsFunction.body with
  | some body => body
  | none => .skip

def extractedScanDigitRunFunction : Function :=
  CoreDecode.function extractedScanDigitRunWire

def extractedScanDigitRunBody : Stmt :=
  match extractedScanDigitRunFunction.body with
  | some body => body
  | none => .skip

def normalizeFunction (function : Function) : Function := {
  function with body := function.body.map removeTrailingSkips
}

theorem verifiedFrontendLexerUnit_checked :
    checkSurfaceArtifact verifiedFrontendLexerArtifact = true ∧
      (ArtifactContextChecker.checkArtifactProgram?
        verifiedFrontendLexerArtifact).isSome = true := by
  native_decide

theorem verifiedFrontendLexerUnit_tracks_source :
    verifiedFrontendLexerArtifact.sources.map (fun source => source.path) =
        ["verified_compiler/src/verified/lexer.lani"] ∧
      verifiedFrontendLexerArtifact.sources.map (fun source => source.bytes) =
        [sourceTextBytes verifiedFrontendLexerSourceText] := by
  native_decide

theorem extracted_isWhitespace_named_selection_checked :
    (verifiedFrontendLexerArtifact.core_program.map CoreDecode.program).bind
        (fun program => program.function? extractedIsWhitespaceFunction.id) =
      some extractedIsWhitespaceFunction := by
  unfold extractedIsWhitespaceFunction extractedIsWhitespaceWire
    verifiedFrontendLexerArtifact
  rfl

theorem extracted_scanWhitespaceEnd_named_selection_checked :
    (verifiedFrontendLexerArtifact.core_program.map CoreDecode.program).bind
        (fun program => program.function? extractedScanWhitespaceEndFunction.id) =
      some extractedScanWhitespaceEndFunction := by
  unfold extractedScanWhitespaceEndFunction extractedScanWhitespaceEndWire
    verifiedFrontendLexerArtifact
  rfl

theorem extracted_isWhitespaceFunction_has_body :
    extractedIsWhitespaceFunction.body = some extractedIsWhitespaceBody := by
  unfold extractedIsWhitespaceFunction extractedIsWhitespaceBody
    extractedIsWhitespaceWire
  rfl

theorem extracted_scanWhitespaceEndFunction_has_body :
    extractedScanWhitespaceEndFunction.body =
      some extractedScanWhitespaceEndBody := by
  unfold extractedScanWhitespaceEndFunction extractedScanWhitespaceEndBody
    extractedScanWhitespaceEndWire
  rfl

theorem extracted_isWhitespaceBody_normalizes :
    removeTrailingSkips extractedIsWhitespaceBody =
      returnBool whitespaceExpr := by
  unfold extractedIsWhitespaceBody extractedIsWhitespaceFunction
    extractedIsWhitespaceWire
  rfl

theorem extracted_scanWhitespaceEndBody_normalizes :
    removeTrailingSkips extractedScanWhitespaceEndBody =
      scannerBody extractedIsWhitespaceFunction := by
  unfold extractedScanWhitespaceEndBody extractedScanWhitespaceEndFunction
    extractedScanWhitespaceEndWire extractedIsWhitespaceFunction
    extractedIsWhitespaceWire scannerBody scannerCondition
  rfl

theorem extracted_isWhitespaceBody_normalization_supported :
    SkipNormalizationSupported extractedIsWhitespaceBody := by
  native_decide

theorem extracted_scanWhitespaceEndBody_normalization_supported :
    SkipNormalizationSupported extractedScanWhitespaceEndBody := by
  native_decide

theorem extracted_isIdentifierStartFunction_has_body :
    extractedIsIdentifierStartFunction.body =
      some extractedIsIdentifierStartBody := by
  unfold extractedIsIdentifierStartFunction extractedIsIdentifierStartBody
    extractedIsIdentifierStartWire
  rfl

theorem extracted_isIdentifierContinueFunction_has_body :
    extractedIsIdentifierContinueFunction.body =
      some extractedIsIdentifierContinueBody := by
  unfold extractedIsIdentifierContinueFunction
    extractedIsIdentifierContinueBody extractedIsIdentifierContinueWire
  rfl

theorem extracted_isDecimalDigitFunction_has_body :
    extractedIsDecimalDigitFunction.body =
      some extractedIsDecimalDigitBody := by
  unfold extractedIsDecimalDigitFunction extractedIsDecimalDigitBody
    extractedIsDecimalDigitWire
  rfl

theorem extracted_scanIdentifierEndFunction_has_body :
    extractedScanIdentifierEndFunction.body =
      some extractedScanIdentifierEndBody := by
  unfold extractedScanIdentifierEndFunction extractedScanIdentifierEndBody
    extractedScanIdentifierEndWire
  rfl

theorem extracted_isIdentifierStartBody_normalizes :
    removeTrailingSkips extractedIsIdentifierStartBody =
      returnBool identifierStartExpr := by
  unfold extractedIsIdentifierStartBody extractedIsIdentifierStartFunction
    extractedIsIdentifierStartWire
  rfl

theorem extracted_isDecimalDigitBody_normalizes :
    removeTrailingSkips extractedIsDecimalDigitBody =
      returnBool decimalDigitExpr := by
  unfold extractedIsDecimalDigitBody extractedIsDecimalDigitFunction
    extractedIsDecimalDigitWire
  rfl

theorem extracted_isIdentifierContinueBody_normalizes :
    removeTrailingSkips extractedIsIdentifierContinueBody =
      returnBool extractedIdentifierContinueExpr := by
  unfold extractedIsIdentifierContinueBody
    extractedIsIdentifierContinueFunction extractedIsIdentifierContinueWire
    extractedIdentifierContinueExpr
  rfl

theorem extracted_scanIdentifierEndBody_normalizes :
    removeTrailingSkips extractedScanIdentifierEndBody =
      scannerBody extractedIsIdentifierContinueFunction := by
  unfold extractedScanIdentifierEndBody extractedScanIdentifierEndFunction
    extractedScanIdentifierEndWire extractedIsIdentifierContinueFunction
    extractedIsIdentifierContinueWire scannerBody scannerCondition
  rfl

theorem extracted_isIdentifierStartBody_normalization_supported :
    SkipNormalizationSupported extractedIsIdentifierStartBody := by
  native_decide

theorem extracted_isIdentifierContinueBody_normalization_supported :
    SkipNormalizationSupported extractedIsIdentifierContinueBody := by
  native_decide

theorem extracted_isDecimalDigitBody_normalization_supported :
    SkipNormalizationSupported extractedIsDecimalDigitBody := by
  native_decide

theorem extracted_scanIdentifierEndBody_normalization_supported :
    SkipNormalizationSupported extractedScanIdentifierEndBody := by
  native_decide

theorem extracted_isIdentifierStartBody_shape :
    extractedIsIdentifierStartBody =
      .sequence (returnBool identifierStartExpr) .skip := by
  unfold extractedIsIdentifierStartBody extractedIsIdentifierStartFunction
    extractedIsIdentifierStartWire returnBool identifierStartExpr
    byteInClosedRange andExpr orExpr compareByte byteLocal i32Literal
  rfl

theorem extracted_isDecimalDigitBody_shape :
    extractedIsDecimalDigitBody =
      .sequence (returnBool decimalDigitExpr) .skip := by
  unfold extractedIsDecimalDigitBody extractedIsDecimalDigitFunction
    extractedIsDecimalDigitWire returnBool decimalDigitExpr
    byteInClosedRange andExpr compareByte byteLocal i32Literal
  rfl

theorem extracted_isIdentifierContinueBody_shape :
    extractedIsIdentifierContinueBody =
      .sequence (returnBool extractedIdentifierContinueExpr) .skip := by
  unfold extractedIsIdentifierContinueBody
    extractedIsIdentifierContinueFunction extractedIsIdentifierContinueWire
    extractedIdentifierContinueExpr returnBool orExpr byteLocal
    extractedIsIdentifierStartFunction extractedIsIdentifierStartWire
    extractedIsDecimalDigitFunction extractedIsDecimalDigitWire
  rfl

theorem extracted_isWhitespaceBody_shape :
    extractedIsWhitespaceBody =
      .sequence (returnBool whitespaceExpr) .skip := by
  unfold extractedIsWhitespaceBody extractedIsWhitespaceFunction
    extractedIsWhitespaceWire returnBool whitespaceExpr byteEqualsAny orExpr
    compareByte byteLocal i32Literal
  rfl

theorem verifiedFrontendLexerCore_finds_isWhitespace :
    verifiedFrontendLexerCore.function? extractedIsWhitespaceFunction.id =
      some extractedIsWhitespaceFunction := by
  unfold verifiedFrontendLexerCore verifiedFrontendLexerArtifact
    extractedIsWhitespaceFunction extractedIsWhitespaceWire
  rfl

theorem verifiedFrontendLexerCore_finds_isIdentifierStart :
    verifiedFrontendLexerCore.function?
        extractedIsIdentifierStartFunction.id =
      some extractedIsIdentifierStartFunction := by
  unfold verifiedFrontendLexerCore verifiedFrontendLexerArtifact
    extractedIsIdentifierStartFunction extractedIsIdentifierStartWire
  rfl

theorem verifiedFrontendLexerCore_finds_isIdentifierContinue :
    verifiedFrontendLexerCore.function?
        extractedIsIdentifierContinueFunction.id =
      some extractedIsIdentifierContinueFunction := by
  unfold verifiedFrontendLexerCore verifiedFrontendLexerArtifact
    extractedIsIdentifierContinueFunction extractedIsIdentifierContinueWire
  rfl

theorem verifiedFrontendLexerCore_finds_isDecimalDigit :
    verifiedFrontendLexerCore.function? extractedIsDecimalDigitFunction.id =
      some extractedIsDecimalDigitFunction := by
  unfold verifiedFrontendLexerCore verifiedFrontendLexerArtifact
    extractedIsDecimalDigitFunction extractedIsDecimalDigitWire
  rfl

theorem verifiedFrontendLexerCore_finds_scanWhitespaceEnd :
    verifiedFrontendLexerCore.function?
        extractedScanWhitespaceEndFunction.id =
      some extractedScanWhitespaceEndFunction := by
  unfold verifiedFrontendLexerCore verifiedFrontendLexerArtifact
    extractedScanWhitespaceEndFunction extractedScanWhitespaceEndWire
  rfl

theorem verifiedFrontendLexerCore_finds_scanIdentifierEnd :
    verifiedFrontendLexerCore.function?
        extractedScanIdentifierEndFunction.id =
      some extractedScanIdentifierEndFunction := by
  unfold verifiedFrontendLexerCore verifiedFrontendLexerArtifact
    extractedScanIdentifierEndFunction extractedScanIdentifierEndWire
  rfl

theorem extracted_isWhitespaceBody_executes_at_fuel
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    execStmt 14 verifiedFrontendLexerCore
      (unaryCalleeState state byte) extractedIsWhitespaceBody =
      .done (.returned (some (.boolean (isWhitespace byte))))
        (unaryCalleeState state byte) := by
  have expressionBase := whitespaceExpr_executes verifiedFrontendLexerCore
    state wellFormed byte
  have expression := Lanius.Fuel.evalExpr_done_at_larger_fuel
    (program := verifiedFrontendLexerCore)
    (by decide : 6 ≤ 12) expressionBase
  rw [extracted_isWhitespaceBody_shape]
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only [returnBool]
  rw [expression]

private theorem rawReturnBoolBody_executes
    (program : Program) (state : State) (body : Stmt) (expression : Expr)
    (result : Bool) (finalState : State) (fuel : Nat)
    (shape : body = .sequence (returnBool expression) .skip)
    (expressionResult : evalExpr fuel program state expression =
      .done (.boolean result) finalState) :
    execStmt (fuel + 2) program state body =
      .done (.returned (some (.boolean result))) finalState := by
  rw [shape]
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only [returnBool]
  rw [expressionResult]

theorem extracted_isIdentifierStartCall_after_argument
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (byte : Byte)
    (argumentResult : evalExpr 9 verifiedFrontendLexerCore state argument =
      .done (.signed .i32 byte.val) state) :
    evalExpr 11 verifiedFrontendLexerCore state
      (.call extractedIsIdentifierStartFunction.id [argument]) =
      .done (.boolean (isIdentifierStart byte))
        (unaryCallState state byte) := by
  have expressionBase := identifierStartExpr_executes
    verifiedFrontendLexerCore state wellFormed byte
  have expression := Lanius.Fuel.evalExpr_done_at_larger_fuel
    (program := verifiedFrontendLexerCore)
    (by decide : 6 ≤ 8) expressionBase
  have body := rawReturnBoolBody_executes verifiedFrontendLexerCore
    (unaryCalleeState state byte) extractedIsIdentifierStartBody
    identifierStartExpr (isIdentifierStart byte) (unaryCalleeState state byte) 8
    extracted_isIdentifierStartBody_shape expression
  simpa [unaryCallState] using
    unaryFunctionCallWithBody_executes verifiedFrontendLexerCore 9
      (by decide) extractedIsIdentifierStartFunction i32Type
      extractedIsIdentifierStartBody state argument (.signed .i32 byte.val)
      (.boolean (isIdentifierStart byte)) (unaryCalleeState state byte)
      verifiedFrontendLexerCore_finds_isIdentifierStart (by rfl)
      extracted_isIdentifierStartFunction_has_body argumentResult body

theorem extracted_isDecimalDigitCall_after_argument
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (byte : Byte)
    (argumentResult : evalExpr 9 verifiedFrontendLexerCore state argument =
      .done (.signed .i32 byte.val) state) :
    evalExpr 11 verifiedFrontendLexerCore state
      (.call extractedIsDecimalDigitFunction.id [argument]) =
      .done (.boolean (isDecimalDigit byte)) (unaryCallState state byte) := by
  have expressionBase := decimalDigitExpr_executes verifiedFrontendLexerCore
    state wellFormed byte
  have expression := Lanius.Fuel.evalExpr_done_at_larger_fuel
    (program := verifiedFrontendLexerCore)
    (by decide : 4 ≤ 8) expressionBase
  have body := rawReturnBoolBody_executes verifiedFrontendLexerCore
    (unaryCalleeState state byte) extractedIsDecimalDigitBody
    decimalDigitExpr (isDecimalDigit byte) (unaryCalleeState state byte) 8
    extracted_isDecimalDigitBody_shape expression
  simpa [unaryCallState] using
    unaryFunctionCallWithBody_executes verifiedFrontendLexerCore 9
      (by decide) extractedIsDecimalDigitFunction i32Type
      extractedIsDecimalDigitBody state argument (.signed .i32 byte.val)
      (.boolean (isDecimalDigit byte)) (unaryCalleeState state byte)
      verifiedFrontendLexerCore_finds_isDecimalDigit (by rfl)
      extracted_isDecimalDigitFunction_has_body argumentResult body

theorem extracted_identifierContinueExpr_executes
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    evalExpr 12 verifiedFrontendLexerCore (unaryCalleeState state byte)
      extractedIdentifierContinueExpr =
      .done (.boolean (isIdentifierContinue byte))
        (identifierContinueBodyState state byte) := by
  let outer := unaryCalleeState state byte
  have outerWellFormed := bindLocal_preserves_well_formed
    (clearLocals state) 0 (.signed .i32 byte.val)
    (clearLocals_well_formed state wellFormed)
  have outerLocal := unaryCalleeState_local state wellFormed byte
  have outerArgument := evalLocal_of_local 8 verifiedFrontendLexerCore outer 0
    (.signed .i32 byte.val) outerLocal
  have firstCall := extracted_isIdentifierStartCall_after_argument outer
    outerWellFormed byteLocal byte outerArgument
  let afterStart := identifierContinueAfterStartState state byte
  have afterStartWellFormed : StateWellFormed afterStart :=
    unaryCallState_well_formed outer outerWellFormed byte
  have afterStartLocal : afterStart.local? 0 =
      some (.signed .i32 byte.val) :=
    (unaryCallState_extends outer byte).preserves_local
      outerWellFormed outerLocal
  have afterStartArgument := evalLocal_of_local 8 verifiedFrontendLexerCore
    afterStart 0 (.signed .i32 byte.val) afterStartLocal
  have secondCall := extracted_isDecimalDigitCall_after_argument afterStart
    afterStartWellFormed byteLocal byte afterStartArgument
  have secondCallExpanded :
      evalExpr 11 verifiedFrontendLexerCore (unaryCallState outer byte)
        (.call extractedIsDecimalDigitFunction.id [byteLocal]) =
        .done (.boolean (isDecimalDigit byte))
          (unaryCallState (unaryCallState outer byte) byte) := by
    simpa [afterStart, identifierContinueAfterStartState, outer] using
      secondCall
  change evalExpr 12 verifiedFrontendLexerCore outer
    (orExpr
      (.call extractedIsIdentifierStartFunction.id [byteLocal])
      (.call extractedIsDecimalDigitFunction.id [byteLocal])) = _
  simp only [orExpr]
  rw [Lanius.Semantics.evalExpr, firstCall]
  by_cases starts : isIdentifierStart byte = true
  · simp [starts, identifierContinueBodyState,
      identifierContinueAfterStartState, outer, isIdentifierContinue]
  · have doesNotStart : isIdentifierStart byte = false :=
      Bool.eq_false_iff.mpr starts
    simp only [doesNotStart]
    rw [secondCallExpanded]
    simp [doesNotStart, identifierContinueBodyState,
      identifierContinueAfterStartState, outer, isIdentifierContinue]

theorem extracted_isIdentifierContinueBody_executes_at_fuel
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    execStmt 14 verifiedFrontendLexerCore
      (unaryCalleeState state byte) extractedIsIdentifierContinueBody =
      .done (.returned (some (.boolean (isIdentifierContinue byte))))
        (identifierContinueBodyState state byte) := by
  exact rawReturnBoolBody_executes verifiedFrontendLexerCore
    (unaryCalleeState state byte) extractedIsIdentifierContinueBody
    extractedIdentifierContinueExpr (isIdentifierContinue byte)
    (identifierContinueBodyState state byte) 12
    extracted_isIdentifierContinueBody_shape
    (extracted_identifierContinueExpr_executes state wellFormed byte)

theorem extracted_isIdentifierContinueCall_after_argument
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (byte : Byte)
    (argumentResult : evalExpr 13 verifiedFrontendLexerCore state argument =
      .done (.signed .i32 byte.val) state) :
    evalExpr 15 verifiedFrontendLexerCore state
      (.call extractedIsIdentifierContinueFunction.id [argument]) =
      .done (.boolean (isIdentifierContinue byte))
        (identifierContinueCallState state byte) := by
  simpa [identifierContinueCallState] using
    unaryFunctionCallWithBody_executes verifiedFrontendLexerCore 13
      (by decide) extractedIsIdentifierContinueFunction i32Type
      extractedIsIdentifierContinueBody state argument (.signed .i32 byte.val)
      (.boolean (isIdentifierContinue byte))
      (identifierContinueBodyState state byte)
      verifiedFrontendLexerCore_finds_isIdentifierContinue (by rfl)
      extracted_isIdentifierContinueFunction_has_body argumentResult
      (extracted_isIdentifierContinueBody_executes_at_fuel state wellFormed byte)

theorem extracted_isWhitespaceCall_after_argument
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (byte : Byte)
    (argumentResult : evalExpr 13 verifiedFrontendLexerCore state argument =
      .done (.signed .i32 byte.val) state) :
    evalExpr 15 verifiedFrontendLexerCore state
      (.call extractedIsWhitespaceFunction.id [argument]) =
      .done (.boolean (isWhitespace byte)) (unaryCallState state byte) := by
  have arguments :
      evalExprs 14 verifiedFrontendLexerCore state [argument] =
        .done [.signed .i32 byte.val] state := by
    rw [Lanius.Semantics.evalExprs.eq_def]
    simp only
    rw [argumentResult]
    rfl
  have parametersBound :
      bindParameters extractedIsWhitespaceFunction.parameters
          [.signed .i32 byte.val] =
        some [(0, .signed .i32 byte.val)] := by
    unfold extractedIsWhitespaceFunction extractedIsWhitespaceWire
    rfl
  have callee :
      ({ state with locals := [] }).bindLocals
          [(0, .signed .i32 byte.val)] =
        unaryCalleeState state byte := by
    rfl
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [arguments]
  simp only
  rw [verifiedFrontendLexerCore_finds_isWhitespace]
  simp only
  rw [parametersBound, extracted_isWhitespaceFunction_has_body]
  simp only
  rw [callee, extracted_isWhitespaceBody_executes_at_fuel state wellFormed byte]
  rfl

def extractedWhitespacePredicateSemantics :
    ScannerPredicateSemantics verifiedFrontendLexerCore
      extractedIsWhitespaceFunction isWhitespace where
  callState := unaryCallState
  call_executes := extracted_isWhitespaceCall_after_argument
  call_extends := unaryCallState_extends
  call_well_formed := unaryCallState_well_formed

def extractedIdentifierPredicateSemantics :
    ScannerPredicateSemantics verifiedFrontendLexerCore
      extractedIsIdentifierContinueFunction isIdentifierContinue where
  callState := identifierContinueCallState
  call_executes := extracted_isIdentifierContinueCall_after_argument
  call_extends := identifierContinueCallState_extends
  call_well_formed := identifierContinueCallState_well_formed

/-- Execution of the exact scanner body emitted from `lexer.lani`. The generic
    loop proof is instantiated with the extracted predicate implementation;
    normalization is then transported back to the raw Core statement tree. -/
theorem extracted_scanWhitespaceEndBody_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ loopFinal,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        extractedScanWhitespaceEndBody
        (.returned (some (.signed .i32 (scanWhitespaceEnd source start))))
        (restoreLocals (scannerParameterState source start) loopFinal) ∧
      ScannerState loopFinal source start (scanWhitespaceEnd source start) := by
  obtain ⟨loopFinal, normalizedExecution, finalInvariant⟩ :=
    scannerBody_executes extractedWhitespacePredicateSemantics source start
      sourceBound startInBounds
  have normalized : Executes verifiedFrontendLexerCore
      (scannerParameterState source start)
      (removeTrailingSkips extractedScanWhitespaceEndBody)
      (.returned (some (.signed .i32 (scanWhitespaceEnd source start))))
      (restoreLocals (scannerParameterState source start) loopFinal) := by
    rw [extracted_scanWhitespaceEndBody_normalizes]
    simpa [scanAcceptedFrom, scanWhitespaceEnd] using normalizedExecution
  exact ⟨loopFinal,
    removeTrailingSkips_executes_complete
      extracted_scanWhitespaceEndBody_normalization_supported normalized,
    by simpa [scanAcceptedFrom, scanWhitespaceEnd] using finalInvariant⟩

def extractedScanWhitespaceEndCall
    (source : List Byte) (start : Nat) : Expr :=
  scannerCall extractedScanWhitespaceEndFunction source start

/-- End-to-end execution of the source-extracted whitespace scanner, including
    argument evaluation, ABI binding, its extracted predicate call, loop
    execution, and restoration of the caller's lexical frame. -/
theorem extracted_scanWhitespaceEndCall_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates verifiedFrontendLexerCore (sourceState source)
        (extractedScanWhitespaceEndCall source start)
        (.signed .i32 (scanWhitespaceEnd source start)) finalState := by
  obtain ⟨loopFinal, bodyExecution, _finalInvariant⟩ :=
    extracted_scanWhitespaceEndBody_executes source start sourceBound
      startInBounds
  have parameters :
      extractedScanWhitespaceEndFunction.parameters = scannerParameters := by
    unfold extractedScanWhitespaceEndFunction extractedScanWhitespaceEndWire
      scannerParameters
    rfl
  have execution := scannerCall_executesBody verifiedFrontendLexerCore
    extractedScanWhitespaceEndFunction extractedScanWhitespaceEndBody
    (.signed .i32 (scanWhitespaceEnd source start))
    verifiedFrontendLexerCore_finds_scanWhitespaceEnd parameters
    extracted_scanWhitespaceEndFunction_has_body source start
    ⟨restoreLocals (scannerParameterState source start) loopFinal,
      bodyExecution⟩
  simpa [extractedScanWhitespaceEndCall] using execution

theorem extracted_scanWhitespaceEndFunction_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    extractedScanWhitespaceEndFunction.id = 7 ∧
      extractedScanWhitespaceEndFunction.parameters = scannerParameters ∧
      extractedScanWhitespaceEndFunction.returnType = i32Type ∧
      extractedScanWhitespaceEndFunction.external = none ∧
      ∃ finalState,
        Evaluates verifiedFrontendLexerCore (sourceState source)
          (extractedScanWhitespaceEndCall source start)
          (.signed .i32 (scanWhitespaceEnd source start)) finalState := by
  have metadata :
      extractedScanWhitespaceEndFunction.id = 7 ∧
        extractedScanWhitespaceEndFunction.parameters = scannerParameters ∧
        extractedScanWhitespaceEndFunction.returnType = i32Type ∧
        extractedScanWhitespaceEndFunction.external = none := by
    unfold extractedScanWhitespaceEndFunction extractedScanWhitespaceEndWire
      scannerParameters i32Type
    decide
  exact ⟨metadata.1, metadata.2.1, metadata.2.2.1, metadata.2.2.2,
    extracted_scanWhitespaceEndCall_executes source start sourceBound
      startInBounds⟩

/-- Execution of the exact identifier-scanner body emitted from `lexer.lani`,
    including both nested source-extracted character-classification calls. -/
theorem extracted_scanIdentifierEndBody_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ loopFinal,
      Executes verifiedFrontendLexerCore (scannerParameterState source start)
        extractedScanIdentifierEndBody
        (.returned (some (.signed .i32 (scanIdentifierEnd source start))))
        (restoreLocals (scannerParameterState source start) loopFinal) ∧
      ScannerState loopFinal source start (scanIdentifierEnd source start) := by
  obtain ⟨loopFinal, normalizedExecution, finalInvariant⟩ :=
    scannerBody_executes extractedIdentifierPredicateSemantics source start
      sourceBound startInBounds
  have normalized : Executes verifiedFrontendLexerCore
      (scannerParameterState source start)
      (removeTrailingSkips extractedScanIdentifierEndBody)
      (.returned (some (.signed .i32 (scanIdentifierEnd source start))))
      (restoreLocals (scannerParameterState source start) loopFinal) := by
    rw [extracted_scanIdentifierEndBody_normalizes]
    simpa [scanAcceptedFrom, scanIdentifierEnd] using normalizedExecution
  exact ⟨loopFinal,
    removeTrailingSkips_executes_complete
      extracted_scanIdentifierEndBody_normalization_supported normalized,
    by simpa [scanAcceptedFrom, scanIdentifierEnd] using finalInvariant⟩

def extractedScanIdentifierEndCall
    (source : List Byte) (start : Nat) : Expr :=
  scannerCall extractedScanIdentifierEndFunction source start

theorem extracted_scanIdentifierEndCall_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates verifiedFrontendLexerCore (sourceState source)
        (extractedScanIdentifierEndCall source start)
        (.signed .i32 (scanIdentifierEnd source start)) finalState := by
  obtain ⟨loopFinal, bodyExecution, _finalInvariant⟩ :=
    extracted_scanIdentifierEndBody_executes source start sourceBound
      startInBounds
  have parameters :
      extractedScanIdentifierEndFunction.parameters = scannerParameters := by
    unfold extractedScanIdentifierEndFunction extractedScanIdentifierEndWire
      scannerParameters
    rfl
  have execution := scannerCall_executesBody verifiedFrontendLexerCore
    extractedScanIdentifierEndFunction extractedScanIdentifierEndBody
    (.signed .i32 (scanIdentifierEnd source start))
    verifiedFrontendLexerCore_finds_scanIdentifierEnd parameters
    extracted_scanIdentifierEndFunction_has_body source start
    ⟨restoreLocals (scannerParameterState source start) loopFinal,
      bodyExecution⟩
  simpa [extractedScanIdentifierEndCall] using execution

theorem extracted_scanIdentifierEndFunction_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    extractedScanIdentifierEndFunction.id = 6 ∧
      extractedScanIdentifierEndFunction.parameters = scannerParameters ∧
      extractedScanIdentifierEndFunction.returnType = i32Type ∧
      extractedScanIdentifierEndFunction.external = none ∧
      ∃ finalState,
        Evaluates verifiedFrontendLexerCore (sourceState source)
          (extractedScanIdentifierEndCall source start)
          (.signed .i32 (scanIdentifierEnd source start)) finalState := by
  have metadata :
      extractedScanIdentifierEndFunction.id = 6 ∧
        extractedScanIdentifierEndFunction.parameters = scannerParameters ∧
        extractedScanIdentifierEndFunction.returnType = i32Type ∧
        extractedScanIdentifierEndFunction.external = none := by
    unfold extractedScanIdentifierEndFunction extractedScanIdentifierEndWire
      scannerParameters i32Type
    decide
  exact ⟨metadata.1, metadata.2.1, metadata.2.2.1, metadata.2.2.2,
    extracted_scanIdentifierEndCall_executes source start sourceBound
      startInBounds⟩

/-- The pack really contains the intended nine units and 54 globally identified
    functions; the fallback branch in `verifiedFrontendCore` is unreachable. -/
theorem verifiedFrontendCore_shape :
    verifiedFrontendPack.units.length = 9 ∧
      verifiedFrontendCore.functions.length = 54 := by
  native_decide

theorem verifiedFrontendDigitsUnit_checked :
    checkSurfaceArtifact verifiedFrontendDigitsArtifact = true ∧
      (ArtifactContextChecker.checkArtifactProgram?
        verifiedFrontendDigitsArtifact).isSome = true := by
  native_decide

theorem extracted_scanDigitRun_named_selection_checked :
    (ArtifactContextChecker.checkArtifactProgram?
        verifiedFrontendDigitsArtifact).isSome = true ∧
      (verifiedFrontendDigitsArtifact.core_program.map CoreDecode.program).bind
          (fun program => program.function? extractedScanDigitRunFunction.id) =
        some extractedScanDigitRunFunction := by
  constructor
  · exact verifiedFrontendDigitsUnit_checked.2
  · unfold extractedScanDigitRunFunction extractedScanDigitRunWire
    unfold verifiedFrontendDigitsArtifact
    rfl

def verifiedFrontendDigitsFunctionNames : Option (List String) :=
  (decodeReconstructedSurface verifiedFrontendDigitsArtifact).map fun surface =>
    (ArtifactContextChecker.collectFunctions surface.items).map (fun function =>
      function.name)

def verifiedFrontendDigitsFunctionIds : Option (List Nat) :=
  (verifiedFrontendDigitsArtifact.core_program.map CoreDecode.program).map fun program =>
    program.functions.map (fun function => function.id)

/-- This is the checked name-to-Core-order certificate used by the named
    quotation above. `checkArtifactProgram?` proves the Surface and Core lists
    are paired in precisely this order. -/
theorem verifiedFrontendDigits_function_order :
    verifiedFrontendDigitsFunctionNames = some [
        "digit_scan_succeeded", "digit_scan_end_offset",
        "digit_scan_error_offset", "successful_digits", "failed_digits",
        "is_digit_for_base", "scan_digit_run"] ∧
      verifiedFrontendDigitsFunctionIds = some [24, 25, 26, 27, 28, 29, 30] ∧
      extractedScanDigitRunFunction.id = 30 := by
  native_decide

/-- The directly quoted unit used by implementation proofs is byte-for-byte
    the checked-in source file, not merely a unit selected by a matching name. -/
theorem verifiedFrontendDigitsUnit_tracks_source :
    verifiedFrontendDigitsArtifact.sources.map (fun source => source.path) =
        ["verified_compiler/src/verified/digits.lani"] ∧
      verifiedFrontendDigitsArtifact.sources.map (fun source => source.bytes) =
        [sourceTextBytes verifiedFrontendDigitsSourceText] := by
  native_decide

/-- This is the first mechanical source-to-proof connection for an algorithm:
    function 30 comes from `digits.lani`, and its canonical Core syntax is the
    exact function whose execution was proved in `LexerProgramNumbers`. -/
theorem extracted_scanDigitRun_matches_proved_function :
    normalizeFunction extractedScanDigitRunFunction = scanDigitRunFunction := by
  unfold normalizeFunction extractedScanDigitRunFunction extractedScanDigitRunWire
  rfl

theorem extracted_scanDigitRunFunction_has_body :
    extractedScanDigitRunFunction.body = some extractedScanDigitRunBody := by
  unfold extractedScanDigitRunFunction extractedScanDigitRunBody
  unfold extractedScanDigitRunWire
  rfl

theorem extracted_scanDigitRunBody_normalizes :
    removeTrailingSkips extractedScanDigitRunBody = scanDigitRunBody := by
  unfold extractedScanDigitRunBody extractedScanDigitRunFunction
  unfold extractedScanDigitRunWire
  rfl

theorem extracted_scanDigitRunBody_normalization_supported :
    SkipNormalizationSupported extractedScanDigitRunBody := by
  native_decide

theorem extracted_isDigitForBaseFunction_has_body :
    extractedIsDigitForBaseFunction.body = some extractedIsDigitForBaseBody := by
  unfold extractedIsDigitForBaseFunction extractedIsDigitForBaseBody
    extractedIsDigitForBaseWire
  rfl

theorem extracted_isDigitForBaseBody_normalization_supported :
    SkipNormalizationSupported extractedIsDigitForBaseBody := by
  native_decide

theorem extracted_successfulDigits_matches_proved_function :
    normalizeFunction extractedSuccessfulDigitsFunction =
      successfulDigitsFunction := by
  unfold normalizeFunction extractedSuccessfulDigitsFunction
    extractedSuccessfulDigitsWire
  rfl

theorem extracted_failedDigits_matches_proved_function :
    normalizeFunction extractedFailedDigitsFunction = failedDigitsFunction := by
  unfold normalizeFunction extractedFailedDigitsFunction extractedFailedDigitsWire
  rfl

theorem extracted_successfulDigitsBody_normalizes :
    removeTrailingSkips extractedSuccessfulDigitsBody =
      (successfulDigitsFunction.body.get (by rfl)) := by
  unfold extractedSuccessfulDigitsBody extractedSuccessfulDigitsFunction
    extractedSuccessfulDigitsWire successfulDigitsFunction
  rfl

theorem extracted_successfulDigitsFunction_has_body :
    extractedSuccessfulDigitsFunction.body =
      some extractedSuccessfulDigitsBody := by
  unfold extractedSuccessfulDigitsBody extractedSuccessfulDigitsFunction
    extractedSuccessfulDigitsWire
  rfl

theorem extracted_failedDigitsFunction_has_body :
    extractedFailedDigitsFunction.body = some extractedFailedDigitsBody := by
  unfold extractedFailedDigitsBody extractedFailedDigitsFunction
    extractedFailedDigitsWire
  rfl

theorem extracted_failedDigitsBody_normalizes :
    removeTrailingSkips extractedFailedDigitsBody =
      (failedDigitsFunction.body.get (by rfl)) := by
  unfold extractedFailedDigitsBody extractedFailedDigitsFunction
    extractedFailedDigitsWire failedDigitsFunction
  rfl

theorem extracted_successfulDigitsBody_supported :
    SkipNormalizationSupported extractedSuccessfulDigitsBody := by
  native_decide

theorem extracted_failedDigitsBody_supported :
    SkipNormalizationSupported extractedFailedDigitsBody := by
  native_decide

private theorem successfulDigitsBody_executes_in_program
    (program : Program) (state : State) (wellFormed : StateWellFormed state)
    (offset : Nat) :
    execStmt 7 program
      (singleArgumentCalleeState state (.signed .i32 offset))
      (.returnValue (some (.structValue digitScanDeclaration.id
        [.value (.boolean true), .local 0, i32Literal 0]))) =
      .done (.returned (some (digitScanValue (.success offset))))
        (singleArgumentCalleeState state (.signed .i32 offset)) := by
  let callee := singleArgumentCalleeState state (.signed .i32 offset)
  have localFound := singleArgumentCalleeState_local state wellFormed
    (.signed .i32 offset)
  have localResult := evalLocal_of_local 2 program callee 0
    (.signed .i32 offset) localFound
  have firstResult : evalExpr 4 program callee (.value (.boolean true)) =
      .done (.boolean true) callee := by rfl
  have fieldsResult :
      evalExprs 5 program callee
        [.value (.boolean true), .local 0, i32Literal 0] =
      .done [.boolean true, .signed .i32 offset, .signed .i32 0] callee := by
    rw [Lanius.Semantics.evalExprs.eq_3, firstResult]
    simp only
    rw [Lanius.Semantics.evalExprs.eq_3, localResult]
    rfl
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only
  rw [Lanius.Semantics.evalExpr]
  rw [fieldsResult]
  rfl

private theorem failedDigitsBody_executes_in_program
    (program : Program) (state : State) (wellFormed : StateWellFormed state)
    (offset : Nat) :
    execStmt 7 program
      (singleArgumentCalleeState state (.signed .i32 offset))
      (.returnValue (some (.structValue digitScanDeclaration.id
        [.value (.boolean false), i32Literal 0, .local 0]))) =
      .done (.returned (some (digitScanValue (.failure offset))))
        (singleArgumentCalleeState state (.signed .i32 offset)) := by
  let callee := singleArgumentCalleeState state (.signed .i32 offset)
  have localFound := singleArgumentCalleeState_local state wellFormed
    (.signed .i32 offset)
  have localResult := evalLocal_of_local 1 program callee 0
    (.signed .i32 offset) localFound
  have firstResult : evalExpr 4 program callee (.value (.boolean false)) =
      .done (.boolean false) callee := by rfl
  have secondResult : evalExpr 3 program callee (i32Literal 0) =
      .done (.signed .i32 0) callee := by rfl
  have fieldsResult :
      evalExprs 5 program callee
        [.value (.boolean false), i32Literal 0, .local 0] =
      .done [.boolean false, .signed .i32 0, .signed .i32 offset] callee := by
    rw [Lanius.Semantics.evalExprs.eq_3, firstResult]
    simp only
    rw [Lanius.Semantics.evalExprs.eq_3, secondResult]
    simp only
    rw [Lanius.Semantics.evalExprs.eq_3, localResult]
    simp only
    rw [Lanius.Semantics.evalExprs.eq_2]
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only
  rw [Lanius.Semantics.evalExpr]
  rw [fieldsResult]
  rfl

theorem extracted_successfulDigitsBody_executes
    (state : State) (wellFormed : StateWellFormed state) (offset : Nat) :
    Executes verifiedFrontendDigitsCore
      (singleArgumentCalleeState state (.signed .i32 offset))
      extractedSuccessfulDigitsBody
      (.returned (some (digitScanValue (.success offset))))
      (singleArgumentCalleeState state (.signed .i32 offset)) := by
  have normalized : Executes verifiedFrontendDigitsCore
      (singleArgumentCalleeState state (.signed .i32 offset))
      (removeTrailingSkips extractedSuccessfulDigitsBody)
      (.returned (some (digitScanValue (.success offset))))
      (singleArgumentCalleeState state (.signed .i32 offset)) := by
    rw [extracted_successfulDigitsBody_normalizes]
    exact ⟨7, successfulDigitsBody_executes_in_program
      verifiedFrontendDigitsCore state wellFormed offset⟩
  exact removeTrailingSkips_executes_complete
    extracted_successfulDigitsBody_supported normalized

theorem extracted_failedDigitsBody_executes
    (state : State) (wellFormed : StateWellFormed state) (offset : Nat) :
    Executes verifiedFrontendDigitsCore
      (singleArgumentCalleeState state (.signed .i32 offset))
      extractedFailedDigitsBody
      (.returned (some (digitScanValue (.failure offset))))
      (singleArgumentCalleeState state (.signed .i32 offset)) := by
  have normalized : Executes verifiedFrontendDigitsCore
      (singleArgumentCalleeState state (.signed .i32 offset))
      (removeTrailingSkips extractedFailedDigitsBody)
      (.returned (some (digitScanValue (.failure offset))))
      (singleArgumentCalleeState state (.signed .i32 offset)) := by
    rw [extracted_failedDigitsBody_normalizes]
    exact ⟨7, failedDigitsBody_executes_in_program
      verifiedFrontendDigitsCore state wellFormed offset⟩
  exact removeTrailingSkips_executes_complete
    extracted_failedDigitsBody_supported normalized

theorem verifiedFrontendDigitsCore_finds_successfulDigits :
    verifiedFrontendDigitsCore.function? extractedSuccessfulDigitsFunction.id =
      some extractedSuccessfulDigitsFunction := by
  unfold verifiedFrontendDigitsCore verifiedFrontendDigitsArtifact
    extractedSuccessfulDigitsFunction extractedSuccessfulDigitsWire
  rfl

theorem verifiedFrontendDigitsCore_finds_failedDigits :
    verifiedFrontendDigitsCore.function? extractedFailedDigitsFunction.id =
      some extractedFailedDigitsFunction := by
  unfold verifiedFrontendDigitsCore verifiedFrontendDigitsArtifact
    extractedFailedDigitsFunction extractedFailedDigitsWire
  rfl

/-- The checked source-derived constructor is callable in the actual decoded
    `digits.lani` program; this theorem covers the call protocol, not merely
    isolated execution of its body. -/
theorem extracted_successfulDigitsCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (offset : Nat)
    (argumentResult : Evaluates verifiedFrontendDigitsCore state argument
      (.signed .i32 offset) state) :
    Evaluates verifiedFrontendDigitsCore state
      (.call extractedSuccessfulDigitsFunction.id [argument])
      (digitScanValue (.success offset))
      (singleArgumentCallState state (.signed .i32 offset)) := by
  have arguments := Lanius.CallContracts.ArgumentsEvaluateTo.singleton
    argumentResult
  have parametersBound :
      bindParameters extractedSuccessfulDigitsFunction.parameters
          [.signed .i32 offset] =
        some [(0, .signed .i32 offset)] := by
    unfold extractedSuccessfulDigitsFunction extractedSuccessfulDigitsWire
    rfl
  have bodyResult : Executes verifiedFrontendDigitsCore
      (enterCall state [(0, .signed .i32 offset)])
      extractedSuccessfulDigitsBody
      (.returned (some (digitScanValue (.success offset))))
      (singleArgumentCalleeState state (.signed .i32 offset)) := by
    simpa [enterCall, singleArgumentCalleeState, clearLocals,
      State.bindLocals] using
      extracted_successfulDigitsBody_executes state wellFormed offset
  simpa [singleArgumentCallState] using
    Lanius.CallContracts.evaluatesCallReturned arguments
      verifiedFrontendDigitsCore_finds_successfulDigits parametersBound
      extracted_successfulDigitsFunction_has_body bodyResult

theorem extracted_failedDigitsCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (offset : Nat)
    (argumentResult : Evaluates verifiedFrontendDigitsCore state argument
      (.signed .i32 offset) state) :
    Evaluates verifiedFrontendDigitsCore state
      (.call extractedFailedDigitsFunction.id [argument])
      (digitScanValue (.failure offset))
      (singleArgumentCallState state (.signed .i32 offset)) := by
  have arguments := Lanius.CallContracts.ArgumentsEvaluateTo.singleton
    argumentResult
  have parametersBound :
      bindParameters extractedFailedDigitsFunction.parameters
          [.signed .i32 offset] =
        some [(0, .signed .i32 offset)] := by
    unfold extractedFailedDigitsFunction extractedFailedDigitsWire
    rfl
  have bodyResult : Executes verifiedFrontendDigitsCore
      (enterCall state [(0, .signed .i32 offset)])
      extractedFailedDigitsBody
      (.returned (some (digitScanValue (.failure offset))))
      (singleArgumentCalleeState state (.signed .i32 offset)) := by
    simpa [enterCall, singleArgumentCalleeState, clearLocals,
      State.bindLocals] using
      extracted_failedDigitsBody_executes state wellFormed offset
  simpa [singleArgumentCallState] using
    Lanius.CallContracts.evaluatesCallReturned arguments
      verifiedFrontendDigitsCore_finds_failedDigits parametersBound
      extracted_failedDigitsFunction_has_body bodyResult

def returnedBool? : Outcome Completion → Option Bool
  | .done (.returned (some (.boolean value))) _ => some value
  | _ => none

private def extractedDecimalDigitValue : Expr :=
  .binary .less
    (.binary .subtract (.local 0) (i32Literal 48))
    (.local 1)

private def extractedIsDigitForBaseNormalizedBody : Stmt :=
  .sequence
    (.ifThenElse (digitByteInRange 48 57)
      (.returnValue (some extractedDecimalDigitValue)) .skip)
    (.sequence
      (.ifThenElse (digitByteInRange 97 102)
        (.returnValue (some (digitValueLessBase 97 10))) .skip)
      (.sequence
        (.ifThenElse (digitByteInRange 65 70)
          (.returnValue (some (digitValueLessBase 65 10))) .skip)
        (.returnValue (some (.value (.boolean false))))))

theorem extracted_isDigitForBaseBody_normalizes :
    removeTrailingSkips extractedIsDigitForBaseBody =
      extractedIsDigitForBaseNormalizedBody := by
  unfold extractedIsDigitForBaseBody extractedIsDigitForBaseFunction
    extractedIsDigitForBaseWire extractedIsDigitForBaseNormalizedBody
    extractedDecimalDigitValue
  rfl

private theorem decideAnd_eq_false_of_not'
    {left right : Prop} [Decidable left] [Decidable right]
    (notBoth : ¬ (left ∧ right)) :
    (decide left && decide right) = false := by
  apply Bool.eq_false_iff.mpr
  intro bothTrue
  have decided := Bool.and_eq_true_iff.mp bothTrue
  exact notBoth ⟨of_decide_eq_true decided.1, of_decide_eq_true decided.2⟩

namespace DigitBaseProof

open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly

private abbrev T := Term signature 2
private abbrev B := Block signature 2
private def slot (index : Fin 2) : T := reference index
private def i32 (value : Int) : T := literal (.signed .i32 value)
private def binary (operation : BinaryOp) (left right : T)
    (result : Ty) : T :=
  apply (.binary operation i32Type i32Type result) [left, right]
private def conjunction (left right : T) : T :=
  Lanius.FunctionalView.Core.logicalAnd left right

private def inRange (lower upper : Int) : T :=
  conjunction
    (binary .greaterEqual (slot 0) (i32 lower) (.scalar .bool))
    (binary .lessEqual (slot 0) (i32 upper) (.scalar .bool))

private def decimalValue : T :=
  binary .less (binary .subtract (slot 0) (i32 48) i32Type) (slot 1)
    (.scalar .bool)

private def adjustedValue (lower adjustment : Int) : T :=
  binary .less
    (binary .add (binary .subtract (slot 0) (i32 lower) i32Type)
      (i32 adjustment) i32Type)
    (slot 1) (.scalar .bool)

def body : B :=
  .sequence
    (.ifThenElse (inRange 48 57) (.returnValue (some decimalValue)) .skip)
    (.sequence
      (.ifThenElse (inRange 97 102)
        (.returnValue (some (adjustedValue 97 10))) .skip)
      (.sequence
        (.ifThenElse (inRange 65 70)
          (.returnValue (some (adjustedValue 65 10))) .skip)
        (.returnValue (some (literal (.boolean false))))))

def world : World := { i32Slice? := fun _ => none }

def environment (byte base : Nat) : Env 2
  | ⟨0, _⟩ => .signed .i32 (Int.ofNat byte)
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat base)

theorem body_toCore_exactly :
    toCoreStmt (identityLayout (arity := 2)) 2 body =
      extractedIsDigitForBaseNormalizedBody := by
  rfl

private theorem inRange_evaluates (byte lower upper base : Nat) :
    Term.evaluate (machine verifiedFrontendDigitsCore) world
        (environment byte base) (inRange lower upper) =
      .ok (.boolean
        (decide (lower ≤ byte) && decide (byte ≤ upper)), world) := by
  simpa [Int.ofNat_le] using (show
    Term.evaluate (machine verifiedFrontendDigitsCore) world
        (environment byte base) (inRange lower upper) =
      .ok (.boolean
        (decide ((Int.ofNat lower) ≤ Int.ofNat byte) &&
          decide (Int.ofNat byte ≤ Int.ofNat upper)), world) by
    simp only [inRange, conjunction, binary, slot, i32,
      Lanius.FunctionalView.Core.apply, Lanius.FunctionalView.Core.reference,
      Lanius.FunctionalView.Core.literal]
    functional_eval)

private theorem decimalValue_evaluates (byte base : Nat)
    (lower : 48 ≤ byte) (bounded : byte - 48 ≤ 2147483647) :
    Term.evaluate (machine verifiedFrontendDigitsCore) world
        (environment byte base) decimalValue =
      .ok (.boolean (decide (byte - 48 < base)), world) := by
  simp only [decimalValue, binary, slot, i32,
    Lanius.FunctionalView.Core.apply, Lanius.FunctionalView.Core.reference,
    Lanius.FunctionalView.Core.literal]
  functional_eval

private theorem adjustedValue_evaluates (byte base lower adjustment : Nat)
    (lowerBound : lower ≤ byte)
    (bounded : byte - lower + adjustment ≤ 2147483647) :
    Term.evaluate (machine verifiedFrontendDigitsCore) world
        (environment byte base) (adjustedValue lower adjustment) =
      .ok (.boolean (decide (byte - lower + adjustment < base)), world) := by
  simp only [adjustedValue, binary, slot, i32,
    Lanius.FunctionalView.Core.apply, Lanius.FunctionalView.Core.reference,
    Lanius.FunctionalView.Core.literal]
  functional_eval

theorem body_evaluates (byte : Byte) (base : Nat) :
    Block.evaluate (machine verifiedFrontendDigitsCore) world
        (environment byte.val base) body =
      .done (.returned (some (.boolean (isDigitForBase byte base)))) world := by
  have decimalCondition := inRange_evaluates byte.val 48 57 base
  by_cases decimal : 48 ≤ byte.val ∧ byte.val ≤ 57
  · have condition : Term.evaluate (machine verifiedFrontendDigitsCore) world
        (environment byte.val base) (inRange 48 57) =
        .ok (.boolean true, world) := by
      simpa [decimal.1, decimal.2] using decimalCondition
    have value := decimalValue_evaluates byte.val base decimal.1 (by omega)
    simp [isDigitForBase, decimal.1, decimal.2]
    rw [body]
    apply Block.evaluate_sequence_returned
    apply Block.evaluate_if_true condition
    exact Block.evaluate_returnValue value
  · have decimalFalse :
        (decide (48 ≤ byte.val) && decide (byte.val ≤ 57)) = false :=
      decideAnd_eq_false_of_not' decimal
    have condition : Term.evaluate (machine verifiedFrontendDigitsCore) world
        (environment byte.val base) (inRange 48 57) =
        .ok (.boolean false, world) := by
      simpa [decimalFalse] using decimalCondition
    have lowercaseCondition := inRange_evaluates byte.val 97 102 base
    by_cases lowercase : 97 ≤ byte.val ∧ byte.val ≤ 102
    · have lowerTrue : Term.evaluate (machine verifiedFrontendDigitsCore) world
          (environment byte.val base) (inRange 97 102) =
          .ok (.boolean true, world) := by
        simpa [lowercase.1, lowercase.2] using lowercaseCondition
      have value := adjustedValue_evaluates byte.val base 97 10 lowercase.1
        (by omega)
      simp [isDigitForBase, decimal, lowercase.1, lowercase.2]
      rw [body]
      apply Block.evaluate_sequence_next
      · exact Block.evaluate_if_false condition (Block.evaluate_skip _ _ _)
      apply Block.evaluate_sequence_returned
      apply Block.evaluate_if_true lowerTrue
      exact Block.evaluate_returnValue value
    · have lowercaseFalse :
          (decide (97 ≤ byte.val) && decide (byte.val ≤ 102)) = false :=
        decideAnd_eq_false_of_not' lowercase
      have lowerFalse : Term.evaluate (machine verifiedFrontendDigitsCore) world
          (environment byte.val base) (inRange 97 102) =
          .ok (.boolean false, world) := by
        simpa [lowercaseFalse] using lowercaseCondition
      have uppercaseCondition := inRange_evaluates byte.val 65 70 base
      by_cases uppercase : 65 ≤ byte.val ∧ byte.val ≤ 70
      · have upperTrue : Term.evaluate (machine verifiedFrontendDigitsCore)
            world (environment byte.val base) (inRange 65 70) =
            .ok (.boolean true, world) := by
          simpa [uppercase.1, uppercase.2] using uppercaseCondition
        have value := adjustedValue_evaluates byte.val base 65 10 uppercase.1
          (by omega)
        simp [isDigitForBase, decimal, lowercase, uppercase.1, uppercase.2]
        rw [body]
        apply Block.evaluate_sequence_next
        · exact Block.evaluate_if_false condition (Block.evaluate_skip _ _ _)
        apply Block.evaluate_sequence_next
        · exact Block.evaluate_if_false lowerFalse (Block.evaluate_skip _ _ _)
        apply Block.evaluate_sequence_returned
        apply Block.evaluate_if_true upperTrue
        exact Block.evaluate_returnValue value
      · have uppercaseFalse :
            (decide (65 ≤ byte.val) && decide (byte.val ≤ 70)) = false :=
          decideAnd_eq_false_of_not' uppercase
        have upperFalse : Term.evaluate (machine verifiedFrontendDigitsCore)
            world (environment byte.val base) (inRange 65 70) =
            .ok (.boolean false, world) := by
          simpa [uppercaseFalse] using uppercaseCondition
        simp [isDigitForBase, decimal, lowercase, uppercase]
        rw [body]
        apply Block.evaluate_sequence_next
        · exact Block.evaluate_if_false condition (Block.evaluate_skip _ _ _)
        apply Block.evaluate_sequence_next
        · exact Block.evaluate_if_false lowerFalse (Block.evaluate_skip _ _ _)
        apply Block.evaluate_sequence_next
        · exact Block.evaluate_if_false upperFalse (Block.evaluate_skip _ _ _)
        rfl

end DigitBaseProof

private theorem extracted_isDigitForBaseNormalizedBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (byte : Byte) (base : Nat) :
    Executes verifiedFrontendDigitsCore
      (twoI32CalleeState state byte.val base)
      extractedIsDigitForBaseNormalizedBody
      (.returned (some (.boolean (isDigitForBase byte base))))
      (twoI32CalleeState state byte.val base) := by
  let callee := twoI32CalleeState state byte.val base
  have environmentMatches : Lanius.FunctionalView.Core.EnvironmentMatches
      (Lanius.FunctionalView.Core.identityLayout (arity := 2))
      (DigitBaseProof.environment byte.val base) callee := by
    intro index
    refine Fin.cases ?_
      (fun second => Fin.cases ?_ (fun impossible => Fin.elim0 impossible)
        second) index
    · simpa [callee, DigitBaseProof.environment,
        Lanius.FunctionalView.Core.identityLayout] using
        twoI32CalleeState_left state wellFormed byte.val base
    · simpa [callee, DigitBaseProof.environment,
        Lanius.FunctionalView.Core.identityLayout] using
        twoI32CalleeState_right state wellFormed byte.val base
  have represented :
      Lanius.FunctionalView.Core.ReadOnly.World.Represents DigitBaseProof.world
        callee := by
    intro _ _ found
    simp [DigitBaseProof.world] at found
  have sound := Lanius.FunctionalView.Core.block_executes_without_locals
    (nextLocal := 2)
    (Lanius.FunctionalView.Core.ReadOnly.bridge verifiedFrontendDigitsCore)
    represented environmentMatches (by rfl)
    (DigitBaseProof.body_evaluates byte base)
  rw [DigitBaseProof.body_toCore_exactly] at sound
  simpa [callee, Lanius.FunctionalView.Core.toCoreCompletion] using sound.1
/-- The raw source-derived predicate body executes in an arbitrary
    well-formed caller store. This is the framed form needed by callers inside
    `scan_digit_run`, unlike the finite empty-state validation below. -/
theorem extracted_isDigitForBaseBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (byte : Byte) (base : Nat) :
    Executes verifiedFrontendDigitsCore
      (twoI32CalleeState state byte.val base) extractedIsDigitForBaseBody
      (.returned (some (.boolean (isDigitForBase byte base))))
      (twoI32CalleeState state byte.val base) := by
  have normalized := extracted_isDigitForBaseNormalizedBody_executes
    state wellFormed byte base
  rw [← extracted_isDigitForBaseBody_normalizes] at normalized
  exact removeTrailingSkips_executes_complete
    extracted_isDigitForBaseBody_normalization_supported normalized

theorem verifiedFrontendDigitsCore_finds_isDigitForBase :
    verifiedFrontendDigitsCore.function? extractedIsDigitForBaseFunction.id =
      some extractedIsDigitForBaseFunction := by
  unfold verifiedFrontendDigitsCore verifiedFrontendDigitsArtifact
    extractedIsDigitForBaseFunction extractedIsDigitForBaseWire
  rfl

/-- Full source-derived call contract for `is_digit_for_base`, valid in an
    arbitrary well-formed caller store. -/
theorem extracted_isDigitForBaseCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (byteExpr baseExpr : Expr) (byte : Byte) (base : Nat)
    (byteResult : Evaluates verifiedFrontendDigitsCore state byteExpr
      (.signed .i32 byte.val) state)
    (baseResult : Evaluates verifiedFrontendDigitsCore state baseExpr
      (.signed .i32 base) state) :
    Evaluates verifiedFrontendDigitsCore state
      (.call extractedIsDigitForBaseFunction.id [byteExpr, baseExpr])
      (.boolean (isDigitForBase byte base))
      (twoI32CallState state byte.val base) := by
  have arguments := Lanius.CallContracts.ArgumentsEvaluateTo.cons byteResult
    (Lanius.CallContracts.ArgumentsEvaluateTo.singleton baseResult)
  have parametersBound :
      bindParameters extractedIsDigitForBaseFunction.parameters
          [.signed .i32 byte.val, .signed .i32 base] =
        some [(0, .signed .i32 byte.val), (1, .signed .i32 base)] := by
    unfold extractedIsDigitForBaseFunction extractedIsDigitForBaseWire
    rfl
  have bodyResult : Executes verifiedFrontendDigitsCore
      (enterCall state
        [(0, .signed .i32 byte.val), (1, .signed .i32 base)])
      extractedIsDigitForBaseBody
      (.returned (some (.boolean (isDigitForBase byte base))))
      (twoI32CalleeState state byte.val base) := by
    simpa [enterCall, twoI32CalleeState, clearLocals] using
      extracted_isDigitForBaseBody_executes state wellFormed byte base
  simpa [twoI32CallState] using
    Lanius.CallContracts.evaluatesCallReturned arguments
      verifiedFrontendDigitsCore_finds_isDigitForBase parametersBound
      extracted_isDigitForBaseFunction_has_body bodyResult

/-- The source-extracted helper implementations provide exactly the call
    semantics required by the reusable numeric-run proof. The proof below is
    the only adapter: the loop proof itself is independent of whether its
    callees came from the handwritten seed or the checked source artifact. -/
instance verifiedFrontendDigitsCoreDigitRunCallSemantics :
    DigitRunCallSemantics verifiedFrontendDigitsCore where
  target := by native_decide
  isDigitForBaseCall_executes := by
    intro state wellFormed byteExpr baseExpr byte base byteResult baseResult
    have execution := extracted_isDigitForBaseCall_executes state wellFormed
      byteExpr baseExpr byte base byteResult baseResult
    have functionId : extractedIsDigitForBaseFunction.id =
        isDigitForBaseFunction.id := by native_decide
    rw [functionId] at execution
    simpa [callIsDigitForBase] using execution
  successfulDigitsCall_executes := by
    intro state wellFormed argument offset argumentResult
    have execution := extracted_successfulDigitsCall_executes state wellFormed
      argument offset argumentResult
    have functionId : extractedSuccessfulDigitsFunction.id =
        successfulDigitsFunction.id := by native_decide
    rw [functionId] at execution
    simpa [callSuccessfulDigits] using execution
  failedDigitsCall_executes := by
    intro state wellFormed argument offset argumentResult
    have execution := extracted_failedDigitsCall_executes state wellFormed
      argument offset argumentResult
    have functionId : extractedFailedDigitsFunction.id =
        failedDigitsFunction.id := by native_decide
    rw [functionId] at execution
    simpa [callFailedDigits] using execution

/-- Direct finite-domain validation of the raw source-derived predicate body.
    The byte domain is exactly 0–255 and these are precisely the bases admitted
    by Lanius numeric literal syntax. Unlike the older proof AST, this executes
    the source's sequential early-return control flow and its literal `byte -
    48` decimal expression. -/
theorem extracted_isDigitForBaseBody_correct
    (base : Nat) (supported : SupportedDigitBase base) :
    ∀ byte : Byte,
      returnedBool? (execStmt 32 verifiedFrontendDigitsCore
        (twoI32CalleeState {} byte.val base) extractedIsDigitForBaseBody) =
        some (isDigitForBase byte base) := by
  rcases supported with rfl | rfl | rfl | rfl <;> native_decide

/-- The body extracted from the checked `digits.lani` source executes the
    abstract digit-run algorithm. This closes the semantic gap introduced by
    source statement-list terminators: correctness is now transferred through
    the proved normalization rather than assumed from syntax. -/
theorem extracted_scanDigitRunBody_executes
    (source : List Byte) (start base : Nat)
    (sourceBound : source.length ≤ 2147483647) :
    ∃ finalState,
      Executes verifiedFrontendDigitsCore
        (digitParameterState source start base)
        extractedScanDigitRunBody
        (.returned (some (digitScanValue (scanDigitRun source start base))))
        finalState := by
  obtain ⟨finalState, normalizedExecution⟩ :=
    scanDigitRunBody_executes (program := verifiedFrontendDigitsCore)
      source start base sourceBound
  rw [← extracted_scanDigitRunBody_normalizes] at normalizedExecution
  exact ⟨finalState, removeTrailingSkips_executes_complete
    extracted_scanDigitRunBody_normalization_supported normalizedExecution⟩

def extractedScanDigitRunCall
    (source : List Byte) (start base : Nat) : Expr :=
  .call extractedScanDigitRunFunction.id
    [sourceSlice source, i32Literal source.length, i32Literal start,
      i32Literal base]

theorem verifiedFrontendDigitsCore_finds_scanDigitRun :
    verifiedFrontendDigitsCore.function? extractedScanDigitRunFunction.id =
      some extractedScanDigitRunFunction := by
  unfold verifiedFrontendDigitsCore verifiedFrontendDigitsArtifact
    extractedScanDigitRunFunction extractedScanDigitRunWire
  rfl

/-- End-to-end execution of the actual source-extracted `scan_digit_run`
    function call, including argument evaluation, ABI binding, the complete
    loop body, and restoration of the caller's lexical frame. -/
theorem extracted_scanDigitRunCall_executes
    (source : List Byte) (start base : Nat)
    (sourceBound : source.length ≤ 2147483647) :
    ∃ finalState,
      Evaluates verifiedFrontendDigitsCore (sourceState source)
        (extractedScanDigitRunCall source start base)
        (digitScanValue (scanDigitRun source start base)) finalState := by
  obtain ⟨bodyFinal, bodyResult⟩ :=
    extracted_scanDigitRunBody_executes source start base sourceBound
  have arguments : Lanius.CallContracts.ArgumentsEvaluateTo
      verifiedFrontendDigitsCore (sourceState source)
      [sourceSlice source, i32Literal source.length, i32Literal start,
        i32Literal base]
      [.slice i32Type 0 [] 0 source.length,
        .signed .i32 source.length, .signed .i32 start,
        .signed .i32 base]
      (sourceState source) := by
    exact ⟨5, rfl⟩
  have parametersBound :
      bindParameters extractedScanDigitRunFunction.parameters
          [.slice i32Type 0 [] 0 source.length,
            .signed .i32 source.length, .signed .i32 start,
            .signed .i32 base] =
        some
          [(0, .slice i32Type 0 [] 0 source.length),
            (1, .signed .i32 source.length), (2, .signed .i32 start),
            (3, .signed .i32 base)] := by
    unfold extractedScanDigitRunFunction extractedScanDigitRunWire
    rfl
  have bodyAtCallState : Executes verifiedFrontendDigitsCore
      (enterCall (sourceState source)
        [(0, .slice i32Type 0 [] 0 source.length),
          (1, .signed .i32 source.length), (2, .signed .i32 start),
          (3, .signed .i32 base)])
      extractedScanDigitRunBody
      (.returned (some (digitScanValue (scanDigitRun source start base))))
      bodyFinal := by
    simpa [enterCall, digitParameterState, sourceState] using bodyResult
  have execution := Lanius.CallContracts.evaluatesCallReturned arguments
    verifiedFrontendDigitsCore_finds_scanDigitRun parametersBound
    extracted_scanDigitRunFunction_has_body bodyAtCallState
  exact ⟨restoreLocals (sourceState source) bodyFinal,
    by simpa [extractedScanDigitRunCall] using execution⟩

/-- Whole-function statement of the extracted implementation theorem. It
    records the source-derived ABI alongside execution of the source-derived
    body, so this theorem does not silently prove a different function with a
    convenient body. -/
theorem extracted_scanDigitRunFunction_executes
    (source : List Byte) (start base : Nat)
    (sourceBound : source.length ≤ 2147483647) :
    extractedScanDigitRunFunction.id = 30 ∧
      extractedScanDigitRunFunction.parameters = digitRunParameters ∧
      extractedScanDigitRunFunction.returnType =
        .structure digitScanDeclaration.id ∧
      extractedScanDigitRunFunction.external = none ∧
      ∃ finalState,
        Evaluates verifiedFrontendDigitsCore (sourceState source)
          (extractedScanDigitRunCall source start base)
          (digitScanValue (scanDigitRun source start base)) finalState := by
  have metadata :
      extractedScanDigitRunFunction.id = 30 ∧
        extractedScanDigitRunFunction.parameters = digitRunParameters ∧
        extractedScanDigitRunFunction.returnType =
          .structure digitScanDeclaration.id ∧
        extractedScanDigitRunFunction.external = none := by
    unfold extractedScanDigitRunFunction extractedScanDigitRunWire
    decide
  exact ⟨metadata.1, metadata.2.1, metadata.2.2.1, metadata.2.2.2,
    extracted_scanDigitRunCall_executes source start base sourceBound⟩

theorem extracted_scanDigitRunFunction_executes_spec
    (source : List Byte) (start base : Nat) (result : DigitScanResult)
    (sourceBound : source.length ≤ 2147483647)
    (scan : DigitRunScan source start base result) :
    ∃ finalState,
      Evaluates verifiedFrontendDigitsCore (sourceState source)
        (extractedScanDigitRunCall source start base)
        (digitScanValue result) finalState := by
  obtain ⟨finalState, execution⟩ :=
    extracted_scanDigitRunCall_executes source start base sourceBound
  rw [scan.executes] at execution
  exact ⟨finalState, execution⟩

end Lanius.Extraction
