import Lanius.Extraction.VerifiedFrontend.Surface.Digits.View.Artifact
import Lanius.Extraction.VerifiedFrontend.Surface.Digits.View.Semantic
import Lanius.Extraction.ParseChecker

namespace Lanius.Extraction
def verifiedFrontendDigitsParseView : ParseArtifactView verifiedFrontendDigitsArtifact := {
  artifactView := verifiedFrontendDigitsView
  leafCapacity := 64
  semanticKinds := verifiedFrontendDigitsSemanticKindTree
  semanticKindsWellFormed := verifiedFrontendDigits_semantic_tree_well_formed_kernel
  semanticKindsRepresent := verifiedFrontendDigits_semantic_tree_represents_kernel
}
end Lanius.Extraction

