import Lanius.Extraction.VerifiedFrontend.Context.Base
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_context_imports_kernel :
    ArtifactPackContextChecker.collectUnitImports verifiedFrontendPackDecodedUnitsKernel
      verifiedFrontendCanonicalTokensProgramUnitKernel
      verifiedFrontendCanonicalTokensProgramUnitKernel.surface.items = some [⟨4, 3⟩] := by
  with_unfolding_all rfl
end Lanius.Extraction
