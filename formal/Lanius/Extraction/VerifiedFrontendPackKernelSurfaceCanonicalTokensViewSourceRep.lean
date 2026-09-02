import Lanius.Extraction.VerifiedFrontendUnitCanonicalTokensCache
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_source_tree_represents_kernel :
    ∀ source, verifiedFrontendCanonicalTokensArtifact.sources[0]? = some source →
      decodeBytes source.bytes = some verifiedFrontendCanonicalTokensSourceByteTree.flatten := by
  intro source found
  with_unfolding_all
    injection found with sourceEq
    subst source
    rfl
end Lanius.Extraction
