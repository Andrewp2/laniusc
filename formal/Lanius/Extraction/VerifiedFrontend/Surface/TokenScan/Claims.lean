import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Reconstruction
import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Origins
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def verifiedFrontendTokenScanClaimsKernel : SurfaceClaims :=
  verifiedFrontendTokenScanOrigins.claims
theorem verifiedFrontendTokenScan_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendTokenScanArtifact
      verifiedFrontendTokenScanReconstructedKernel =
        some verifiedFrontendTokenScanClaimsKernel := by
  decide +kernel
theorem verifiedFrontendTokenScan_claims_equal_kernel :
    verifiedFrontendTokenScanOrigins.claims =
      verifiedFrontendTokenScanClaimsKernel := by
  rfl
end Lanius.Extraction
