import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Reconstruction
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendRawLexer_decoded_surface_present_kernel :
    (decodeSurfaceFile (verifiedFrontendRawLexerView.nodeCount + 1)
      verifiedFrontendRawLexerReconstructedKernel).isSome = true := by
  kernel_rfl

def verifiedFrontendRawLexerDecodedSurfaceKernel : Lanius.Surface.File :=
  (decodeSurfaceFile (verifiedFrontendRawLexerView.nodeCount + 1)
    verifiedFrontendRawLexerReconstructedKernel).get
      verifiedFrontendRawLexer_decoded_surface_present_kernel

theorem verifiedFrontendRawLexer_decoded_surface_found_kernel :
    decodeSurfaceFile (verifiedFrontendRawLexerArtifact.parse_nodes.length + 1)
      verifiedFrontendRawLexerReconstructedKernel = some verifiedFrontendRawLexerDecodedSurfaceKernel :=
  decodeSurfaceFile_of_nodeCount verifiedFrontendRawLexerView
    verifiedFrontendRawLexerReconstructedKernel verifiedFrontendRawLexerDecodedSurfaceKernel
    (option_eq_some_get verifiedFrontendRawLexer_decoded_surface_present_kernel)

end Lanius.Extraction
