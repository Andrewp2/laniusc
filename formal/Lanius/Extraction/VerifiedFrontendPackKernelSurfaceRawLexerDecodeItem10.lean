import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_decode_item10_present_kernel :
    (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 10)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerDecodedItem10Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 10)).get
    verifiedFrontendRawLexer_decode_item10_present_kernel
theorem verifiedFrontendRawLexer_decode_item10_found_kernel :
    decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 10) =
      some verifiedFrontendRawLexerDecodedItem10Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_decode_item10_present_kernel
end Lanius.Extraction
