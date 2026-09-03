import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendCanonicalTokensAccessItem4 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendCanonicalTokensView
theorem verifiedFrontendCanonicalTokens_reconstruct_item4_kernel :
    (reconstructItem 10307 verifiedFrontendCanonicalTokensArtifact 8533).run 1290 =
      some (verifiedFrontendCanonicalTokensProposedItemKernel 4, 1339) := by
  with_unfolding_all rfl
end Lanius.Extraction
