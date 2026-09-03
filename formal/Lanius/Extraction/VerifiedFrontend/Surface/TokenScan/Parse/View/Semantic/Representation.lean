import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Cache.Semantic
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_semantic_tree_represents_kernel :
    verifiedFrontendTokenScanSemanticKindTree.Represents verifiedFrontendTokenScanArtifact.semantic_token_kinds := by
  with_unfolding_all rfl
end Lanius.Extraction
