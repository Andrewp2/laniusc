import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedFunctionsBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

open ArtifactContextChecker

theorem verifiedFrontendNumber_context_functions_materialized_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextMaterializedKernel.forModule
        verifiedFrontendNumberAllocationKernel.unit.moduleId)
      verifiedFrontendNumberAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendNumberAllocationKernel.unit.surface.items)
      verifiedFrontendNumberAllocationKernel.unit.core.functions =
        some (verifiedFrontendPackMaterializedFunctionHeaders 40 2) := by
  cbv

end Lanius.Extraction

