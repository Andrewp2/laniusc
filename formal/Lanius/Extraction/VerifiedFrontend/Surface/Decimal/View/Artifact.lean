import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.Decimal.Cache.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.Decimal.Artifact

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendDecimal_cache_checked_kernel :
    verifiedFrontendDecimalCache.matches verifiedFrontendDecimalArtifact = true := by
  apply ArtifactCache.matches_of_sharedNodes
  · rfl
  · kernel_rfl
def verifiedFrontendDecimalView : ArtifactView verifiedFrontendDecimalArtifact :=
  verifiedFrontendDecimalCache.ofMatches
    verifiedFrontendDecimal_cache_checked_kernel

end Lanius.Extraction
