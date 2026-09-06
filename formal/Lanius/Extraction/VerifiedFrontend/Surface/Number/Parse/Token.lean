import Lanius.Extraction.VerifiedFrontend.Artifact.Number.Artifact
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0

-- One reduction boundary shares decoded input across raw and canonical checks.
theorem verifiedFrontendNumber_token_trace_checked_kernel :
    checkTokenArtifact verifiedFrontendNumberArtifact = true := by
  kernel_rfl

end Lanius.Extraction
