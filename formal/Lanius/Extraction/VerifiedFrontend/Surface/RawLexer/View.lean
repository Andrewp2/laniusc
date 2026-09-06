import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Artifact
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Semantic
import Lanius.Extraction.ParseChecker

namespace Lanius.Extraction
def verifiedFrontendRawLexerParseView : ParseArtifactView verifiedFrontendRawLexerArtifact := {
  artifactView := verifiedFrontendRawLexerView
  leafCapacity := 64
  semanticKinds := verifiedFrontendRawLexerSemanticKindTree
  semanticKindsWellFormed := verifiedFrontendRawLexer_semantic_tree_well_formed_kernel
  semanticKindsRepresent := verifiedFrontendRawLexer_semantic_tree_represents_kernel
}
end Lanius.Extraction

