import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedFunctionsBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

open ArtifactContextChecker

theorem verifiedFrontendToken_context_functions_materialized_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextMaterializedKernel.forModule
        verifiedFrontendTokenAllocationKernel.unit.moduleId)
      verifiedFrontendTokenAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendTokenAllocationKernel.unit.surface.items)
      verifiedFrontendTokenAllocationKernel.unit.core.functions =
        some (verifiedFrontendPackMaterializedFunctionHeaders 31 0) := by
  have count := congrArg (fun value => value.2.2.2)
    verifiedFrontendToken_context_counts_kernel
  have empty : collectFunctions
      verifiedFrontendTokenAllocationKernel.unit.surface.items = [] :=
    List.eq_nil_of_length_eq_zero count
  rw [empty]
  rfl

end Lanius.Extraction
