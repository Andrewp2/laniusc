import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionTrace
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem2
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem3
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem4
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem5
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem6
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem7
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem8
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem9
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem10
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem11
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem12
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem13
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem14
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem15
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem16
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerDecodeItem17
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

theorem verifiedFrontendRawLexer_decode_items18_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 18).mapM (decodeSurfaceItem 5968) =
      some [] := by
  with_unfolding_all rfl
theorem verifiedFrontendRawLexer_decode_items17_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 17).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 17 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item17_found_kernel, verifiedFrontendRawLexer_decode_items18_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items16_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 16).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 16 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item16_found_kernel, verifiedFrontendRawLexer_decode_items17_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items15_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 15).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 15 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item15_found_kernel, verifiedFrontendRawLexer_decode_items16_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items14_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 14).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 14 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item14_found_kernel, verifiedFrontendRawLexer_decode_items15_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items13_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 13).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 13 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item13_found_kernel, verifiedFrontendRawLexer_decode_items14_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items12_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 12).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 12 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item12_found_kernel, verifiedFrontendRawLexer_decode_items13_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items11_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 11).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem11Kernel, verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 11 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item11_found_kernel, verifiedFrontendRawLexer_decode_items12_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items10_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 10).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem10Kernel, verifiedFrontendRawLexerDecodedItem11Kernel, verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 10 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item10_found_kernel, verifiedFrontendRawLexer_decode_items11_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items9_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 9).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem9Kernel, verifiedFrontendRawLexerDecodedItem10Kernel, verifiedFrontendRawLexerDecodedItem11Kernel, verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 9 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item9_found_kernel, verifiedFrontendRawLexer_decode_items10_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items8_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 8).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem8Kernel, verifiedFrontendRawLexerDecodedItem9Kernel, verifiedFrontendRawLexerDecodedItem10Kernel, verifiedFrontendRawLexerDecodedItem11Kernel, verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 8 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item8_found_kernel, verifiedFrontendRawLexer_decode_items9_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items7_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 7).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem7Kernel, verifiedFrontendRawLexerDecodedItem8Kernel, verifiedFrontendRawLexerDecodedItem9Kernel, verifiedFrontendRawLexerDecodedItem10Kernel, verifiedFrontendRawLexerDecodedItem11Kernel, verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 7 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item7_found_kernel, verifiedFrontendRawLexer_decode_items8_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items6_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 6).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem6Kernel, verifiedFrontendRawLexerDecodedItem7Kernel, verifiedFrontendRawLexerDecodedItem8Kernel, verifiedFrontendRawLexerDecodedItem9Kernel, verifiedFrontendRawLexerDecodedItem10Kernel, verifiedFrontendRawLexerDecodedItem11Kernel, verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 6 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item6_found_kernel, verifiedFrontendRawLexer_decode_items7_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items5_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 5).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem5Kernel, verifiedFrontendRawLexerDecodedItem6Kernel, verifiedFrontendRawLexerDecodedItem7Kernel, verifiedFrontendRawLexerDecodedItem8Kernel, verifiedFrontendRawLexerDecodedItem9Kernel, verifiedFrontendRawLexerDecodedItem10Kernel, verifiedFrontendRawLexerDecodedItem11Kernel, verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 5 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item5_found_kernel, verifiedFrontendRawLexer_decode_items6_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items4_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 4).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem4Kernel, verifiedFrontendRawLexerDecodedItem5Kernel, verifiedFrontendRawLexerDecodedItem6Kernel, verifiedFrontendRawLexerDecodedItem7Kernel, verifiedFrontendRawLexerDecodedItem8Kernel, verifiedFrontendRawLexerDecodedItem9Kernel, verifiedFrontendRawLexerDecodedItem10Kernel, verifiedFrontendRawLexerDecodedItem11Kernel, verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 4 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item4_found_kernel, verifiedFrontendRawLexer_decode_items5_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items3_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 3).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem3Kernel, verifiedFrontendRawLexerDecodedItem4Kernel, verifiedFrontendRawLexerDecodedItem5Kernel, verifiedFrontendRawLexerDecodedItem6Kernel, verifiedFrontendRawLexerDecodedItem7Kernel, verifiedFrontendRawLexerDecodedItem8Kernel, verifiedFrontendRawLexerDecodedItem9Kernel, verifiedFrontendRawLexerDecodedItem10Kernel, verifiedFrontendRawLexerDecodedItem11Kernel, verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 3 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item3_found_kernel, verifiedFrontendRawLexer_decode_items4_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items2_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 2).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem2Kernel, verifiedFrontendRawLexerDecodedItem3Kernel, verifiedFrontendRawLexerDecodedItem4Kernel, verifiedFrontendRawLexerDecodedItem5Kernel, verifiedFrontendRawLexerDecodedItem6Kernel, verifiedFrontendRawLexerDecodedItem7Kernel, verifiedFrontendRawLexerDecodedItem8Kernel, verifiedFrontendRawLexerDecodedItem9Kernel, verifiedFrontendRawLexerDecodedItem10Kernel, verifiedFrontendRawLexerDecodedItem11Kernel, verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 2 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item2_found_kernel, verifiedFrontendRawLexer_decode_items3_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items1_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 1).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem1Kernel, verifiedFrontendRawLexerDecodedItem2Kernel, verifiedFrontendRawLexerDecodedItem3Kernel, verifiedFrontendRawLexerDecodedItem4Kernel, verifiedFrontendRawLexerDecodedItem5Kernel, verifiedFrontendRawLexerDecodedItem6Kernel, verifiedFrontendRawLexerDecodedItem7Kernel, verifiedFrontendRawLexerDecodedItem8Kernel, verifiedFrontendRawLexerDecodedItem9Kernel, verifiedFrontendRawLexerDecodedItem10Kernel, verifiedFrontendRawLexerDecodedItem11Kernel, verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 1 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item1_found_kernel, verifiedFrontendRawLexer_decode_items2_kernel]
  rfl
