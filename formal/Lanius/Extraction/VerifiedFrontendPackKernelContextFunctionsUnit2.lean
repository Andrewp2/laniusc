import Lanius.Extraction.VerifiedFrontendPackKernelContextConstants
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendDigits_context_functions_present_kernel :
    (buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendDigitsAllocationKernel.unit.moduleId)
      verifiedFrontendDigitsAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendDigitsAllocationKernel.unit.surface.items)
      verifiedFrontendDigitsAllocationKernel.unit.core.functions).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDigitsContextFunctionsKernel :=
  (buildFunctionHeaders
    (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendDigitsAllocationKernel.unit.moduleId)
    verifiedFrontendDigitsAllocationKernel.functionDeclarationStart
    (collectFunctions verifiedFrontendDigitsAllocationKernel.unit.surface.items)
    verifiedFrontendDigitsAllocationKernel.unit.core.functions).get
      verifiedFrontendDigits_context_functions_present_kernel
theorem verifiedFrontendDigits_context_functions_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendDigitsAllocationKernel.unit.moduleId)
      verifiedFrontendDigitsAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendDigitsAllocationKernel.unit.surface.items)
      verifiedFrontendDigitsAllocationKernel.unit.core.functions = some verifiedFrontendDigitsContextFunctionsKernel :=
  parseOptionEqSomeGet verifiedFrontendDigits_context_functions_present_kernel
end Lanius.Extraction
