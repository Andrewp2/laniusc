import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_decode_item0_present_kernel :
    (decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 0)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolDecodedItem0Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 0)).get
    verifiedFrontendSymbol_decode_item0_present_kernel
theorem verifiedFrontendSymbol_decode_item0_found_kernel :
    decodeSurfaceItem 8245 (verifiedFrontendSymbolProposedItemKernel 0) =
      some verifiedFrontendSymbolDecodedItem0Kernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_decode_item0_present_kernel
end Lanius.Extraction
