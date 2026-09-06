import Lanius.Extraction.VerifiedFrontend.Surface.Token.View.Artifact
import Lanius.Extraction.VerifiedFrontend.Surface.Token.View.Semantic
import Lanius.Extraction.ParseChecker

namespace Lanius.Extraction
def verifiedFrontendTokenParseView : ParseArtifactView verifiedFrontendTokenArtifact := {
  artifactView := verifiedFrontendTokenView
  leafCapacity := 64
  semanticKinds := verifiedFrontendTokenSemanticKindTree
  semanticKindsWellFormed := verifiedFrontendToken_semantic_tree_well_formed_kernel
  semanticKindsRepresent := verifiedFrontendToken_semantic_tree_represents_kernel
}
end Lanius.Extraction

