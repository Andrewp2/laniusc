import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerView
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem13 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item13_kernel :
    (reconstructItem 5954 verifiedFrontendRawLexerArtifact 502).run 91 =
      some (verifiedFrontendRawLexerProposedItemKernel 13, 113) := by
  with_unfolding_all rfl
end Lanius.Extraction
