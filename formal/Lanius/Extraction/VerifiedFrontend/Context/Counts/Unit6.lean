import Lanius.Extraction.VerifiedFrontend.Decoded.Unit6
namespace Lanius.Extraction
set_option maxRecDepth 100000
open ArtifactContextChecker
theorem verifiedFrontendNumber_context_counts_kernel :
    ((collectStructures verifiedFrontendNumberProgramUnitKernel.surface.items).length,
      (collectTypeAliases verifiedFrontendNumberProgramUnitKernel.surface.items).length,
      (collectConstants verifiedFrontendNumberProgramUnitKernel.surface.items).length,
      (collectFunctions verifiedFrontendNumberProgramUnitKernel.surface.items).length) =
      (0, 0, 0, 2) := by
  with_unfolding_all rfl
end Lanius.Extraction
