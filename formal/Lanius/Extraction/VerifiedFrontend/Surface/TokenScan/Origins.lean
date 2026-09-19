import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Claims
import Lanius.Extraction.KernelReduction
import Lanius.Extraction.Surface.Views

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_origins_checked_kernel :
    verifiedFrontendTokenScanOrigins.valid verifiedFrontendTokenScanArtifact
      verifiedFrontendTokenScanView = true := by
  apply SurfaceOrigins.valid_of_components <;> try kernel_rfl
  apply spellingCoverageValid_of_multiset
  kernel_rfl
end Lanius.Extraction
