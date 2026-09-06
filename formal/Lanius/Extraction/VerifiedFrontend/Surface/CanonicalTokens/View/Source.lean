import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Assembly

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_source_tree_well_formed_kernel :
    verifiedFrontendCanonicalTokensSourceByteTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  kernel_rfl
end Lanius.Extraction

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