theorem verifiedFrontendRawLexer_decode_items0_kernel :
    (verifiedFrontendRawLexerProposedItemsKernel.drop 0).mapM (decodeSurfaceItem 5968) =
      some [verifiedFrontendRawLexerDecodedItem0Kernel, verifiedFrontendRawLexerDecodedItem1Kernel, verifiedFrontendRawLexerDecodedItem2Kernel, verifiedFrontendRawLexerDecodedItem3Kernel, verifiedFrontendRawLexerDecodedItem4Kernel, verifiedFrontendRawLexerDecodedItem5Kernel, verifiedFrontendRawLexerDecodedItem6Kernel, verifiedFrontendRawLexerDecodedItem7Kernel, verifiedFrontendRawLexerDecodedItem8Kernel, verifiedFrontendRawLexerDecodedItem9Kernel, verifiedFrontendRawLexerDecodedItem10Kernel, verifiedFrontendRawLexerDecodedItem11Kernel, verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel] := by
  rw [itemsDrop 0 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendRawLexer_decode_item0_found_kernel, verifiedFrontendRawLexer_decode_items1_kernel]
  rfl
def verifiedFrontendRawLexerDecodedSurfaceTraceKernel : Lanius.Surface.File := {
  items := [verifiedFrontendRawLexerDecodedItem0Kernel, verifiedFrontendRawLexerDecodedItem1Kernel, verifiedFrontendRawLexerDecodedItem2Kernel, verifiedFrontendRawLexerDecodedItem3Kernel, verifiedFrontendRawLexerDecodedItem4Kernel, verifiedFrontendRawLexerDecodedItem5Kernel, verifiedFrontendRawLexerDecodedItem6Kernel, verifiedFrontendRawLexerDecodedItem7Kernel, verifiedFrontendRawLexerDecodedItem8Kernel, verifiedFrontendRawLexerDecodedItem9Kernel, verifiedFrontendRawLexerDecodedItem10Kernel, verifiedFrontendRawLexerDecodedItem11Kernel, verifiedFrontendRawLexerDecodedItem12Kernel, verifiedFrontendRawLexerDecodedItem13Kernel, verifiedFrontendRawLexerDecodedItem14Kernel, verifiedFrontendRawLexerDecodedItem15Kernel, verifiedFrontendRawLexerDecodedItem16Kernel, verifiedFrontendRawLexerDecodedItem17Kernel]
}
theorem verifiedFrontendRawLexer_decoded_surface_trace_found_kernel :
    decodeSurfaceFile 5968 verifiedFrontendRawLexerReconstructedTraceKernel =
      some verifiedFrontendRawLexerDecodedSurfaceTraceKernel := by
  unfold decodeSurfaceFile verifiedFrontendRawLexerReconstructedTraceKernel
  change (verifiedFrontendRawLexerProposedItemsKernel.mapM (decodeSurfaceItem 5968)).bind
    (fun items => some { items := items }) = some verifiedFrontendRawLexerDecodedSurfaceTraceKernel
  have itemsFound := verifiedFrontendRawLexer_decode_items0_kernel
  simp only [List.drop_zero] at itemsFound
  rw [itemsFound]
  rfl
end Lanius.Extraction
