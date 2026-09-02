import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigitsReconstruction
import Lanius.Extraction.VerifiedFrontendUnitDigitsOrigins
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def verifiedFrontendDigitsClaimsKernel : SurfaceClaims := (verifiedFrontendDigitsOrigins).claims
theorem verifiedFrontendDigits_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendDigitsArtifact verifiedFrontendDigitsReconstructedKernel =
      some verifiedFrontendDigitsClaimsKernel := by
  with_unfolding_all rfl
end Lanius.Extraction
