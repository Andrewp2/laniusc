import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerView
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
local instance verifiedFrontendLexerAccessShard1 : ArtifactAccess :=
  ArtifactAccess.ofView verifiedFrontendLexerView
theorem verifiedFrontendLexer_reconstruct_item13_kernel :
    (reconstructItem 6978 verifiedFrontendLexerArtifact 1905).run 157 =
      some (verifiedFrontendLexerProposedItemKernel 13, 309) := by with_unfolding_all rfl
end Lanius.Extraction
