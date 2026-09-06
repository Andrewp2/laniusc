import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction
import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Origins
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

def verifiedFrontendSymbolClaimsKernel : SurfaceClaims :=
  verifiedFrontendSymbolOrigins.claims

theorem verifiedFrontendSymbol_claims_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendSymbolArtifact
      verifiedFrontendSymbolReconstructedKernel = some verifiedFrontendSymbolClaimsKernel := by
  kernel_rfl

theorem verifiedFrontendSymbol_claims_equal_kernel :
    verifiedFrontendSymbolOrigins.claims = verifiedFrontendSymbolClaimsKernel := rfl

end Lanius.Extraction
