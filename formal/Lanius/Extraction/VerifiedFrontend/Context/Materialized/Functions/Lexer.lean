import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Functions.Base
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

open ArtifactContextChecker

theorem verifiedFrontendLexer_context_functions_materialized_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextMaterializedKernel.forModule
        verifiedFrontendLexerAllocationKernel.unit.moduleId)
      verifiedFrontendLexerAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendLexerAllocationKernel.unit.surface.items)
      verifiedFrontendLexerAllocationKernel.unit.core.functions =
        some (verifiedFrontendPackMaterializedFunctionHeaders 0 18) := by
  kernel_rfl

end Lanius.Extraction
