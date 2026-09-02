import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionTrace
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem2
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem3
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem4
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem5
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem6
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem7
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem8
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem9
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem10
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem11
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem12
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem13
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem14
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem15
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem16
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerClaimsItem17
namespace Lanius.Extraction
set_option maxRecDepth 500000
private theorem itemsDrop (index : Nat) (bounded : index < 18) :
    verifiedFrontendRawLexerProposedItemsKernel.drop index =
      verifiedFrontendRawLexerProposedItemKernel index :: verifiedFrontendRawLexerProposedItemsKernel.drop (index + 1) := by
  have inBounds : index < verifiedFrontendRawLexerProposedItemsKernel.length := by
    rw [verifiedFrontendRawLexerProposedItemsKernel_length]
    exact bounded
  rw [List.drop_eq_getElem_cons inBounds]
  congr 1
  simpa [verifiedFrontendRawLexerProposedItemKernel] using
    (getElem!_pos verifiedFrontendRawLexerProposedItemsKernel index inBounds).symm

theorem verifiedFrontendRawLexer_claims_items18_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 18) = some {} := by
  with_unfolding_all rfl
theorem verifiedFrontendRawLexer_claims_items17_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 17) = some (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({})) := by
  rw [itemsDrop 17 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item17_found_kernel, verifiedFrontendRawLexer_claims_items18_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items16_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 16) = some (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({}))) := by
  rw [itemsDrop 16 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item16_found_kernel, verifiedFrontendRawLexer_claims_items17_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items15_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 15) = some (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({})))) := by
  rw [itemsDrop 15 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item15_found_kernel, verifiedFrontendRawLexer_claims_items16_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items14_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 14) = some (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({}))))) := by
  rw [itemsDrop 14 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item14_found_kernel, verifiedFrontendRawLexer_claims_items15_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items13_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 13) = some (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({})))))) := by
  rw [itemsDrop 13 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item13_found_kernel, verifiedFrontendRawLexer_claims_items14_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items12_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 12) = some (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({}))))))) := by
  rw [itemsDrop 12 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item12_found_kernel, verifiedFrontendRawLexer_claims_items13_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items11_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 11) = some (verifiedFrontendRawLexerClaimsItem11Kernel <+> (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({})))))))) := by
  rw [itemsDrop 11 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item11_found_kernel, verifiedFrontendRawLexer_claims_items12_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items10_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 10) = some (verifiedFrontendRawLexerClaimsItem10Kernel <+> (verifiedFrontendRawLexerClaimsItem11Kernel <+> (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({}))))))))) := by
  rw [itemsDrop 10 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item10_found_kernel, verifiedFrontendRawLexer_claims_items11_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items9_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 9) = some (verifiedFrontendRawLexerClaimsItem9Kernel <+> (verifiedFrontendRawLexerClaimsItem10Kernel <+> (verifiedFrontendRawLexerClaimsItem11Kernel <+> (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({})))))))))) := by
  rw [itemsDrop 9 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item9_found_kernel, verifiedFrontendRawLexer_claims_items10_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items8_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 8) = some (verifiedFrontendRawLexerClaimsItem8Kernel <+> (verifiedFrontendRawLexerClaimsItem9Kernel <+> (verifiedFrontendRawLexerClaimsItem10Kernel <+> (verifiedFrontendRawLexerClaimsItem11Kernel <+> (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({}))))))))))) := by
  rw [itemsDrop 8 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item8_found_kernel, verifiedFrontendRawLexer_claims_items9_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items7_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 7) = some (verifiedFrontendRawLexerClaimsItem7Kernel <+> (verifiedFrontendRawLexerClaimsItem8Kernel <+> (verifiedFrontendRawLexerClaimsItem9Kernel <+> (verifiedFrontendRawLexerClaimsItem10Kernel <+> (verifiedFrontendRawLexerClaimsItem11Kernel <+> (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({})))))))))))) := by
  rw [itemsDrop 7 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item7_found_kernel, verifiedFrontendRawLexer_claims_items8_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items6_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 6) = some (verifiedFrontendRawLexerClaimsItem6Kernel <+> (verifiedFrontendRawLexerClaimsItem7Kernel <+> (verifiedFrontendRawLexerClaimsItem8Kernel <+> (verifiedFrontendRawLexerClaimsItem9Kernel <+> (verifiedFrontendRawLexerClaimsItem10Kernel <+> (verifiedFrontendRawLexerClaimsItem11Kernel <+> (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({}))))))))))))) := by
  rw [itemsDrop 6 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item6_found_kernel, verifiedFrontendRawLexer_claims_items7_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items5_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 5) = some (verifiedFrontendRawLexerClaimsItem5Kernel <+> (verifiedFrontendRawLexerClaimsItem6Kernel <+> (verifiedFrontendRawLexerClaimsItem7Kernel <+> (verifiedFrontendRawLexerClaimsItem8Kernel <+> (verifiedFrontendRawLexerClaimsItem9Kernel <+> (verifiedFrontendRawLexerClaimsItem10Kernel <+> (verifiedFrontendRawLexerClaimsItem11Kernel <+> (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({})))))))))))))) := by
  rw [itemsDrop 5 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item5_found_kernel, verifiedFrontendRawLexer_claims_items6_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items4_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 4) = some (verifiedFrontendRawLexerClaimsItem4Kernel <+> (verifiedFrontendRawLexerClaimsItem5Kernel <+> (verifiedFrontendRawLexerClaimsItem6Kernel <+> (verifiedFrontendRawLexerClaimsItem7Kernel <+> (verifiedFrontendRawLexerClaimsItem8Kernel <+> (verifiedFrontendRawLexerClaimsItem9Kernel <+> (verifiedFrontendRawLexerClaimsItem10Kernel <+> (verifiedFrontendRawLexerClaimsItem11Kernel <+> (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({}))))))))))))))) := by
  rw [itemsDrop 4 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item4_found_kernel, verifiedFrontendRawLexer_claims_items5_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items3_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 3) = some (verifiedFrontendRawLexerClaimsItem3Kernel <+> (verifiedFrontendRawLexerClaimsItem4Kernel <+> (verifiedFrontendRawLexerClaimsItem5Kernel <+> (verifiedFrontendRawLexerClaimsItem6Kernel <+> (verifiedFrontendRawLexerClaimsItem7Kernel <+> (verifiedFrontendRawLexerClaimsItem8Kernel <+> (verifiedFrontendRawLexerClaimsItem9Kernel <+> (verifiedFrontendRawLexerClaimsItem10Kernel <+> (verifiedFrontendRawLexerClaimsItem11Kernel <+> (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({})))))))))))))))) := by
  rw [itemsDrop 3 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item3_found_kernel, verifiedFrontendRawLexer_claims_items4_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items2_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 2) = some (verifiedFrontendRawLexerClaimsItem2Kernel <+> (verifiedFrontendRawLexerClaimsItem3Kernel <+> (verifiedFrontendRawLexerClaimsItem4Kernel <+> (verifiedFrontendRawLexerClaimsItem5Kernel <+> (verifiedFrontendRawLexerClaimsItem6Kernel <+> (verifiedFrontendRawLexerClaimsItem7Kernel <+> (verifiedFrontendRawLexerClaimsItem8Kernel <+> (verifiedFrontendRawLexerClaimsItem9Kernel <+> (verifiedFrontendRawLexerClaimsItem10Kernel <+> (verifiedFrontendRawLexerClaimsItem11Kernel <+> (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({}))))))))))))))))) := by
  rw [itemsDrop 2 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item2_found_kernel, verifiedFrontendRawLexer_claims_items3_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items1_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 1) = some (verifiedFrontendRawLexerClaimsItem1Kernel <+> (verifiedFrontendRawLexerClaimsItem2Kernel <+> (verifiedFrontendRawLexerClaimsItem3Kernel <+> (verifiedFrontendRawLexerClaimsItem4Kernel <+> (verifiedFrontendRawLexerClaimsItem5Kernel <+> (verifiedFrontendRawLexerClaimsItem6Kernel <+> (verifiedFrontendRawLexerClaimsItem7Kernel <+> (verifiedFrontendRawLexerClaimsItem8Kernel <+> (verifiedFrontendRawLexerClaimsItem9Kernel <+> (verifiedFrontendRawLexerClaimsItem10Kernel <+> (verifiedFrontendRawLexerClaimsItem11Kernel <+> (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({})))))))))))))))))) := by
  rw [itemsDrop 1 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item1_found_kernel, verifiedFrontendRawLexer_claims_items2_kernel]
  rfl
