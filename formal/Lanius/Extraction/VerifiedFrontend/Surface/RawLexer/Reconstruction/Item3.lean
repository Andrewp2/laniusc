import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem3 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item3_kernel :
    (reconstructItem 5964 verifiedFrontendRawLexerArtifact 30).run 12 =
      some (verifiedFrontendRawLexerProposedItemKernel 3, 16) := by
  with_unfolding_all rfl
end Lanius.Extraction
