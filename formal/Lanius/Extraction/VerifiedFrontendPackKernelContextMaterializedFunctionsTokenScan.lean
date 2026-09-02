import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedFunctionsBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

open ArtifactContextChecker

theorem verifiedFrontendTokenScan_context_functions_materialized_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextMaterializedKernel.forModule
        verifiedFrontendTokenScanAllocationKernel.unit.moduleId)
      verifiedFrontendTokenScanAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendTokenScanAllocationKernel.unit.surface.items)
      verifiedFrontendTokenScanAllocationKernel.unit.core.functions =
        some (verifiedFrontendPackMaterializedFunctionHeaders 18 6) := by
  cbv

end Lanius.Extraction
