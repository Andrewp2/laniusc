import Lanius.Extraction.VerifiedFrontendPackKernelContextConstants
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendTokenScan_context_functions_present_kernel :
    (buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendTokenScanAllocationKernel.unit.moduleId)
      verifiedFrontendTokenScanAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendTokenScanAllocationKernel.unit.surface.items)
      verifiedFrontendTokenScanAllocationKernel.unit.core.functions).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenScanContextFunctionsKernel :=
  (buildFunctionHeaders
    (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendTokenScanAllocationKernel.unit.moduleId)
    verifiedFrontendTokenScanAllocationKernel.functionDeclarationStart
    (collectFunctions verifiedFrontendTokenScanAllocationKernel.unit.surface.items)
    verifiedFrontendTokenScanAllocationKernel.unit.core.functions).get
      verifiedFrontendTokenScan_context_functions_present_kernel
theorem verifiedFrontendTokenScan_context_functions_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendTokenScanAllocationKernel.unit.moduleId)
      verifiedFrontendTokenScanAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendTokenScanAllocationKernel.unit.surface.items)
      verifiedFrontendTokenScanAllocationKernel.unit.core.functions = some verifiedFrontendTokenScanContextFunctionsKernel :=
  parseOptionEqSomeGet verifiedFrontendTokenScan_context_functions_present_kernel
end Lanius.Extraction
