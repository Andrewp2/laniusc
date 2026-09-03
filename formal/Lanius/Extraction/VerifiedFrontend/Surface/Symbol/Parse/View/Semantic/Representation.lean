import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Cache.Semantic
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_semantic_tree_represents_kernel :
    verifiedFrontendSymbolSemanticKindTree.Represents
      verifiedFrontendSymbolArtifact.semantic_token_kinds := by
  with_unfolding_all rfl
end Lanius.Extraction
