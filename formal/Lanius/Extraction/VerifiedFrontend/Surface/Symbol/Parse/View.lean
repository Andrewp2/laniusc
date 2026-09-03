import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Parse.ViewSemanticWell
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Parse.ViewSemanticRep
import Lanius.Extraction.ParseChecker
namespace Lanius.Extraction
def verifiedFrontendSymbolParseView : ParseArtifactView verifiedFrontendSymbolArtifact := {
  artifactView := verifiedFrontendSymbolView
  leafCapacity := 64
  semanticKinds := verifiedFrontendSymbolSemanticKindTree
  semanticKindsWellFormed := verifiedFrontendSymbol_semantic_tree_well_formed_kernel
  semanticKindsRepresent := verifiedFrontendSymbol_semantic_tree_represents_kernel
}
end Lanius.Extraction
