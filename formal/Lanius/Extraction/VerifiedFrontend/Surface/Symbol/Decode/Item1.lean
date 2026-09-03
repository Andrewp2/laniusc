import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.ProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_decode_item1_present_kernel :
    (decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 1)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolDecodedItem1Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 1)).get
    verifiedFrontendSymbol_decode_item1_present_kernel
theorem verifiedFrontendSymbol_decode_item1_found_kernel :
    decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 1) =
      some verifiedFrontendSymbolDecodedItem1Kernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_decode_item1_present_kernel
end Lanius.Extraction
