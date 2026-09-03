import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_claims_item2_present_kernel :
    (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 2)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerClaimsItem2Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 2)).get
    verifiedFrontendRawLexer_claims_item2_present_kernel
theorem verifiedFrontendRawLexer_claims_item2_found_kernel :
    collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 2) =
      some verifiedFrontendRawLexerClaimsItem2Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_claims_item2_present_kernel
end Lanius.Extraction
