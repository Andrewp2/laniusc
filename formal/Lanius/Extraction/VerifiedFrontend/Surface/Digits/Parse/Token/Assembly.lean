import Lanius.Extraction.VerifiedFrontend.Surface.Digits.Parse.Token.Header
import Lanius.Extraction.VerifiedFrontend.Surface.Digits.Parse.Token.Raw
import Lanius.Extraction.VerifiedFrontend.Surface.Digits.Parse.Token.Canonical
namespace Lanius.Extraction
theorem verifiedFrontendDigits_token_trace_checked_kernel :
    checkTokenArtifact verifiedFrontendDigitsArtifact = true :=
  checkTokenArtifact_of_trace_phases
    verifiedFrontendDigits_token_header_trace_checked_kernel
    verifiedFrontendDigits_token_raw_trace_checked_kernel
    verifiedFrontendDigits_token_canonical_trace_checked_kernel
end Lanius.Extraction
