import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedFunctionsLexer
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedFunctionsTokenScan
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedFunctionsDigits
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedFunctionsToken
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedFunctionsCanonicalTokens
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedFunctionsDecimal
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedFunctionsNumber
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedFunctionsSymbol
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedFunctionsRawLexer

namespace Lanius.Extraction

open ArtifactPackContextChecker

def verifiedFrontendPackContextFunctionsMaterializedAssembledKernel :
    ArtifactContextChecker.FunctionHeaders :=
  appendFunctionHeaders (verifiedFrontendPackMaterializedFunctionHeaders 0 18)
    (appendFunctionHeaders (verifiedFrontendPackMaterializedFunctionHeaders 18 6)
      (appendFunctionHeaders (verifiedFrontendPackMaterializedFunctionHeaders 24 7)
        (appendFunctionHeaders (verifiedFrontendPackMaterializedFunctionHeaders 31 0)
          (appendFunctionHeaders (verifiedFrontendPackMaterializedFunctionHeaders 31 4)
            (appendFunctionHeaders (verifiedFrontendPackMaterializedFunctionHeaders 35 5)
              (appendFunctionHeaders (verifiedFrontendPackMaterializedFunctionHeaders 40 2)
                (appendFunctionHeaders (verifiedFrontendPackMaterializedFunctionHeaders 42 4)
                  (appendFunctionHeaders (verifiedFrontendPackMaterializedFunctionHeaders 46 8)
                    ⟨[], []⟩))))))))

def verifiedFrontendPackContextFunctionsMaterializedKernel :
    ArtifactContextChecker.FunctionHeaders :=
  ⟨verifiedFrontendPackContextTablesLiteralKernel.functions,
    verifiedFrontendPackContextTablesLiteralKernel.functionInstances⟩

theorem verifiedFrontendPack_context_functions_materialized_assembled_kernel :
    buildPackFunctions verifiedFrontendPackConstantContextMaterializedKernel
      verifiedFrontendPackAllocationsExplicitKernel =
        some verifiedFrontendPackContextFunctionsMaterializedAssembledKernel := by
  unfold verifiedFrontendPackAllocationsExplicitKernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendLexer_context_functions_materialized_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendTokenScan_context_functions_materialized_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendDigits_context_functions_materialized_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendToken_context_functions_materialized_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendCanonicalTokens_context_functions_materialized_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendDecimal_context_functions_materialized_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendNumber_context_functions_materialized_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendSymbol_context_functions_materialized_found_kernel
  apply buildPackFunctions_cons_of _ _ _ _ _
    verifiedFrontendRawLexer_context_functions_materialized_found_kernel
  simp only [buildPackFunctions,
    verifiedFrontendPackContextFunctionsMaterializedAssembledKernel]

theorem verifiedFrontendPackContextFunctionsMaterializedAssembledKernel_eq :
    verifiedFrontendPackContextFunctionsMaterializedAssembledKernel =
      verifiedFrontendPackContextFunctionsMaterializedKernel := by
  rfl

theorem verifiedFrontendPack_context_functions_materialized_found_kernel :
    buildPackFunctions verifiedFrontendPackConstantContextMaterializedKernel
      verifiedFrontendPackAllocationsExplicitKernel =
        some verifiedFrontendPackContextFunctionsMaterializedKernel := by
  rw [← verifiedFrontendPackContextFunctionsMaterializedAssembledKernel_eq]
  exact verifiedFrontendPack_context_functions_materialized_assembled_kernel

theorem verifiedFrontendPackContextFunctionsMaterializedKernel_eq :
    verifiedFrontendPackContextFunctionsMaterializedKernel =
      verifiedFrontendPackContextFunctionsKernel := by
  have old := verifiedFrontendPack_context_functions_found_kernel
  rw [← verifiedFrontendPackConstantContextMaterializedKernel_eq] at old
  rw [verifiedFrontendPack_allocations_explicit_kernel] at old
  exact Option.some.inj
    (verifiedFrontendPack_context_functions_materialized_found_kernel.symm.trans old)

theorem verifiedFrontendPackContextTablesLiteralKernel_functions_eq :
    (verifiedFrontendPackContextTablesLiteralKernel.functions,
      verifiedFrontendPackContextTablesLiteralKernel.functionInstances) =
    (verifiedFrontendPackContextExplicitKernel.functions,
      verifiedFrontendPackContextExplicitKernel.functionInstances) := by
  exact congrArg (fun headers => (headers.schemes, headers.instances))
    verifiedFrontendPackContextFunctionsMaterializedKernel_eq

end Lanius.Extraction

