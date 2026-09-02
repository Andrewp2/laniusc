import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceTokenScanReconstruction
import Lanius.Extraction.VerifiedFrontendUnitTokenScanOrigins
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def verifiedFrontendTokenScanClaimsKernel : SurfaceClaims := (verifiedFrontendTokenScanOrigins).claims
theorem verifiedFrontendTokenScan_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanReconstructedKernel =
      some verifiedFrontendTokenScanClaimsKernel := by
  with_unfolding_all rfl
end Lanius.Extraction
