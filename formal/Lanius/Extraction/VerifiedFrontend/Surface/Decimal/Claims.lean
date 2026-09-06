import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Reconstruction
import Lanius.Extraction.VerifiedFrontend.Artifact.Decimal.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.View.Artifact
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def verifiedFrontendDecimalClaimsKernel : SurfaceClaims := (verifiedFrontendDecimalOrigins).claims
theorem verifiedFrontendDecimal_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendDecimalArtifact verifiedFrontendDecimalReconstructedKernel =
      some verifiedFrontendDecimalClaimsKernel := by
  kernel_rfl
end Lanius.Extraction

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_claims_equal_kernel :
    (verifiedFrontendDecimalOrigins).claims = verifiedFrontendDecimalClaimsKernel := by
  rfl
end Lanius.Extraction

