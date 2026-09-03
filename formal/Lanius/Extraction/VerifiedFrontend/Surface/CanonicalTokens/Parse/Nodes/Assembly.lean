import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Token.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Semantic
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Root
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Nodes.Chunk0
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Nodes.Chunk1
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Nodes.Chunk2
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Nodes.Chunk3
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Nodes.Chunk4
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Nodes.Chunk5
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Nodes.Chunk6
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Nodes.Chunk7
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Nodes.Chunk8
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Nodes.Chunk9
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Nodes.Chunk10

namespace Lanius.Extraction
set_option maxRecDepth 500000

theorem verifiedFrontendCanonicalTokens_nodes_cached_trace_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendCanonicalTokensArtifact verifiedFrontendCanonicalTokensParseView 0
      verifiedFrontendCanonicalTokensArtifact.parse_nodes = true := by
  let nodes0 := verifiedFrontendCanonicalTokensParseView.artifactView.cache.parseNodes.rangeToList 0 1000
  let nodes1 := verifiedFrontendCanonicalTokensParseView.artifactView.cache.parseNodes.rangeToList 1000 1000
  let nodes2 := verifiedFrontendCanonicalTokensParseView.artifactView.cache.parseNodes.rangeToList 2000 1000
  let nodes3 := verifiedFrontendCanonicalTokensParseView.artifactView.cache.parseNodes.rangeToList 3000 1000
  let nodes4 := verifiedFrontendCanonicalTokensParseView.artifactView.cache.parseNodes.rangeToList 4000 1000
  let nodes5 := verifiedFrontendCanonicalTokensParseView.artifactView.cache.parseNodes.rangeToList 5000 1000
  let nodes6 := verifiedFrontendCanonicalTokensParseView.artifactView.cache.parseNodes.rangeToList 6000 1000
  let nodes7 := verifiedFrontendCanonicalTokensParseView.artifactView.cache.parseNodes.rangeToList 7000 1000
  let nodes8 := verifiedFrontendCanonicalTokensParseView.artifactView.cache.parseNodes.rangeToList 8000 1000
  let nodes9 := verifiedFrontendCanonicalTokensParseView.artifactView.cache.parseNodes.rangeToList 9000 1000
  let nodes10 := verifiedFrontendCanonicalTokensParseView.artifactView.cache.parseNodes.rangeToList 10000 311
  have nodesSplit : verifiedFrontendCanonicalTokensArtifact.parse_nodes =
      nodes0 ++ (nodes1 ++ (nodes2 ++ (nodes3 ++ (nodes4 ++ (nodes5 ++ (nodes6 ++ (nodes7 ++ (nodes8 ++ (nodes9 ++ (nodes10)))))))))) := by
    with_unfolding_all rfl
  rw [nodesSplit]
  rw [checkNodesFromParseView_append,
    verifiedFrontendCanonicalTokens_nodes_0_trace_checked_kernel,
    verifiedFrontendCanonicalTokens_nodes_0_trace_length_kernel]
  simp only [Bool.true_and, Nat.zero_add]
  rw [checkNodesFromParseView_append,
    verifiedFrontendCanonicalTokens_nodes_1_trace_checked_kernel,
    verifiedFrontendCanonicalTokens_nodes_1_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendCanonicalTokens_nodes_2_trace_checked_kernel,
    verifiedFrontendCanonicalTokens_nodes_2_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendCanonicalTokens_nodes_3_trace_checked_kernel,
    verifiedFrontendCanonicalTokens_nodes_3_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendCanonicalTokens_nodes_4_trace_checked_kernel,
    verifiedFrontendCanonicalTokens_nodes_4_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendCanonicalTokens_nodes_5_trace_checked_kernel,
    verifiedFrontendCanonicalTokens_nodes_5_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendCanonicalTokens_nodes_6_trace_checked_kernel,
    verifiedFrontendCanonicalTokens_nodes_6_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendCanonicalTokens_nodes_7_trace_checked_kernel,
    verifiedFrontendCanonicalTokens_nodes_7_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendCanonicalTokens_nodes_8_trace_checked_kernel,
    verifiedFrontendCanonicalTokens_nodes_8_trace_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendCanonicalTokens_nodes_9_trace_checked_kernel,
    verifiedFrontendCanonicalTokens_nodes_9_trace_length_kernel]
  simp only [Bool.true_and]
  simpa only [Bool.true_and] using verifiedFrontendCanonicalTokens_nodes_10_trace_checked_kernel

theorem verifiedFrontendCanonicalTokens_nodes_trace_checked_kernel :
    checkNodesFromView laniusGrammar verifiedFrontendCanonicalTokensArtifact
      verifiedFrontendCanonicalTokensView 0
      verifiedFrontendCanonicalTokensArtifact.parse_nodes = true := by
  change checkNodesFromView laniusGrammar verifiedFrontendCanonicalTokensArtifact
    verifiedFrontendCanonicalTokensParseView.artifactView 0
    verifiedFrontendCanonicalTokensArtifact.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar
    verifiedFrontendCanonicalTokensArtifact
    verifiedFrontendCanonicalTokensParseView]
  exact verifiedFrontendCanonicalTokens_nodes_cached_trace_checked_kernel

theorem verifiedFrontendCanonicalTokensParseValidChunkKernel :
    ParseArtifactValid verifiedFrontendCanonicalTokensArtifact :=
  parseArtifactValid_of_view_checks verifiedFrontendCanonicalTokensArtifact verifiedFrontendCanonicalTokensView
    verifiedFrontendCanonicalTokensRootTraceKernel
    verifiedFrontendCanonicalTokens_token_trace_checked_kernel
    verifiedFrontendCanonicalTokens_semantic_trace_checked_kernel
    verifiedFrontendCanonicalTokens_nodes_trace_checked_kernel
    verifiedFrontendCanonicalTokens_root_trace_found_kernel
    verifiedFrontendCanonicalTokens_root_trace_shape_kernel

end Lanius.Extraction
