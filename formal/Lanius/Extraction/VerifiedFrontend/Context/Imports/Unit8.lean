import Lanius.Extraction.VerifiedFrontend.Context.Base
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_context_imports_kernel :
    ArtifactPackContextChecker.collectUnitImports verifiedFrontendPackDecodedUnitsKernel
      verifiedFrontendRawLexerProgramUnitKernel verifiedFrontendRawLexerProgramUnitKernel.surface.items =
        some [⟨8, 0⟩, ⟨8, 6⟩, ⟨8, 7⟩, ⟨8, 3⟩, ⟨8, 1⟩] := by
  with_unfolding_all rfl
end Lanius.Extraction
