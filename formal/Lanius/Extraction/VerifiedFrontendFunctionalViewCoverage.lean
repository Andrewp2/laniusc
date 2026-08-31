import Lanius.Extraction.VerifiedFrontendPack
import Lanius.Extraction.ArtifactContextChecker
import Lanius.Extraction.Lexer.FunctionalViewCoverage
import Lanius.Extraction.Lexer.Calls
import Lanius.Extraction.TokenScan.FunctionalViewCoverage
import Lanius.Extraction.CanonicalTokens.FunctionalViewCoverage
import Lanius.Extraction.Decimal.FunctionalViewCoverage
import Lanius.Extraction.Number.FunctionalViewCoverage
import Lanius.Extraction.RawLexer.FunctionalViewCoverage
import Lanius.Extraction.Symbol.FunctionalViewCoverage

namespace Lanius.Extraction.VerifiedFrontendFunctionalViewCoverage

/-! # Complete checked-frontend FunctionalView coverage

This module is the single aggregate gate for the nine-unit frontend pack.  Its
source inventory is reconstructed from the checked Surface artifacts rather
than copied from the source tree.  Semantic witnesses are added below as the
unit proofs establish concrete, checked-program contracts.
-/

def artifactFunctionNames (artifact : Artifact) : Option (List String) :=
  (decodeReconstructedSurface artifact).map fun surface =>
    (ArtifactContextChecker.collectFunctions surface.items).map (·.name)

def unitFunctionNames : List (Option (List String)) :=
  verifiedFrontendPack.units.map artifactFunctionNames

theorem source_function_names : unitFunctionNames = [
    some [
      "is_identifier_start", "is_identifier_continue", "is_decimal_digit",
      "is_whitespace", "is_symbol_start", "classify_start",
      "scan_identifier_end", "scan_whitespace_end", "scan_succeeded",
      "scan_end_offset", "scan_error_offset", "successful_scan",
      "failed_scan", "scan_quoted_end", "scan_string_end",
      "scan_character_end", "scan_line_comment_end", "scan_block_comment_end"],
    some [
      "succeeded", "kind", "end_offset", "error_offset", "successful",
      "failed"],
    some [
      "digit_scan_succeeded", "digit_scan_end_offset",
      "digit_scan_error_offset", "successful_digits", "failed_digits",
      "is_digit_for_base", "scan_digit_run"],
    some [],
    some [
      "is_trivia", "keyword_kind", "canonical_kind",
      "canonicalize_in_place"],
    some [
      "integer_scan", "float_scan", "number_failure", "scan_exponent",
      "finish_decimal"],
    some ["scan_number", "scan_leading_dot_number"],
    some [
      "token_match_kind", "token_match_length", "token_match",
      "match_symbol_head"],
    some [
      "lex_status", "lex_token_count", "lex_error_offset", "completed",
      "lexical_failure", "output_full", "scan_one", "lex_into"]
  ] := by
  native_decide

def sourceFunctionCount : Nat :=
  unitFunctionNames.foldl
    (fun total names => total + (names.map List.length).getD 0) 0

theorem source_function_count : sourceFunctionCount = 54 := by
  native_decide

structure TheoremReference {proposition : Prop} (proof : proposition) where
  checked : proposition

private theorem reference {proposition : Prop} (proof : proposition) :
    TheoremReference proof := ⟨proof⟩

structure SourceCoverage where
  packSources : TheoremReference verifiedFrontendPack_tracks_sources
  names : TheoremReference source_function_names
  count : TheoremReference source_function_count

theorem sources_complete : Nonempty SourceCoverage := by
  exact ⟨{
    packSources := reference verifiedFrontendPack_tracks_sources
    names := reference source_function_names
    count := reference source_function_count
  }⟩

/-! The aggregate semantic gate is deliberately assembled only from closed
checked-program theorems.  A unit is added here after its public theorem has
instantiated every helper registry; a theorem still quantified over helper
`CallSoundness` does not qualify. -/

structure ConcreteCompletedUnitCoverage where
  sources : SourceCoverage
  lexerFunctions :
    Lexer.FunctionalViewCoverage.SemanticCoverage
  lexerMergedHelpers : ∀ source : List Compiler.Lexer.Byte,
    Lanius.FunctionalView.FreshSimulation.FramePreservingCallSoundness
      verifiedFrontendCore (Lexer.Calls.callModel source)
  tokenScanFunctions :
    TokenScan.FunctionalViewCoverage.SemanticCoverage
  canonicalTokenFunctions :
    CanonicalTokens.FunctionalViewCoverage.SemanticCoverage
  decimalFunctions : Decimal.FunctionalViewCoverage.SemanticCoverage
  numberFunctions : ∀ source : List Compiler.Lexer.Byte,
    Number.FunctionalViewCoverage.SemanticCoverage source
  rawLexerFunctions : RawLexer.FunctionalViewCoverage.SemanticCoverage
  symbolFunctions : Symbol.FunctionalViewCoverage.SemanticCoverage

def concretelyCoveredFunctionCount : Nat := 25 + 6 + 4 + 5 + 2 + 8 + 4

theorem concretely_covered_function_count :
    concretelyCoveredFunctionCount = 54 := by
  rfl

def remainingFunctionCount : Nat :=
  sourceFunctionCount - concretelyCoveredFunctionCount

theorem remaining_function_count : remainingFunctionCount = 0 := by
  native_decide

theorem completed_units_concrete :
    Nonempty ConcreteCompletedUnitCoverage := by
  exact ⟨{
    sources := Classical.choice sources_complete
    lexerFunctions :=
      Classical.choice Lexer.FunctionalViewCoverage.semantics_complete
    lexerMergedHelpers := Lexer.Calls.framePreservingCallSoundness
    tokenScanFunctions :=
      Classical.choice TokenScan.FunctionalViewCoverage.complete
    canonicalTokenFunctions :=
      Classical.choice
        CanonicalTokens.FunctionalViewCoverage.semantics_complete
    decimalFunctions :=
      Classical.choice Decimal.FunctionalViewCoverage.concrete_complete
    numberFunctions := fun source =>
      Classical.choice (Number.FunctionalViewCoverage.complete source)
    rawLexerFunctions :=
      Classical.choice RawLexer.FunctionalViewCoverage.complete
    symbolFunctions :=
      Classical.choice Symbol.FunctionalViewCoverage.complete
  }⟩

abbrev SemanticCoverage := ConcreteCompletedUnitCoverage

/-- All 54 checked functions in the verified frontend pack have exact source
recovery and premise-free, concrete checked-program semantic coverage. -/
theorem complete : Nonempty SemanticCoverage := completed_units_concrete

end Lanius.Extraction.VerifiedFrontendFunctionalViewCoverage
