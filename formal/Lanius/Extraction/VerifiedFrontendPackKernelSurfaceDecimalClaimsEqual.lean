import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDecimalClaims
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDecimalView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_claims_equal_kernel :
    (verifiedFrontendDecimalOrigins).claims = verifiedFrontendDecimalClaimsKernel := by
  rfl
end Lanius.Extraction
