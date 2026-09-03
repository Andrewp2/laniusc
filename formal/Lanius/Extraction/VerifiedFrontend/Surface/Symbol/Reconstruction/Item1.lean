import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendSymbolAccessItem1 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendSymbolView
theorem verifiedFrontendSymbol_reconstruct_item1_kernel :
    (reconstructItem 8243 verifiedFrontendSymbolArtifact 14).run 4 =
      some (verifiedFrontendSymbolProposedItemKernel 1, 8) := by
  with_unfolding_all rfl
end Lanius.Extraction
