import Lanius.Extraction.VerifiedFrontend.Artifact.Decimal.Cache.Semantic
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_semantic_tree_represents_kernel :
    verifiedFrontendDecimalSemanticKindTree.Represents verifiedFrontendDecimalArtifact.semantic_token_kinds := by
  with_unfolding_all rfl
end Lanius.Extraction
