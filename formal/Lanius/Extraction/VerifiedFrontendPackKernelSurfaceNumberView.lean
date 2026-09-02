import Lanius.Extraction.VerifiedFrontendUnitNumberCache

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendNumber_cache_checked_kernel :
    verifiedFrontendNumberCache.matches verifiedFrontendNumberArtifact = true := by
  with_unfolding_all rfl
def verifiedFrontendNumberView : ArtifactView verifiedFrontendNumberArtifact :=
  verifiedFrontendNumberCache.ofMatches
    verifiedFrontendNumber_cache_checked_kernel

end Lanius.Extraction
