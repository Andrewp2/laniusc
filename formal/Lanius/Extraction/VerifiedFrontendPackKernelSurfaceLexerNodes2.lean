import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerNodes1

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_parse_nodes_2_checked_kernel :
    checkNodesFromChunks laniusGrammar
      verifiedFrontendLexerArtifact.semantic_token_kinds
      verifiedFrontendLexerNodeChunks 2000
      verifiedFrontendLexerParseNodes2 = true := by
  cbv

theorem verifiedFrontendLexer_parse_nodes_2_length_kernel :
    verifiedFrontendLexerParseNodes2.length = 1000 := by
  cbv

end Lanius.Extraction
