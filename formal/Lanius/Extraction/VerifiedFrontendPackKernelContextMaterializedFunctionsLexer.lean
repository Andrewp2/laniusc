import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedFunctionsBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

open ArtifactContextChecker

theorem verifiedFrontendLexer_context_functions_materialized_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextMaterializedKernel.forModule
        verifiedFrontendLexerAllocationKernel.unit.moduleId)
      verifiedFrontendLexerAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendLexerAllocationKernel.unit.surface.items)
      verifiedFrontendLexerAllocationKernel.unit.core.functions =
        some (verifiedFrontendPackMaterializedFunctionHeaders 0 18) := by
  cbv

end Lanius.Extraction

