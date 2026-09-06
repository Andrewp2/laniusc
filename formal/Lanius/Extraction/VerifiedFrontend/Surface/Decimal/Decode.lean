import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Reconstruction

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_decoded_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendDecimalView.nodeCount + 1)
      verifiedFrontendDecimalReconstructedKernel).isSome = true := by
  kernel_rfl
def verifiedFrontendDecimalDecodedSurfaceKernel :=
  (decodeSurfaceFile (verifiedFrontendDecimalView.nodeCount + 1)
    verifiedFrontendDecimalReconstructedKernel).get verifiedFrontendDecimal_decoded_surface_present_kernel
theorem verifiedFrontendDecimal_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendDecimalArtifact.parse_nodes.length + 1)
      verifiedFrontendDecimalReconstructedKernel = some verifiedFrontendDecimalDecodedSurfaceKernel :=
  decodeSurfaceFile_of_nodeCount verifiedFrontendDecimalView
    verifiedFrontendDecimalReconstructedKernel verifiedFrontendDecimalDecodedSurfaceKernel
    (option_eq_some_get verifiedFrontendDecimal_decoded_surface_present_kernel)
end Lanius.Extraction
