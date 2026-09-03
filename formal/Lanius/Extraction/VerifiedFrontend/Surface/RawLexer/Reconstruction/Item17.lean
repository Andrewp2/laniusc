import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Reconstruction.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem17 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item17_kernel :
    (reconstructItem 5950 verifiedFrontendRawLexerArtifact 5946).run 712 =
      some (verifiedFrontendRawLexerProposedItemKernel 17, 902) := by
  with_unfolding_all rfl
end Lanius.Extraction
