import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigitsParseToken
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigitsParseSemantic
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigitsParseRoot
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigitsParseNodes0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigitsParseNodes1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigitsParseNodes2
namespace Lanius.Extraction
set_option maxRecDepth 500000
theorem verifiedFrontendDigits_nodes_cached_trace_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendDigitsArtifact verifiedFrontendDigitsParseView 0
      verifiedFrontendDigitsArtifact.parse_nodes = true := by
  let nodes0 := verifiedFrontendDigitsParseView.artifactView.cache.parseNodes.rangeToList 0 1000
  let nodes1 := verifiedFrontendDigitsParseView.artifactView.cache.parseNodes.rangeToList 1000 1000
  let nodes2 := verifiedFrontendDigitsParseView.artifactView.cache.parseNodes.rangeToList 2000 333
  have nodesSplit : verifiedFrontendDigitsArtifact.parse_nodes = nodes0 ++ (nodes1 ++ (nodes2)) := by
    with_unfolding_all rfl
  rw [nodesSplit]
  rw [checkNodesFromParseView_append,
    verifiedFrontendDigits_nodes_0_trace_checked_kernel,
    verifiedFrontendDigits_nodes_0_trace_length_kernel]
  simp only [Bool.true_and, Nat.zero_add]
  rw [checkNodesFromParseView_append,
    verifiedFrontendDigits_nodes_1_trace_checked_kernel,
    verifiedFrontendDigits_nodes_1_trace_length_kernel]
  simp only [Bool.true_and]
  simpa only [Bool.true_and] using verifiedFrontendDigits_nodes_2_trace_checked_kernel

theorem verifiedFrontendDigits_nodes_trace_checked_kernel :
    checkNodesFromView laniusGrammar verifiedFrontendDigitsArtifact verifiedFrontendDigitsView 0
      verifiedFrontendDigitsArtifact.parse_nodes = true := by
  change checkNodesFromView laniusGrammar verifiedFrontendDigitsArtifact
    verifiedFrontendDigitsParseView.artifactView 0 verifiedFrontendDigitsArtifact.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar verifiedFrontendDigitsArtifact verifiedFrontendDigitsParseView]
  exact verifiedFrontendDigits_nodes_cached_trace_checked_kernel

theorem verifiedFrontendDigitsParseValidChunkKernel : ParseArtifactValid verifiedFrontendDigitsArtifact :=
  parseArtifactValid_of_view_checks verifiedFrontendDigitsArtifact verifiedFrontendDigitsView
    verifiedFrontendDigitsRootTraceKernel verifiedFrontendDigits_token_trace_checked_kernel
    verifiedFrontendDigits_semantic_trace_checked_kernel verifiedFrontendDigits_nodes_trace_checked_kernel
    verifiedFrontendDigits_root_trace_found_kernel verifiedFrontendDigits_root_trace_shape_kernel
end Lanius.Extraction
