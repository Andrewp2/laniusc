import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerNodes5

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_parse_nodes_6_checked_kernel :
    checkNodesFromChunks laniusGrammar
      verifiedFrontendLexerArtifact.semantic_token_kinds
      verifiedFrontendLexerNodeChunks 6000
      verifiedFrontendLexerParseNodes6 = true := by
  cbv

end Lanius.Extraction
