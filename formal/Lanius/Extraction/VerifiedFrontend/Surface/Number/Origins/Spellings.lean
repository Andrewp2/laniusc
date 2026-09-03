import Lanius.Extraction.VerifiedFrontend.Artifact.Number.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Number.View.Assembly
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_origin_spellings_checked_kernel :
    spellingOriginPathsValid verifiedFrontendNumberArtifact verifiedFrontendNumberView
      (verifiedFrontendNumberOrigins).claims.spellings
      (verifiedFrontendNumberOrigins).spellingPaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
