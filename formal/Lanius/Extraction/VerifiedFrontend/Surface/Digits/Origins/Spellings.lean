import Lanius.Extraction.VerifiedFrontend.Artifact.Digits.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Digits.View.Assembly
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_origin_spellings_checked_kernel :
    spellingOriginPathsValid verifiedFrontendDigitsArtifact verifiedFrontendDigitsView
      (verifiedFrontendDigitsOrigins).claims.spellings (verifiedFrontendDigitsOrigins).spellingPaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
