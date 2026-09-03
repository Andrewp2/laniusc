import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Claims.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Origins
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_claims_equal_kernel :
    (verifiedFrontendSymbolOrigins).claims = verifiedFrontendSymbolClaimsKernel := by
  rfl
end Lanius.Extraction
