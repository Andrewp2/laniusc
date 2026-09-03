import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Claims.Trace
import Lanius.Extraction.VerifiedFrontend.Artifact.Lexer.Origins

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendLexer_origin_trace_claims_equal_kernel :
    verifiedFrontendLexerOrigins.claims = verifiedFrontendLexerClaimsTraceKernel := by
  with_unfolding_all rfl
end Lanius.Extraction
