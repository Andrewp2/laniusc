import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Parse.Token.Header
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Parse.Token.Raw
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Parse.Token.Canonical

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_token_checked_kernel :
    checkTokenArtifact verifiedFrontendLexerArtifact = true :=
  checkTokenArtifact_of_trace_phases
    verifiedFrontendLexer_token_header_trace_checked_kernel
    verifiedFrontendLexer_token_raw_trace_checked_kernel
    verifiedFrontendLexer_token_canonical_trace_checked_kernel

end Lanius.Extraction
