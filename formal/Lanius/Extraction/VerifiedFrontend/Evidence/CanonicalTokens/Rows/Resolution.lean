import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_evidence_resolution_checked_kernel :
    resolutionRowsInUnits 4 verifiedFrontendPackSurfaceNodeCountsKernel
      verifiedFrontendCanonicalTokensArtifact.resolutions = true := by
  with_unfolding_all rfl

end Lanius.Extraction
