import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Token
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Metadata
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Nodes.Chunk0
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Nodes.Chunk1
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.Nodes.Chunk2

/-! Assembly of three measured parse-node check shards into the public parse
certificate. The chunks divide kernel reduction work; this module owns the
semantic statement about the complete node list. -/

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendTokenScan_nodes_cached_trace_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendTokenScanArtifact
      verifiedFrontendTokenScanParseView 0
      verifiedFrontendTokenScanArtifact.parse_nodes = true := by
  let nodes0 :=
    verifiedFrontendTokenScanParseView.artifactView.cache.parseNodes.rangeToList 0 217
  let nodes1 :=
    verifiedFrontendTokenScanParseView.artifactView.cache.parseNodes.rangeToList 217 217
  let nodes2 :=
    verifiedFrontendTokenScanParseView.artifactView.cache.parseNodes.rangeToList 434 217
  have nodesSplit :
      verifiedFrontendTokenScanArtifact.parse_nodes =
        nodes0 ++ (nodes1 ++ nodes2) := by
    with_unfolding_all rfl
  rw [nodesSplit, checkNodesFromParseView_append,
    verifiedFrontendTokenScan_nodes_0_trace_checked_kernel,
    verifiedFrontendTokenScan_nodes_0_trace_length_kernel]
  simp only [Bool.true_and, Nat.zero_add]
  rw [checkNodesFromParseView_append,
    verifiedFrontendTokenScan_nodes_1_trace_checked_kernel,
    verifiedFrontendTokenScan_nodes_1_trace_length_kernel]
  simpa only [Bool.true_and] using
    verifiedFrontendTokenScan_nodes_2_trace_checked_kernel

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

theorem verifiedFrontendTokenScanParseValidChunkKernel :
    ParseArtifactValid verifiedFrontendTokenScanArtifact :=
  parseArtifactValid_of_view_checks verifiedFrontendTokenScanArtifact
    verifiedFrontendTokenScanView verifiedFrontendTokenScanRootTraceKernel
    verifiedFrontendTokenScan_token_trace_checked_kernel
    verifiedFrontendTokenScan_semantic_trace_checked_kernel
    verifiedFrontendTokenScan_nodes_trace_checked_kernel
    verifiedFrontendTokenScan_root_trace_found_kernel
    verifiedFrontendTokenScan_root_trace_shape_kernel

theorem verifiedFrontendTokenScanParseValidTraceKernel :
    ParseArtifactValid verifiedFrontendTokenScanArtifact :=
  verifiedFrontendTokenScanParseValidChunkKernel

end Lanius.Extraction
