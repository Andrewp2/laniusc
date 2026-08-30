import Lanius.Extraction.VerifiedLexerProgram
import Lanius.Extraction.ArtifactQuote
import Lanius.FunctionalViewCoreReification

namespace Lanius.Extraction.Lexer.Functions

open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Reification

private def isIdentifierStartWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "is_identifier_start"

private def isIdentifierContinueWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "is_identifier_continue"

private def isDecimalDigitWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "is_decimal_digit"

private def isWhitespaceWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "is_whitespace"

private def isSymbolStartWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "is_symbol_start"

private def classifyStartWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "classify_start"

private def scanSucceededWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "scan_succeeded"

private def scanEndOffsetWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "scan_end_offset"

private def scanErrorOffsetWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "scan_error_offset"

private def successfulScanWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "successful_scan"

private def failedScanWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani",
    "failed_scan"

def isIdentifierStartFunction : Function :=
  CoreDecode.function isIdentifierStartWire

def isIdentifierContinueFunction : Function :=
  CoreDecode.function isIdentifierContinueWire

def isDecimalDigitFunction : Function :=
  CoreDecode.function isDecimalDigitWire

def isWhitespaceFunction : Function :=
  CoreDecode.function isWhitespaceWire

def isSymbolStartFunction : Function :=
  CoreDecode.function isSymbolStartWire

def classifyStartFunction : Function :=
  CoreDecode.function classifyStartWire

def scanSucceededFunction : Function :=
  CoreDecode.function scanSucceededWire

def scanEndOffsetFunction : Function :=
  CoreDecode.function scanEndOffsetWire

def scanErrorOffsetFunction : Function :=
  CoreDecode.function scanErrorOffsetWire

def successfulScanFunction : Function :=
  CoreDecode.function successfulScanWire

def failedScanFunction : Function :=
  CoreDecode.function failedScanWire

def functionBody (function : Function) : Stmt :=
  function.body.getD .skip

def reification? (function : Function) :=
  reifyBlock? verifiedFrontendLexerCore function.returnType
    (Lanius.Typing.parameterContext function.parameters) false
    (identityLayout (arity := function.parameters.length))
    function.parameters.length (functionBody function)

theorem isIdentifierStartReification_exists :
    (reification? isIdentifierStartFunction).isSome := by native_decide

theorem isIdentifierContinueReification_exists :
    (reification? isIdentifierContinueFunction).isSome := by native_decide

theorem isDecimalDigitReification_exists :
    (reification? isDecimalDigitFunction).isSome := by native_decide

theorem isWhitespaceReification_exists :
    (reification? isWhitespaceFunction).isSome := by native_decide

theorem isSymbolStartReification_exists :
    (reification? isSymbolStartFunction).isSome := by native_decide

theorem classifyStartReification_exists :
    (reification? classifyStartFunction).isSome := by native_decide

theorem scanSucceededReification_exists :
    (reification? scanSucceededFunction).isSome := by native_decide

theorem scanEndOffsetReification_exists :
    (reification? scanEndOffsetFunction).isSome := by native_decide

theorem scanErrorOffsetReification_exists :
    (reification? scanErrorOffsetFunction).isSome := by native_decide

theorem successfulScanReification_exists :
    (reification? successfulScanFunction).isSome := by native_decide

theorem failedScanReification_exists :
    (reification? failedScanFunction).isSome := by native_decide

def isIdentifierStartView :=
  (reification? isIdentifierStartFunction).get
    isIdentifierStartReification_exists

def isIdentifierContinueView :=
  (reification? isIdentifierContinueFunction).get
    isIdentifierContinueReification_exists

def isDecimalDigitView :=
  (reification? isDecimalDigitFunction).get
    isDecimalDigitReification_exists

def isWhitespaceView :=
  (reification? isWhitespaceFunction).get isWhitespaceReification_exists

def isSymbolStartView :=
  (reification? isSymbolStartFunction).get isSymbolStartReification_exists

def classifyStartView :=
  (reification? classifyStartFunction).get classifyStartReification_exists

def scanSucceededView :=
  (reification? scanSucceededFunction).get scanSucceededReification_exists

def scanEndOffsetView :=
  (reification? scanEndOffsetFunction).get scanEndOffsetReification_exists

def scanErrorOffsetView :=
  (reification? scanErrorOffsetFunction).get scanErrorOffsetReification_exists

def successfulScanView :=
  (reification? successfulScanFunction).get successfulScanReification_exists

def failedScanView :=
  (reification? failedScanFunction).get failedScanReification_exists

