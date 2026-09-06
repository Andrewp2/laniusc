import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.View
import Lanius.Extraction.Reconstruction.Validated
import Lanius.Extraction.KernelReduction
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
def comparisonSurface : SurfaceFile := verifiedFrontendTokenScanArtifact.surface.get (by kernel_rfl)
set_option profiler true in
theorem comparisonAccepted :
 Reconstruction.Validated.checkedView laniusGrammar verifiedFrontendTokenScanParseView =
 some comparisonSurface := by kernel_rfl
theorem comparisonSound :
 checkNodesFromParseView laniusGrammar verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanParseView 0 verifiedFrontendTokenScanArtifact.parse_nodes = true ∧
 reconstructArtifactSurfaceView verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanView = some comparisonSurface :=
 Reconstruction.Validated.checkedView_sound laniusGrammar verifiedFrontendTokenScanParseView comparisonSurface comparisonAccepted
#print axioms comparisonSound
end Lanius.Extraction


