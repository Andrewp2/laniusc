import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_claims_item3_present_kernel :
    (collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 3)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolClaimsItem3Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 3)).get
    verifiedFrontendSymbol_claims_item3_present_kernel
theorem verifiedFrontendSymbol_claims_item3_found_kernel :
    collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 3) =
      some verifiedFrontendSymbolClaimsItem3Kernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_claims_item3_present_kernel
end Lanius.Extraction
