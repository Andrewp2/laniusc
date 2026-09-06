import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Reconstruction

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendLexer_parse_nodes_cached_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendLexerArtifact
      verifiedFrontendLexerParseView 0
      verifiedFrontendLexerArtifact.parse_nodes = true := by
  exact verifiedFrontendLexer_validated_nodes_kernel

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
