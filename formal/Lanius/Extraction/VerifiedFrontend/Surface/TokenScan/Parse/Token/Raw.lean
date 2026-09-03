import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Artifact
import Lanius.Extraction.ParseChunks

/-! Header and raw-token trace checks. This is the measured reduction shard
behind the complete token certificate in the parent module. -/

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

kernel_parse_token_header
  verifiedFrontendTokenScan_token_header_trace_checked_kernel for
  verifiedFrontendTokenScanArtifact

kernel_parse_token_raw
  verifiedFrontendTokenScan_token_raw_trace_checked_kernel for
  verifiedFrontendTokenScanArtifact

end Lanius.Extraction
