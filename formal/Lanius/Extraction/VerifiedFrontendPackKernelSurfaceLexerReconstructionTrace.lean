import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructionShard0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructionShard1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructionShard2
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructionShard3
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructionShard4
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructionShard5
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructionShard6
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructionShard7
import Lanius.Extraction.SurfaceReconstructTrace

namespace Lanius.Extraction

set_option maxRecDepth 100000

local instance verifiedFrontendLexerAccessAssembly : ArtifactAccess :=
  ArtifactAccess.ofView verifiedFrontendLexerView

private theorem itemsDrop (index : Nat) (bounded : index < 28) :
    verifiedFrontendLexerProposedItemsKernel.drop index =
      verifiedFrontendLexerProposedItemKernel index ::
        verifiedFrontendLexerProposedItemsKernel.drop (index + 1) := by
  have inBounds : index < verifiedFrontendLexerProposedItemsKernel.length := by
    rw [verifiedFrontendLexerProposedItemsKernel_length]
    exact bounded
  rw [List.drop_eq_getElem_cons inBounds]
  congr 1
  simpa [verifiedFrontendLexerProposedItemKernel] using
    (getElem!_pos verifiedFrontendLexerProposedItemsKernel index inBounds).symm

theorem verifiedFrontendLexer_reconstruct_items28_kernel :
    (reconstructItems 6964 verifiedFrontendLexerArtifact 6961).run 1107 =
      some (verifiedFrontendLexerProposedItemsKernel.drop 28, 1107) := by
  with_unfolding_all rfl

