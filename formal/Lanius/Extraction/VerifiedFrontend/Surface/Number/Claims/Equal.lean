import Lanius.Extraction.VerifiedFrontend.Surface.Number.Claims.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.Number.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Number.View.Assembly
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_claims_equal_kernel :
    (verifiedFrontendNumberOrigins).claims = verifiedFrontendNumberClaimsKernel := by
  rfl
end Lanius.Extraction
