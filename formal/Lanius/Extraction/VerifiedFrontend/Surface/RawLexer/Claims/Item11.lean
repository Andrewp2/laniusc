import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_claims_item11_present_kernel :
    (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 11)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerClaimsItem11Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 11)).get
    verifiedFrontendRawLexer_claims_item11_present_kernel
theorem verifiedFrontendRawLexer_claims_item11_found_kernel :
    collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 11) =
      some verifiedFrontendRawLexerClaimsItem11Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_claims_item11_present_kernel
end Lanius.Extraction
