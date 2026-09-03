import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_token_tree_represents_kernel :
    verifiedFrontendCanonicalTokensTokenTree.Represents verifiedFrontendCanonicalTokensArtifact.tokens := by
  with_unfolding_all rfl
end Lanius.Extraction
