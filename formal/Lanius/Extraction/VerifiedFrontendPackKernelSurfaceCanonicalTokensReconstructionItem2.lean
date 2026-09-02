import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensView
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendCanonicalTokensAccessItem2 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendCanonicalTokensView
theorem verifiedFrontendCanonicalTokens_reconstruct_item2_kernel :
    (reconstructItem 10309 verifiedFrontendCanonicalTokensArtifact 186).run 8 =
      some (verifiedFrontendCanonicalTokensProposedItemKernel 2, 46) := by
  with_unfolding_all rfl
end Lanius.Extraction
