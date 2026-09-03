import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Parse.Token.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Parse.Semantic
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Parse.Root
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Parse.Nodes.Chunk0
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Parse.Nodes.Chunk1
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Parse.Nodes.Chunk2
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Parse.Nodes.Chunk3
namespace Lanius.Extraction
set_option maxRecDepth 500000
theorem verifiedFrontendDecimal_nodes_cached_trace_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendDecimalArtifact verifiedFrontendDecimalParseView 0
      verifiedFrontendDecimalArtifact.parse_nodes = true := by
  let nodes0 := verifiedFrontendDecimalParseView.artifactView.cache.parseNodes.rangeToList 0 1000
  let nodes1 := verifiedFrontendDecimalParseView.artifactView.cache.parseNodes.rangeToList 1000 1000
  let nodes2 := verifiedFrontendDecimalParseView.artifactView.cache.parseNodes.rangeToList 2000 1000
  let nodes3 := verifiedFrontendDecimalParseView.artifactView.cache.parseNodes.rangeToList 3000 445
  have nodesSplit : verifiedFrontendDecimalArtifact.parse_nodes = nodes0 ++ (nodes1 ++ (nodes2 ++ (nodes3))) := by
    with_unfolding_all rfl
  rw [nodesSplit]
  rw [checkNodesFromParseView_append,
    verifiedFrontendDecimal_nodes_0_trace_checked_kernel,
    verifiedFrontendDecimal_nodes_0_trace_length_kernel]
  simp only [Bool.true_and, Nat.zero_add]
  rw [checkNodesFromParseView_append,
    verifiedFrontendDecimal_nodes_1_trace_checked_kernel,
    verifiedFrontendDecimal_nodes_1_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendDecimal_nodes_2_trace_checked_kernel,
    verifiedFrontendDecimal_nodes_2_trace_length_kernel]
  simp only [Bool.true_and]
  simpa only [Bool.true_and] using verifiedFrontendDecimal_nodes_3_trace_checked_kernel

theorem verifiedFrontendDecimal_nodes_trace_checked_kernel :
    checkNodesFromView laniusGrammar verifiedFrontendDecimalArtifact verifiedFrontendDecimalView 0
      verifiedFrontendDecimalArtifact.parse_nodes = true := by
  change checkNodesFromView laniusGrammar verifiedFrontendDecimalArtifact
    verifiedFrontendDecimalParseView.artifactView 0 verifiedFrontendDecimalArtifact.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar verifiedFrontendDecimalArtifact verifiedFrontendDecimalParseView]
  exact verifiedFrontendDecimal_nodes_cached_trace_checked_kernel

theorem verifiedFrontendDecimalParseValidChunkKernel : ParseArtifactValid verifiedFrontendDecimalArtifact :=
  parseArtifactValid_of_view_checks verifiedFrontendDecimalArtifact verifiedFrontendDecimalView
    verifiedFrontendDecimalRootTraceKernel verifiedFrontendDecimal_token_trace_checked_kernel
    verifiedFrontendDecimal_semantic_trace_checked_kernel verifiedFrontendDecimal_nodes_trace_checked_kernel
    verifiedFrontendDecimal_root_trace_found_kernel verifiedFrontendDecimal_root_trace_shape_kernel
end Lanius.Extraction
