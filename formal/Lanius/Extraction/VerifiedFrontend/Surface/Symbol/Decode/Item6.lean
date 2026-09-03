import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.ProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_decode_item6_present_kernel :
    (decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 6)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolDecodedItem6Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 6)).get
    verifiedFrontendSymbol_decode_item6_present_kernel
theorem verifiedFrontendSymbol_decode_item6_found_kernel :
    decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 6) =
      some verifiedFrontendSymbolDecodedItem6Kernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_decode_item6_present_kernel
end Lanius.Extraction
