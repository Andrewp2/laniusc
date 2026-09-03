import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Reconstruction.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem11 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item11_kernel :
    (reconstructItem 5956 verifiedFrontendRawLexerArtifact 293).run 65 =
      some (verifiedFrontendRawLexerProposedItemKernel 11, 78) := by
  with_unfolding_all rfl
end Lanius.Extraction
