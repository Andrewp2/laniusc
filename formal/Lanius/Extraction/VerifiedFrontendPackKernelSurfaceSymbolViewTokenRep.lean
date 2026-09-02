import Lanius.Extraction.VerifiedFrontendUnitSymbolCache
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_token_tree_represents_kernel :
    verifiedFrontendSymbolTokenTree.Represents verifiedFrontendSymbolArtifact.tokens := by
  with_unfolding_all rfl
end Lanius.Extraction
