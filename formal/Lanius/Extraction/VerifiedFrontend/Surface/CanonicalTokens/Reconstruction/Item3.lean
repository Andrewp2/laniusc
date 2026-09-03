import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendCanonicalTokensAccessItem3 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendCanonicalTokensView
theorem verifiedFrontendCanonicalTokens_reconstruct_item3_kernel :
    (reconstructItem 10308 verifiedFrontendCanonicalTokensArtifact 8260).run 46 =
      some (verifiedFrontendCanonicalTokensProposedItemKernel 3, 1290) := by
  with_unfolding_all rfl
end Lanius.Extraction
