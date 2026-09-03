import Lanius.Extraction.VerifiedFrontend.Surface.Number.Parse.TokenHeader
import Lanius.Extraction.VerifiedFrontend.Surface.Number.Parse.TokenRaw
import Lanius.Extraction.VerifiedFrontend.Surface.Number.Parse.TokenCanonical
namespace Lanius.Extraction
theorem verifiedFrontendNumber_token_trace_checked_kernel :
    checkTokenArtifact verifiedFrontendNumberArtifact = true :=
  checkTokenArtifact_of_trace_phases
    verifiedFrontendNumber_token_header_trace_checked_kernel
    verifiedFrontendNumber_token_raw_trace_checked_kernel
    verifiedFrontendNumber_token_canonical_trace_checked_kernel
end Lanius.Extraction
