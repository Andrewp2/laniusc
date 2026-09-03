import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Reconstruction.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_decoded_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendTokenScanArtifact.parse_nodes.length + 1)
      verifiedFrontendTokenScanReconstructedKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenScanDecodedSurfaceKernel :=
  (decodeSurfaceFile (verifiedFrontendTokenScanArtifact.parse_nodes.length + 1)
    verifiedFrontendTokenScanReconstructedKernel).get verifiedFrontendTokenScan_decoded_surface_present_kernel
theorem verifiedFrontendTokenScan_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendTokenScanArtifact.parse_nodes.length + 1)
      verifiedFrontendTokenScanReconstructedKernel = some verifiedFrontendTokenScanDecodedSurfaceKernel :=
  option_eq_some_get verifiedFrontendTokenScan_decoded_surface_present_kernel
end Lanius.Extraction
