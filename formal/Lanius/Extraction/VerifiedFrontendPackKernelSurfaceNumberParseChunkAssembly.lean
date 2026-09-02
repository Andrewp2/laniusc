import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumberParseToken
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumberParseSemantic
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumberParseRoot
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumberParseNodes0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumberParseNodes1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumberParseNodes2
namespace Lanius.Extraction
set_option maxRecDepth 500000
theorem verifiedFrontendNumber_nodes_cached_trace_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendNumberArtifact verifiedFrontendNumberParseView 0
      verifiedFrontendNumberArtifact.parse_nodes = true := by
  let nodes0 := verifiedFrontendNumberParseView.artifactView.cache.parseNodes.rangeToList 0 1000
  let nodes1 := verifiedFrontendNumberParseView.artifactView.cache.parseNodes.rangeToList 1000 1000
  let nodes2 := verifiedFrontendNumberParseView.artifactView.cache.parseNodes.rangeToList 2000 730
  have nodesSplit : verifiedFrontendNumberArtifact.parse_nodes = nodes0 ++ (nodes1 ++ (nodes2)) := by
    with_unfolding_all rfl
  rw [nodesSplit]
  rw [checkNodesFromParseView_append,
    verifiedFrontendNumber_nodes_0_trace_checked_kernel,
    verifiedFrontendNumber_nodes_0_trace_length_kernel]
  simp only [Bool.true_and, Nat.zero_add]
  rw [checkNodesFromParseView_append,
    verifiedFrontendNumber_nodes_1_trace_checked_kernel,
    verifiedFrontendNumber_nodes_1_trace_length_kernel]
  simp only [Bool.true_and]
  simpa only [Bool.true_and] using verifiedFrontendNumber_nodes_2_trace_checked_kernel

theorem verifiedFrontendNumber_nodes_trace_checked_kernel :
    checkNodesFromView laniusGrammar verifiedFrontendNumberArtifact verifiedFrontendNumberView 0
      verifiedFrontendNumberArtifact.parse_nodes = true := by
  change checkNodesFromView laniusGrammar verifiedFrontendNumberArtifact
    verifiedFrontendNumberParseView.artifactView 0 verifiedFrontendNumberArtifact.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar verifiedFrontendNumberArtifact verifiedFrontendNumberParseView]
  exact verifiedFrontendNumber_nodes_cached_trace_checked_kernel

theorem verifiedFrontendNumberParseValidChunkKernel : ParseArtifactValid verifiedFrontendNumberArtifact :=
  parseArtifactValid_of_view_checks verifiedFrontendNumberArtifact verifiedFrontendNumberView
    verifiedFrontendNumberRootTraceKernel verifiedFrontendNumber_token_trace_checked_kernel
    verifiedFrontendNumber_semantic_trace_checked_kernel verifiedFrontendNumber_nodes_trace_checked_kernel
    verifiedFrontendNumber_root_trace_found_kernel verifiedFrontendNumber_root_trace_shape_kernel
end Lanius.Extraction
