import Lanius.Extraction.Lexer.Functions
import Lanius.Extraction.Lexer.Scanners
import Lanius.Extraction.Lexer.Digits
import Lanius.Extraction.Lexer.DigitAccessorContracts
import Lanius.Extraction.Lexer.Predicates
import Lanius.Extraction.Lexer.ScanEnd
import Lanius.Extraction.Lexer.BasicScanners
import Lanius.Extraction.Lexer.Quoted
import Lanius.Extraction.Lexer.QuotedWrappers
import Lanius.Extraction.Lexer.LineComment
import Lanius.Extraction.Lexer.BlockComment

namespace Lanius.Extraction.Lexer.FunctionalViewCoverage

open Lanius.Core
open Lanius.FunctionalView.Core

/-! # Enforceable lexer FunctionalView coverage

Each field is the exact FunctionalView-to-Core equality for one source
function in `lexer.lani` or `digits.lani`.  Consequently, this module stops
building when any source function loses its mechanically checked round trip.
-/

/-- Ordered source-function names reconstructed from the checked `lexer.lani`
    Surface artifact. -/
def lexerFunctionNames : Option (List String) :=
  (decodeReconstructedSurface verifiedFrontendLexerArtifact).map fun surface =>
    (ArtifactContextChecker.collectFunctions surface.items).map (·.name)

/-- Ordered source-function names reconstructed from the checked `digits.lani`
    Surface artifact. -/
def digitsFunctionNames : Option (List String) :=
  (decodeReconstructedSurface verifiedFrontendDigitsArtifact).map fun surface =>
    (ArtifactContextChecker.collectFunctions surface.items).map (·.name)

/-- The complete declaration inventory of the checked `lexer.lani` unit. -/
theorem lexer_source_function_names :
    lexerFunctionNames = some [
      "is_identifier_start", "is_identifier_continue", "is_decimal_digit",
      "is_whitespace", "is_symbol_start", "classify_start",
      "scan_identifier_end", "scan_whitespace_end", "scan_succeeded",
      "scan_end_offset", "scan_error_offset", "successful_scan",
      "failed_scan", "scan_quoted_end", "scan_string_end",
      "scan_character_end", "scan_line_comment_end",
      "scan_block_comment_end"] := by
  native_decide

/-- The complete declaration inventory of the checked `digits.lani` unit. -/
theorem digits_source_function_names :
    digitsFunctionNames = some [
      "digit_scan_succeeded", "digit_scan_end_offset",
      "digit_scan_error_offset", "successful_digits", "failed_digits",
      "is_digit_for_base", "scan_digit_run"] := by
  native_decide

/-- A proof term used as a type index, preventing the coverage witness from
    substituting an unrelated proof with the same result type. -/
structure TheoremReference {proposition : Prop} (proof : proposition) where
  checked : proposition

private theorem reference {proposition : Prop} (proof : proposition) :
    TheoremReference proof :=
  ⟨proof⟩

structure ExactCoverage where
  lexerSourceFunctionNames : TheoremReference lexer_source_function_names
  digitsSourceFunctionNames : TheoremReference digits_source_function_names
  isIdentifierStart :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.isIdentifierStartView.block =
      Functions.functionBody Functions.isIdentifierStartFunction
  isIdentifierContinue :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.isIdentifierContinueView.block =
      Functions.functionBody Functions.isIdentifierContinueFunction
  isDecimalDigit :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.isDecimalDigitView.block =
      Functions.functionBody Functions.isDecimalDigitFunction
  isWhitespace :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.isWhitespaceView.block =
      Functions.functionBody Functions.isWhitespaceFunction
  isSymbolStart :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.isSymbolStartView.block =
      Functions.functionBody Functions.isSymbolStartFunction
  classifyStart :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.classifyStartView.block =
      Functions.functionBody Functions.classifyStartFunction
  scanIdentifierEnd :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        Scanners.scanIdentifierEndView.command =
      Scanners.scanIdentifierEndBody
  scanWhitespaceEnd :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        Scanners.scanWhitespaceEndView.command =
      Scanners.scanWhitespaceEndBody
  scanSucceeded :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.scanSucceededView.block =
      Functions.functionBody Functions.scanSucceededFunction
  scanEndOffset :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.scanEndOffsetView.block =
      Functions.functionBody Functions.scanEndOffsetFunction
  scanErrorOffset :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.scanErrorOffsetView.block =
      Functions.functionBody Functions.scanErrorOffsetFunction
  successfulScan :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.successfulScanView.block =
      Functions.functionBody Functions.successfulScanFunction
  failedScan :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.failedScanView.block =
      Functions.functionBody Functions.failedScanFunction
  scanQuotedEnd :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 4
        Scanners.scanQuotedEndView.command =
      Scanners.scanQuotedEndBody
  scanStringEnd :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        Scanners.scanStringEndView.command =
      Scanners.scanStringEndBody
  scanCharacterEnd :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        Scanners.scanCharacterEndView.command =
      Scanners.scanCharacterEndBody
  scanLineCommentEnd :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        Scanners.scanLineCommentEndView.command =
      Scanners.scanLineCommentEndBody
  scanBlockCommentEnd :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        Scanners.scanBlockCommentEndView.command =
      Scanners.scanBlockCommentEndBody
  digitScanSucceeded :
    toCoreStmt (identityLayout (arity := 1)) 1
        Digits.digitScanSucceededView.block =
      Digits.digitScanSucceededBody
  digitScanEndOffset :
    toCoreStmt (identityLayout (arity := 1)) 1
        Digits.digitScanEndOffsetView.block =
      Digits.digitScanEndOffsetBody
  digitScanErrorOffset :
    toCoreStmt (identityLayout (arity := 1)) 1
        Digits.digitScanErrorOffsetView.block =
      Digits.digitScanErrorOffsetBody
  successfulDigits :
    toCoreStmt (identityLayout (arity := 1)) 1
        Digits.successfulDigitsView.block =
      Digits.successfulDigitsBody
  failedDigits :
    toCoreStmt (identityLayout (arity := 1)) 1
        Digits.failedDigitsView.block =
      Digits.failedDigitsBody
  isDigitForBase :
    toCoreStmt (identityLayout (arity := 2)) 2
        Digits.isDigitForBaseView.block =
      Digits.isDigitForBaseBody
  scanDigitRun :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter
        (identityLayout (arity := 4)) 4 Digits.scanDigitRunView.command =
      Digits.scanDigitRunBody

