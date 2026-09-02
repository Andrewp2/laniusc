import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerNodes0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerNodes1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerNodes2
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerNodes3
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerNodes4
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerNodes5
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerNodes6

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendLexer_parse_nodes_cached_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendLexerArtifact
      verifiedFrontendLexerParseView 0
      verifiedFrontendLexerArtifact.parse_nodes = true := by
  change checkNodesFromParseView laniusGrammar verifiedFrontendLexerArtifact
    verifiedFrontendLexerParseView 0
    (verifiedFrontendLexerParseNodes0 ++
      (verifiedFrontendLexerParseNodes1 ++
      (verifiedFrontendLexerParseNodes2 ++
      (verifiedFrontendLexerParseNodes3 ++
      (verifiedFrontendLexerParseNodes4 ++
      (verifiedFrontendLexerParseNodes5 ++
        verifiedFrontendLexerParseNodes6)))))) = true
  rw [checkNodesFromParseView_append,
    verifiedFrontendLexer_parse_nodes_0_checked_kernel,
    verifiedFrontendLexer_parse_nodes_0_length_kernel]
  simp only [Bool.true_and, Nat.zero_add]
  rw [checkNodesFromParseView_append,
    verifiedFrontendLexer_parse_nodes_1_checked_kernel,
    verifiedFrontendLexer_parse_nodes_1_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendLexer_parse_nodes_2_checked_kernel,
    verifiedFrontendLexer_parse_nodes_2_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendLexer_parse_nodes_3_checked_kernel,
    verifiedFrontendLexer_parse_nodes_3_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendLexer_parse_nodes_4_checked_kernel,
    verifiedFrontendLexer_parse_nodes_4_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromParseView_append,
    verifiedFrontendLexer_parse_nodes_5_checked_kernel,
    verifiedFrontendLexer_parse_nodes_5_length_kernel]
  simpa only [Bool.true_and] using
    verifiedFrontendLexer_parse_nodes_6_checked_kernel

theorem verifiedFrontendLexer_parse_nodes_checked_kernel :
    checkNodesFrom laniusGrammar
      verifiedFrontendLexerArtifact.semantic_token_kinds
      verifiedFrontendLexerArtifact.parse_nodes 0
      verifiedFrontendLexerArtifact.parse_nodes = true := by
  rw [← checkNodesFromView_eq laniusGrammar verifiedFrontendLexerArtifact
    verifiedFrontendLexerView]
  change checkNodesFromView laniusGrammar verifiedFrontendLexerArtifact
    verifiedFrontendLexerParseView.artifactView 0
    verifiedFrontendLexerArtifact.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar verifiedFrontendLexerArtifact
    verifiedFrontendLexerParseView]
  exact verifiedFrontendLexer_parse_nodes_cached_checked_kernel

end Lanius.Extraction
