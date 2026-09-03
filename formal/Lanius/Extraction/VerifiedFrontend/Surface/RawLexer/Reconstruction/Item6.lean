import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem6 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item6_kernel :
    (reconstructItem 5961 verifiedFrontendRawLexerArtifact 81).run 24 =
      some (verifiedFrontendRawLexerProposedItemKernel 6, 29) := by
  with_unfolding_all rfl
end Lanius.Extraction
