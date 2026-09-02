import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolView
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendSymbolAccessItem1 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendSymbolView
theorem verifiedFrontendSymbol_reconstruct_item1_kernel :
    (reconstructItem 8243 verifiedFrontendSymbolArtifact 14).run 4 =
      some (verifiedFrontendSymbolProposedItemKernel 1, 8) := by
  with_unfolding_all rfl
end Lanius.Extraction
