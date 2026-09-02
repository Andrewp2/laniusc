import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerView
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
local instance verifiedFrontendLexerAccessShard3 : ArtifactAccess :=
  ArtifactAccess.ofView verifiedFrontendLexerView
theorem verifiedFrontendLexer_reconstruct_item15_kernel :
    (reconstructItem 6976 verifiedFrontendLexerArtifact 4012).run 567 =
      some (verifiedFrontendLexerProposedItemKernel 15, 623) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item16_kernel :
    (reconstructItem 6975 verifiedFrontendLexerArtifact 4332).run 623 =
      some (verifiedFrontendLexerProposedItemKernel 16, 679) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item17_kernel :
    (reconstructItem 6974 verifiedFrontendLexerArtifact 4362).run 679 =
      some (verifiedFrontendLexerProposedItemKernel 17, 692) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item18_kernel :
    (reconstructItem 6973 verifiedFrontendLexerArtifact 4418).run 692 =
      some (verifiedFrontendLexerProposedItemKernel 18, 705) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item19_kernel :
    (reconstructItem 6972 verifiedFrontendLexerArtifact 4474).run 705 =
      some (verifiedFrontendLexerProposedItemKernel 19, 718) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item20_kernel :
    (reconstructItem 6971 verifiedFrontendLexerArtifact 4530).run 718 =
      some (verifiedFrontendLexerProposedItemKernel 20, 731) := by with_unfolding_all rfl
end Lanius.Extraction
