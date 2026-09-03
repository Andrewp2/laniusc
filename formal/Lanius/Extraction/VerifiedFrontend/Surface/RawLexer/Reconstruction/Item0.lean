import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Reconstruction.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem0 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item0_kernel :
    (reconstructItem 5967 verifiedFrontendRawLexerArtifact 6).run 0 =
      some (verifiedFrontendRawLexerProposedItemKernel 0, 4) := by
  with_unfolding_all rfl
end Lanius.Extraction
