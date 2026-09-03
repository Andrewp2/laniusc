import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction.ProposedItems
import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_decode_item1_present_kernel :
    (decodeSurfaceItem 10312 (verifiedFrontendCanonicalTokensProposedItemKernel 1)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensDecodedItem1Kernel : Lanius.Surface.Item :=
  (decodeSurfaceItem 10312 (verifiedFrontendCanonicalTokensProposedItemKernel 1)).get
    verifiedFrontendCanonicalTokens_decode_item1_present_kernel
theorem verifiedFrontendCanonicalTokens_decode_item1_found_kernel :
    decodeSurfaceItem 10312 (verifiedFrontendCanonicalTokensProposedItemKernel 1) =
      some verifiedFrontendCanonicalTokensDecodedItem1Kernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_decode_item1_present_kernel
end Lanius.Extraction
