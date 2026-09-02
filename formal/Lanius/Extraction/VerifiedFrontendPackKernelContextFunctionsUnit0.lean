import Lanius.Extraction.VerifiedFrontendPackKernelContextConstants
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendLexer_context_functions_present_kernel :
    (buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendLexerAllocationKernel.unit.moduleId)
      verifiedFrontendLexerAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendLexerAllocationKernel.unit.surface.items)
      verifiedFrontendLexerAllocationKernel.unit.core.functions).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendLexerContextFunctionsKernel :=
  (buildFunctionHeaders
    (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendLexerAllocationKernel.unit.moduleId)
    verifiedFrontendLexerAllocationKernel.functionDeclarationStart
    (collectFunctions verifiedFrontendLexerAllocationKernel.unit.surface.items)
    verifiedFrontendLexerAllocationKernel.unit.core.functions).get
      verifiedFrontendLexer_context_functions_present_kernel
theorem verifiedFrontendLexer_context_functions_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendLexerAllocationKernel.unit.moduleId)
      verifiedFrontendLexerAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendLexerAllocationKernel.unit.surface.items)
      verifiedFrontendLexerAllocationKernel.unit.core.functions = some verifiedFrontendLexerContextFunctionsKernel :=
  parseOptionEqSomeGet verifiedFrontendLexer_context_functions_present_kernel
end Lanius.Extraction
