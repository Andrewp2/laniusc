import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumberReconstruction
import Lanius.Extraction.VerifiedFrontendUnitNumberOrigins
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def verifiedFrontendNumberClaimsKernel : SurfaceClaims :=
  (verifiedFrontendNumberOrigins).claims
theorem verifiedFrontendNumber_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendNumberArtifact
      verifiedFrontendNumberReconstructedKernel =
      some verifiedFrontendNumberClaimsKernel := by
  with_unfolding_all rfl
end Lanius.Extraction
