import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.Token.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Token.Claims

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendToken_origins_checked_kernel :
    verifiedFrontendTokenOrigins.valid verifiedFrontendTokenArtifact
      verifiedFrontendTokenView = true := by
  kernel_rfl

end Lanius.Extraction
