import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolReconstructionTrace
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolClaimsItem0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolClaimsItem1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolClaimsItem2
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolClaimsItem3
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolClaimsItem4
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolClaimsItem5
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolClaimsItem6
namespace Lanius.Extraction
set_option maxRecDepth 500000
private theorem itemsDrop (index : Nat) (bounded : index < 7) :
    verifiedFrontendSymbolProposedItemsKernel.drop index =
      verifiedFrontendSymbolProposedItemKernel index :: verifiedFrontendSymbolProposedItemsKernel.drop (index + 1) := by
  have inBounds : index < verifiedFrontendSymbolProposedItemsKernel.length := by
    rw [verifiedFrontendSymbolProposedItemsKernel_length]
    exact bounded
  rw [List.drop_eq_getElem_cons inBounds]
  congr 1
  simpa [verifiedFrontendSymbolProposedItemKernel] using
    (getElem!_pos verifiedFrontendSymbolProposedItemsKernel index inBounds).symm

theorem verifiedFrontendSymbol_claims_items7_kernel :
    collectMany (collectItemClaimsWithFuel 1265 8243)
      (verifiedFrontendSymbolProposedItemsKernel.drop 7) = some {} := by
  with_unfolding_all rfl
theorem verifiedFrontendSymbol_claims_items6_kernel :
    collectMany (collectItemClaimsWithFuel 1265 8243)
      (verifiedFrontendSymbolProposedItemsKernel.drop 6) = some (verifiedFrontendSymbolClaimsItem6Kernel <+> ({})) := by
  rw [itemsDrop 6 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendSymbol_claims_item6_found_kernel, verifiedFrontendSymbol_claims_items7_kernel]
  rfl
theorem verifiedFrontendSymbol_claims_items5_kernel :
    collectMany (collectItemClaimsWithFuel 1265 8243)
      (verifiedFrontendSymbolProposedItemsKernel.drop 5) = some (verifiedFrontendSymbolClaimsItem5Kernel <+> (verifiedFrontendSymbolClaimsItem6Kernel <+> ({}))) := by
  rw [itemsDrop 5 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendSymbol_claims_item5_found_kernel, verifiedFrontendSymbol_claims_items6_kernel]
  rfl
theorem verifiedFrontendSymbol_claims_items4_kernel :
    collectMany (collectItemClaimsWithFuel 1265 8243)
      (verifiedFrontendSymbolProposedItemsKernel.drop 4) = some (verifiedFrontendSymbolClaimsItem4Kernel <+> (verifiedFrontendSymbolClaimsItem5Kernel <+> (verifiedFrontendSymbolClaimsItem6Kernel <+> ({})))) := by
  rw [itemsDrop 4 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendSymbol_claims_item4_found_kernel, verifiedFrontendSymbol_claims_items5_kernel]
  rfl
theorem verifiedFrontendSymbol_claims_items3_kernel :
    collectMany (collectItemClaimsWithFuel 1265 8243)
      (verifiedFrontendSymbolProposedItemsKernel.drop 3) = some (verifiedFrontendSymbolClaimsItem3Kernel <+> (verifiedFrontendSymbolClaimsItem4Kernel <+> (verifiedFrontendSymbolClaimsItem5Kernel <+> (verifiedFrontendSymbolClaimsItem6Kernel <+> ({}))))) := by
  rw [itemsDrop 3 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendSymbol_claims_item3_found_kernel, verifiedFrontendSymbol_claims_items4_kernel]
  rfl
theorem verifiedFrontendSymbol_claims_items2_kernel :
    collectMany (collectItemClaimsWithFuel 1265 8243)
      (verifiedFrontendSymbolProposedItemsKernel.drop 2) = some (verifiedFrontendSymbolClaimsItem2Kernel <+> (verifiedFrontendSymbolClaimsItem3Kernel <+> (verifiedFrontendSymbolClaimsItem4Kernel <+> (verifiedFrontendSymbolClaimsItem5Kernel <+> (verifiedFrontendSymbolClaimsItem6Kernel <+> ({})))))) := by
  rw [itemsDrop 2 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendSymbol_claims_item2_found_kernel, verifiedFrontendSymbol_claims_items3_kernel]
  rfl
theorem verifiedFrontendSymbol_claims_items1_kernel :
    collectMany (collectItemClaimsWithFuel 1265 8243)
      (verifiedFrontendSymbolProposedItemsKernel.drop 1) = some (verifiedFrontendSymbolClaimsItem1Kernel <+> (verifiedFrontendSymbolClaimsItem2Kernel <+> (verifiedFrontendSymbolClaimsItem3Kernel <+> (verifiedFrontendSymbolClaimsItem4Kernel <+> (verifiedFrontendSymbolClaimsItem5Kernel <+> (verifiedFrontendSymbolClaimsItem6Kernel <+> ({}))))))) := by
  rw [itemsDrop 1 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendSymbol_claims_item1_found_kernel, verifiedFrontendSymbol_claims_items2_kernel]
  rfl
theorem verifiedFrontendSymbol_claims_items0_kernel :
    collectMany (collectItemClaimsWithFuel 1265 8243)
      (verifiedFrontendSymbolProposedItemsKernel.drop 0) = some (verifiedFrontendSymbolClaimsItem0Kernel <+> (verifiedFrontendSymbolClaimsItem1Kernel <+> (verifiedFrontendSymbolClaimsItem2Kernel <+> (verifiedFrontendSymbolClaimsItem3Kernel <+> (verifiedFrontendSymbolClaimsItem4Kernel <+> (verifiedFrontendSymbolClaimsItem5Kernel <+> (verifiedFrontendSymbolClaimsItem6Kernel <+> ({})))))))) := by
  rw [itemsDrop 0 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendSymbol_claims_item0_found_kernel, verifiedFrontendSymbol_claims_items1_kernel]
  rfl
def verifiedFrontendSymbolClaimsTraceKernel : SurfaceClaims :=
  (verifiedFrontendSymbolClaimsItem0Kernel <+> (verifiedFrontendSymbolClaimsItem1Kernel <+> (verifiedFrontendSymbolClaimsItem2Kernel <+> (verifiedFrontendSymbolClaimsItem3Kernel <+> (verifiedFrontendSymbolClaimsItem4Kernel <+> (verifiedFrontendSymbolClaimsItem5Kernel <+> (verifiedFrontendSymbolClaimsItem6Kernel <+> ({})))))))) <+> SurfaceClaims.node 999 8243 none [0]
theorem verifiedFrontendSymbol_claims_trace_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendSymbolArtifact verifiedFrontendSymbolReconstructedTraceKernel =
      some verifiedFrontendSymbolClaimsTraceKernel := by
  unfold collectSurfaceClaimsFrom verifiedFrontendSymbolReconstructedTraceKernel
  rw [show verifiedFrontendSymbolArtifact.tokens.length + 1 = 1265 by with_unfolding_all rfl]
  change (collectMany (collectItemClaimsWithFuel 1265 8243)
      verifiedFrontendSymbolProposedItemsKernel).bind
    (fun items => some (items <+> SurfaceClaims.node 999 8243 none [0])) =
      some verifiedFrontendSymbolClaimsTraceKernel
  have itemsFound := verifiedFrontendSymbol_claims_items0_kernel
  simp only [List.drop_zero] at itemsFound
  rw [itemsFound]
  rfl
end Lanius.Extraction
