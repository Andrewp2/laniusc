import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Artifact.Digits.Cache.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.Digits.Artifact

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendDigits_cache_checked_kernel :
    verifiedFrontendDigitsCache.matches verifiedFrontendDigitsArtifact = true := by
  apply ArtifactCache.matches_of_sharedNodes
  · rfl
  · kernel_rfl
def verifiedFrontendDigitsView : ArtifactView verifiedFrontendDigitsArtifact :=
  verifiedFrontendDigitsCache.ofMatches
    verifiedFrontendDigits_cache_checked_kernel

end Lanius.Extraction
