import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigitsReconstruction
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_decoded_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendDigitsArtifact.parse_nodes.length + 1)
      verifiedFrontendDigitsReconstructedKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDigitsDecodedSurfaceKernel :=
  (decodeSurfaceFile (verifiedFrontendDigitsArtifact.parse_nodes.length + 1)
    verifiedFrontendDigitsReconstructedKernel).get verifiedFrontendDigits_decoded_surface_present_kernel
theorem verifiedFrontendDigits_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendDigitsArtifact.parse_nodes.length + 1)
      verifiedFrontendDigitsReconstructedKernel = some verifiedFrontendDigitsDecodedSurfaceKernel :=
  option_eq_some_get verifiedFrontendDigits_decoded_surface_present_kernel
end Lanius.Extraction
