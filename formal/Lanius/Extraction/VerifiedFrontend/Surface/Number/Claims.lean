import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Surface.Number.Reconstruction
import Lanius.Extraction.VerifiedFrontend.Artifact.Number.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Number.View.Artifact
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def verifiedFrontendNumberClaimsKernel : SurfaceClaims :=
  (verifiedFrontendNumberOrigins).claims
theorem verifiedFrontendNumber_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendNumberArtifact
      verifiedFrontendNumberReconstructedKernel =
      some verifiedFrontendNumberClaimsKernel := by
  kernel_rfl
end Lanius.Extraction

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_claims_equal_kernel :
    (verifiedFrontendNumberOrigins).claims = verifiedFrontendNumberClaimsKernel := by
  rfl
end Lanius.Extraction

