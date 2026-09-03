import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Token.Raw

/-! Canonical-token validation and assembly of the complete token trace
certificate. -/

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

kernel_parse_token_canonical
  verifiedFrontendTokenScan_token_canonical_trace_checked_kernel for
  verifiedFrontendTokenScanArtifact

theorem verifiedFrontendTokenScan_token_trace_checked_kernel :
    checkTokenArtifact verifiedFrontendTokenScanArtifact = true :=
  checkTokenArtifact_of_trace_phases
    verifiedFrontendTokenScan_token_header_trace_checked_kernel
    verifiedFrontendTokenScan_token_raw_trace_checked_kernel
    verifiedFrontendTokenScan_token_canonical_trace_checked_kernel

end Lanius.Extraction
