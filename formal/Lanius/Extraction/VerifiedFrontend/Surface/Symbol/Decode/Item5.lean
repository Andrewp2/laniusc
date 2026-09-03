import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction.ProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_decode_item5_present_kernel :
    (decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 5)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolDecodedItem5Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 5)).get
    verifiedFrontendSymbol_decode_item5_present_kernel
theorem verifiedFrontendSymbol_decode_item5_found_kernel :
    decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 5) =
      some verifiedFrontendSymbolDecodedItem5Kernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_decode_item5_present_kernel
end Lanius.Extraction
