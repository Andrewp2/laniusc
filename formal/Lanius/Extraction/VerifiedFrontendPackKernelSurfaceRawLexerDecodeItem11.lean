import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_decode_item11_present_kernel :
    (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 11)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerDecodedItem11Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 11)).get
    verifiedFrontendRawLexer_decode_item11_present_kernel
theorem verifiedFrontendRawLexer_decode_item11_found_kernel :
    decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 11) =
      some verifiedFrontendRawLexerDecodedItem11Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_decode_item11_present_kernel
end Lanius.Extraction
