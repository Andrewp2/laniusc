import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumberClaims
import Lanius.Extraction.VerifiedFrontendUnitNumberOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumberView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_claims_equal_kernel :
    (verifiedFrontendNumberOrigins).claims = verifiedFrontendNumberClaimsKernel := by
  rfl
end Lanius.Extraction
