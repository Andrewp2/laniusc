import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Functions.Base
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

open ArtifactContextChecker

theorem verifiedFrontendNumber_context_functions_materialized_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextMaterializedKernel.forModule
        verifiedFrontendNumberAllocationKernel.unit.moduleId)
      verifiedFrontendNumberAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendNumberAllocationKernel.unit.surface.items)
      verifiedFrontendNumberAllocationKernel.unit.core.functions =
        some (verifiedFrontendPackMaterializedFunctionHeaders 40 2) := by
  kernel_rfl

end Lanius.Extraction
