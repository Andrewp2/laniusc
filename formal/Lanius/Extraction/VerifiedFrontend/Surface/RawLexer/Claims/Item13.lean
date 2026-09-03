import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_claims_item13_present_kernel :
    (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 13)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerClaimsItem13Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 13)).get
    verifiedFrontendRawLexer_claims_item13_present_kernel
theorem verifiedFrontendRawLexer_claims_item13_found_kernel :
    collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 13) =
      some verifiedFrontendRawLexerClaimsItem13Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_claims_item13_present_kernel
end Lanius.Extraction
