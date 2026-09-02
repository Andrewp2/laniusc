import Lanius.Extraction.VerifiedFrontendPackKernelContextBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_context_imports_kernel :
    ArtifactPackContextChecker.collectUnitImports verifiedFrontendPackDecodedUnitsKernel
      verifiedFrontendTokenScanProgramUnitKernel verifiedFrontendTokenScanProgramUnitKernel.surface.items = some [] := by
  with_unfolding_all rfl
end Lanius.Extraction
