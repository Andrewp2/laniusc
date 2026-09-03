import Lanius.Extraction.VerifiedFrontend.Artifact.Lexer.Cache.Semantic
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendLexer_semantic_tree_represents_kernel :
    verifiedFrontendLexerSemanticKindTree.Represents
      verifiedFrontendLexerArtifact.semantic_token_kinds := by
  with_unfolding_all rfl
end Lanius.Extraction
