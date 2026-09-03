import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Reconstruction.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
local instance verifiedFrontendLexerAccessShard5 : ArtifactAccess :=
  ArtifactAccess.ofView verifiedFrontendLexerView
theorem verifiedFrontendLexer_reconstruct_item23_kernel :
    (reconstructItem 6968 verifiedFrontendLexerArtifact 5714).run 771 =
      some (verifiedFrontendLexerProposedItemKernel 23, 899) := by with_unfolding_all rfl
end Lanius.Extraction
