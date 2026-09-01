import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructParseRoot

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexer_parse_nodes_length_kernel :
    verifiedFrontendLexerArtifact.parse_nodes.length = 6991 := by
  have chunksEqual :
      verifiedFrontendLexerNodeChunks.flatten =
        verifiedFrontendLexerArtifact.parse_nodes := by
    exact verifiedFrontendLexer_parse_node_chunks_valid_kernel
  rw [← chunksEqual]
  simp [verifiedFrontendLexerNodeChunks,
    verifiedFrontendLexerParseNodes0_length,
    verifiedFrontendLexerParseNodes1_length,
    verifiedFrontendLexerParseNodes2_length,
    verifiedFrontendLexerParseNodes3_length,
    verifiedFrontendLexerParseNodes4_length,
    verifiedFrontendLexerParseNodes5_length,
    verifiedFrontendLexerParseNodes6_length]

end Lanius.Extraction
