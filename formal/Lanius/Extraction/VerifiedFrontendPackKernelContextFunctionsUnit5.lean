import Lanius.Extraction.VerifiedFrontendPackKernelContextConstants
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendDecimal_context_functions_present_kernel :
    (buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendDecimalAllocationKernel.unit.moduleId)
      verifiedFrontendDecimalAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendDecimalAllocationKernel.unit.surface.items)
      verifiedFrontendDecimalAllocationKernel.unit.core.functions).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDecimalContextFunctionsKernel :=
  (buildFunctionHeaders
    (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendDecimalAllocationKernel.unit.moduleId)
    verifiedFrontendDecimalAllocationKernel.functionDeclarationStart
    (collectFunctions verifiedFrontendDecimalAllocationKernel.unit.surface.items)
    verifiedFrontendDecimalAllocationKernel.unit.core.functions).get
      verifiedFrontendDecimal_context_functions_present_kernel
theorem verifiedFrontendDecimal_context_functions_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendDecimalAllocationKernel.unit.moduleId)
      verifiedFrontendDecimalAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendDecimalAllocationKernel.unit.surface.items)
      verifiedFrontendDecimalAllocationKernel.unit.core.functions = some verifiedFrontendDecimalContextFunctionsKernel :=
  parseOptionEqSomeGet verifiedFrontendDecimal_context_functions_present_kernel
end Lanius.Extraction
