import Lanius.Extraction.VerifiedFrontendPackKernelContextHeadersUnit0
import Lanius.Extraction.VerifiedFrontendPackKernelContextHeadersUnit1
import Lanius.Extraction.VerifiedFrontendPackKernelContextHeadersUnit2
import Lanius.Extraction.VerifiedFrontendPackKernelContextHeadersUnit3
import Lanius.Extraction.VerifiedFrontendPackKernelContextHeadersUnit4
import Lanius.Extraction.VerifiedFrontendPackKernelContextHeadersUnit5
import Lanius.Extraction.VerifiedFrontendPackKernelContextHeadersUnit6
import Lanius.Extraction.VerifiedFrontendPackKernelContextHeadersUnit7
import Lanius.Extraction.VerifiedFrontendPackKernelContextHeadersUnit8
namespace Lanius.Extraction
open ArtifactPackContextChecker
def verifiedFrontendPackContextHeadersKernel : PackHeaders :=
  verifiedFrontendLexerContextHeadersKernel.append
    (verifiedFrontendTokenScanContextHeadersKernel.append
      (verifiedFrontendDigitsContextHeadersKernel.append
        (verifiedFrontendTokenContextHeadersKernel.append
          (verifiedFrontendCanonicalTokensContextHeadersKernel.append
            (verifiedFrontendDecimalContextHeadersKernel.append
              (verifiedFrontendNumberContextHeadersKernel.append
                (verifiedFrontendSymbolContextHeadersKernel.append
                  (verifiedFrontendRawLexerContextHeadersKernel.append
                    ⟨[], [], [], []⟩))))))))
theorem verifiedFrontendPack_context_headers_found_kernel :
    buildPackHeaders verifiedFrontendPackAllocationsKernel =
      some verifiedFrontendPackContextHeadersKernel := by
  rw [verifiedFrontendPack_allocations_explicit_kernel]
  unfold verifiedFrontendPackAllocationsExplicitKernel
  apply buildPackHeaders_cons_of _ _ _ _
    verifiedFrontendLexer_context_headers_found_kernel
  apply buildPackHeaders_cons_of _ _ _ _
    verifiedFrontendTokenScan_context_headers_found_kernel
  apply buildPackHeaders_cons_of _ _ _ _
    verifiedFrontendDigits_context_headers_found_kernel
  apply buildPackHeaders_cons_of _ _ _ _
    verifiedFrontendToken_context_headers_found_kernel
  apply buildPackHeaders_cons_of _ _ _ _
    verifiedFrontendCanonicalTokens_context_headers_found_kernel
  apply buildPackHeaders_cons_of _ _ _ _
    verifiedFrontendDecimal_context_headers_found_kernel
  apply buildPackHeaders_cons_of _ _ _ _
    verifiedFrontendNumber_context_headers_found_kernel
  apply buildPackHeaders_cons_of _ _ _ _
    verifiedFrontendSymbol_context_headers_found_kernel
  apply buildPackHeaders_cons_of _ _ _ _
    verifiedFrontendRawLexer_context_headers_found_kernel
  simp only [buildPackHeaders, verifiedFrontendPackContextHeadersKernel]

theorem verifiedFrontendPack_context_headers_present_kernel :
    (buildPackHeaders verifiedFrontendPackAllocationsKernel).isSome = true := by
  rw [verifiedFrontendPack_context_headers_found_kernel]
  rfl
end Lanius.Extraction
