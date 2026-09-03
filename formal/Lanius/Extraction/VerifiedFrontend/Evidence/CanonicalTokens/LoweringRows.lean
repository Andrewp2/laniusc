import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_evidence_lowering_rows_checked_kernel :
    loweringRowsInSurface
      verifiedFrontendCanonicalTokensSurfaceKernel.claims.nodes.length
      verifiedFrontendCanonicalTokensArtifact.lowering = true := by
  with_unfolding_all rfl

end Lanius.Extraction
