import Lanius.Extraction.VerifiedFrontend.Context.Base
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_context_imports_kernel :
    ArtifactPackContextChecker.collectUnitImports verifiedFrontendPackDecodedUnitsKernel
      verifiedFrontendDigitsProgramUnitKernel verifiedFrontendDigitsProgramUnitKernel.surface.items = some [] := by
  with_unfolding_all rfl
end Lanius.Extraction
