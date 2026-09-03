import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Token
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Semantic
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Root
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Nodes0
namespace Lanius.Extraction
set_option maxRecDepth 500000
theorem verifiedFrontendTokenScan_nodes_cached_trace_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanParseView 0
      verifiedFrontendTokenScanArtifact.parse_nodes = true := by
  let nodes0 := verifiedFrontendTokenScanParseView.artifactView.cache.parseNodes.rangeToList 0 651
  have nodesSplit : verifiedFrontendTokenScanArtifact.parse_nodes = nodes0 := by
    with_unfolding_all rfl
  rw [nodesSplit]
  simpa only [Bool.true_and] using verifiedFrontendTokenScan_nodes_0_trace_checked_kernel

theorem verifiedFrontendTokenScan_nodes_trace_checked_kernel :
    checkNodesFromView laniusGrammar verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanView 0
      verifiedFrontendTokenScanArtifact.parse_nodes = true := by
  change checkNodesFromView laniusGrammar verifiedFrontendTokenScanArtifact
    verifiedFrontendTokenScanParseView.artifactView 0 verifiedFrontendTokenScanArtifact.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanParseView]
  exact verifiedFrontendTokenScan_nodes_cached_trace_checked_kernel

theorem verifiedFrontendTokenScanParseValidChunkKernel : ParseArtifactValid verifiedFrontendTokenScanArtifact :=
  parseArtifactValid_of_view_checks verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanView
    verifiedFrontendTokenScanRootTraceKernel verifiedFrontendTokenScan_token_trace_checked_kernel
    verifiedFrontendTokenScan_semantic_trace_checked_kernel verifiedFrontendTokenScan_nodes_trace_checked_kernel
    verifiedFrontendTokenScan_root_trace_found_kernel verifiedFrontendTokenScan_root_trace_shape_kernel
end Lanius.Extraction
