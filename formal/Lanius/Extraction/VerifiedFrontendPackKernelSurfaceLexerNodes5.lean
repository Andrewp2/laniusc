import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerParseView

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_parse_nodes_5_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendLexerArtifact
      verifiedFrontendLexerParseView 5000
      verifiedFrontendLexerParseNodes5 = true := by
  with_unfolding_all rfl

theorem verifiedFrontendLexer_parse_nodes_5_length_kernel :
    verifiedFrontendLexerParseNodes5.length = 1000 := by
  with_unfolding_all rfl

end Lanius.Extraction
