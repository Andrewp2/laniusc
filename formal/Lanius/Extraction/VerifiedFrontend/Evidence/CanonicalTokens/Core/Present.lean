import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_evidence_core_present_kernel :
    verifiedFrontendCanonicalTokensArtifact.core_program.isSome = true := by
  with_unfolding_all rfl

end Lanius.Extraction
