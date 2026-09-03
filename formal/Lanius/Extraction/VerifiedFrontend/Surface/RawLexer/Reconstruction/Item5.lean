import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Reconstruction.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem5 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item5_kernel :
    (reconstructItem 5962 verifiedFrontendRawLexerArtifact 46).run 20 =
      some (verifiedFrontendRawLexerProposedItemKernel 5, 24) := by
  with_unfolding_all rfl
end Lanius.Extraction
