import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Artifact
import Lanius.Extraction.ParseChunks

/-! Semantic-token and root trace checks grouped at one measured compilation
boundary. -/

/-! Semantic token kinds. -/
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
kernel_parse_semantic verifiedFrontendTokenScan_semantic_trace_checked_kernel for verifiedFrontendTokenScanArtifact
end Lanius.Extraction

/-! Root node. -/
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
kernel_parse_root verifiedFrontendTokenScan_root_trace_present_kernel,
  verifiedFrontendTokenScanRootTraceKernel, verifiedFrontendTokenScan_root_trace_found_kernel,
  verifiedFrontendTokenScan_root_trace_shape_kernel for verifiedFrontendTokenScanArtifact
end Lanius.Extraction
