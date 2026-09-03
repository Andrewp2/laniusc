import Lanius.Extraction.VerifiedFrontend.Surface.Digits.Claims.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Digits.View.Assembly
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_claims_equal_kernel :
    (verifiedFrontendDigitsOrigins).claims = verifiedFrontendDigitsClaimsKernel := by
  rfl
end Lanius.Extraction
