import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_claims_item3_present_kernel :
    (collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 3)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensClaimsItem3Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 3)).get
    verifiedFrontendCanonicalTokens_claims_item3_present_kernel
theorem verifiedFrontendCanonicalTokens_claims_item3_found_kernel :
    collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 3) =
      some verifiedFrontendCanonicalTokensClaimsItem3Kernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_claims_item3_present_kernel
end Lanius.Extraction
