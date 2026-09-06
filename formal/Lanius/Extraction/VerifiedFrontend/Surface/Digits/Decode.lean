import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Surface.Digits.Reconstruction

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_decoded_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendDigitsView.nodeCount + 1)
      verifiedFrontendDigitsReconstructedKernel).isSome = true := by
  kernel_rfl
def verifiedFrontendDigitsDecodedSurfaceKernel :=
  (decodeSurfaceFile (verifiedFrontendDigitsView.nodeCount + 1)
    verifiedFrontendDigitsReconstructedKernel).get verifiedFrontendDigits_decoded_surface_present_kernel
theorem verifiedFrontendDigits_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendDigitsArtifact.parse_nodes.length + 1)
      verifiedFrontendDigitsReconstructedKernel = some verifiedFrontendDigitsDecodedSurfaceKernel :=
  decodeSurfaceFile_of_nodeCount verifiedFrontendDigitsView
    verifiedFrontendDigitsReconstructedKernel verifiedFrontendDigitsDecodedSurfaceKernel
    (option_eq_some_get verifiedFrontendDigits_decoded_surface_present_kernel)
end Lanius.Extraction
