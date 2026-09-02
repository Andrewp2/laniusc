import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensView
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendCanonicalTokensAccessItem0 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendCanonicalTokensView
theorem verifiedFrontendCanonicalTokens_reconstruct_item0_kernel :
    (reconstructItem 10311 verifiedFrontendCanonicalTokensArtifact 6).run 0 =
      some (verifiedFrontendCanonicalTokensProposedItemKernel 0, 4) := by
  with_unfolding_all rfl
end Lanius.Extraction
