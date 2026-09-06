import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_decoded_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendCanonicalTokensView.nodeCount + 1)
      verifiedFrontendCanonicalTokensReconstructedKernel).isSome = true := by
  kernel_rfl

def verifiedFrontendCanonicalTokensDecodedSurfaceKernel : Lanius.Surface.File :=
  (decodeSurfaceFile (verifiedFrontendCanonicalTokensView.nodeCount + 1)
    verifiedFrontendCanonicalTokensReconstructedKernel).get
      verifiedFrontendCanonicalTokens_decoded_surface_present_kernel

theorem verifiedFrontendCanonicalTokens_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendCanonicalTokensArtifact.parse_nodes.length + 1)
      verifiedFrontendCanonicalTokensReconstructedKernel = some verifiedFrontendCanonicalTokensDecodedSurfaceKernel :=
  decodeSurfaceFile_of_nodeCount verifiedFrontendCanonicalTokensView
    verifiedFrontendCanonicalTokensReconstructedKernel verifiedFrontendCanonicalTokensDecodedSurfaceKernel
    (option_eq_some_get verifiedFrontendCanonicalTokens_decoded_surface_present_kernel)

end Lanius.Extraction
