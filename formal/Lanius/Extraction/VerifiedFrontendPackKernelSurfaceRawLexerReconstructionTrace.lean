import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem2
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem3
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem4
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem5
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem6
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem7
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem8
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem9
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem10
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem11
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem12
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem13
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem14
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem15
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem16
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerReconstructionItem17
import Lanius.Extraction.SurfaceReconstructTrace
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessAssembly : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
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

theorem verifiedFrontendRawLexer_reconstruct_items18_kernel :
    (reconstructItems 5950 verifiedFrontendRawLexerArtifact 5947).run 902 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 18, 902) := by
  with_unfolding_all rfl

theorem verifiedFrontendRawLexer_reconstruct_items17_kernel :
    (reconstructItems 5951 verifiedFrontendRawLexerArtifact 5948).run 712 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 17, 902) := by
  rw [itemsDrop 17 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item17_kernel
    verifiedFrontendRawLexer_reconstruct_items18_kernel
theorem verifiedFrontendRawLexer_reconstruct_items16_kernel :
    (reconstructItems 5952 verifiedFrontendRawLexerArtifact 5949).run 169 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 16, 902) := by
  rw [itemsDrop 16 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item16_kernel
    verifiedFrontendRawLexer_reconstruct_items17_kernel
theorem verifiedFrontendRawLexer_reconstruct_items15_kernel :
    (reconstructItems 5953 verifiedFrontendRawLexerArtifact 5950).run 141 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 15, 902) := by
  rw [itemsDrop 15 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item15_kernel
    verifiedFrontendRawLexer_reconstruct_items16_kernel
theorem verifiedFrontendRawLexer_reconstruct_items14_kernel :
    (reconstructItems 5954 verifiedFrontendRawLexerArtifact 5951).run 113 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 14, 902) := by
  rw [itemsDrop 14 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item14_kernel
    verifiedFrontendRawLexer_reconstruct_items15_kernel
theorem verifiedFrontendRawLexer_reconstruct_items13_kernel :
    (reconstructItems 5955 verifiedFrontendRawLexerArtifact 5952).run 91 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 13, 902) := by
  rw [itemsDrop 13 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item13_kernel
    verifiedFrontendRawLexer_reconstruct_items14_kernel
theorem verifiedFrontendRawLexer_reconstruct_items12_kernel :
    (reconstructItems 5956 verifiedFrontendRawLexerArtifact 5953).run 78 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 12, 902) := by
  rw [itemsDrop 12 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item12_kernel
    verifiedFrontendRawLexer_reconstruct_items13_kernel
theorem verifiedFrontendRawLexer_reconstruct_items11_kernel :
    (reconstructItems 5957 verifiedFrontendRawLexerArtifact 5954).run 65 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 11, 902) := by
  rw [itemsDrop 11 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item11_kernel
    verifiedFrontendRawLexer_reconstruct_items12_kernel
theorem verifiedFrontendRawLexer_reconstruct_items10_kernel :
    (reconstructItems 5958 verifiedFrontendRawLexerArtifact 5955).run 52 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 10, 902) := by
  rw [itemsDrop 10 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item10_kernel
    verifiedFrontendRawLexer_reconstruct_items11_kernel
theorem verifiedFrontendRawLexer_reconstruct_items9_kernel :
    (reconstructItems 5959 verifiedFrontendRawLexerArtifact 5956).run 39 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 9, 902) := by
  rw [itemsDrop 9 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item9_kernel
    verifiedFrontendRawLexer_reconstruct_items10_kernel
theorem verifiedFrontendRawLexer_reconstruct_items8_kernel :
    (reconstructItems 5960 verifiedFrontendRawLexerArtifact 5957).run 34 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 8, 902) := by
  rw [itemsDrop 8 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item8_kernel
    verifiedFrontendRawLexer_reconstruct_items9_kernel
theorem verifiedFrontendRawLexer_reconstruct_items7_kernel :
    (reconstructItems 5961 verifiedFrontendRawLexerArtifact 5958).run 29 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 7, 902) := by
  rw [itemsDrop 7 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item7_kernel
    verifiedFrontendRawLexer_reconstruct_items8_kernel
theorem verifiedFrontendRawLexer_reconstruct_items6_kernel :
    (reconstructItems 5962 verifiedFrontendRawLexerArtifact 5959).run 24 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 6, 902) := by
  rw [itemsDrop 6 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item6_kernel
    verifiedFrontendRawLexer_reconstruct_items7_kernel
theorem verifiedFrontendRawLexer_reconstruct_items5_kernel :
    (reconstructItems 5963 verifiedFrontendRawLexerArtifact 5960).run 20 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 5, 902) := by
  rw [itemsDrop 5 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item5_kernel
    verifiedFrontendRawLexer_reconstruct_items6_kernel
theorem verifiedFrontendRawLexer_reconstruct_items4_kernel :
    (reconstructItems 5964 verifiedFrontendRawLexerArtifact 5961).run 16 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 4, 902) := by
  rw [itemsDrop 4 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item4_kernel
    verifiedFrontendRawLexer_reconstruct_items5_kernel
theorem verifiedFrontendRawLexer_reconstruct_items3_kernel :
    (reconstructItems 5965 verifiedFrontendRawLexerArtifact 5962).run 12 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 3, 902) := by
  rw [itemsDrop 3 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item3_kernel
    verifiedFrontendRawLexer_reconstruct_items4_kernel
theorem verifiedFrontendRawLexer_reconstruct_items2_kernel :
    (reconstructItems 5966 verifiedFrontendRawLexerArtifact 5963).run 8 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 2, 902) := by
  rw [itemsDrop 2 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item2_kernel
    verifiedFrontendRawLexer_reconstruct_items3_kernel
theorem verifiedFrontendRawLexer_reconstruct_items1_kernel :
    (reconstructItems 5967 verifiedFrontendRawLexerArtifact 5964).run 4 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 1, 902) := by
  rw [itemsDrop 1 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item1_kernel
    verifiedFrontendRawLexer_reconstruct_items2_kernel
theorem verifiedFrontendRawLexer_reconstruct_items0_kernel :
    (reconstructItems 5968 verifiedFrontendRawLexerArtifact 5965).run 0 =
      some (verifiedFrontendRawLexerProposedItemsKernel.drop 0, 902) := by
  rw [itemsDrop 0 (by omega)]
  exact reconstructItems_cons_of
    (by with_unfolding_all rfl) (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_item0_kernel
    verifiedFrontendRawLexer_reconstruct_items1_kernel

def verifiedFrontendRawLexerReconstructedTraceKernel : SurfaceFile := {
  id := 902, parse_node := 5966,
  value := { items := verifiedFrontendRawLexerProposedItemsKernel }
}
theorem verifiedFrontendRawLexer_reconstruct_file_trace_kernel :
    (reconstructFile 5968 verifiedFrontendRawLexerArtifact 5966).run 0 =
      some (verifiedFrontendRawLexerReconstructedTraceKernel, 903) := by
  exact reconstructFile_of (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendRawLexer_reconstruct_items0_kernel
theorem verifiedFrontendRawLexer_reconstructed_trace_kernel :
    reconstructArtifactSurfaceView verifiedFrontendRawLexerArtifact verifiedFrontendRawLexerView =
      some verifiedFrontendRawLexerReconstructedTraceKernel := by
  unfold reconstructArtifactSurfaceView reconstructArtifactSurfaceWithAccess
  rw [show verifiedFrontendRawLexerArtifact.parse_root = some 5966 by with_unfolding_all rfl]
  rw [show verifiedFrontendRawLexerArtifact.parse_nodes.length + 1 = 5968 by with_unfolding_all rfl]
  simp [verifiedFrontendRawLexer_reconstruct_file_trace_kernel]
end Lanius.Extraction
