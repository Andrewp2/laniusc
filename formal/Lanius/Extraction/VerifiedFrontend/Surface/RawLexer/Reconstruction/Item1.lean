import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem1 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item1_kernel :
    (reconstructItem 5966 verifiedFrontendRawLexerArtifact 14).run 4 =
      some (verifiedFrontendRawLexerProposedItemKernel 1, 8) := by
  with_unfolding_all rfl
end Lanius.Extraction
