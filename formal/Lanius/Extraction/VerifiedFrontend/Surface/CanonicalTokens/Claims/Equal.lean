import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Claims.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Origins
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_claims_equal_kernel :
    (verifiedFrontendCanonicalTokensOrigins).claims = verifiedFrontendCanonicalTokensClaimsKernel := by
  rfl
end Lanius.Extraction
