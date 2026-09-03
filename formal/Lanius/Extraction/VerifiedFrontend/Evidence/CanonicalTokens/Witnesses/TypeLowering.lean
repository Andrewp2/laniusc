import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.View

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_type_lowering_witnesses_checked_kernel :
    checkTypeLoweringWitnesses
      verifiedFrontendCanonicalTokensEvidenceLoweringTree
      verifiedFrontendCanonicalTokensArtifact.types
      verifiedFrontendCanonicalTokensTypeLoweringRefs = true := by
  with_unfolding_all rfl

end Lanius.Extraction
