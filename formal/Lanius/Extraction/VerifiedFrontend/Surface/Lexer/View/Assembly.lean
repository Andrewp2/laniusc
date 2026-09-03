import Lanius.Extraction.VerifiedFrontend.Artifact.Lexer.Cache.Assembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_parse_tree_well_formed_kernel :
    verifiedFrontendLexerParseNodeTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendLexer_parse_tree_represents_kernel :
    verifiedFrontendLexerParseNodeTree.Represents
      verifiedFrontendLexerArtifact.parse_nodes := by
  with_unfolding_all rfl

theorem verifiedFrontendLexer_token_tree_well_formed_kernel :
    verifiedFrontendLexerTokenTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendLexer_token_tree_represents_kernel :
    verifiedFrontendLexerTokenTree.Represents
      verifiedFrontendLexerArtifact.tokens := by
  with_unfolding_all rfl

theorem verifiedFrontendLexer_source_tree_well_formed_kernel :
    verifiedFrontendLexerSourceByteTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendLexer_source_tree_represents_kernel :
    ∀ source, verifiedFrontendLexerArtifact.sources[0]? = some source →
      decodeBytes source.bytes =
        some verifiedFrontendLexerSourceByteTree.flatten := by
  intro source found
  with_unfolding_all
    injection found with sourceEq
    subst source
    rfl

def verifiedFrontendLexerView : ArtifactView verifiedFrontendLexerArtifact := {
  cache := verifiedFrontendLexerCache
  parseNodesWellFormed := verifiedFrontendLexer_parse_tree_well_formed_kernel
  parseNodesRepresent := verifiedFrontendLexer_parse_tree_represents_kernel
  tokensWellFormed := verifiedFrontendLexer_token_tree_well_formed_kernel
  tokensRepresent := verifiedFrontendLexer_token_tree_represents_kernel
  sourceBytesWellFormed := verifiedFrontendLexer_source_tree_well_formed_kernel
  sourceBytesRepresent := verifiedFrontendLexer_source_tree_represents_kernel
}

end Lanius.Extraction
