import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Reconstruction.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem12 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item12_kernel :
    (reconstructItem 5955 verifiedFrontendRawLexerArtifact 349).run 78 =
      some (verifiedFrontendRawLexerProposedItemKernel 12, 91) := by
  with_unfolding_all rfl
end Lanius.Extraction
