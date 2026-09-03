import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Functions.Base

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

open ArtifactContextChecker

theorem verifiedFrontendDecimal_context_functions_materialized_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextMaterializedKernel.forModule
        verifiedFrontendDecimalAllocationKernel.unit.moduleId)
      verifiedFrontendDecimalAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendDecimalAllocationKernel.unit.surface.items)
      verifiedFrontendDecimalAllocationKernel.unit.core.functions =
        some (verifiedFrontendPackMaterializedFunctionHeaders 35 5) := by
  cbv

end Lanius.Extraction
