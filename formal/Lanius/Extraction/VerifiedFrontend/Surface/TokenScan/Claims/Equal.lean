import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Claims.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.View.Assembly
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_claims_equal_kernel :
    (verifiedFrontendTokenScanOrigins).claims = verifiedFrontendTokenScanClaimsKernel := by
  rfl
end Lanius.Extraction
