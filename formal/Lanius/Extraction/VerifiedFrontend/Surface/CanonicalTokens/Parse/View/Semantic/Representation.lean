import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Semantic
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_semantic_tree_represents_kernel :
    verifiedFrontendCanonicalTokensSemanticKindTree.Represents
      verifiedFrontendCanonicalTokensArtifact.semantic_token_kinds := by
  with_unfolding_all rfl
end Lanius.Extraction
