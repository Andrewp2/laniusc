import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_decode_item3_present_kernel :
    (decodeSurfaceItem 10312 (verifiedFrontendCanonicalTokensProposedItemKernel 3)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensDecodedItem3Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 10312 (verifiedFrontendCanonicalTokensProposedItemKernel 3)).get
    verifiedFrontendCanonicalTokens_decode_item3_present_kernel
theorem verifiedFrontendCanonicalTokens_decode_item3_found_kernel :
    decodeSurfaceItem 10312 (verifiedFrontendCanonicalTokensProposedItemKernel 3) =
      some verifiedFrontendCanonicalTokensDecodedItem3Kernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_decode_item3_present_kernel
end Lanius.Extraction
