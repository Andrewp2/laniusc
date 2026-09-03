import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Parse.Token.Header
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Parse.Token.Raw
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Parse.Token.Canonical
namespace Lanius.Extraction
theorem verifiedFrontendRawLexer_token_trace_checked_kernel :
    checkTokenArtifact verifiedFrontendRawLexerArtifact = true :=
  checkTokenArtifact_of_trace_phases
    verifiedFrontendRawLexer_token_header_trace_checked_kernel
    verifiedFrontendRawLexer_token_raw_trace_checked_kernel
    verifiedFrontendRawLexer_token_canonical_trace_checked_kernel
end Lanius.Extraction
