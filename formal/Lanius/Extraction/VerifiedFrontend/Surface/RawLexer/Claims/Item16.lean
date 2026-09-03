import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_claims_item16_present_kernel :
    (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 16)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerClaimsItem16Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 16)).get
    verifiedFrontendRawLexer_claims_item16_present_kernel
theorem verifiedFrontendRawLexer_claims_item16_found_kernel :
    collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 16) =
      some verifiedFrontendRawLexerClaimsItem16Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_claims_item16_present_kernel
end Lanius.Extraction
