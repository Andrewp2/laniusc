import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.ViewSemanticWell
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.ViewSemanticRep
import Lanius.Extraction.ParseChecker
namespace Lanius.Extraction
def verifiedFrontendCanonicalTokensParseView :
    ParseArtifactView verifiedFrontendCanonicalTokensArtifact := {
  artifactView := verifiedFrontendCanonicalTokensView
  leafCapacity := 64
  semanticKinds := verifiedFrontendCanonicalTokensSemanticKindTree
  semanticKindsWellFormed :=
    verifiedFrontendCanonicalTokens_semantic_tree_well_formed_kernel
  semanticKindsRepresent :=
    verifiedFrontendCanonicalTokens_semantic_tree_represents_kernel
}
end Lanius.Extraction
