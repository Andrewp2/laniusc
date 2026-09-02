import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceTokenReconstruction
import Lanius.Extraction.VerifiedFrontendUnitTokenOrigins
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def verifiedFrontendTokenClaimsKernel : SurfaceClaims := (verifiedFrontendTokenOrigins).claims
theorem verifiedFrontendToken_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendTokenArtifact verifiedFrontendTokenReconstructedKernel =
      some verifiedFrontendTokenClaimsKernel := by
  with_unfolding_all rfl
end Lanius.Extraction
