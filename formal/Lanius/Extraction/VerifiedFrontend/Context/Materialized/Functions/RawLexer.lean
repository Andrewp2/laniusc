import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Functions.Base

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

open ArtifactContextChecker

theorem verifiedFrontendRawLexer_context_functions_materialized_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextMaterializedKernel.forModule
        verifiedFrontendRawLexerAllocationKernel.unit.moduleId)
      verifiedFrontendRawLexerAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendRawLexerAllocationKernel.unit.surface.items)
      verifiedFrontendRawLexerAllocationKernel.unit.core.functions =
        some (verifiedFrontendPackMaterializedFunctionHeaders 46 8) := by
  cbv

end Lanius.Extraction
