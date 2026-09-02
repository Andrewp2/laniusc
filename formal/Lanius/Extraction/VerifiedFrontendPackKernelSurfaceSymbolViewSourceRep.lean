import Lanius.Extraction.VerifiedFrontendUnitSymbolCache
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_source_tree_represents_kernel :
    ∀ source, verifiedFrontendSymbolArtifact.sources[0]? = some source →
      decodeBytes source.bytes = some verifiedFrontendSymbolSourceByteTree.flatten := by
  intro source found
  with_unfolding_all
    injection found with sourceEq
    subst source
    rfl
end Lanius.Extraction
