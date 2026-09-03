import Lanius.Extraction.VerifiedFrontend.Artifact.Digits.Cache.Semantic
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_semantic_tree_represents_kernel :
    verifiedFrontendDigitsSemanticKindTree.Represents verifiedFrontendDigitsArtifact.semantic_token_kinds := by
  with_unfolding_all rfl
end Lanius.Extraction
