import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Reconstruction.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.Decimal.Origins
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def verifiedFrontendDecimalClaimsKernel : SurfaceClaims := (verifiedFrontendDecimalOrigins).claims
theorem verifiedFrontendDecimal_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendDecimalArtifact verifiedFrontendDecimalReconstructedKernel =
      some verifiedFrontendDecimalClaimsKernel := by
  with_unfolding_all rfl
end Lanius.Extraction
