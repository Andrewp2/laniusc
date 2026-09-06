import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Claims
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_origins_checked_kernel :
    verifiedFrontendTokenScanOrigins.valid verifiedFrontendTokenScanArtifact
      verifiedFrontendTokenScanView = true := by
  decide +kernel
end Lanius.Extraction
