import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Data.TypeTree
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Artifact

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_evidence_type_tree_represents_kernel :
    verifiedFrontendCanonicalTokensEvidenceTypeTree.Represents
      verifiedFrontendCanonicalTokensArtifact.types := by
  with_unfolding_all rfl

end Lanius.Extraction
