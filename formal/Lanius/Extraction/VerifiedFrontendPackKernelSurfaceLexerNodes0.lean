import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerSemantic

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_parse_nodes_0_checked_kernel :
    checkNodesFromChunks laniusGrammar
      verifiedFrontendLexerArtifact.semantic_token_kinds
      verifiedFrontendLexerNodeChunks 0
      verifiedFrontendLexerParseNodes0 = true := by
  cbv

theorem verifiedFrontendLexer_parse_nodes_0_length_kernel :
    verifiedFrontendLexerParseNodes0.length = 1000 := by
  cbv

end Lanius.Extraction
