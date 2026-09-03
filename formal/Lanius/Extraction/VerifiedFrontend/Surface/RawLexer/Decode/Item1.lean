import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_decode_item1_present_kernel :
    (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 1)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerDecodedItem1Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 1)).get
    verifiedFrontendRawLexer_decode_item1_present_kernel
theorem verifiedFrontendRawLexer_decode_item1_found_kernel :
    decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 1) =
      some verifiedFrontendRawLexerDecodedItem1Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_decode_item1_present_kernel
end Lanius.Extraction
