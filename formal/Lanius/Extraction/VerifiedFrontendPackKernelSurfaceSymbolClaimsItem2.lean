import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_claims_item2_present_kernel :
    (collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 2)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolClaimsItem2Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 2)).get
    verifiedFrontendSymbol_claims_item2_present_kernel
theorem verifiedFrontendSymbol_claims_item2_found_kernel :
    collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 2) =
      some verifiedFrontendSymbolClaimsItem2Kernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_claims_item2_present_kernel
end Lanius.Extraction
