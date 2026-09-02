import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolParseToken
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolParseSemantic
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolParseRoot
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolParseNodes0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolParseNodes1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolParseNodes2
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolParseNodes3
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolParseNodes4
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolParseNodes5

namespace Lanius.Extraction
set_option maxRecDepth 100000

theorem verifiedFrontendSymbol_nodes_cached_trace_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendSymbolArtifact
      verifiedFrontendSymbolParseView 0 verifiedFrontendSymbolArtifact.parse_nodes = true := by
  let nodes0 := verifiedFrontendSymbolParseView.artifactView.cache.parseNodes.rangeToList 0 1500
  let nodes1 := verifiedFrontendSymbolParseView.artifactView.cache.parseNodes.rangeToList 1500 1500
  let nodes2 := verifiedFrontendSymbolParseView.artifactView.cache.parseNodes.rangeToList 3000 1500
  let nodes3 := verifiedFrontendSymbolParseView.artifactView.cache.parseNodes.rangeToList 4500 1500
  let nodes4 := verifiedFrontendSymbolParseView.artifactView.cache.parseNodes.rangeToList 6000 1500
  let nodes5 := verifiedFrontendSymbolParseView.artifactView.cache.parseNodes.rangeToList 7500 744
  have nodesSplit : verifiedFrontendSymbolArtifact.parse_nodes =
      nodes0 ++ (nodes1 ++ (nodes2 ++ (nodes3 ++ (nodes4 ++ nodes5)))) := by
    with_unfolding_all rfl
  rw [nodesSplit]
  rw [checkNodesFromParseView_append,
    verifiedFrontendSymbol_nodes_0_trace_checked_kernel,
    verifiedFrontendSymbol_nodes_0_trace_length_kernel]
  simp only [Bool.true_and, Nat.zero_add]
  rw [checkNodesFromParseView_append,
    verifiedFrontendSymbol_nodes_1_trace_checked_kernel,
    verifiedFrontendSymbol_nodes_1_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendSymbol_nodes_2_trace_checked_kernel,
    verifiedFrontendSymbol_nodes_2_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendSymbol_nodes_3_trace_checked_kernel,
    verifiedFrontendSymbol_nodes_3_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendSymbol_nodes_4_trace_checked_kernel,
    verifiedFrontendSymbol_nodes_4_trace_length_kernel]
  simpa only [Bool.true_and] using
    verifiedFrontendSymbol_nodes_5_trace_checked_kernel

theorem verifiedFrontendSymbol_nodes_trace_checked_kernel :
    checkNodesFromView laniusGrammar verifiedFrontendSymbolArtifact
      verifiedFrontendSymbolView 0 verifiedFrontendSymbolArtifact.parse_nodes = true := by
  change checkNodesFromView laniusGrammar verifiedFrontendSymbolArtifact
    verifiedFrontendSymbolParseView.artifactView 0
    verifiedFrontendSymbolArtifact.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar verifiedFrontendSymbolArtifact
    verifiedFrontendSymbolParseView]
  exact verifiedFrontendSymbol_nodes_cached_trace_checked_kernel

theorem verifiedFrontendSymbolParseValidChunkKernel :
    ParseArtifactValid verifiedFrontendSymbolArtifact :=
  parseArtifactValid_of_view_checks verifiedFrontendSymbolArtifact
    verifiedFrontendSymbolView verifiedFrontendSymbolRootTraceKernel
    verifiedFrontendSymbol_token_trace_checked_kernel
    verifiedFrontendSymbol_semantic_trace_checked_kernel
    verifiedFrontendSymbol_nodes_trace_checked_kernel
    verifiedFrontendSymbol_root_trace_found_kernel
    verifiedFrontendSymbol_root_trace_shape_kernel

end Lanius.Extraction
