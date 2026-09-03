import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem7 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item7_kernel :
    (reconstructItem 5960 verifiedFrontendRawLexerArtifact 116).run 29 =
      some (verifiedFrontendRawLexerProposedItemKernel 7, 34) := by
  with_unfolding_all rfl
end Lanius.Extraction
