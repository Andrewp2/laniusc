import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolView
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendSymbolAccessItem3 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendSymbolView
theorem verifiedFrontendSymbol_reconstruct_item3_kernel :
    (reconstructItem 8241 verifiedFrontendSymbolArtifact 92).run 17 =
      some (verifiedFrontendSymbolProposedItemKernel 3, 30) := by
  with_unfolding_all rfl
end Lanius.Extraction
