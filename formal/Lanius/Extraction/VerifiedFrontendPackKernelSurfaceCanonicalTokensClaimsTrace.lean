import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensReconstructionTrace
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensClaimsItem0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensClaimsItem1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensClaimsItem2
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensClaimsItem3
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensClaimsItem4
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensClaimsItem5
namespace Lanius.Extraction
set_option maxRecDepth 500000
private theorem itemsDrop (index : Nat) (bounded : index < 6) :
    verifiedFrontendCanonicalTokensProposedItemsKernel.drop index =
      verifiedFrontendCanonicalTokensProposedItemKernel index :: verifiedFrontendCanonicalTokensProposedItemsKernel.drop (index + 1) := by
  have inBounds : index < verifiedFrontendCanonicalTokensProposedItemsKernel.length := by
    rw [verifiedFrontendCanonicalTokensProposedItemsKernel_length]
    exact bounded
  rw [List.drop_eq_getElem_cons inBounds]
  congr 1
  simpa [verifiedFrontendCanonicalTokensProposedItemKernel] using
    (getElem!_pos verifiedFrontendCanonicalTokensProposedItemsKernel index inBounds).symm

theorem verifiedFrontendCanonicalTokens_claims_items6_kernel :
    collectMany (collectItemClaimsWithFuel 1546 10310)
      (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 6) = some {} := by
  with_unfolding_all rfl
theorem verifiedFrontendCanonicalTokens_claims_items5_kernel :
    collectMany (collectItemClaimsWithFuel 1546 10310)
      (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 5) = some (verifiedFrontendCanonicalTokensClaimsItem5Kernel <+> ({})) := by
  rw [itemsDrop 5 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendCanonicalTokens_claims_item5_found_kernel, verifiedFrontendCanonicalTokens_claims_items6_kernel]
  rfl
theorem verifiedFrontendCanonicalTokens_claims_items4_kernel :
    collectMany (collectItemClaimsWithFuel 1546 10310)
      (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 4) = some (verifiedFrontendCanonicalTokensClaimsItem4Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem5Kernel <+> ({}))) := by
  rw [itemsDrop 4 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendCanonicalTokens_claims_item4_found_kernel, verifiedFrontendCanonicalTokens_claims_items5_kernel]
  rfl
theorem verifiedFrontendCanonicalTokens_claims_items3_kernel :
    collectMany (collectItemClaimsWithFuel 1546 10310)
      (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 3) = some (verifiedFrontendCanonicalTokensClaimsItem3Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem4Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem5Kernel <+> ({})))) := by
  rw [itemsDrop 3 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendCanonicalTokens_claims_item3_found_kernel, verifiedFrontendCanonicalTokens_claims_items4_kernel]
  rfl
theorem verifiedFrontendCanonicalTokens_claims_items2_kernel :
    collectMany (collectItemClaimsWithFuel 1546 10310)
      (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 2) = some (verifiedFrontendCanonicalTokensClaimsItem2Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem3Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem4Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem5Kernel <+> ({}))))) := by
  rw [itemsDrop 2 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendCanonicalTokens_claims_item2_found_kernel, verifiedFrontendCanonicalTokens_claims_items3_kernel]
  rfl
theorem verifiedFrontendCanonicalTokens_claims_items1_kernel :
    collectMany (collectItemClaimsWithFuel 1546 10310)
      (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 1) = some (verifiedFrontendCanonicalTokensClaimsItem1Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem2Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem3Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem4Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem5Kernel <+> ({})))))) := by
  rw [itemsDrop 1 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendCanonicalTokens_claims_item1_found_kernel, verifiedFrontendCanonicalTokens_claims_items2_kernel]
  rfl
theorem verifiedFrontendCanonicalTokens_claims_items0_kernel :
    collectMany (collectItemClaimsWithFuel 1546 10310)
      (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 0) = some (verifiedFrontendCanonicalTokensClaimsItem0Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem1Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem2Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem3Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem4Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem5Kernel <+> ({}))))))) := by
  rw [itemsDrop 0 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendCanonicalTokens_claims_item0_found_kernel, verifiedFrontendCanonicalTokens_claims_items1_kernel]
  rfl
def verifiedFrontendCanonicalTokensClaimsTraceKernel : SurfaceClaims :=
  (verifiedFrontendCanonicalTokensClaimsItem0Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem1Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem2Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem3Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem4Kernel <+> (verifiedFrontendCanonicalTokensClaimsItem5Kernel <+> ({}))))))) <+> SurfaceClaims.node 1609 10310 none [0]
theorem verifiedFrontendCanonicalTokens_claims_trace_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendCanonicalTokensArtifact verifiedFrontendCanonicalTokensReconstructedTraceKernel =
      some verifiedFrontendCanonicalTokensClaimsTraceKernel := by
  unfold collectSurfaceClaimsFrom verifiedFrontendCanonicalTokensReconstructedTraceKernel
  rw [show verifiedFrontendCanonicalTokensArtifact.tokens.length + 1 = 1546 by with_unfolding_all rfl]
  change (collectMany (collectItemClaimsWithFuel 1546 10310)
      verifiedFrontendCanonicalTokensProposedItemsKernel).bind
    (fun items => some (items <+> SurfaceClaims.node 1609 10310 none [0])) =
      some verifiedFrontendCanonicalTokensClaimsTraceKernel
  have itemsFound := verifiedFrontendCanonicalTokens_claims_items0_kernel
  simp only [List.drop_zero] at itemsFound
  rw [itemsFound]
  rfl
end Lanius.Extraction
