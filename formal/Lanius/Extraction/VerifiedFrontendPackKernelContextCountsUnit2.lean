import Lanius.Extraction.VerifiedFrontendPackKernelDecodedUnit2
namespace Lanius.Extraction
set_option maxRecDepth 100000
open ArtifactContextChecker
theorem verifiedFrontendDigits_context_counts_kernel :
    ((collectStructures verifiedFrontendDigitsProgramUnitKernel.surface.items).length,
      (collectTypeAliases verifiedFrontendDigitsProgramUnitKernel.surface.items).length,
      (collectConstants verifiedFrontendDigitsProgramUnitKernel.surface.items).length,
      (collectFunctions verifiedFrontendDigitsProgramUnitKernel.surface.items).length) =
      (1, 0, 0, 7) := by
  with_unfolding_all rfl
end Lanius.Extraction
