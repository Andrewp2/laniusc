import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.Lexer.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Claims

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendLexer_origin_trace_claims_equal_kernel :
    verifiedFrontendLexerOrigins.claims = verifiedFrontendLexerClaimsTraceKernel := by
  kernel_rfl

theorem verifiedFrontendLexer_origins_trace_checked_kernel :
    verifiedFrontendLexerOrigins.valid verifiedFrontendLexerArtifact
      verifiedFrontendLexerView = true := by
  kernel_rfl

end Lanius.Extraction
