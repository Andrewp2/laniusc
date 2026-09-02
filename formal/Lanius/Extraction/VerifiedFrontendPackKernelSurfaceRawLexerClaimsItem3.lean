import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_claims_item3_present_kernel :
    (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 3)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerClaimsItem3Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 3)).get
    verifiedFrontendRawLexer_claims_item3_present_kernel
theorem verifiedFrontendRawLexer_claims_item3_found_kernel :
    collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 3) =
      some verifiedFrontendRawLexerClaimsItem3Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_claims_item3_present_kernel
end Lanius.Extraction
