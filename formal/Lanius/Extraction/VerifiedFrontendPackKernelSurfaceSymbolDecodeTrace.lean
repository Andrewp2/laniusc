import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolReconstructionTrace
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolDecodeItem0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolDecodeItem1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolDecodeItem2
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolDecodeItem3
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolDecodeItem4
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolDecodeItem5
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolDecodeItem6
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

theorem verifiedFrontendSymbol_decode_items7_kernel :
    (verifiedFrontendSymbolProposedItemsKernel.drop 7).mapM (decodeSurfaceItem 8245) =
      some [] := by
  with_unfolding_all rfl
theorem verifiedFrontendSymbol_decode_items6_kernel :
    (verifiedFrontendSymbolProposedItemsKernel.drop 6).mapM (decodeSurfaceItem 8245) =
      some [verifiedFrontendSymbolDecodedItem6Kernel] := by
  rw [itemsDrop 6 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendSymbol_decode_item6_found_kernel, verifiedFrontendSymbol_decode_items7_kernel]
  rfl
theorem verifiedFrontendSymbol_decode_items5_kernel :
    (verifiedFrontendSymbolProposedItemsKernel.drop 5).mapM (decodeSurfaceItem 8245) =
      some [verifiedFrontendSymbolDecodedItem5Kernel, verifiedFrontendSymbolDecodedItem6Kernel] := by
  rw [itemsDrop 5 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendSymbol_decode_item5_found_kernel, verifiedFrontendSymbol_decode_items6_kernel]
  rfl
theorem verifiedFrontendSymbol_decode_items4_kernel :
    (verifiedFrontendSymbolProposedItemsKernel.drop 4).mapM (decodeSurfaceItem 8245) =
      some [verifiedFrontendSymbolDecodedItem4Kernel, verifiedFrontendSymbolDecodedItem5Kernel, verifiedFrontendSymbolDecodedItem6Kernel] := by
  rw [itemsDrop 4 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendSymbol_decode_item4_found_kernel, verifiedFrontendSymbol_decode_items5_kernel]
  rfl
theorem verifiedFrontendSymbol_decode_items3_kernel :
    (verifiedFrontendSymbolProposedItemsKernel.drop 3).mapM (decodeSurfaceItem 8245) =
      some [verifiedFrontendSymbolDecodedItem3Kernel, verifiedFrontendSymbolDecodedItem4Kernel, verifiedFrontendSymbolDecodedItem5Kernel, verifiedFrontendSymbolDecodedItem6Kernel] := by
  rw [itemsDrop 3 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendSymbol_decode_item3_found_kernel, verifiedFrontendSymbol_decode_items4_kernel]
  rfl
theorem verifiedFrontendSymbol_decode_items2_kernel :
    (verifiedFrontendSymbolProposedItemsKernel.drop 2).mapM (decodeSurfaceItem 8245) =
      some [verifiedFrontendSymbolDecodedItem2Kernel, verifiedFrontendSymbolDecodedItem3Kernel, verifiedFrontendSymbolDecodedItem4Kernel, verifiedFrontendSymbolDecodedItem5Kernel, verifiedFrontendSymbolDecodedItem6Kernel] := by
  rw [itemsDrop 2 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendSymbol_decode_item2_found_kernel, verifiedFrontendSymbol_decode_items3_kernel]
  rfl
theorem verifiedFrontendSymbol_decode_items1_kernel :
    (verifiedFrontendSymbolProposedItemsKernel.drop 1).mapM (decodeSurfaceItem 8245) =
      some [verifiedFrontendSymbolDecodedItem1Kernel, verifiedFrontendSymbolDecodedItem2Kernel, verifiedFrontendSymbolDecodedItem3Kernel, verifiedFrontendSymbolDecodedItem4Kernel, verifiedFrontendSymbolDecodedItem5Kernel, verifiedFrontendSymbolDecodedItem6Kernel] := by
  rw [itemsDrop 1 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendSymbol_decode_item1_found_kernel, verifiedFrontendSymbol_decode_items2_kernel]
  rfl
theorem verifiedFrontendSymbol_decode_items0_kernel :
    (verifiedFrontendSymbolProposedItemsKernel.drop 0).mapM (decodeSurfaceItem 8245) =
      some [verifiedFrontendSymbolDecodedItem0Kernel, verifiedFrontendSymbolDecodedItem1Kernel, verifiedFrontendSymbolDecodedItem2Kernel, verifiedFrontendSymbolDecodedItem3Kernel, verifiedFrontendSymbolDecodedItem4Kernel, verifiedFrontendSymbolDecodedItem5Kernel, verifiedFrontendSymbolDecodedItem6Kernel] := by
  rw [itemsDrop 0 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendSymbol_decode_item0_found_kernel, verifiedFrontendSymbol_decode_items1_kernel]
  rfl
def verifiedFrontendSymbolDecodedSurfaceTraceKernel : Lanius.Surface.File := {
  items := [verifiedFrontendSymbolDecodedItem0Kernel, verifiedFrontendSymbolDecodedItem1Kernel, verifiedFrontendSymbolDecodedItem2Kernel, verifiedFrontendSymbolDecodedItem3Kernel, verifiedFrontendSymbolDecodedItem4Kernel, verifiedFrontendSymbolDecodedItem5Kernel, verifiedFrontendSymbolDecodedItem6Kernel]
}
theorem verifiedFrontendSymbol_decoded_surface_trace_found_kernel :
    decodeSurfaceFile 8245 verifiedFrontendSymbolReconstructedTraceKernel =
      some verifiedFrontendSymbolDecodedSurfaceTraceKernel := by
  unfold decodeSurfaceFile verifiedFrontendSymbolReconstructedTraceKernel
  change (verifiedFrontendSymbolProposedItemsKernel.mapM (decodeSurfaceItem 8245)).bind
    (fun items => some { items := items }) = some verifiedFrontendSymbolDecodedSurfaceTraceKernel
  have itemsFound := verifiedFrontendSymbol_decode_items0_kernel
  simp only [List.drop_zero] at itemsFound
  rw [itemsFound]
  rfl
end Lanius.Extraction
