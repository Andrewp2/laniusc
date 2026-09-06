import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.Digits.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Digits.Claims

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendDigits_origins_checked_kernel :
    verifiedFrontendDigitsOrigins.valid verifiedFrontendDigitsArtifact
      verifiedFrontendDigitsView = true := by
  kernel_rfl

end Lanius.Extraction
