import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_claims_item2_present_kernel :
    (collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 2)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensClaimsItem2Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 2)).get
    verifiedFrontendCanonicalTokens_claims_item2_present_kernel
theorem verifiedFrontendCanonicalTokens_claims_item2_found_kernel :
    collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 2) =
      some verifiedFrontendCanonicalTokensClaimsItem2Kernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_claims_item2_present_kernel
end Lanius.Extraction
