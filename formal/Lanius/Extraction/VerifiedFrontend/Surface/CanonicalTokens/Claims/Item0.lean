import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_claims_item0_present_kernel :
    (collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 0)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensClaimsItem0Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 0)).get
    verifiedFrontendCanonicalTokens_claims_item0_present_kernel
theorem verifiedFrontendCanonicalTokens_claims_item0_found_kernel :
    collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 0) =
      some verifiedFrontendCanonicalTokensClaimsItem0Kernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_claims_item0_present_kernel
end Lanius.Extraction
