import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Surface.Number.Reconstruction

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_decoded_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendNumberView.nodeCount + 1)
      verifiedFrontendNumberReconstructedKernel).isSome = true := by
  kernel_rfl
def verifiedFrontendNumberDecodedSurfaceKernel :=
  (decodeSurfaceFile (verifiedFrontendNumberView.nodeCount + 1)
    verifiedFrontendNumberReconstructedKernel).get verifiedFrontendNumber_decoded_surface_present_kernel
theorem verifiedFrontendNumber_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendNumberArtifact.parse_nodes.length + 1)
      verifiedFrontendNumberReconstructedKernel = some verifiedFrontendNumberDecodedSurfaceKernel :=
  decodeSurfaceFile_of_nodeCount verifiedFrontendNumberView
    verifiedFrontendNumberReconstructedKernel verifiedFrontendNumberDecodedSurfaceKernel
    (option_eq_some_get verifiedFrontendNumber_decoded_surface_present_kernel)
end Lanius.Extraction
