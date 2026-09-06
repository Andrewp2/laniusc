import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.Number.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Number.Claims

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendNumber_origins_checked_kernel :
    verifiedFrontendNumberOrigins.valid verifiedFrontendNumberArtifact
      verifiedFrontendNumberView = true := by
  kernel_rfl

end Lanius.Extraction
