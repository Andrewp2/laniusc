import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Reconstruction
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Token
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Metadata

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendTokenScan_nodes_cached_trace_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendTokenScanArtifact
      verifiedFrontendTokenScanParseView 0
      verifiedFrontendTokenScanArtifact.parse_nodes = true := by
  exact verifiedFrontendTokenScan_validated_nodes_kernel

theorem verifiedFrontendTokenScan_nodes_trace_checked_kernel :
    checkNodesFromView laniusGrammar verifiedFrontendTokenScanArtifact
      verifiedFrontendTokenScanView 0
      verifiedFrontendTokenScanArtifact.parse_nodes = true := by
  change checkNodesFromView laniusGrammar verifiedFrontendTokenScanArtifact
    verifiedFrontendTokenScanParseView.artifactView 0
    verifiedFrontendTokenScanArtifact.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar
    verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanParseView]
  exact verifiedFrontendTokenScan_nodes_cached_trace_checked_kernel

theorem verifiedFrontendTokenScanParseValidTraceKernel :
    ParseArtifactValid verifiedFrontendTokenScanArtifact :=
  parseArtifactValid_of_view_checks verifiedFrontendTokenScanArtifact
    verifiedFrontendTokenScanView verifiedFrontendTokenScanRootTraceKernel
    verifiedFrontendTokenScan_token_trace_checked_kernel
    verifiedFrontendTokenScan_semantic_trace_checked_kernel
    verifiedFrontendTokenScan_nodes_trace_checked_kernel
    verifiedFrontendTokenScan_root_trace_found_kernel
    verifiedFrontendTokenScan_root_trace_shape_kernel

end Lanius.Extraction
