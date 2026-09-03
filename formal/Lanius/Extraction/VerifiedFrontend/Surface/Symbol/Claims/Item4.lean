import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_claims_item4_present_kernel :
    (collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 4)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolClaimsItem4Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 4)).get
    verifiedFrontendSymbol_claims_item4_present_kernel
theorem verifiedFrontendSymbol_claims_item4_found_kernel :
    collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 4) =
      some verifiedFrontendSymbolClaimsItem4Kernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_claims_item4_present_kernel
end Lanius.Extraction
