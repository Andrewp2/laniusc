import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_decode_item7_present_kernel :
    (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 7)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerDecodedItem7Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 7)).get
    verifiedFrontendRawLexer_decode_item7_present_kernel
theorem verifiedFrontendRawLexer_decode_item7_found_kernel :
    decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 7) =
      some verifiedFrontendRawLexerDecodedItem7Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_decode_item7_present_kernel
end Lanius.Extraction
