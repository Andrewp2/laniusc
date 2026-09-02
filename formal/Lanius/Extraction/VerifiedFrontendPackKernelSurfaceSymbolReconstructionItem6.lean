import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolView
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendSymbolAccessItem6 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendSymbolView
theorem verifiedFrontendSymbol_reconstruct_item6_kernel :
    (reconstructItem 8238 verifiedFrontendSymbolArtifact 8234).run 67 =
      some (verifiedFrontendSymbolProposedItemKernel 6, 999) := by
  with_unfolding_all rfl
end Lanius.Extraction
