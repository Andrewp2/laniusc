import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.View.Assembly
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_origin_spellings_checked_kernel :
    spellingOriginPathsValid verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanView
      (verifiedFrontendTokenScanOrigins).claims.spellings (verifiedFrontendTokenScanOrigins).spellingPaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
