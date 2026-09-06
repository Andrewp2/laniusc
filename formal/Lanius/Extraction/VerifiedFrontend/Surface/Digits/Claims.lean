import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Surface.Digits.Reconstruction
import Lanius.Extraction.VerifiedFrontend.Artifact.Digits.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Digits.View.Artifact
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def verifiedFrontendDigitsClaimsKernel : SurfaceClaims := (verifiedFrontendDigitsOrigins).claims
theorem verifiedFrontendDigits_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendDigitsArtifact verifiedFrontendDigitsReconstructedKernel =
      some verifiedFrontendDigitsClaimsKernel := by
  kernel_rfl
end Lanius.Extraction

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_claims_equal_kernel :
    (verifiedFrontendDigitsOrigins).claims = verifiedFrontendDigitsClaimsKernel := by
  rfl
end Lanius.Extraction

