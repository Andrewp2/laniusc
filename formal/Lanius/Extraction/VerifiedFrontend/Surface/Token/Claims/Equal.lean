import Lanius.Extraction.VerifiedFrontend.Surface.Token.Claims.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Token.View.Assembly
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendToken_claims_equal_kernel :
    (verifiedFrontendTokenOrigins).claims = verifiedFrontendTokenClaimsKernel := by
  rfl
end Lanius.Extraction
