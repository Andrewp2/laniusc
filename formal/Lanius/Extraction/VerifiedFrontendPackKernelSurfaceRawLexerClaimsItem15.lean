import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_claims_item15_present_kernel :
    (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 15)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerClaimsItem15Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 15)).get
    verifiedFrontendRawLexer_claims_item15_present_kernel
theorem verifiedFrontendRawLexer_claims_item15_found_kernel :
    collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 15) =
      some verifiedFrontendRawLexerClaimsItem15Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_claims_item15_present_kernel
end Lanius.Extraction
