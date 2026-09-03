import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.View.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Parse.View.Semantic.WellFormed
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Parse.View.Semantic.Representation
import Lanius.Extraction.ParseChecker
namespace Lanius.Extraction
def verifiedFrontendLexerParseView : ParseArtifactView verifiedFrontendLexerArtifact := {
  artifactView := verifiedFrontendLexerView
  leafCapacity := 64
  semanticKinds := verifiedFrontendLexerSemanticKindTree
  semanticKindsWellFormed := verifiedFrontendLexer_semantic_tree_well_formed_kernel
  semanticKindsRepresent := verifiedFrontendLexer_semantic_tree_represents_kernel
}
end Lanius.Extraction
