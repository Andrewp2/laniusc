import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem14 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item14_kernel :
    (reconstructItem 5953 verifiedFrontendRawLexerArtifact 667).run 113 =
      some (verifiedFrontendRawLexerProposedItemKernel 14, 141) := by
  with_unfolding_all rfl
end Lanius.Extraction
