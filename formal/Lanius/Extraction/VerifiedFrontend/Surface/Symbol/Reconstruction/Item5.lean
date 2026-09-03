import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendSymbolAccessItem5 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendSymbolView
theorem verifiedFrontendSymbol_reconstruct_item5_kernel :
    (reconstructItem 8239 verifiedFrontendSymbolArtifact 278).run 43 =
      some (verifiedFrontendSymbolProposedItemKernel 5, 67) := by
  with_unfolding_all rfl
end Lanius.Extraction
