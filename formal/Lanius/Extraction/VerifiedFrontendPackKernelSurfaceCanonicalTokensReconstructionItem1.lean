import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensView
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendCanonicalTokensAccessItem1 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendCanonicalTokensView
theorem verifiedFrontendCanonicalTokens_reconstruct_item1_kernel :
    (reconstructItem 10310 verifiedFrontendCanonicalTokensArtifact 14).run 4 =
      some (verifiedFrontendCanonicalTokensProposedItemKernel 1, 8) := by
  with_unfolding_all rfl
end Lanius.Extraction
