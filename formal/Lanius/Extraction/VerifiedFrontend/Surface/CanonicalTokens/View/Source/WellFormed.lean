import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_source_tree_well_formed_kernel :
    verifiedFrontendCanonicalTokensSourceByteTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl
end Lanius.Extraction
