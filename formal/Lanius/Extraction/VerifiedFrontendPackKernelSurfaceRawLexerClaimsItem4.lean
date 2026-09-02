import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_claims_item4_present_kernel :
    (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 4)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerClaimsItem4Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 4)).get
    verifiedFrontendRawLexer_claims_item4_present_kernel
theorem verifiedFrontendRawLexer_claims_item4_found_kernel :
    collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 4) =
      some verifiedFrontendRawLexerClaimsItem4Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_claims_item4_present_kernel
end Lanius.Extraction
