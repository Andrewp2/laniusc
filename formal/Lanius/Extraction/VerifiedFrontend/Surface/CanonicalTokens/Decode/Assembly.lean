import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Decode.Trace
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
def verifiedFrontendCanonicalTokensDecodedSurfaceKernel : Lanius.Surface.File :=
  verifiedFrontendCanonicalTokensDecodedSurfaceTraceKernel
theorem verifiedFrontendCanonicalTokens_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendCanonicalTokensArtifact.parse_nodes.length + 1)
      verifiedFrontendCanonicalTokensReconstructedKernel = some verifiedFrontendCanonicalTokensDecodedSurfaceKernel := by
  rw [show verifiedFrontendCanonicalTokensArtifact.parse_nodes.length + 1 = 10312 by
    with_unfolding_all rfl]
  unfold verifiedFrontendCanonicalTokensReconstructedKernel
    verifiedFrontendCanonicalTokensDecodedSurfaceKernel
  exact verifiedFrontendCanonicalTokens_decoded_surface_trace_found_kernel
end Lanius.Extraction
