import Lanius.Extraction.VerifiedFrontendUnitDigitsOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigitsView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_coverage_checked_kernel :
    spellingCoverageValid verifiedFrontendDigitsArtifact (verifiedFrontendDigitsOrigins).claims = true := by
  with_unfolding_all rfl
end Lanius.Extraction
