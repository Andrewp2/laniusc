import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Reconstruction.ProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_decode_item15_present_kernel :
    (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 15)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerDecodedItem15Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 15)).get
    verifiedFrontendRawLexer_decode_item15_present_kernel
theorem verifiedFrontendRawLexer_decode_item15_found_kernel :
    decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 15) =
      some verifiedFrontendRawLexerDecodedItem15Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_decode_item15_present_kernel
end Lanius.Extraction
