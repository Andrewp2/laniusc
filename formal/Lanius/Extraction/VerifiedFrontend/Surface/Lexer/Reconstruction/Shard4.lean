import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Reconstruction.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
local instance verifiedFrontendLexerAccessShard4 : ArtifactAccess :=
  ArtifactAccess.ofView verifiedFrontendLexerView
theorem verifiedFrontendLexer_reconstruct_item21_kernel :
    (reconstructItem 6970 verifiedFrontendLexerArtifact 4678).run 731 =
      some (verifiedFrontendLexerProposedItemKernel 21, 751) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item22_kernel :
    (reconstructItem 6969 verifiedFrontendLexerArtifact 4826).run 751 =
      some (verifiedFrontendLexerProposedItemKernel 22, 771) := by with_unfolding_all rfl
end Lanius.Extraction
