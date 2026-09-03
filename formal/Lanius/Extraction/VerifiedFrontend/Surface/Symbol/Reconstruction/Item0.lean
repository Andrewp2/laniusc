import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendSymbolAccessItem0 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendSymbolView
theorem verifiedFrontendSymbol_reconstruct_item0_kernel :
    (reconstructItem 8244 verifiedFrontendSymbolArtifact 6).run 0 =
      some (verifiedFrontendSymbolProposedItemKernel 0, 4) := by
  with_unfolding_all rfl
end Lanius.Extraction
