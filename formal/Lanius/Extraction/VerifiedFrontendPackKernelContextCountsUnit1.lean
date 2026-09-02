import Lanius.Extraction.VerifiedFrontendPackKernelDecodedUnit1
namespace Lanius.Extraction
set_option maxRecDepth 100000
open ArtifactContextChecker
theorem verifiedFrontendTokenScan_context_counts_kernel :
    ((collectStructures verifiedFrontendTokenScanProgramUnitKernel.surface.items).length,
      (collectTypeAliases verifiedFrontendTokenScanProgramUnitKernel.surface.items).length,
      (collectConstants verifiedFrontendTokenScanProgramUnitKernel.surface.items).length,
      (collectFunctions verifiedFrontendTokenScanProgramUnitKernel.surface.items).length) =
      (1, 0, 0, 6) := by
  with_unfolding_all rfl
end Lanius.Extraction
