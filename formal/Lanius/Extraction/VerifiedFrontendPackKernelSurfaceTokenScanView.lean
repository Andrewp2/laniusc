import Lanius.Extraction.VerifiedFrontendUnitTokenScanCache

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendTokenScan_cache_checked_kernel :
    verifiedFrontendTokenScanCache.matches
      verifiedFrontendTokenScanArtifact = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenScanView :
    ArtifactView verifiedFrontendTokenScanArtifact := {
  cache := verifiedFrontendTokenScanCache
  parseNodesWellFormed :=
    (verifiedFrontendTokenScanCache.ofMatches
      verifiedFrontendTokenScan_cache_checked_kernel).parseNodesWellFormed
  parseNodesRepresent :=
    (verifiedFrontendTokenScanCache.ofMatches
      verifiedFrontendTokenScan_cache_checked_kernel).parseNodesRepresent
  tokensWellFormed :=
    (verifiedFrontendTokenScanCache.ofMatches
      verifiedFrontendTokenScan_cache_checked_kernel).tokensWellFormed
  tokensRepresent :=
    (verifiedFrontendTokenScanCache.ofMatches
      verifiedFrontendTokenScan_cache_checked_kernel).tokensRepresent
  sourceBytesWellFormed :=
    (verifiedFrontendTokenScanCache.ofMatches
      verifiedFrontendTokenScan_cache_checked_kernel).sourceBytesWellFormed
  sourceBytesRepresent :=
    (verifiedFrontendTokenScanCache.ofMatches
      verifiedFrontendTokenScan_cache_checked_kernel).sourceBytesRepresent
}

end Lanius.Extraction
