import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem2 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item2_kernel :
    (reconstructItem 5965 verifiedFrontendRawLexerArtifact 22).run 8 =
      some (verifiedFrontendRawLexerProposedItemKernel 2, 12) := by
  with_unfolding_all rfl
end Lanius.Extraction
