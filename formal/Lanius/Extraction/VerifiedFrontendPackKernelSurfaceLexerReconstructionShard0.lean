import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerView
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
local instance verifiedFrontendLexerAccessShard0 : ArtifactAccess :=
  ArtifactAccess.ofView verifiedFrontendLexerView

theorem verifiedFrontendLexer_reconstruct_item0_kernel :
    (reconstructItem 6991 verifiedFrontendLexerArtifact 6).run 0 =
      some (verifiedFrontendLexerProposedItemKernel 0, 4) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item1_kernel :
    (reconstructItem 6990 verifiedFrontendLexerArtifact 16).run 4 =
      some (verifiedFrontendLexerProposedItemKernel 1, 8) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item2_kernel :
    (reconstructItem 6989 verifiedFrontendLexerArtifact 51).run 8 =
      some (verifiedFrontendLexerProposedItemKernel 2, 13) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item3_kernel :
    (reconstructItem 6988 verifiedFrontendLexerArtifact 86).run 13 =
      some (verifiedFrontendLexerProposedItemKernel 3, 18) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item4_kernel :
    (reconstructItem 6987 verifiedFrontendLexerArtifact 121).run 18 =
      some (verifiedFrontendLexerProposedItemKernel 4, 23) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item5_kernel :
    (reconstructItem 6986 verifiedFrontendLexerArtifact 156).run 23 =
      some (verifiedFrontendLexerProposedItemKernel 5, 28) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item6_kernel :
    (reconstructItem 6985 verifiedFrontendLexerArtifact 191).run 28 =
      some (verifiedFrontendLexerProposedItemKernel 6, 33) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item7_kernel :
    (reconstructItem 6984 verifiedFrontendLexerArtifact 226).run 33 =
      some (verifiedFrontendLexerProposedItemKernel 7, 38) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item8_kernel :
    (reconstructItem 6983 verifiedFrontendLexerArtifact 261).run 38 =
      some (verifiedFrontendLexerProposedItemKernel 8, 43) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item9_kernel :
    (reconstructItem 6982 verifiedFrontendLexerArtifact 477).run 43 =
      some (verifiedFrontendLexerProposedItemKernel 9, 81) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item10_kernel :
    (reconstructItem 6981 verifiedFrontendLexerArtifact 627).run 81 =
      some (verifiedFrontendLexerProposedItemKernel 10, 105) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item11_kernel :
    (reconstructItem 6980 verifiedFrontendLexerArtifact 729).run 105 =
      some (verifiedFrontendLexerProposedItemKernel 11, 125) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item12_kernel :
    (reconstructItem 6979 verifiedFrontendLexerArtifact 917).run 125 =
      some (verifiedFrontendLexerProposedItemKernel 12, 157) := by with_unfolding_all rfl
end Lanius.Extraction
