import Lanius.Extraction.VerifiedFrontend.Surface.Number.Reconstruction.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_decoded_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendNumberArtifact.parse_nodes.length + 1)
      verifiedFrontendNumberReconstructedKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendNumberDecodedSurfaceKernel :=
  (decodeSurfaceFile (verifiedFrontendNumberArtifact.parse_nodes.length + 1)
    verifiedFrontendNumberReconstructedKernel).get verifiedFrontendNumber_decoded_surface_present_kernel
theorem verifiedFrontendNumber_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendNumberArtifact.parse_nodes.length + 1)
      verifiedFrontendNumberReconstructedKernel = some verifiedFrontendNumberDecodedSurfaceKernel :=
  option_eq_some_get verifiedFrontendNumber_decoded_surface_present_kernel
end Lanius.Extraction
