import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolClaims
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolView
import Lanius.Extraction.VerifiedFrontendUnitSymbolOrigins
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_claims_equal_kernel :
    (verifiedFrontendSymbolOrigins).claims = verifiedFrontendSymbolClaimsKernel := by
  rfl
end Lanius.Extraction
