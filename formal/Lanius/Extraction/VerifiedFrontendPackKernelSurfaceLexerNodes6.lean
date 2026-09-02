import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerParseView

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_parse_nodes_6_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendLexerArtifact
      verifiedFrontendLexerParseView 6000
      verifiedFrontendLexerParseNodes6 = true := by
  with_unfolding_all rfl

end Lanius.Extraction
