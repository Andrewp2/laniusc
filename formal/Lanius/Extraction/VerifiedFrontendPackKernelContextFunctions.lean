import Lanius.Extraction.VerifiedFrontendPackKernelContextFunctionsUnit0
import Lanius.Extraction.VerifiedFrontendPackKernelContextFunctionsUnit1
import Lanius.Extraction.VerifiedFrontendPackKernelContextFunctionsUnit2
import Lanius.Extraction.VerifiedFrontendPackKernelContextFunctionsUnit3
import Lanius.Extraction.VerifiedFrontendPackKernelContextFunctionsUnit4
import Lanius.Extraction.VerifiedFrontendPackKernelContextFunctionsUnit5
import Lanius.Extraction.VerifiedFrontendPackKernelContextFunctionsUnit6
import Lanius.Extraction.VerifiedFrontendPackKernelContextFunctionsUnit7
import Lanius.Extraction.VerifiedFrontendPackKernelContextFunctionsUnit8

namespace Lanius.Extraction
set_option maxRecDepth 100000
open ArtifactPackContextChecker
def verifiedFrontendPackContextFunctionsKernel : ArtifactContextChecker.FunctionHeaders :=
  appendFunctionHeaders verifiedFrontendLexerContextFunctionsKernel
    (appendFunctionHeaders verifiedFrontendTokenScanContextFunctionsKernel
      (appendFunctionHeaders verifiedFrontendDigitsContextFunctionsKernel
        (appendFunctionHeaders verifiedFrontendTokenContextFunctionsKernel
          (appendFunctionHeaders verifiedFrontendCanonicalTokensContextFunctionsKernel
            (appendFunctionHeaders verifiedFrontendDecimalContextFunctionsKernel
              (appendFunctionHeaders verifiedFrontendNumberContextFunctionsKernel
                (appendFunctionHeaders verifiedFrontendSymbolContextFunctionsKernel
                  (appendFunctionHeaders verifiedFrontendRawLexerContextFunctionsKernel ⟨[], []⟩))))))))
theorem verifiedFrontendPack_context_functions_found_kernel :
    buildPackFunctions verifiedFrontendPackConstantContextKernel
      verifiedFrontendPackAllocationsKernel =
        some verifiedFrontendPackContextFunctionsKernel := by
  rw [verifiedFrontendPack_allocations_explicit_kernel]
  unfold verifiedFrontendPackAllocationsExplicitKernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendLexer_context_functions_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendTokenScan_context_functions_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendDigits_context_functions_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendToken_context_functions_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendCanonicalTokens_context_functions_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendDecimal_context_functions_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendNumber_context_functions_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendSymbol_context_functions_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendRawLexer_context_functions_found_kernel
  simp only [buildPackFunctions, verifiedFrontendPackContextFunctionsKernel]
def verifiedFrontendPackContextExplicitKernel : Lanius.SurfaceElaboration.Context := {
  verifiedFrontendPackConstantContextKernel with
  functions := verifiedFrontendPackContextFunctionsKernel.schemes
  functionInstances := verifiedFrontendPackContextFunctionsKernel.instances
}

theorem verifiedFrontendPack_finish_context_found_kernel :
    finishPackContext verifiedFrontendPackTypeContextKernel
      verifiedFrontendPackAllocationsKernel =
        some verifiedFrontendPackContextExplicitKernel := by
  unfold finishPackContext
  rw [verifiedFrontendPack_context_struct_details_found_kernel]
  simp only [Option.bind_eq_bind, Option.bind_some]
  change ((buildPackConstants verifiedFrontendPackDeclarationContextKernel
    verifiedFrontendPackAllocationsKernel).bind fun constants => _) = _
  rw [verifiedFrontendPack_context_constants_found_kernel]
  simp only [Option.bind_some]
  change ((buildPackFunctions verifiedFrontendPackConstantContextKernel
    verifiedFrontendPackAllocationsKernel).bind fun functions => _) = _
  rw [verifiedFrontendPack_context_functions_found_kernel]
  change some verifiedFrontendPackContextExplicitKernel =
    some verifiedFrontendPackContextExplicitKernel
  rfl

theorem verifiedFrontendPack_finish_certified_context_found_kernel
    (moduleNames : SurfaceElaborationChecker.Evidence
      (Lanius.Names.ModulesHaveUniquePaths ({
        modules := verifiedFrontendPackDecodedUnitsKernel.map (fun unit => unit.module)
        symbols := verifiedFrontendPackContextHeadersKernel.symbols
        imports := verifiedFrontendPackContextImportsKernel
      } : Lanius.Names.Environment)))
    (symbolNames : SurfaceElaborationChecker.Evidence
      (Lanius.Names.SymbolsAreUnique ({
        modules := verifiedFrontendPackDecodedUnitsKernel.map (fun unit => unit.module)
        symbols := verifiedFrontendPackContextHeadersKernel.symbols
        imports := verifiedFrontendPackContextImportsKernel
      } : Lanius.Names.Environment))) :
    finishCertifiedPackContext verifiedFrontendPackContextTargetKernel ({
      modules := verifiedFrontendPackDecodedUnitsKernel.map (fun unit => unit.module)
      symbols := verifiedFrontendPackContextHeadersKernel.symbols
      imports := verifiedFrontendPackContextImportsKernel
    } : Lanius.Names.Environment) verifiedFrontendPackContextHeadersKernel
      verifiedFrontendPackAllocationsKernel moduleNames symbolNames =
        some verifiedFrontendPackContextExplicitKernel := by
  unfold finishCertifiedPackContext
  rw [verifiedFrontendPackTypeContextKernel_of_evidence moduleNames symbolNames]
  exact verifiedFrontendPack_finish_context_found_kernel
end Lanius.Extraction
