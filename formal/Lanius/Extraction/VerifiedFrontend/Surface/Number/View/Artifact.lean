import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.Number.Cache.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.Number.Artifact

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendNumber_cache_checked_kernel :
    verifiedFrontendNumberCache.matches verifiedFrontendNumberArtifact = true := by
  apply ArtifactCache.matches_of_sharedNodes
  · rfl
  · kernel_rfl
def verifiedFrontendNumberView : ArtifactView verifiedFrontendNumberArtifact :=
  verifiedFrontendNumberCache.ofMatches
    verifiedFrontendNumber_cache_checked_kernel

end Lanius.Extraction
