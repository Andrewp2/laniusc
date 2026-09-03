import Lanius.Extraction.VerifiedFrontend.Context.Constants.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendRawLexer_context_functions_present_kernel :
    (buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendRawLexerAllocationKernel.unit.moduleId)
      verifiedFrontendRawLexerAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendRawLexerAllocationKernel.unit.surface.items)
      verifiedFrontendRawLexerAllocationKernel.unit.core.functions).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerContextFunctionsKernel :=
  (buildFunctionHeaders
    (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendRawLexerAllocationKernel.unit.moduleId)
    verifiedFrontendRawLexerAllocationKernel.functionDeclarationStart
    (collectFunctions verifiedFrontendRawLexerAllocationKernel.unit.surface.items)
    verifiedFrontendRawLexerAllocationKernel.unit.core.functions).get
      verifiedFrontendRawLexer_context_functions_present_kernel
theorem verifiedFrontendRawLexer_context_functions_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendRawLexerAllocationKernel.unit.moduleId)
      verifiedFrontendRawLexerAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendRawLexerAllocationKernel.unit.surface.items)
      verifiedFrontendRawLexerAllocationKernel.unit.core.functions = some verifiedFrontendRawLexerContextFunctionsKernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_context_functions_present_kernel
end Lanius.Extraction
