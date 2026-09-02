import Lanius.Extraction.VerifiedFrontendUnitTokenScanOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceTokenScanView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_coverage_checked_kernel :
    spellingCoverageValid verifiedFrontendTokenScanArtifact (verifiedFrontendTokenScanOrigins).claims = true := by
  with_unfolding_all rfl
end Lanius.Extraction
