import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Functions.Base
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

open ArtifactContextChecker

theorem verifiedFrontendDigits_context_functions_materialized_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextMaterializedKernel.forModule
        verifiedFrontendDigitsAllocationKernel.unit.moduleId)
      verifiedFrontendDigitsAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendDigitsAllocationKernel.unit.surface.items)
      verifiedFrontendDigitsAllocationKernel.unit.core.functions =
        some (verifiedFrontendPackMaterializedFunctionHeaders 24 7) := by
  kernel_rfl

end Lanius.Extraction
