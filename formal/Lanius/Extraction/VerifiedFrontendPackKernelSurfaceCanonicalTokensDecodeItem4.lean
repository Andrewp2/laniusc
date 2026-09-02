import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_decode_item4_present_kernel :
    (decodeSurfaceItem 10312 (verifiedFrontendCanonicalTokensProposedItemKernel 4)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensDecodedItem4Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 10312 (verifiedFrontendCanonicalTokensProposedItemKernel 4)).get
    verifiedFrontendCanonicalTokens_decode_item4_present_kernel
theorem verifiedFrontendCanonicalTokens_decode_item4_found_kernel :
    decodeSurfaceItem 10312 (verifiedFrontendCanonicalTokensProposedItemKernel 4) =
      some verifiedFrontendCanonicalTokensDecodedItem4Kernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_decode_item4_present_kernel
end Lanius.Extraction
