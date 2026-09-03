import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_evidence_node_count_checked_kernel :
    (verifiedFrontendPackSurfaceNodeCountsKernel[4]? ==
      some verifiedFrontendCanonicalTokensSurfaceKernel.claims.nodes.length) = true := by
  with_unfolding_all rfl

end Lanius.Extraction
