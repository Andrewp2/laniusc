import Lanius.Extraction.VerifiedFrontend.Decoded.Unit4
namespace Lanius.Extraction
set_option maxRecDepth 100000
open ArtifactContextChecker
theorem verifiedFrontendCanonicalTokens_context_counts_kernel :
    ((collectStructures verifiedFrontendCanonicalTokensProgramUnitKernel.surface.items).length,
      (collectTypeAliases verifiedFrontendCanonicalTokensProgramUnitKernel.surface.items).length,
      (collectConstants verifiedFrontendCanonicalTokensProgramUnitKernel.surface.items).length,
      (collectFunctions verifiedFrontendCanonicalTokensProgramUnitKernel.surface.items).length) =
      (0, 0, 0, 4) := by
  with_unfolding_all rfl
end Lanius.Extraction
