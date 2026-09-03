import Lanius.Extraction.VerifiedFrontend.Decoded.Unit5
namespace Lanius.Extraction
set_option maxRecDepth 100000
open ArtifactContextChecker
theorem verifiedFrontendDecimal_context_counts_kernel :
    ((collectStructures verifiedFrontendDecimalProgramUnitKernel.surface.items).length,
      (collectTypeAliases verifiedFrontendDecimalProgramUnitKernel.surface.items).length,
      (collectConstants verifiedFrontendDecimalProgramUnitKernel.surface.items).length,
      (collectFunctions verifiedFrontendDecimalProgramUnitKernel.surface.items).length) =
      (0, 1, 0, 5) := by
  with_unfolding_all rfl
end Lanius.Extraction
