import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.View.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Parse.View.Semantic.WellFormed
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Parse.View.Semantic.Representation
import Lanius.Extraction.ParseChecker
namespace Lanius.Extraction
def verifiedFrontendDecimalParseView : ParseArtifactView verifiedFrontendDecimalArtifact := {
  artifactView := verifiedFrontendDecimalView
  leafCapacity := 64
  semanticKinds := verifiedFrontendDecimalSemanticKindTree
  semanticKindsWellFormed := verifiedFrontendDecimal_semantic_tree_well_formed_kernel
  semanticKindsRepresent := verifiedFrontendDecimal_semantic_tree_represents_kernel
}
end Lanius.Extraction
