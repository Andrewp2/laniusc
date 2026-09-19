import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Artifact
import Lanius.Extraction.ParseChunks

/-! Complete token validation at one kernel-reduction boundary. -/

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendTokenScan_token_trace_checked_kernel :
    checkTokenArtifact verifiedFrontendTokenScanArtifact = true := by
  kernel_rfl

end Lanius.Extraction