private def local0 : Term signature 1 := reference ⟨0, by omega⟩

private def returned (term : Term signature 1) : Block signature 1 :=
  .sequence (.returnValue (some term)) .skip

def scanSucceededBlock : Block signature 1 :=
  returned (apply (.field (.structure 0) 0 (.scalar .bool)) [local0])

def scanEndOffsetBlock : Block signature 1 :=
  returned (apply
    (.field (.structure 0) 1 (.scalar (.signed .i32))) [local0])

def scanErrorOffsetBlock : Block signature 1 :=
  returned (apply
    (.field (.structure 0) 2 (.scalar (.signed .i32))) [local0])

def successfulScanBlock : Block signature 1 :=
  returned (apply
    (.structValue 0 [.scalar .bool, .scalar (.signed .i32),
      .scalar (.signed .i32)])
    [literal (.boolean true), local0, literal (.signed .i32 0)])

def failedScanBlock : Block signature 1 :=
  returned (apply
    (.structValue 0 [.scalar .bool, .scalar (.signed .i32),
      .scalar (.signed .i32)])
    [literal (.boolean false), literal (.signed .i32 0), local0])

theorem scanSucceededBlock_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 scanSucceededBlock =
      functionBody scanSucceededFunction := by
  change toCoreStmt (identityLayout (arity := 1)) 1 scanSucceededBlock =
    .sequence (.returnValue (some (.field (.local 0) 0))) .skip
  rfl

theorem scanEndOffsetBlock_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 scanEndOffsetBlock =
      functionBody scanEndOffsetFunction := by
  change toCoreStmt (identityLayout (arity := 1)) 1 scanEndOffsetBlock =
    .sequence (.returnValue (some (.field (.local 0) 1))) .skip
  rfl

theorem scanErrorOffsetBlock_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 scanErrorOffsetBlock =
      functionBody scanErrorOffsetFunction := by
  change toCoreStmt (identityLayout (arity := 1)) 1 scanErrorOffsetBlock =
    .sequence (.returnValue (some (.field (.local 0) 2))) .skip
  rfl

theorem successfulScanBlock_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 successfulScanBlock =
      functionBody successfulScanFunction := by
  change toCoreStmt (identityLayout (arity := 1)) 1 successfulScanBlock =
    .sequence (.returnValue (some (.structValue 0 [
      .value (.boolean true), .local 0, .value (.signed .i32 0)]))) .skip
  rfl

theorem failedScanBlock_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 failedScanBlock =
      functionBody failedScanFunction := by
  change toCoreStmt (identityLayout (arity := 1)) 1 failedScanBlock =
    .sequence (.returnValue (some (.structValue 0 [
      .value (.boolean false), .value (.signed .i32 0), .local 0]))) .skip
  rfl

theorem isIdentifierStartView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1
      isIdentifierStartView.block = functionBody isIdentifierStartFunction :=
  isIdentifierStartView.toCoreExactly

theorem isIdentifierContinueView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1
      isIdentifierContinueView.block = functionBody isIdentifierContinueFunction :=
  isIdentifierContinueView.toCoreExactly

theorem isDecimalDigitView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1
      isDecimalDigitView.block = functionBody isDecimalDigitFunction :=
  isDecimalDigitView.toCoreExactly

theorem isWhitespaceView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1
      isWhitespaceView.block = functionBody isWhitespaceFunction :=
  isWhitespaceView.toCoreExactly

theorem isSymbolStartView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1
      isSymbolStartView.block = functionBody isSymbolStartFunction :=
  isSymbolStartView.toCoreExactly

theorem classifyStartView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1
      classifyStartView.block = functionBody classifyStartFunction :=
  classifyStartView.toCoreExactly

theorem scanSucceededView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1
      scanSucceededView.block = functionBody scanSucceededFunction :=
  scanSucceededView.toCoreExactly

theorem scanEndOffsetView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1
      scanEndOffsetView.block = functionBody scanEndOffsetFunction :=
  scanEndOffsetView.toCoreExactly

theorem scanErrorOffsetView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1
      scanErrorOffsetView.block = functionBody scanErrorOffsetFunction :=
  scanErrorOffsetView.toCoreExactly

theorem successfulScanView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1
      successfulScanView.block = functionBody successfulScanFunction :=
  successfulScanView.toCoreExactly

theorem failedScanView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1
      failedScanView.block = functionBody failedScanFunction :=
  failedScanView.toCoreExactly

end Lanius.Extraction.Lexer.Functions
