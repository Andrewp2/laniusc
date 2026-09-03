import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Reconstruction.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Origins
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def verifiedFrontendTokenScanClaimsKernel : SurfaceClaims := (verifiedFrontendTokenScanOrigins).claims
theorem verifiedFrontendTokenScan_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanReconstructedKernel =
      some verifiedFrontendTokenScanClaimsKernel := by
  with_unfolding_all rfl
end Lanius.Extraction
