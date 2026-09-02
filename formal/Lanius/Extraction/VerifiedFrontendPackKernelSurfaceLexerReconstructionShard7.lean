import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerView
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
local instance verifiedFrontendLexerAccessShard7 : ArtifactAccess :=
  ArtifactAccess.ofView verifiedFrontendLexerView
theorem verifiedFrontendLexer_reconstruct_item27_kernel :
    (reconstructItem 6964 verifiedFrontendLexerArtifact 6960).run 1017 =
      some (verifiedFrontendLexerProposedItemKernel 27, 1107) := by with_unfolding_all rfl
end Lanius.Extraction
