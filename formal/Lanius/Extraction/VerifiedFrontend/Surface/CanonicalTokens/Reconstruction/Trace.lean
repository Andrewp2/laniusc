import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction.Item0
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction.Item1
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction.Item2
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction.Item3
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction.Item4
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction.Item5
import Lanius.Extraction.SurfaceReconstructTrace
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendCanonicalTokensAccessAssembly : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendCanonicalTokensView
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

theorem verifiedFrontendCanonicalTokens_reconstruct_items6_kernel :
    (reconstructItems 10306 verifiedFrontendCanonicalTokensArtifact 10303).run 1609 =
      some (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 6, 1609) := by
  with_unfolding_all rfl

theorem verifiedFrontendCanonicalTokens_reconstruct_items5_kernel :
    (reconstructItems 10307 verifiedFrontendCanonicalTokensArtifact 10304).run 1339 =
      some (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 5, 1609) := by
  rw [itemsDrop 5 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendCanonicalTokens_reconstruct_item5_kernel
    verifiedFrontendCanonicalTokens_reconstruct_items6_kernel
theorem verifiedFrontendCanonicalTokens_reconstruct_items4_kernel :
    (reconstructItems 10308 verifiedFrontendCanonicalTokensArtifact 10305).run 1290 =
      some (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 4, 1609) := by
  rw [itemsDrop 4 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendCanonicalTokens_reconstruct_item4_kernel
    verifiedFrontendCanonicalTokens_reconstruct_items5_kernel
theorem verifiedFrontendCanonicalTokens_reconstruct_items3_kernel :
    (reconstructItems 10309 verifiedFrontendCanonicalTokensArtifact 10306).run 46 =
      some (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 3, 1609) := by
  rw [itemsDrop 3 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendCanonicalTokens_reconstruct_item3_kernel
    verifiedFrontendCanonicalTokens_reconstruct_items4_kernel
theorem verifiedFrontendCanonicalTokens_reconstruct_items2_kernel :
    (reconstructItems 10310 verifiedFrontendCanonicalTokensArtifact 10307).run 8 =
      some (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 2, 1609) := by
  rw [itemsDrop 2 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendCanonicalTokens_reconstruct_item2_kernel
    verifiedFrontendCanonicalTokens_reconstruct_items3_kernel
theorem verifiedFrontendCanonicalTokens_reconstruct_items1_kernel :
    (reconstructItems 10311 verifiedFrontendCanonicalTokensArtifact 10308).run 4 =
      some (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 1, 1609) := by
  rw [itemsDrop 1 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendCanonicalTokens_reconstruct_item1_kernel
    verifiedFrontendCanonicalTokens_reconstruct_items2_kernel
theorem verifiedFrontendCanonicalTokens_reconstruct_items0_kernel :
    (reconstructItems 10312 verifiedFrontendCanonicalTokensArtifact 10309).run 0 =
      some (verifiedFrontendCanonicalTokensProposedItemsKernel.drop 0, 1609) := by
  rw [itemsDrop 0 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendCanonicalTokens_reconstruct_item0_kernel
    verifiedFrontendCanonicalTokens_reconstruct_items1_kernel

def verifiedFrontendCanonicalTokensReconstructedTraceKernel : SurfaceFile := {
  id := 1609, parse_node := 10310,
  value := { items := verifiedFrontendCanonicalTokensProposedItemsKernel }
}
theorem verifiedFrontendCanonicalTokens_reconstruct_file_trace_kernel :
    (reconstructFile 10312 verifiedFrontendCanonicalTokensArtifact 10310).run 0 =
      some (verifiedFrontendCanonicalTokensReconstructedTraceKernel, 1610) := by
  exact reconstructFile_of (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendCanonicalTokens_reconstruct_items0_kernel
theorem verifiedFrontendCanonicalTokens_reconstructed_trace_kernel :
    reconstructArtifactSurfaceView verifiedFrontendCanonicalTokensArtifact verifiedFrontendCanonicalTokensView =
      some verifiedFrontendCanonicalTokensReconstructedTraceKernel := by
  unfold reconstructArtifactSurfaceView reconstructArtifactSurfaceWithAccess
  rw [show verifiedFrontendCanonicalTokensArtifact.parse_root = some 10310 by with_unfolding_all rfl]
  rw [show verifiedFrontendCanonicalTokensArtifact.parse_nodes.length + 1 = 10312 by with_unfolding_all rfl]
  simp [verifiedFrontendCanonicalTokens_reconstruct_file_trace_kernel]
end Lanius.Extraction
