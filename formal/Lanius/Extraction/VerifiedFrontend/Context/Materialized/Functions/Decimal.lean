import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Functions.Base
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

open ArtifactContextChecker

theorem verifiedFrontendDecimal_context_functions_materialized_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextMaterializedKernel.forModule
        verifiedFrontendDecimalAllocationKernel.unit.moduleId)
      verifiedFrontendDecimalAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendDecimalAllocationKernel.unit.surface.items)
      verifiedFrontendDecimalAllocationKernel.unit.core.functions =
        some (verifiedFrontendPackMaterializedFunctionHeaders 35 5) := by
  kernel_rfl

end Lanius.Extraction
