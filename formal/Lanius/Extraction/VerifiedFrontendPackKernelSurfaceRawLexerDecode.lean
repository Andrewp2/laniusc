import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeTrace
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstruction
namespace Lanius.Extraction
set_option maxRecDepth 500000
def verifiedFrontendRawLexerDecodedSurfaceKernel : Lanius.Surface.File :=
  verifiedFrontendRawLexerDecodedSurfaceTraceKernel
theorem verifiedFrontendRawLexer_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendRawLexerArtifact.parse_nodes.length + 1)
      verifiedFrontendRawLexerReconstructedKernel = some verifiedFrontendRawLexerDecodedSurfaceKernel := by
  rw [show verifiedFrontendRawLexerArtifact.parse_nodes.length + 1 = 5968 by
    with_unfolding_all rfl]
  unfold verifiedFrontendRawLexerReconstructedKernel
    verifiedFrontendRawLexerDecodedSurfaceKernel
  exact verifiedFrontendRawLexer_decoded_surface_trace_found_kernel
end Lanius.Extraction
