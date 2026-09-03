import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem15 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item15_kernel :
    (reconstructItem 5952 verifiedFrontendRawLexerArtifact 832).run 141 =
      some (verifiedFrontendRawLexerProposedItemKernel 15, 169) := by
  with_unfolding_all rfl
end Lanius.Extraction
