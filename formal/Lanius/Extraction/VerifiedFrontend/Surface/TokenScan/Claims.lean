import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Reconstruction
import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.View
import Lanius.Extraction.KernelSurfacePhases

/-! Collected surface claims and their identity certificate. -/

/-! Claim collection. -/
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def verifiedFrontendTokenScanClaimsKernel : SurfaceClaims := (verifiedFrontendTokenScanOrigins).claims
theorem verifiedFrontendTokenScan_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanReconstructedKernel =
      some verifiedFrontendTokenScanClaimsKernel := by
  with_unfolding_all rfl
end Lanius.Extraction

/-! Claim identity. -/
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_claims_equal_kernel :
    (verifiedFrontendTokenScanOrigins).claims = verifiedFrontendTokenScanClaimsKernel := by
  rfl
end Lanius.Extraction
