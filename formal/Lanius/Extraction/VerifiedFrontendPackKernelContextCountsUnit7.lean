import Lanius.Extraction.VerifiedFrontendPackKernelDecodedUnit7
namespace Lanius.Extraction
set_option maxRecDepth 100000
open ArtifactContextChecker
theorem verifiedFrontendSymbol_context_counts_kernel :
    ((collectStructures verifiedFrontendSymbolProgramUnitKernel.surface.items).length,
      (collectTypeAliases verifiedFrontendSymbolProgramUnitKernel.surface.items).length,
      (collectConstants verifiedFrontendSymbolProgramUnitKernel.surface.items).length,
      (collectFunctions verifiedFrontendSymbolProgramUnitKernel.surface.items).length) =
      (1, 0, 0, 4) := by
  with_unfolding_all rfl
end Lanius.Extraction
