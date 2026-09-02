import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolProposedItems
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolView
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendSymbolAccessItem2 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendSymbolView
theorem verifiedFrontendSymbol_reconstruct_item2_kernel :
    (reconstructItem 8242 verifiedFrontendSymbolArtifact 36).run 8 =
      some (verifiedFrontendSymbolProposedItemKernel 2, 17) := by
  with_unfolding_all rfl
end Lanius.Extraction
