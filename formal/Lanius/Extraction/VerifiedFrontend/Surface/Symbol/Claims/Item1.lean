import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_claims_item1_present_kernel :
    (collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 1)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolClaimsItem1Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 1)).get
    verifiedFrontendSymbol_claims_item1_present_kernel
theorem verifiedFrontendSymbol_claims_item1_found_kernel :
    collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 1) =
      some verifiedFrontendSymbolClaimsItem1Kernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_claims_item1_present_kernel
end Lanius.Extraction
