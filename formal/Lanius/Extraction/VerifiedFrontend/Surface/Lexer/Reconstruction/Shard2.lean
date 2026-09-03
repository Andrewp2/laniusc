import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.View.Assembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

local instance verifiedFrontendLexerAccessShard2 : ArtifactAccess :=
  ArtifactAccess.ofView verifiedFrontendLexerView

theorem verifiedFrontendLexer_reconstruct_item14_kernel :
    (reconstructItem 6977 verifiedFrontendLexerArtifact 3692).run 309 =
      some (verifiedFrontendLexerProposedItemKernel 14, 567) := by
  with_unfolding_all rfl

end Lanius.Extraction
