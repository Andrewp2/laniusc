import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Data.LoweringTree
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Artifact

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_evidence_lowering_tree_represents_kernel :
    verifiedFrontendCanonicalTokensEvidenceLoweringTree.Represents
      verifiedFrontendCanonicalTokensArtifact.lowering := by
  with_unfolding_all rfl

end Lanius.Extraction
