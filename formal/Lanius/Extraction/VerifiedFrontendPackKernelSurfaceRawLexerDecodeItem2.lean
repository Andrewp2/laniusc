import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_decode_item2_present_kernel :
    (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 2)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerDecodedItem2Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 2)).get
    verifiedFrontendRawLexer_decode_item2_present_kernel
theorem verifiedFrontendRawLexer_decode_item2_found_kernel :
    decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 2) =
      some verifiedFrontendRawLexerDecodedItem2Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_decode_item2_present_kernel
end Lanius.Extraction
