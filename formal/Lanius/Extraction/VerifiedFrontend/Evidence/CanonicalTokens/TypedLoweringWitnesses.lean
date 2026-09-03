import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.View

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_typed_lowering_witnesses_checked_kernel :
    checkTypedLoweringWitnesses
      verifiedFrontendCanonicalTokensEvidenceTypeTree
      verifiedFrontendCanonicalTokensArtifact.lowering
      verifiedFrontendCanonicalTokensLoweringTypeRefs = true := by
  with_unfolding_all rfl

end Lanius.Extraction
