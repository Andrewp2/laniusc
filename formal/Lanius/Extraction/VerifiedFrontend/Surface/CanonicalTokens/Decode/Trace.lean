import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction.Trace
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Decode.Item0
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Decode.Item1
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Decode.Item2
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Decode.Item3
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Decode.Item4
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Decode.Item5
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

theorem verifiedFrontendCanonicalTokens_decode_items6_kernel :
    (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 6).mapM (decodeSurfaceItem 10312) =
      some [] := by
  with_unfolding_all rfl
theorem verifiedFrontendCanonicalTokens_decode_items5_kernel :
    (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 5).mapM (decodeSurfaceItem 10312) =
      some [verifiedFrontendCanonicalTokensDecodedItem5Kernel] := by
  rw [itemsDrop 5 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendCanonicalTokens_decode_item5_found_kernel, verifiedFrontendCanonicalTokens_decode_items6_kernel]
  rfl
theorem verifiedFrontendCanonicalTokens_decode_items4_kernel :
    (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 4).mapM (decodeSurfaceItem 10312) =
      some [verifiedFrontendCanonicalTokensDecodedItem4Kernel, verifiedFrontendCanonicalTokensDecodedItem5Kernel] := by
  rw [itemsDrop 4 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendCanonicalTokens_decode_item4_found_kernel, verifiedFrontendCanonicalTokens_decode_items5_kernel]
  rfl
theorem verifiedFrontendCanonicalTokens_decode_items3_kernel :
    (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 3).mapM (decodeSurfaceItem 10312) =
      some [verifiedFrontendCanonicalTokensDecodedItem3Kernel, verifiedFrontendCanonicalTokensDecodedItem4Kernel, verifiedFrontendCanonicalTokensDecodedItem5Kernel] := by
  rw [itemsDrop 3 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendCanonicalTokens_decode_item3_found_kernel, verifiedFrontendCanonicalTokens_decode_items4_kernel]
  rfl
theorem verifiedFrontendCanonicalTokens_decode_items2_kernel :
    (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 2).mapM (decodeSurfaceItem 10312) =
      some [verifiedFrontendCanonicalTokensDecodedItem2Kernel, verifiedFrontendCanonicalTokensDecodedItem3Kernel, verifiedFrontendCanonicalTokensDecodedItem4Kernel, verifiedFrontendCanonicalTokensDecodedItem5Kernel] := by
  rw [itemsDrop 2 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendCanonicalTokens_decode_item2_found_kernel, verifiedFrontendCanonicalTokens_decode_items3_kernel]
  rfl
theorem verifiedFrontendCanonicalTokens_decode_items1_kernel :
    (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 1).mapM (decodeSurfaceItem 10312) =
      some [verifiedFrontendCanonicalTokensDecodedItem1Kernel, verifiedFrontendCanonicalTokensDecodedItem2Kernel, verifiedFrontendCanonicalTokensDecodedItem3Kernel, verifiedFrontendCanonicalTokensDecodedItem4Kernel, verifiedFrontendCanonicalTokensDecodedItem5Kernel] := by
  rw [itemsDrop 1 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendCanonicalTokens_decode_item1_found_kernel, verifiedFrontendCanonicalTokens_decode_items2_kernel]
  rfl
theorem verifiedFrontendCanonicalTokens_decode_items0_kernel :
    (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 0).mapM (decodeSurfaceItem 10312) =
      some [verifiedFrontendCanonicalTokensDecodedItem0Kernel, verifiedFrontendCanonicalTokensDecodedItem1Kernel, verifiedFrontendCanonicalTokensDecodedItem2Kernel, verifiedFrontendCanonicalTokensDecodedItem3Kernel, verifiedFrontendCanonicalTokensDecodedItem4Kernel, verifiedFrontendCanonicalTokensDecodedItem5Kernel] := by
  rw [itemsDrop 0 (by omega)]
  simp only [List.mapM_cons]
  rw [verifiedFrontendCanonicalTokens_decode_item0_found_kernel, verifiedFrontendCanonicalTokens_decode_items1_kernel]
  rfl
def verifiedFrontendCanonicalTokensDecodedSurfaceTraceKernel : Lanius.Surface.File := {
  items := [verifiedFrontendCanonicalTokensDecodedItem0Kernel, verifiedFrontendCanonicalTokensDecodedItem1Kernel, verifiedFrontendCanonicalTokensDecodedItem2Kernel, verifiedFrontendCanonicalTokensDecodedItem3Kernel, verifiedFrontendCanonicalTokensDecodedItem4Kernel, verifiedFrontendCanonicalTokensDecodedItem5Kernel]
}
theorem verifiedFrontendCanonicalTokens_decoded_surface_trace_found_kernel :
    decodeSurfaceFile 10312 verifiedFrontendCanonicalTokensReconstructedTraceKernel =
      some verifiedFrontendCanonicalTokensDecodedSurfaceTraceKernel := by
  unfold decodeSurfaceFile verifiedFrontendCanonicalTokensReconstructedTraceKernel
  change (verifiedFrontendCanonicalTokensProposedItemsKernel.mapM (decodeSurfaceItem 10312)).bind
    (fun items => some { items := items }) = some verifiedFrontendCanonicalTokensDecodedSurfaceTraceKernel
  have itemsFound := verifiedFrontendCanonicalTokens_decode_items0_kernel
  simp only [List.drop_zero] at itemsFound
  rw [itemsFound]
  rfl
end Lanius.Extraction
