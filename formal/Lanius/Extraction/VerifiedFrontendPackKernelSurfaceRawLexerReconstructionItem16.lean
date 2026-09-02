import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerView
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendRawLexerAccessItem16 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendRawLexerView
theorem verifiedFrontendRawLexer_reconstruct_item16_kernel :
    (reconstructItem 5951 verifiedFrontendRawLexerArtifact 4624).run 169 =
      some (verifiedFrontendRawLexerProposedItemKernel 16, 712) := by
  with_unfolding_all rfl
end Lanius.Extraction
