import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensView
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensParseViewSemanticWell
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensParseViewSemanticRep
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
