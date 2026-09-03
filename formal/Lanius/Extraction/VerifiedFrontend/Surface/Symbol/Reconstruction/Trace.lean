import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.Item0
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.Item1
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.Item2
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.Item3
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.Item4
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.Item5
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.Item6
import Lanius.Extraction.SurfaceReconstructTrace
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendSymbolAccessAssembly : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendSymbolView
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

theorem verifiedFrontendSymbol_reconstruct_items7_kernel :
    (reconstructItems 8238 verifiedFrontendSymbolArtifact 8235).run 999 =
      some (verifiedFrontendSymbolProposedItemsKernel.drop 7, 999) := by
  with_unfolding_all rfl

theorem verifiedFrontendSymbol_reconstruct_items6_kernel :
    (reconstructItems 8239 verifiedFrontendSymbolArtifact 8236).run 67 =
      some (verifiedFrontendSymbolProposedItemsKernel.drop 6, 999) := by
  rw [itemsDrop 6 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendSymbol_reconstruct_item6_kernel
    verifiedFrontendSymbol_reconstruct_items7_kernel
theorem verifiedFrontendSymbol_reconstruct_items5_kernel :
    (reconstructItems 8240 verifiedFrontendSymbolArtifact 8237).run 43 =
      some (verifiedFrontendSymbolProposedItemsKernel.drop 5, 999) := by
  rw [itemsDrop 5 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendSymbol_reconstruct_item5_kernel
    verifiedFrontendSymbol_reconstruct_items6_kernel
theorem verifiedFrontendSymbol_reconstruct_items4_kernel :
    (reconstructItems 8241 verifiedFrontendSymbolArtifact 8238).run 30 =
      some (verifiedFrontendSymbolProposedItemsKernel.drop 4, 999) := by
  rw [itemsDrop 4 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendSymbol_reconstruct_item4_kernel
    verifiedFrontendSymbol_reconstruct_items5_kernel
theorem verifiedFrontendSymbol_reconstruct_items3_kernel :
    (reconstructItems 8242 verifiedFrontendSymbolArtifact 8239).run 17 =
      some (verifiedFrontendSymbolProposedItemsKernel.drop 3, 999) := by
  rw [itemsDrop 3 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendSymbol_reconstruct_item3_kernel
    verifiedFrontendSymbol_reconstruct_items4_kernel
theorem verifiedFrontendSymbol_reconstruct_items2_kernel :
    (reconstructItems 8243 verifiedFrontendSymbolArtifact 8240).run 8 =
      some (verifiedFrontendSymbolProposedItemsKernel.drop 2, 999) := by
  rw [itemsDrop 2 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendSymbol_reconstruct_item2_kernel
    verifiedFrontendSymbol_reconstruct_items3_kernel
theorem verifiedFrontendSymbol_reconstruct_items1_kernel :
    (reconstructItems 8244 verifiedFrontendSymbolArtifact 8241).run 4 =
      some (verifiedFrontendSymbolProposedItemsKernel.drop 1, 999) := by
  rw [itemsDrop 1 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendSymbol_reconstruct_item1_kernel
    verifiedFrontendSymbol_reconstruct_items2_kernel
theorem verifiedFrontendSymbol_reconstruct_items0_kernel :
    (reconstructItems 8245 verifiedFrontendSymbolArtifact 8242).run 0 =
      some (verifiedFrontendSymbolProposedItemsKernel.drop 0, 999) := by
  rw [itemsDrop 0 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendSymbol_reconstruct_item0_kernel
    verifiedFrontendSymbol_reconstruct_items1_kernel

def verifiedFrontendSymbolReconstructedTraceKernel : SurfaceFile := {
  id := 999, parse_node := 8243,
  value := { items := verifiedFrontendSymbolProposedItemsKernel }
}
theorem verifiedFrontendSymbol_reconstruct_file_trace_kernel :
    (reconstructFile 8245 verifiedFrontendSymbolArtifact 8243).run 0 =
      some (verifiedFrontendSymbolReconstructedTraceKernel, 1000) := by
  exact reconstructFile_of (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendSymbol_reconstruct_items0_kernel
theorem verifiedFrontendSymbol_reconstructed_trace_kernel :
    reconstructArtifactSurfaceView verifiedFrontendSymbolArtifact verifiedFrontendSymbolView =
      some verifiedFrontendSymbolReconstructedTraceKernel := by
  unfold reconstructArtifactSurfaceView reconstructArtifactSurfaceWithAccess
  rw [show verifiedFrontendSymbolArtifact.parse_root = some 8243 by with_unfolding_all rfl]
  rw [show verifiedFrontendSymbolArtifact.parse_nodes.length + 1 = 8245 by with_unfolding_all rfl]
  simp [verifiedFrontendSymbol_reconstruct_file_trace_kernel]
end Lanius.Extraction
