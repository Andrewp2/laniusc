import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Reconstruction.ProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_decode_item9_present_kernel :
    (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 9)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerDecodedItem9Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 9)).get
    verifiedFrontendRawLexer_decode_item9_present_kernel
theorem verifiedFrontendRawLexer_decode_item9_found_kernel :
    decodeSurfaceItem 5968 (verifiedFrontendRawLexerProposedItemKernel 9) =
      some verifiedFrontendRawLexerDecodedItem9Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_decode_item9_present_kernel
end Lanius.Extraction
