import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.View.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.ViewSemanticWell
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Parse.ViewSemanticRep
import Lanius.Extraction.ParseChecker
namespace Lanius.Extraction
def verifiedFrontendTokenScanParseView : ParseArtifactView verifiedFrontendTokenScanArtifact := {
  artifactView := verifiedFrontendTokenScanView
  leafCapacity := 64
  semanticKinds := verifiedFrontendTokenScanSemanticKindTree
  semanticKindsWellFormed := verifiedFrontendTokenScan_semantic_tree_well_formed_kernel
  semanticKindsRepresent := verifiedFrontendTokenScan_semantic_tree_represents_kernel
}
end Lanius.Extraction
