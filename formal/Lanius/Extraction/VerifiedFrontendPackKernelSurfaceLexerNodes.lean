import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerNodes6

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_parse_nodes_fast_checked_kernel :
    checkNodesFromChunks laniusGrammar
      verifiedFrontendLexerArtifact.semantic_token_kinds
      verifiedFrontendLexerNodeChunks 0
      verifiedFrontendLexerArtifact.parse_nodes = true := by
  change checkNodesFromChunks laniusGrammar
    verifiedFrontendLexerArtifact.semantic_token_kinds
    verifiedFrontendLexerNodeChunks 0
    (verifiedFrontendLexerParseNodes0 ++
      (verifiedFrontendLexerParseNodes1 ++
      (verifiedFrontendLexerParseNodes2 ++
      (verifiedFrontendLexerParseNodes3 ++
      (verifiedFrontendLexerParseNodes4 ++
      (verifiedFrontendLexerParseNodes5 ++
        verifiedFrontendLexerParseNodes6)))))) = true
  rw [checkNodesFromChunks_append,
    verifiedFrontendLexer_parse_nodes_0_checked_kernel,
    verifiedFrontendLexer_parse_nodes_0_length_kernel]
  simp only [Bool.true_and, Nat.zero_add]
  rw [checkNodesFromChunks_append,
    verifiedFrontendLexer_parse_nodes_1_checked_kernel,
    verifiedFrontendLexer_parse_nodes_1_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromChunks_append,
    verifiedFrontendLexer_parse_nodes_2_checked_kernel,
    verifiedFrontendLexer_parse_nodes_2_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromChunks_append,
    verifiedFrontendLexer_parse_nodes_3_checked_kernel,
    verifiedFrontendLexer_parse_nodes_3_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromChunks_append,
    verifiedFrontendLexer_parse_nodes_4_checked_kernel,
    verifiedFrontendLexer_parse_nodes_4_length_kernel]
  simp only [Bool.true_and]
  rw [checkNodesFromChunks_append,
    verifiedFrontendLexer_parse_nodes_5_checked_kernel,
    verifiedFrontendLexer_parse_nodes_5_length_kernel]
  simpa only [Bool.true_and] using
    verifiedFrontendLexer_parse_nodes_6_checked_kernel

theorem verifiedFrontendLexer_parse_nodes_checked_kernel :
    checkNodesFrom laniusGrammar
      verifiedFrontendLexerArtifact.semantic_token_kinds
      verifiedFrontendLexerArtifact.parse_nodes 0
      verifiedFrontendLexerArtifact.parse_nodes = true := by
  change checkNodesFrom laniusGrammar
    verifiedFrontendLexerArtifact.semantic_token_kinds
    verifiedFrontendLexerNodeChunks.flatten 0
    verifiedFrontendLexerNodeChunks.flatten = true
  rw [← checkNodesFromChunks_eq]
  exact verifiedFrontendLexer_parse_nodes_fast_checked_kernel

end Lanius.Extraction
