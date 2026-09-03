import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_claims_item4_present_kernel :
    (collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 4)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensClaimsItem4Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 4)).get
    verifiedFrontendCanonicalTokens_claims_item4_present_kernel
theorem verifiedFrontendCanonicalTokens_claims_item4_found_kernel :
    collectItemClaimsWithFuel 1546 10310 (verifiedFrontendCanonicalTokensProposedItemKernel 4) =
      some verifiedFrontendCanonicalTokensClaimsItem4Kernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_claims_item4_present_kernel
end Lanius.Extraction
