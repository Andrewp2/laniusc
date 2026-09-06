import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Assembly

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_token_tree_well_formed_kernel :
    verifiedFrontendCanonicalTokensTokenTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  kernel_rfl
end Lanius.Extraction

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_token_tree_represents_kernel :
    verifiedFrontendCanonicalTokensTokenTree.Represents verifiedFrontendCanonicalTokensArtifact.tokens := by
  kernel_rfl
end Lanius.Extraction

