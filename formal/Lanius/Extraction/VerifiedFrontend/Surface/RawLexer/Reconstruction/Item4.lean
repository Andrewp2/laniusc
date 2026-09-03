import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Reconstruction.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem4 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item4_kernel :
    (reconstructItem 5963 verifiedFrontendRawLexerArtifact 38).run 16 =
      some (verifiedFrontendRawLexerProposedItemKernel 4, 20) := by
  with_unfolding_all rfl
end Lanius.Extraction
