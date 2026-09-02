import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolDecodeTrace
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolReconstruction
namespace Lanius.Extraction
set_option maxRecDepth 500000
def verifiedFrontendSymbolDecodedSurfaceKernel : Lanius.Surface.File :=
  verifiedFrontendSymbolDecodedSurfaceTraceKernel
theorem verifiedFrontendSymbol_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendSymbolArtifact.parse_nodes.length + 1)
      verifiedFrontendSymbolReconstructedKernel = some verifiedFrontendSymbolDecodedSurfaceKernel := by
  rw [show verifiedFrontendSymbolArtifact.parse_nodes.length + 1 = 8245 by
    with_unfolding_all rfl]
  unfold verifiedFrontendSymbolReconstructedKernel
    verifiedFrontendSymbolDecodedSurfaceKernel
  exact verifiedFrontendSymbol_decoded_surface_trace_found_kernel
end Lanius.Extraction
