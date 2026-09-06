import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.RawLexer.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Claims

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendRawLexer_origins_checked_kernel :
    verifiedFrontendRawLexerOrigins.valid verifiedFrontendRawLexerArtifact
      verifiedFrontendRawLexerView = true := by
  kernel_rfl

end Lanius.Extraction
