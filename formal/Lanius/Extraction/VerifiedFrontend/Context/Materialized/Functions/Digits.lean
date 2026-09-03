import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Functions.Base

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

open ArtifactContextChecker

theorem verifiedFrontendDigits_context_functions_materialized_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextMaterializedKernel.forModule
        verifiedFrontendDigitsAllocationKernel.unit.moduleId)
      verifiedFrontendDigitsAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendDigitsAllocationKernel.unit.surface.items)
      verifiedFrontendDigitsAllocationKernel.unit.core.functions =
        some (verifiedFrontendPackMaterializedFunctionHeaders 24 7) := by
  cbv

end Lanius.Extraction
