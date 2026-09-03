import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Functions.Base

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

open ArtifactContextChecker

theorem verifiedFrontendSymbol_context_functions_materialized_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextMaterializedKernel.forModule
        verifiedFrontendSymbolAllocationKernel.unit.moduleId)
      verifiedFrontendSymbolAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendSymbolAllocationKernel.unit.surface.items)
      verifiedFrontendSymbolAllocationKernel.unit.core.functions =
        some (verifiedFrontendPackMaterializedFunctionHeaders 42 4) := by
  cbv

end Lanius.Extraction