macro "lexer_items_step " result:ident ", " index:num ", " fuel:num ", "
    node:num ", " itemNode:num ", " restNode:num ", " start:num ", "
    middle:num ", " itemProof:ident ", " restProof:ident : command =>
  `(theorem $result :
      (reconstructItems $fuel verifiedFrontendLexerArtifact $node).run $start =
        some (verifiedFrontendLexerProposedItemsKernel.drop $index, 1107) := by
      rw [itemsDrop $index (by omega)]
      exact reconstructItems_cons_of
        (by with_unfolding_all rfl)
        (by with_unfolding_all rfl)
        (by with_unfolding_all rfl)
        $itemProof $restProof)

lexer_items_step verifiedFrontendLexer_reconstruct_items27_kernel,
  27, 6965, 6962, 6960, 6961, 1017, 1107,
  verifiedFrontendLexer_reconstruct_item27_kernel,
  verifiedFrontendLexer_reconstruct_items28_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items26_kernel,
  26, 6966, 6963, 6417, 6962, 963, 1017,
  verifiedFrontendLexer_reconstruct_item26_kernel,
  verifiedFrontendLexer_reconstruct_items27_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items25_kernel,
  25, 6967, 6964, 6118, 6963, 931, 963,
  verifiedFrontendLexer_reconstruct_item25_kernel,
  verifiedFrontendLexer_reconstruct_items26_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items24_kernel,
  24, 6968, 6965, 5916, 6964, 899, 931,
  verifiedFrontendLexer_reconstruct_item24_kernel,
  verifiedFrontendLexer_reconstruct_items25_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items23_kernel,
  23, 6969, 6966, 5714, 6965, 771, 899,
  verifiedFrontendLexer_reconstruct_item23_kernel,
  verifiedFrontendLexer_reconstruct_items24_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items22_kernel,
  22, 6970, 6967, 4826, 6966, 751, 771,
  verifiedFrontendLexer_reconstruct_item22_kernel,
  verifiedFrontendLexer_reconstruct_items23_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items21_kernel,
  21, 6971, 6968, 4678, 6967, 731, 751,
  verifiedFrontendLexer_reconstruct_item21_kernel,
  verifiedFrontendLexer_reconstruct_items22_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items20_kernel,
  20, 6972, 6969, 4530, 6968, 718, 731,
  verifiedFrontendLexer_reconstruct_item20_kernel,
  verifiedFrontendLexer_reconstruct_items21_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items19_kernel,
  19, 6973, 6970, 4474, 6969, 705, 718,
  verifiedFrontendLexer_reconstruct_item19_kernel,
  verifiedFrontendLexer_reconstruct_items20_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items18_kernel,
  18, 6974, 6971, 4418, 6970, 692, 705,
  verifiedFrontendLexer_reconstruct_item18_kernel,
  verifiedFrontendLexer_reconstruct_items19_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items17_kernel,
  17, 6975, 6972, 4362, 6971, 679, 692,
  verifiedFrontendLexer_reconstruct_item17_kernel,
  verifiedFrontendLexer_reconstruct_items18_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items16_kernel,
  16, 6976, 6973, 4332, 6972, 623, 679,
  verifiedFrontendLexer_reconstruct_item16_kernel,
  verifiedFrontendLexer_reconstruct_items17_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items15_kernel,
  15, 6977, 6974, 4012, 6973, 567, 623,
  verifiedFrontendLexer_reconstruct_item15_kernel,
  verifiedFrontendLexer_reconstruct_items16_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items14_kernel,
  14, 6978, 6975, 3692, 6974, 309, 567,
  verifiedFrontendLexer_reconstruct_item14_kernel,
  verifiedFrontendLexer_reconstruct_items15_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items13_kernel,
  13, 6979, 6976, 1905, 6975, 157, 309,
  verifiedFrontendLexer_reconstruct_item13_kernel,
  verifiedFrontendLexer_reconstruct_items14_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items12_kernel,
  12, 6980, 6977, 917, 6976, 125, 157,
  verifiedFrontendLexer_reconstruct_item12_kernel,
  verifiedFrontendLexer_reconstruct_items13_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items11_kernel,
  11, 6981, 6978, 729, 6977, 105, 125,
  verifiedFrontendLexer_reconstruct_item11_kernel,
  verifiedFrontendLexer_reconstruct_items12_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items10_kernel,
  10, 6982, 6979, 627, 6978, 81, 105,
  verifiedFrontendLexer_reconstruct_item10_kernel,
  verifiedFrontendLexer_reconstruct_items11_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items9_kernel,
  9, 6983, 6980, 477, 6979, 43, 81,
  verifiedFrontendLexer_reconstruct_item9_kernel,
  verifiedFrontendLexer_reconstruct_items10_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items8_kernel,
  8, 6984, 6981, 261, 6980, 38, 43,
  verifiedFrontendLexer_reconstruct_item8_kernel,
  verifiedFrontendLexer_reconstruct_items9_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items7_kernel,
  7, 6985, 6982, 226, 6981, 33, 38,
  verifiedFrontendLexer_reconstruct_item7_kernel,
  verifiedFrontendLexer_reconstruct_items8_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items6_kernel,
  6, 6986, 6983, 191, 6982, 28, 33,
  verifiedFrontendLexer_reconstruct_item6_kernel,
  verifiedFrontendLexer_reconstruct_items7_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items5_kernel,
  5, 6987, 6984, 156, 6983, 23, 28,
  verifiedFrontendLexer_reconstruct_item5_kernel,
  verifiedFrontendLexer_reconstruct_items6_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items4_kernel,
  4, 6988, 6985, 121, 6984, 18, 23,
  verifiedFrontendLexer_reconstruct_item4_kernel,
  verifiedFrontendLexer_reconstruct_items5_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items3_kernel,
  3, 6989, 6986, 86, 6985, 13, 18,
  verifiedFrontendLexer_reconstruct_item3_kernel,
  verifiedFrontendLexer_reconstruct_items4_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items2_kernel,
  2, 6990, 6987, 51, 6986, 8, 13,
  verifiedFrontendLexer_reconstruct_item2_kernel,
  verifiedFrontendLexer_reconstruct_items3_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items1_kernel,
  1, 6991, 6988, 16, 6987, 4, 8,
  verifiedFrontendLexer_reconstruct_item1_kernel,
  verifiedFrontendLexer_reconstruct_items2_kernel
lexer_items_step verifiedFrontendLexer_reconstruct_items0_kernel,
  0, 6992, 6989, 6, 6988, 0, 4,
  verifiedFrontendLexer_reconstruct_item0_kernel,
  verifiedFrontendLexer_reconstruct_items1_kernel

def verifiedFrontendLexerReconstructedTraceKernel : SurfaceFile := {
  id := 1107
  parse_node := 6990
  value := { items := verifiedFrontendLexerProposedItemsKernel }
}

theorem verifiedFrontendLexer_reconstruct_file_trace_kernel :
    (reconstructFile 6992 verifiedFrontendLexerArtifact 6990).run 0 =
      some (verifiedFrontendLexerReconstructedTraceKernel, 1108) := by
  exact reconstructFile_of (by with_unfolding_all rfl)
    (by with_unfolding_all rfl) verifiedFrontendLexer_reconstruct_items0_kernel

theorem verifiedFrontendLexer_reconstructed_trace_kernel :
    reconstructArtifactSurfaceView verifiedFrontendLexerArtifact
      verifiedFrontendLexerView =
        some verifiedFrontendLexerReconstructedTraceKernel := by
  unfold reconstructArtifactSurfaceView reconstructArtifactSurfaceWithAccess
  rw [show verifiedFrontendLexerArtifact.parse_root = some 6990 by
    with_unfolding_all rfl]
  rw [show verifiedFrontendLexerArtifact.parse_nodes.length + 1 = 6992 by
    with_unfolding_all rfl]
  simp [verifiedFrontendLexer_reconstruct_file_trace_kernel]

end Lanius.Extraction
