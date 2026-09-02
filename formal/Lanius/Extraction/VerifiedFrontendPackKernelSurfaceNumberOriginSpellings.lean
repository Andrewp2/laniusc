import Lanius.Extraction.VerifiedFrontendUnitNumberOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumberView
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
