import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerNodes2

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_parse_nodes_3_checked_kernel :
    checkNodesFromChunks laniusGrammar
      verifiedFrontendLexerArtifact.semantic_token_kinds
      verifiedFrontendLexerNodeChunks 3000
      verifiedFrontendLexerParseNodes3 = true := by
  cbv

theorem verifiedFrontendLexer_parse_nodes_3_length_kernel :
    verifiedFrontendLexerParseNodes3.length = 1000 := by
  cbv

end Lanius.Extraction
