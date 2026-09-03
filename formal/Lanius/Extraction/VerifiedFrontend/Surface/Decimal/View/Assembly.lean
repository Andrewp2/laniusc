import Lanius.Extraction.VerifiedFrontend.Artifact.Decimal.Cache.Assembly

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendDecimal_cache_checked_kernel :
    verifiedFrontendDecimalCache.matches verifiedFrontendDecimalArtifact = true := by
  with_unfolding_all rfl
def verifiedFrontendDecimalView : ArtifactView verifiedFrontendDecimalArtifact :=
  verifiedFrontendDecimalCache.ofMatches
    verifiedFrontendDecimal_cache_checked_kernel

end Lanius.Extraction
