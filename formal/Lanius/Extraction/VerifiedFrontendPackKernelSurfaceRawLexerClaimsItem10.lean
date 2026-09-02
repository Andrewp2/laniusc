import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_claims_item10_present_kernel :
    (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 10)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerClaimsItem10Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 10)).get
    verifiedFrontendRawLexer_claims_item10_present_kernel
theorem verifiedFrontendRawLexer_claims_item10_found_kernel :
    collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 10) =
      some verifiedFrontendRawLexerClaimsItem10Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_claims_item10_present_kernel
end Lanius.Extraction
