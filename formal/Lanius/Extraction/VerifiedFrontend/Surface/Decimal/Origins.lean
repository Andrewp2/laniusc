import Lanius.Extraction.KernelReduction
import Lanius.Extraction.Surface.Views
import Lanius.Extraction.VerifiedFrontend.Artifact.Decimal.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Claims

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendDecimal_origins_checked_kernel :
    verifiedFrontendDecimalOrigins.valid verifiedFrontendDecimalArtifact
      verifiedFrontendDecimalView = true := by
  apply SurfaceOrigins.valid_of_components <;> try kernel_rfl
  apply spellingCoverageValid_of_multiset
  kernel_rfl

end Lanius.Extraction