theorem verifiedFrontendRawLexer_claims_items0_kernel :
    collectMany (collectItemClaimsWithFuel 1086 5966)
      (verifiedFrontendRawLexerProposedItemsKernel.drop 0) = some (verifiedFrontendRawLexerClaimsItem0Kernel <+> (verifiedFrontendRawLexerClaimsItem1Kernel <+> (verifiedFrontendRawLexerClaimsItem2Kernel <+> (verifiedFrontendRawLexerClaimsItem3Kernel <+> (verifiedFrontendRawLexerClaimsItem4Kernel <+> (verifiedFrontendRawLexerClaimsItem5Kernel <+> (verifiedFrontendRawLexerClaimsItem6Kernel <+> (verifiedFrontendRawLexerClaimsItem7Kernel <+> (verifiedFrontendRawLexerClaimsItem8Kernel <+> (verifiedFrontendRawLexerClaimsItem9Kernel <+> (verifiedFrontendRawLexerClaimsItem10Kernel <+> (verifiedFrontendRawLexerClaimsItem11Kernel <+> (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({}))))))))))))))))))) := by
  rw [itemsDrop 0 (by omega)]
  simp only [collectMany]
  rw [verifiedFrontendRawLexer_claims_item0_found_kernel, verifiedFrontendRawLexer_claims_items1_kernel]
  rfl
