import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Parse.View

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_parse_nodes_2_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendLexerArtifact
      verifiedFrontendLexerParseView 2000
      verifiedFrontendLexerParseNodes2 = true := by
  with_unfolding_all rfl

theorem verifiedFrontendLexer_parse_nodes_2_length_kernel :
    verifiedFrontendLexerParseNodes2.length = 1000 := by
  with_unfolding_all rfl

end Lanius.Extraction
