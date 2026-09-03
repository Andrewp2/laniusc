import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.ProposedItems
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
local instance verifiedFrontendSymbolAccessItem4 : ArtifactAccess := ArtifactAccess.ofView verifiedFrontendSymbolView
theorem verifiedFrontendSymbol_reconstruct_item4_kernel :
    (reconstructItem 8240 verifiedFrontendSymbolArtifact 148).run 30 =
      some (verifiedFrontendSymbolProposedItemKernel 4, 43) := by
  with_unfolding_all rfl
end Lanius.Extraction
