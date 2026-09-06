import Lanius.Extraction.VerifiedFrontend.Surface.Number.View.Artifact
import Lanius.Extraction.VerifiedFrontend.Surface.Number.View.Semantic
import Lanius.Extraction.ParseChecker

namespace Lanius.Extraction
def verifiedFrontendNumberParseView : ParseArtifactView verifiedFrontendNumberArtifact := {
  artifactView := verifiedFrontendNumberView
  leafCapacity := 64
  semanticKinds := verifiedFrontendNumberSemanticKindTree
  semanticKindsWellFormed := verifiedFrontendNumber_semantic_tree_well_formed_kernel
  semanticKindsRepresent := verifiedFrontendNumber_semantic_tree_represents_kernel
}
end Lanius.Extraction

