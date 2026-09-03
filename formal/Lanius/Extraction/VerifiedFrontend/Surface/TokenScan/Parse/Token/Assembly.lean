import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Token.Header
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Token.Raw
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Token.Canonical
namespace Lanius.Extraction
theorem verifiedFrontendTokenScan_token_trace_checked_kernel :
    checkTokenArtifact verifiedFrontendTokenScanArtifact = true :=
  checkTokenArtifact_of_trace_phases
    verifiedFrontendTokenScan_token_header_trace_checked_kernel
    verifiedFrontendTokenScan_token_raw_trace_checked_kernel
    verifiedFrontendTokenScan_token_canonical_trace_checked_kernel
end Lanius.Extraction
