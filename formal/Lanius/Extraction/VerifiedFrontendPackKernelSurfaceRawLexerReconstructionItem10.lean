import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerView
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem10 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item10_kernel :
    (reconstructItem 5957 verifiedFrontendRawLexerArtifact 237).run 52 =
      some (verifiedFrontendRawLexerProposedItemKernel 10, 65) := by
  with_unfolding_all rfl
end Lanius.Extraction
