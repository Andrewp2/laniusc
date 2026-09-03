import Lanius.Extraction.VerifiedFrontend.Artifact.Number.Cache.Semantic
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_semantic_tree_represents_kernel :
    verifiedFrontendNumberSemanticKindTree.Represents verifiedFrontendNumberArtifact.semantic_token_kinds := by
  with_unfolding_all rfl
end Lanius.Extraction
