import Lanius.Extraction.VerifiedFrontendUnitSymbolCache
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_parse_tree_represents_kernel :
    verifiedFrontendSymbolParseNodeTree.Represents verifiedFrontendSymbolArtifact.parse_nodes := by
  with_unfolding_all rfl
end Lanius.Extraction
