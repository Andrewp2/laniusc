import Lanius.Extraction.VerifiedFrontendUnitDigitsOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigitsView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_origin_spellings_checked_kernel :
    spellingOriginPathsValid verifiedFrontendDigitsArtifact verifiedFrontendDigitsView
      (verifiedFrontendDigitsOrigins).claims.spellings (verifiedFrontendDigitsOrigins).spellingPaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
