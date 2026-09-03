import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendSymbolAccessItem2 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendSymbolView
theorem verifiedFrontendSymbol_reconstruct_item2_kernel :
    (reconstructItem 8242 verifiedFrontendSymbolArtifact 36).run 8 =
      some (verifiedFrontendSymbolProposedItemKernel 2, 17) := by
  with_unfolding_all rfl
end Lanius.Extraction
