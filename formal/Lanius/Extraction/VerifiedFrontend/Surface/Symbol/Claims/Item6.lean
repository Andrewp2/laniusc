import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_claims_item6_present_kernel :
    (collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 6)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolClaimsItem6Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 6)).get
    verifiedFrontendSymbol_claims_item6_present_kernel
theorem verifiedFrontendSymbol_claims_item6_found_kernel :
    collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 6) =
      some verifiedFrontendSymbolClaimsItem6Kernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_claims_item6_present_kernel
end Lanius.Extraction
