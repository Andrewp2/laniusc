import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_reconstructed_view_kernel :
    reconstructArtifactSurfaceView verifiedFrontendLexerArtifact
      verifiedFrontendLexerView = some verifiedFrontendLexerProposedKernel := by
  with_unfolding_all rfl

end Lanius.Extraction
