import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDecimalReconstruction
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_decoded_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendDecimalArtifact.parse_nodes.length + 1)
      verifiedFrontendDecimalReconstructedKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDecimalDecodedSurfaceKernel :=
  (decodeSurfaceFile (verifiedFrontendDecimalArtifact.parse_nodes.length + 1)
    verifiedFrontendDecimalReconstructedKernel).get verifiedFrontendDecimal_decoded_surface_present_kernel
theorem verifiedFrontendDecimal_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendDecimalArtifact.parse_nodes.length + 1)
      verifiedFrontendDecimalReconstructedKernel = some verifiedFrontendDecimalDecodedSurfaceKernel :=
  option_eq_some_get verifiedFrontendDecimal_decoded_surface_present_kernel
end Lanius.Extraction
