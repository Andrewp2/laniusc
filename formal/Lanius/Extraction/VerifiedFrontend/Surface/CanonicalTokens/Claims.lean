import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Origins
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

def verifiedFrontendCanonicalTokensClaimsKernel : SurfaceClaims :=
  verifiedFrontendCanonicalTokensOrigins.claims

theorem verifiedFrontendCanonicalTokens_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendCanonicalTokensArtifact
      verifiedFrontendCanonicalTokensReconstructedKernel = some verifiedFrontendCanonicalTokensClaimsKernel := by
  kernel_rfl

theorem verifiedFrontendCanonicalTokens_claims_equal_kernel :
    verifiedFrontendCanonicalTokensOrigins.claims = verifiedFrontendCanonicalTokensClaimsKernel := rfl

end Lanius.Extraction