/-- The checked source artifacts currently provide exact FunctionalView
    coverage for all eighteen `lexer.lani` functions and all seven
    `digits.lani` functions. -/
theorem complete : Nonempty ExactCoverage := by
  exact ⟨{
    lexerSourceFunctionNames := reference lexer_source_function_names
    digitsSourceFunctionNames := reference digits_source_function_names
    isIdentifierStart := Functions.isIdentifierStartView_toCore_exactly
    isIdentifierContinue := Functions.isIdentifierContinueView_toCore_exactly
    isDecimalDigit := Functions.isDecimalDigitView_toCore_exactly
    isWhitespace := Functions.isWhitespaceView_toCore_exactly
    isSymbolStart := Functions.isSymbolStartView_toCore_exactly
    classifyStart := Functions.classifyStartView_toCore_exactly
    scanIdentifierEnd := Scanners.scanIdentifierEndView_toCore_exactly
    scanWhitespaceEnd := Scanners.scanWhitespaceEndView_toCore_exactly
    scanSucceeded := Functions.scanSucceededView_toCore_exactly
    scanEndOffset := Functions.scanEndOffsetView_toCore_exactly
    scanErrorOffset := Functions.scanErrorOffsetView_toCore_exactly
    successfulScan := Functions.successfulScanView_toCore_exactly
    failedScan := Functions.failedScanView_toCore_exactly
    scanQuotedEnd := Scanners.scanQuotedEndView_toCore_exactly
    scanStringEnd := Scanners.scanStringEndView_toCore_exactly
    scanCharacterEnd := Scanners.scanCharacterEndView_toCore_exactly
    scanLineCommentEnd := Scanners.scanLineCommentEndView_toCore_exactly
    scanBlockCommentEnd := Scanners.scanBlockCommentEndView_toCore_exactly
    digitScanSucceeded := Digits.digitScanSucceededView_toCore_exactly
    digitScanEndOffset := Digits.digitScanEndOffsetView_toCore_exactly
    digitScanErrorOffset := Digits.digitScanErrorOffsetView_toCore_exactly
    successfulDigits := Digits.successfulDigitsView_toCore_exactly
    failedDigits := Digits.failedDigitsView_toCore_exactly
    isDigitForBase := Digits.isDigitForBaseView_toCore_exactly
    scanDigitRun := Digits.scanDigitRunView_toCore_exactly
  }⟩

/-! `ExactCoverage` prevents the proof-facing syntax from drifting from the
checked sources.  `SemanticCoverage` additionally names the execution theorem
for every covered body or call.  Its theorem-indexed fields cannot be filled by
an unrelated proposition with a coincidentally compatible result type. -/

