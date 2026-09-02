import Lanius.Extraction.VerifiedFrontendPackKernelContextConstantsUnit0
import Lanius.Extraction.VerifiedFrontendPackKernelContextConstantsUnit1
import Lanius.Extraction.VerifiedFrontendPackKernelContextConstantsUnit2
import Lanius.Extraction.VerifiedFrontendPackKernelContextConstantsUnit3
import Lanius.Extraction.VerifiedFrontendPackKernelContextConstantsUnit4
import Lanius.Extraction.VerifiedFrontendPackKernelContextConstantsUnit5
import Lanius.Extraction.VerifiedFrontendPackKernelContextConstantsUnit6
import Lanius.Extraction.VerifiedFrontendPackKernelContextConstantsUnit7
import Lanius.Extraction.VerifiedFrontendPackKernelContextConstantsUnit8

namespace Lanius.Extraction
set_option maxRecDepth 100000
open ArtifactPackContextChecker
def verifiedFrontendPackContextConstantsKernel :
    List Lanius.SurfaceElaboration.ConstantEntry :=
  verifiedFrontendLexerContextConstantsKernel ++
    (verifiedFrontendTokenScanContextConstantsKernel ++
      (verifiedFrontendDigitsContextConstantsKernel ++
        (verifiedFrontendTokenContextConstantsKernel ++
          (verifiedFrontendCanonicalTokensContextConstantsKernel ++
            (verifiedFrontendDecimalContextConstantsKernel ++
              (verifiedFrontendNumberContextConstantsKernel ++
                (verifiedFrontendSymbolContextConstantsKernel ++
                  (verifiedFrontendRawLexerContextConstantsKernel ++ []))))))))
theorem verifiedFrontendPack_context_constants_found_kernel :
    buildPackConstants verifiedFrontendPackDeclarationContextKernel
      verifiedFrontendPackAllocationsKernel =
        some verifiedFrontendPackContextConstantsKernel := by
  rw [verifiedFrontendPack_allocations_explicit_kernel]
  unfold verifiedFrontendPackAllocationsExplicitKernel
    verifiedFrontendPackContextConstantsKernel
  apply buildPackConstants_cons_of _ _ _ _ _
    verifiedFrontendLexer_context_constants_found_kernel
  apply buildPackConstants_cons_of _ _ _ _ _
    verifiedFrontendTokenScan_context_constants_found_kernel
  apply buildPackConstants_cons_of _ _ _ _ _
    verifiedFrontendDigits_context_constants_found_kernel
  apply buildPackConstants_cons_of _ _ _ _ _
    verifiedFrontendToken_context_constants_found_kernel
  apply buildPackConstants_cons_of _ _ _ _ _
    verifiedFrontendCanonicalTokens_context_constants_found_kernel
  apply buildPackConstants_cons_of _ _ _ _ _
    verifiedFrontendDecimal_context_constants_found_kernel
  apply buildPackConstants_cons_of _ _ _ _ _
    verifiedFrontendNumber_context_constants_found_kernel
  apply buildPackConstants_cons_of _ _ _ _ _
    verifiedFrontendSymbol_context_constants_found_kernel
  apply buildPackConstants_cons_of _ _ _ _ _
    verifiedFrontendRawLexer_context_constants_found_kernel
  simp only [buildPackConstants, verifiedFrontendPackContextConstantsKernel,
    List.append_nil]
def verifiedFrontendPackConstantContextKernel : Lanius.SurfaceElaboration.Context := {
  verifiedFrontendPackDeclarationContextKernel with
  constants := verifiedFrontendPackContextConstantsKernel
}
end Lanius.Extraction
