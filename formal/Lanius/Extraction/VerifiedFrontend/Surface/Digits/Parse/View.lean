import Lanius.Extraction.VerifiedFrontend.Surface.Digits.View.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Digits.Parse.ViewSemanticWell
import Lanius.Extraction.VerifiedFrontend.Surface.Digits.Parse.ViewSemanticRep
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
