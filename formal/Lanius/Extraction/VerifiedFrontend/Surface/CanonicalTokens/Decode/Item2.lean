import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.ProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_decode_item2_present_kernel :
    (decodeSurfaceItem 10312 (verifiedFrontendCanonicalTokensProposedItemKernel 2)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensDecodedItem2Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 10312 (verifiedFrontendCanonicalTokensProposedItemKernel 2)).get
    verifiedFrontendCanonicalTokens_decode_item2_present_kernel
theorem verifiedFrontendCanonicalTokens_decode_item2_found_kernel :
    decodeSurfaceItem 10312 (verifiedFrontendCanonicalTokensProposedItemKernel 2) =
      some verifiedFrontendCanonicalTokensDecodedItem2Kernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_decode_item2_present_kernel
end Lanius.Extraction
