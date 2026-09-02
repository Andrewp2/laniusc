import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerView
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem8 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item8_kernel :
    (reconstructItem 5959 verifiedFrontendRawLexerArtifact 151).run 34 =
      some (verifiedFrontendRawLexerProposedItemKernel 8, 39) := by
  with_unfolding_all rfl
end Lanius.Extraction
