import Lanius.Extraction.VerifiedFrontendPackKernelDecodedUnit3
namespace Lanius.Extraction
set_option maxRecDepth 100000
open ArtifactContextChecker
theorem verifiedFrontendToken_context_counts_kernel :
    ((collectStructures verifiedFrontendTokenProgramUnitKernel.surface.items).length,
      (collectTypeAliases verifiedFrontendTokenProgramUnitKernel.surface.items).length,
      (collectConstants verifiedFrontendTokenProgramUnitKernel.surface.items).length,
      (collectFunctions verifiedFrontendTokenProgramUnitKernel.surface.items).length) =
      (0, 1, 82, 0) := by
  with_unfolding_all rfl
end Lanius.Extraction
