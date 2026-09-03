import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.ProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_decode_item2_present_kernel :
    (decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 2)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolDecodedItem2Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 2)).get
    verifiedFrontendSymbol_decode_item2_present_kernel
theorem verifiedFrontendSymbol_decode_item2_found_kernel :
    decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 2) =
      some verifiedFrontendSymbolDecodedItem2Kernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_decode_item2_present_kernel
end Lanius.Extraction