def verifiedFrontendRawLexerClaimsTraceKernel : SurfaceClaims :=
  (verifiedFrontendRawLexerClaimsItem0Kernel <+> (verifiedFrontendRawLexerClaimsItem1Kernel <+> (verifiedFrontendRawLexerClaimsItem2Kernel <+> (verifiedFrontendRawLexerClaimsItem3Kernel <+> (verifiedFrontendRawLexerClaimsItem4Kernel <+> (verifiedFrontendRawLexerClaimsItem5Kernel <+> (verifiedFrontendRawLexerClaimsItem6Kernel <+> (verifiedFrontendRawLexerClaimsItem7Kernel <+> (verifiedFrontendRawLexerClaimsItem8Kernel <+> (verifiedFrontendRawLexerClaimsItem9Kernel <+> (verifiedFrontendRawLexerClaimsItem10Kernel <+> (verifiedFrontendRawLexerClaimsItem11Kernel <+> (verifiedFrontendRawLexerClaimsItem12Kernel <+> (verifiedFrontendRawLexerClaimsItem13Kernel <+> (verifiedFrontendRawLexerClaimsItem14Kernel <+> (verifiedFrontendRawLexerClaimsItem15Kernel <+> (verifiedFrontendRawLexerClaimsItem16Kernel <+> (verifiedFrontendRawLexerClaimsItem17Kernel <+> ({}))))))))))))))))))) <+> SurfaceClaims.node 902 5966 none [0]
theorem verifiedFrontendRawLexer_claims_trace_found_kernel :
    collectSurfaceClaimsFrom verifiedFrontendRawLexerArtifact verifiedFrontendRawLexerReconstructedTraceKernel =
      some verifiedFrontendRawLexerClaimsTraceKernel := by
  unfold collectSurfaceClaimsFrom verifiedFrontendRawLexerReconstructedTraceKernel
  rw [show verifiedFrontendRawLexerArtifact.tokens.length + 1 = 1086 by with_unfolding_all rfl]
  change (collectMany (collectItemClaimsWithFuel 1086 5966)
      verifiedFrontendRawLexerProposedItemsKernel).bind
    (fun items => some (items <+> SurfaceClaims.node 902 5966 none [0])) =
      some verifiedFrontendRawLexerClaimsTraceKernel
  have itemsFound := verifiedFrontendRawLexer_claims_items0_kernel
  simp only [List.drop_zero] at itemsFound
  rw [itemsFound]
  rfl
end Lanius.Extraction
