import Lanius.Extraction.VerifiedFrontend.Artifact.Token.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Token.View.Assembly
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendToken_coverage_checked_kernel :
    spellingCoverageValid verifiedFrontendTokenArtifact (verifiedFrontendTokenOrigins).claims = true := by
  with_unfolding_all rfl
end Lanius.Extraction
