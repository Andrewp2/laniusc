import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Functions.Base
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

open ArtifactContextChecker

theorem verifiedFrontendRawLexer_context_functions_materialized_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextMaterializedKernel.forModule
        verifiedFrontendRawLexerAllocationKernel.unit.moduleId)
      verifiedFrontendRawLexerAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendRawLexerAllocationKernel.unit.surface.items)
      verifiedFrontendRawLexerAllocationKernel.unit.core.functions =
        some (verifiedFrontendPackMaterializedFunctionHeaders 46 8) := by
  kernel_rfl

end Lanius.Extraction