structure SemanticCoverage where
  exact : ExactCoverage
  isIdentifierStart :
    TheoremReference Lanius.Extraction.extracted_isIdentifierStartCall_after_argument
  isIdentifierContinue :
    TheoremReference Predicates.isIdentifierContinueCall_executes
  isDecimalDigit :
    TheoremReference Lanius.Extraction.extracted_isDecimalDigitCall_after_argument
  isWhitespace :
    TheoremReference Lanius.Extraction.extracted_isWhitespaceCall_after_argument
  isSymbolStart :
    TheoremReference Predicates.isSymbolStartCall_executes
  classifyStart :
    TheoremReference Predicates.classifyStartCall_executes
  scanIdentifierEnd :
    TheoremReference BasicScanners.scanIdentifierEndCall_executes
  scanWhitespaceEnd :
    TheoremReference BasicScanners.scanWhitespaceEndCall_executes
  scanSucceeded :
    TheoremReference ScanEnd.scanSucceededCall_executes
  scanEndOffset :
    TheoremReference ScanEnd.scanEndOffsetCall_executes
  scanErrorOffset :
    TheoremReference ScanEnd.scanErrorOffsetCall_executes
  successfulScan :
    TheoremReference Quoted.successfulScanCall_contract
  failedScan :
    TheoremReference Quoted.failedScanCall_contract
  scanQuotedEnd :
    TheoremReference Quoted.call_executes
  scanStringEnd :
    TheoremReference QuotedWrappers.stringCall_executes
  scanCharacterEnd :
    TheoremReference QuotedWrappers.characterCall_executes
  scanLineCommentEnd :
    TheoremReference LineComment.call_executes
  scanBlockCommentEnd :
    TheoremReference BlockComment.call_executes
  digitScanSucceeded :
    TheoremReference DigitAccessorContracts.digitScanSucceededCall_evaluates
  digitScanEndOffset :
    TheoremReference DigitAccessorContracts.digitScanEndOffsetCall_evaluates
  digitScanErrorOffset :
    TheoremReference DigitAccessorContracts.digitScanErrorOffsetCall_evaluates
  successfulDigits :
    TheoremReference Lanius.Extraction.extracted_successfulDigitsCall_executes
  failedDigits :
    TheoremReference Lanius.Extraction.extracted_failedDigitsCall_executes
  isDigitForBase :
    TheoremReference Lanius.Extraction.extracted_isDigitForBaseCall_executes
  scanDigitRun :
    TheoremReference Lanius.Extraction.extracted_scanDigitRunCall_executes

private theorem exactCoverage : ExactCoverage :=
  Classical.choice complete

theorem semantics_complete : Nonempty SemanticCoverage := by
  exact ⟨{
    exact := exactCoverage
    isIdentifierStart :=
      reference Lanius.Extraction.extracted_isIdentifierStartCall_after_argument
    isIdentifierContinue :=
      reference Predicates.isIdentifierContinueCall_executes
    isDecimalDigit :=
      reference Lanius.Extraction.extracted_isDecimalDigitCall_after_argument
    isWhitespace :=
      reference Lanius.Extraction.extracted_isWhitespaceCall_after_argument
    isSymbolStart := reference Predicates.isSymbolStartCall_executes
    classifyStart := reference Predicates.classifyStartCall_executes
    scanIdentifierEnd :=
      reference BasicScanners.scanIdentifierEndCall_executes
    scanWhitespaceEnd :=
      reference BasicScanners.scanWhitespaceEndCall_executes
    scanSucceeded := reference ScanEnd.scanSucceededCall_executes
    scanEndOffset := reference ScanEnd.scanEndOffsetCall_executes
    scanErrorOffset := reference ScanEnd.scanErrorOffsetCall_executes
    successfulScan := reference Quoted.successfulScanCall_contract
    failedScan := reference Quoted.failedScanCall_contract
    scanQuotedEnd := reference Quoted.call_executes
    scanStringEnd := reference QuotedWrappers.stringCall_executes
    scanCharacterEnd := reference QuotedWrappers.characterCall_executes
    scanLineCommentEnd := reference LineComment.call_executes
    scanBlockCommentEnd := reference BlockComment.call_executes
    digitScanSucceeded :=
      reference DigitAccessorContracts.digitScanSucceededCall_evaluates
    digitScanEndOffset :=
      reference DigitAccessorContracts.digitScanEndOffsetCall_evaluates
    digitScanErrorOffset :=
      reference DigitAccessorContracts.digitScanErrorOffsetCall_evaluates
    successfulDigits :=
      reference Lanius.Extraction.extracted_successfulDigitsCall_executes
    failedDigits :=
      reference Lanius.Extraction.extracted_failedDigitsCall_executes
    isDigitForBase :=
      reference Lanius.Extraction.extracted_isDigitForBaseCall_executes
    scanDigitRun :=
      reference Lanius.Extraction.extracted_scanDigitRunCall_executes
  }⟩

end Lanius.Extraction.Lexer.FunctionalViewCoverage
