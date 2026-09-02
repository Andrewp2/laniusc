import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedStructsLexer
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedStructsTokenScan
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedStructsDigits
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedStructsToken
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedStructsCanonicalTokens
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedStructsDecimal
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedStructsNumber
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedStructsSymbol
import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedStructsRawLexer

namespace Lanius.Extraction

open ArtifactPackContextChecker

def verifiedFrontendPackContextStructDetailsMaterializedAssembledKernel :
    ArtifactContextChecker.StructDetails :=
  appendStructDetails (verifiedFrontendPackMaterializedStructDetails 0 3 0)
    (appendStructDetails (verifiedFrontendPackMaterializedStructDetails 3 4 1)
      (appendStructDetails (verifiedFrontendPackMaterializedStructDetails 7 3 2)
        (appendStructDetails ⟨[], []⟩
          (appendStructDetails ⟨[], []⟩
            (appendStructDetails ⟨[], []⟩
              (appendStructDetails ⟨[], []⟩
                (appendStructDetails
                  (verifiedFrontendPackMaterializedStructDetails 10 2 3)
                  (appendStructDetails
                    (verifiedFrontendPackMaterializedStructDetails 12 3 4)
                    ⟨[], []⟩))))))))

def verifiedFrontendPackContextStructDetailsMaterializedKernel :
    ArtifactContextChecker.StructDetails :=
  ⟨verifiedFrontendPackContextTablesLiteralKernel.fields,
    verifiedFrontendPackContextTablesLiteralKernel.structConstructors⟩

theorem verifiedFrontendPack_context_struct_details_materialized_assembled_kernel :
    buildPackStructDetails verifiedFrontendPackTypeContextMaterializedKernel
      verifiedFrontendPackAllocationsExplicitKernel =
        some verifiedFrontendPackContextStructDetailsMaterializedAssembledKernel := by
  unfold verifiedFrontendPackAllocationsExplicitKernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendLexer_context_struct_details_materialized_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendTokenScan_context_struct_details_materialized_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendDigits_context_struct_details_materialized_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendToken_context_struct_details_materialized_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendCanonicalTokens_context_struct_details_materialized_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendDecimal_context_struct_details_materialized_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendNumber_context_struct_details_materialized_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendSymbol_context_struct_details_materialized_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendRawLexer_context_struct_details_materialized_found_kernel
  simp only [buildPackStructDetails,
    verifiedFrontendPackContextStructDetailsMaterializedAssembledKernel]

theorem verifiedFrontendPackContextStructDetailsMaterializedAssembledKernel_eq :
    verifiedFrontendPackContextStructDetailsMaterializedAssembledKernel =
      verifiedFrontendPackContextStructDetailsMaterializedKernel := by
  rfl

theorem verifiedFrontendPack_context_struct_details_materialized_found_kernel :
    buildPackStructDetails verifiedFrontendPackTypeContextMaterializedKernel
      verifiedFrontendPackAllocationsExplicitKernel =
        some verifiedFrontendPackContextStructDetailsMaterializedKernel := by
  rw [← verifiedFrontendPackContextStructDetailsMaterializedAssembledKernel_eq]
  exact verifiedFrontendPack_context_struct_details_materialized_assembled_kernel

theorem verifiedFrontendPackContextStructDetailsMaterializedKernel_eq :
    verifiedFrontendPackContextStructDetailsMaterializedKernel =
      verifiedFrontendPackContextStructDetailsKernel := by
  have old := verifiedFrontendPack_context_struct_details_found_kernel
  rw [← verifiedFrontendPackTypeContextMaterializedKernel_eq] at old
  rw [verifiedFrontendPack_allocations_explicit_kernel] at old
  exact Option.some.inj
    (verifiedFrontendPack_context_struct_details_materialized_found_kernel.symm.trans old)

theorem verifiedFrontendPackContextTablesLiteralKernel_structs_eq :
    (verifiedFrontendPackContextTablesLiteralKernel.fields,
      verifiedFrontendPackContextTablesLiteralKernel.structConstructors) =
    (verifiedFrontendPackContextExplicitKernel.fields,
      verifiedFrontendPackContextExplicitKernel.structConstructors) := by
  exact congrArg (fun details => (details.fields, details.constructors))
    verifiedFrontendPackContextStructDetailsMaterializedKernel_eq

end Lanius.Extraction

