import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Surface.Token.Reconstruction
import Lanius.Extraction.VerifiedFrontend.Artifact.Token.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Token.View.Artifact
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def verifiedFrontendTokenClaimsKernel : SurfaceClaims := (verifiedFrontendTokenOrigins).claims
theorem verifiedFrontendToken_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendTokenArtifact verifiedFrontendTokenReconstructedKernel =
      some verifiedFrontendTokenClaimsKernel := by
  kernel_rfl
end Lanius.Extraction

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendToken_claims_equal_kernel :
    (verifiedFrontendTokenOrigins).claims = verifiedFrontendTokenClaimsKernel := by
  rfl
end Lanius.Extraction

