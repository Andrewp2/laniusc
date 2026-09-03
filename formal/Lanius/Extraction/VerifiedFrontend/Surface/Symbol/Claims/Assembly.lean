import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Claims.Trace
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
def verifiedFrontendSymbolClaimsKernel : SurfaceClaims :=
  verifiedFrontendSymbolClaimsTraceKernel
theorem verifiedFrontendSymbol_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendSymbolArtifact verifiedFrontendSymbolReconstructedKernel =
      some verifiedFrontendSymbolClaimsKernel := by
  unfold verifiedFrontendSymbolReconstructedKernel verifiedFrontendSymbolClaimsKernel
  exact verifiedFrontendSymbol_claims_trace_found_kernel
end Lanius.Extraction
