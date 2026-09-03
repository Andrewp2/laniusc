import Lanius.Extraction.VerifiedFrontend.Surface.Token.Parse.Token.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Token.Parse.Semantic
import Lanius.Extraction.VerifiedFrontend.Surface.Token.Parse.Root
import Lanius.Extraction.VerifiedFrontend.Surface.Token.Parse.Nodes.Chunk0
import Lanius.Extraction.VerifiedFrontend.Surface.Token.Parse.Nodes.Chunk1
import Lanius.Extraction.VerifiedFrontend.Surface.Token.Parse.Nodes.Chunk2
namespace Lanius.Extraction
set_option maxRecDepth 500000
theorem verifiedFrontendToken_nodes_cached_trace_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendTokenArtifact verifiedFrontendTokenParseView 0
      verifiedFrontendTokenArtifact.parse_nodes = true := by
  let nodes0 := verifiedFrontendTokenParseView.artifactView.cache.parseNodes.rangeToList 0 1000
  let nodes1 := verifiedFrontendTokenParseView.artifactView.cache.parseNodes.rangeToList 1000 1000
  let nodes2 := verifiedFrontendTokenParseView.artifactView.cache.parseNodes.rangeToList 2000 973
  have nodesSplit : verifiedFrontendTokenArtifact.parse_nodes = nodes0 ++ (nodes1 ++ (nodes2)) := by
    with_unfolding_all rfl
  rw [nodesSplit]
  rw [checkNodesFromParseView_append,
    verifiedFrontendToken_nodes_0_trace_checked_kernel,
    verifiedFrontendToken_nodes_0_trace_length_kernel]
  simp only [Bool.true_and, Nat.zero_add]
  rw [checkNodesFromParseView_append,
    verifiedFrontendToken_nodes_1_trace_checked_kernel,
    verifiedFrontendToken_nodes_1_trace_length_kernel]
  simp only [Bool.true_and]
  simpa only [Bool.true_and] using verifiedFrontendToken_nodes_2_trace_checked_kernel

theorem verifiedFrontendToken_nodes_trace_checked_kernel :
    checkNodesFromView laniusGrammar verifiedFrontendTokenArtifact verifiedFrontendTokenView 0
      verifiedFrontendTokenArtifact.parse_nodes = true := by
  change checkNodesFromView laniusGrammar verifiedFrontendTokenArtifact
    verifiedFrontendTokenParseView.artifactView 0 verifiedFrontendTokenArtifact.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar verifiedFrontendTokenArtifact verifiedFrontendTokenParseView]
  exact verifiedFrontendToken_nodes_cached_trace_checked_kernel

theorem verifiedFrontendTokenParseValidChunkKernel : ParseArtifactValid verifiedFrontendTokenArtifact :=
  parseArtifactValid_of_view_checks verifiedFrontendTokenArtifact verifiedFrontendTokenView
    verifiedFrontendTokenRootTraceKernel verifiedFrontendToken_token_trace_checked_kernel
    verifiedFrontendToken_semantic_trace_checked_kernel verifiedFrontendToken_nodes_trace_checked_kernel
    verifiedFrontendToken_root_trace_found_kernel verifiedFrontendToken_root_trace_shape_kernel
end Lanius.Extraction
