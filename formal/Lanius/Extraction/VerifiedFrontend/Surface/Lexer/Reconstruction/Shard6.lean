import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Reconstruction.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
local instance verifiedFrontendLexerAccessShard6 : ArtifactAccess :=
  ArtifactAccess.ofView verifiedFrontendLexerView
theorem verifiedFrontendLexer_reconstruct_item24_kernel :
    (reconstructItem 6967 verifiedFrontendLexerArtifact 5916).run 899 =
      some (verifiedFrontendLexerProposedItemKernel 24, 931) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item25_kernel :
    (reconstructItem 6966 verifiedFrontendLexerArtifact 6118).run 931 =
      some (verifiedFrontendLexerProposedItemKernel 25, 963) := by with_unfolding_all rfl
theorem verifiedFrontendLexer_reconstruct_item26_kernel :
    (reconstructItem 6965 verifiedFrontendLexerArtifact 6417).run 963 =
      some (verifiedFrontendLexerProposedItemKernel 26, 1017) := by with_unfolding_all rfl
end Lanius.Extraction
