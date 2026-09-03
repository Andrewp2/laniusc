import Lanius.Extraction.VerifiedFrontend.Artifact.Token.Cache.Assembly

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendToken_cache_checked_kernel :
    verifiedFrontendTokenCache.matches verifiedFrontendTokenArtifact = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenView : ArtifactView verifiedFrontendTokenArtifact :=
  verifiedFrontendTokenCache.ofMatches
    verifiedFrontendToken_cache_checked_kernel

end Lanius.Extraction
