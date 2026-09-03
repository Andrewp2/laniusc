import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Reconstruction.ProposedItems
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_claims_item9_present_kernel :
    (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 9)).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerClaimsItem9Kernel : SurfaceClaims :=
  (collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 9)).get
    verifiedFrontendRawLexer_claims_item9_present_kernel
theorem verifiedFrontendRawLexer_claims_item9_found_kernel :
    collectItemClaimsWithFuel 1086 5966 (verifiedFrontendRawLexerProposedItemKernel 9) =
      some verifiedFrontendRawLexerClaimsItem9Kernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_claims_item9_present_kernel
end Lanius.Extraction
