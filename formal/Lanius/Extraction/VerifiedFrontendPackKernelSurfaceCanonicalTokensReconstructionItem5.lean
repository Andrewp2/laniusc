import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensView
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendCanonicalTokensAccessItem5 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendCanonicalTokensView
theorem verifiedFrontendCanonicalTokens_reconstruct_item5_kernel :
    (reconstructItem 10306 verifiedFrontendCanonicalTokensArtifact 10302).run 1339 =
      some (verifiedFrontendCanonicalTokensProposedItemKernel 5, 1609) := by
  with_unfolding_all rfl
end Lanius.Extraction
