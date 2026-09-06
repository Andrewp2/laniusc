import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Surface.Token.Reconstruction

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendToken_decoded_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendTokenView.nodeCount + 1)
      verifiedFrontendTokenReconstructedKernel).isSome = true := by
  kernel_rfl
def verifiedFrontendTokenDecodedSurfaceKernel :=
  (decodeSurfaceFile (verifiedFrontendTokenView.nodeCount + 1)
    verifiedFrontendTokenReconstructedKernel).get verifiedFrontendToken_decoded_surface_present_kernel
theorem verifiedFrontendToken_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendTokenArtifact.parse_nodes.length + 1)
      verifiedFrontendTokenReconstructedKernel = some verifiedFrontendTokenDecodedSurfaceKernel :=
  decodeSurfaceFile_of_nodeCount verifiedFrontendTokenView
    verifiedFrontendTokenReconstructedKernel verifiedFrontendTokenDecodedSurfaceKernel
    (option_eq_some_get verifiedFrontendToken_decoded_surface_present_kernel)
end Lanius.Extraction
