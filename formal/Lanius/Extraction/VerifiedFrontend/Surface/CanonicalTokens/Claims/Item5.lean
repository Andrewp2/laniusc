import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_claims_item5_present_kernel :
    (collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 5)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensClaimsItem5Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 5)).get
    verifiedFrontendCanonicalTokens_claims_item5_present_kernel
theorem verifiedFrontendCanonicalTokens_claims_item5_found_kernel :
    collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 5) =
      some verifiedFrontendCanonicalTokensClaimsItem5Kernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_claims_item5_present_kernel
end Lanius.Extraction
