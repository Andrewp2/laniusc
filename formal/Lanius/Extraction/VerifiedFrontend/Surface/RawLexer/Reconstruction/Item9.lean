import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem9 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item9_kernel :
    (reconstructItem 5958 verifiedFrontendRawLexerArtifact 181).run 39 =
      some (verifiedFrontendRawLexerProposedItemKernel 9, 52) := by
  with_unfolding_all rfl
end Lanius.Extraction
