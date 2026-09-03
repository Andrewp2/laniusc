import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_claims_item0_present_kernel :
    (collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 0)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolClaimsItem0Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 0)).get
    verifiedFrontendSymbol_claims_item0_present_kernel
theorem verifiedFrontendSymbol_claims_item0_found_kernel :
    collectItemClaimsWithFuel 1265 8243 (verifiedFrontendSymbolProposedItemKernel 0) =
      some verifiedFrontendSymbolClaimsItem0Kernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_claims_item0_present_kernel
end Lanius.Extraction
