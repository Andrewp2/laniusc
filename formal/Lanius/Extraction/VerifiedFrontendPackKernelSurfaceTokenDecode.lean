import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceTokenReconstruction
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendToken_decoded_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendTokenArtifact.parse_nodes.length + 1)
      verifiedFrontendTokenReconstructedKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenDecodedSurfaceKernel :=
  (decodeSurfaceFile (verifiedFrontendTokenArtifact.parse_nodes.length + 1)
    verifiedFrontendTokenReconstructedKernel).get verifiedFrontendToken_decoded_surface_present_kernel
theorem verifiedFrontendToken_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendTokenArtifact.parse_nodes.length + 1)
      verifiedFrontendTokenReconstructedKernel = some verifiedFrontendTokenDecodedSurfaceKernel :=
  option_eq_some_get verifiedFrontendToken_decoded_surface_present_kernel
end Lanius.Extraction
