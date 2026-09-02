import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerParseToken
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerParseSemantic
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerParseRoot
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerParseNodes0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerParseNodes1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerParseNodes2
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerParseNodes3
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerParseNodes4
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerParseNodes5
namespace Lanius.Extraction
set_option maxRecDepth 500000
theorem verifiedFrontendRawLexer_nodes_cached_trace_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendRawLexerArtifact verifiedFrontendRawLexerParseView 0
      verifiedFrontendRawLexerArtifact.parse_nodes = true := by
  let nodes0 := verifiedFrontendRawLexerParseView.artifactView.cache.parseNodes.rangeToList 0 1000
  let nodes1 := verifiedFrontendRawLexerParseView.artifactView.cache.parseNodes.rangeToList 1000 1000
  let nodes2 := verifiedFrontendRawLexerParseView.artifactView.cache.parseNodes.rangeToList 2000 1000
  let nodes3 := verifiedFrontendRawLexerParseView.artifactView.cache.parseNodes.rangeToList 3000 1000
  let nodes4 := verifiedFrontendRawLexerParseView.artifactView.cache.parseNodes.rangeToList 4000 1000
  let nodes5 := verifiedFrontendRawLexerParseView.artifactView.cache.parseNodes.rangeToList 5000 967
  have nodesSplit : verifiedFrontendRawLexerArtifact.parse_nodes = nodes0 ++ (nodes1 ++ (nodes2 ++ (nodes3 ++ (nodes4 ++ (nodes5))))) := by
    with_unfolding_all rfl
  rw [nodesSplit]
  rw [checkNodesFromParseView_append,
    verifiedFrontendRawLexer_nodes_0_trace_checked_kernel,
    verifiedFrontendRawLexer_nodes_0_trace_length_kernel]
  simp only [Bool.true_and, Nat.zero_add]
  rw [checkNodesFromParseView_append,
    verifiedFrontendRawLexer_nodes_1_trace_checked_kernel,
    verifiedFrontendRawLexer_nodes_1_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendRawLexer_nodes_2_trace_checked_kernel,
    verifiedFrontendRawLexer_nodes_2_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendRawLexer_nodes_3_trace_checked_kernel,
    verifiedFrontendRawLexer_nodes_3_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendRawLexer_nodes_4_trace_checked_kernel,
    verifiedFrontendRawLexer_nodes_4_trace_length_kernel]
  simp only [Bool.true_and]
  simpa only [Bool.true_and] using verifiedFrontendRawLexer_nodes_5_trace_checked_kernel

theorem verifiedFrontendRawLexer_nodes_trace_checked_kernel :
    checkNodesFromView laniusGrammar verifiedFrontendRawLexerArtifact verifiedFrontendRawLexerView 0
      verifiedFrontendRawLexerArtifact.parse_nodes = true := by
  change checkNodesFromView laniusGrammar verifiedFrontendRawLexerArtifact
    verifiedFrontendRawLexerParseView.artifactView 0 verifiedFrontendRawLexerArtifact.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar verifiedFrontendRawLexerArtifact verifiedFrontendRawLexerParseView]
  exact verifiedFrontendRawLexer_nodes_cached_trace_checked_kernel

theorem verifiedFrontendRawLexerParseValidChunkKernel : ParseArtifactValid verifiedFrontendRawLexerArtifact :=
  parseArtifactValid_of_view_checks verifiedFrontendRawLexerArtifact verifiedFrontendRawLexerView
    verifiedFrontendRawLexerRootTraceKernel verifiedFrontendRawLexer_token_trace_checked_kernel
    verifiedFrontendRawLexer_semantic_trace_checked_kernel verifiedFrontendRawLexer_nodes_trace_checked_kernel
    verifiedFrontendRawLexer_root_trace_found_kernel verifiedFrontendRawLexer_root_trace_shape_kernel
end Lanius.Extraction
