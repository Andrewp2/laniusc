import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendSymbol_decoded_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendSymbolView.nodeCount + 1)
      verifiedFrontendSymbolReconstructedKernel).isSome = true := by
  kernel_rfl

def verifiedFrontendSymbolDecodedSurfaceKernel : Lanius.Surface.File :=
  (decodeSurfaceFile (verifiedFrontendSymbolView.nodeCount + 1)
    verifiedFrontendSymbolReconstructedKernel).get
      verifiedFrontendSymbol_decoded_surface_present_kernel

theorem verifiedFrontendSymbol_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendSymbolArtifact.parse_nodes.length + 1)
      verifiedFrontendSymbolReconstructedKernel = some verifiedFrontendSymbolDecodedSurfaceKernel :=
  decodeSurfaceFile_of_nodeCount verifiedFrontendSymbolView
    verifiedFrontendSymbolReconstructedKernel verifiedFrontendSymbolDecodedSurfaceKernel
    (option_eq_some_get verifiedFrontendSymbol_decoded_surface_present_kernel)

end Lanius.Extraction
