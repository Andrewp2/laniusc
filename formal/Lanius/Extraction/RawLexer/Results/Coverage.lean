import Lanius.Extraction.RawLexer.Results.Semantics
import Lanius.Extraction.ArtifactContextChecker

namespace Lanius.Extraction.RawLexer.Results.Coverage

open Lanius.Core
open Lanius.FunctionalView.Core
open Lanius.Extraction.RawLexer.Results

/-! # Enforceable result-function slice of `raw_lexer.lani`

The source inventory is reconstructed from the checked Surface artifact.  The
coverage witness names all six result/accessor functions and deliberately
leaves `scan_one` and `lex_into` visible as the only two remaining functions
for the enclosing raw-lexer gate.
-/

def rawLexerFunctionNames : Option (List String) :=
  (decodeReconstructedSurface verifiedFrontendRawLexerArtifact).map fun surface =>
    (ArtifactContextChecker.collectFunctions surface.items).map (·.name)

theorem raw_lexer_source_function_names :
    rawLexerFunctionNames = some [
      "lex_status", "lex_token_count", "lex_error_offset", "completed",
      "lexical_failure", "output_full", "scan_one", "lex_into"] := by
  native_decide

structure TheoremReference {proposition : Prop} (proof : proposition) where
  checked : proposition

private theorem reference {proposition : Prop} (proof : proposition) :
    TheoremReference proof := ⟨proof⟩

structure ExactCoverage where
  sourceFunctionNames : TheoremReference raw_lexer_source_function_names
  lexStatus :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.lexStatusView.block = Functions.lexStatusBody
  lexTokenCount :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.lexTokenCountView.block = Functions.lexTokenCountBody
  lexErrorOffset :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.lexErrorOffsetView.block = Functions.lexErrorOffsetBody
  completed :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.completedView.block = Functions.completedBody
  lexicalFailure :
    toCoreStmt (identityLayout (arity := 2)) 2
        Functions.lexicalFailureView.block = Functions.lexicalFailureBody
  outputFull :
    toCoreStmt (identityLayout (arity := 2)) 2
        Functions.outputFullView.block = Functions.outputFullBody

theorem exact : Nonempty ExactCoverage := by
  exact ⟨{
    sourceFunctionNames := reference raw_lexer_source_function_names
    lexStatus := Functions.lexStatus_toCore_exactly
    lexTokenCount := Functions.lexTokenCount_toCore_exactly
    lexErrorOffset := Functions.lexErrorOffset_toCore_exactly
    completed := Functions.completed_toCore_exactly
    lexicalFailure := Functions.lexicalFailure_toCore_exactly
    outputFull := Functions.outputFull_toCore_exactly
  }⟩

structure SemanticCoverage where
  exact : ExactCoverage
  lexStatus : TheoremReference Semantics.lexStatusCall_soundness
  lexTokenCount : TheoremReference Semantics.lexTokenCountCall_soundness
  lexErrorOffset : TheoremReference Semantics.lexErrorOffsetCall_soundness
  completed : TheoremReference Semantics.completedCall_soundness
  lexicalFailure : TheoremReference Semantics.lexicalFailureCall_soundness
  outputFull : TheoremReference Semantics.outputFullCall_soundness

theorem complete : Nonempty SemanticCoverage := by
  obtain ⟨exactCoverage⟩ := exact
  exact ⟨{
    exact := exactCoverage
    lexStatus := reference Semantics.lexStatusCall_soundness
    lexTokenCount := reference Semantics.lexTokenCountCall_soundness
    lexErrorOffset := reference Semantics.lexErrorOffsetCall_soundness
    completed := reference Semantics.completedCall_soundness
    lexicalFailure := reference Semantics.lexicalFailureCall_soundness
    outputFull := reference Semantics.outputFullCall_soundness
  }⟩

end Lanius.Extraction.RawLexer.Results.Coverage
