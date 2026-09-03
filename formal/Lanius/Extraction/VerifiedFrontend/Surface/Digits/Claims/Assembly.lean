import Lanius.Extraction.VerifiedFrontend.Surface.Digits.Reconstruction.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.Digits.Origins
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def verifiedFrontendDigitsClaimsKernel : SurfaceClaims := (verifiedFrontendDigitsOrigins).claims
theorem verifiedFrontendDigits_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendDigitsArtifact verifiedFrontendDigitsReconstructedKernel =
      some verifiedFrontendDigitsClaimsKernel := by
  with_unfolding_all rfl
end Lanius.Extraction
