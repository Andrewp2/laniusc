import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Parse.TokenHeader
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Parse.TokenRaw
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Parse.TokenCanonical
namespace Lanius.Extraction
theorem verifiedFrontendDecimal_token_trace_checked_kernel :
    checkTokenArtifact verifiedFrontendDecimalArtifact = true :=
  checkTokenArtifact_of_trace_phases
    verifiedFrontendDecimal_token_header_trace_checked_kernel
    verifiedFrontendDecimal_token_raw_trace_checked_kernel
    verifiedFrontendDecimal_token_canonical_trace_checked_kernel
end Lanius.Extraction
