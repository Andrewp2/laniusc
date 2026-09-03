import Lanius.Extraction.VerifiedFrontend.Surface.Token.Parse.TokenHeader
import Lanius.Extraction.VerifiedFrontend.Surface.Token.Parse.TokenRaw
import Lanius.Extraction.VerifiedFrontend.Surface.Token.Parse.TokenCanonical
namespace Lanius.Extraction
theorem verifiedFrontendToken_token_trace_checked_kernel :
    checkTokenArtifact verifiedFrontendTokenArtifact = true :=
  checkTokenArtifact_of_trace_phases
    verifiedFrontendToken_token_header_trace_checked_kernel
    verifiedFrontendToken_token_raw_trace_checked_kernel
    verifiedFrontendToken_token_canonical_trace_checked_kernel
end Lanius.Extraction
