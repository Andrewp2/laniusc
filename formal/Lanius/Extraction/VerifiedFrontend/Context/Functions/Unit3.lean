import Lanius.Extraction.VerifiedFrontend.Context.Constants.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendToken_context_functions_present_kernel :
    (buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendTokenAllocationKernel.unit.moduleId)
      verifiedFrontendTokenAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendTokenAllocationKernel.unit.surface.items)
      verifiedFrontendTokenAllocationKernel.unit.core.functions).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenContextFunctionsKernel :=
  (buildFunctionHeaders
    (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendTokenAllocationKernel.unit.moduleId)
    verifiedFrontendTokenAllocationKernel.functionDeclarationStart
    (collectFunctions verifiedFrontendTokenAllocationKernel.unit.surface.items)
    verifiedFrontendTokenAllocationKernel.unit.core.functions).get
      verifiedFrontendToken_context_functions_present_kernel
theorem verifiedFrontendToken_context_functions_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendTokenAllocationKernel.unit.moduleId)
      verifiedFrontendTokenAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendTokenAllocationKernel.unit.surface.items)
      verifiedFrontendTokenAllocationKernel.unit.core.functions = some verifiedFrontendTokenContextFunctionsKernel :=
  parseOptionEqSomeGet verifiedFrontendToken_context_functions_present_kernel
end Lanius.Extraction
