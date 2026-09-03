import Lanius.Extraction.VerifiedFrontend.Context.Constants.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendNumber_context_functions_present_kernel :
    (buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendNumberAllocationKernel.unit.moduleId)
      verifiedFrontendNumberAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendNumberAllocationKernel.unit.surface.items)
      verifiedFrontendNumberAllocationKernel.unit.core.functions).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendNumberContextFunctionsKernel :=
  (buildFunctionHeaders
    (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendNumberAllocationKernel.unit.moduleId)
    verifiedFrontendNumberAllocationKernel.functionDeclarationStart
    (collectFunctions verifiedFrontendNumberAllocationKernel.unit.surface.items)
    verifiedFrontendNumberAllocationKernel.unit.core.functions).get
      verifiedFrontendNumber_context_functions_present_kernel
theorem verifiedFrontendNumber_context_functions_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendNumberAllocationKernel.unit.moduleId)
      verifiedFrontendNumberAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendNumberAllocationKernel.unit.surface.items)
      verifiedFrontendNumberAllocationKernel.unit.core.functions = some verifiedFrontendNumberContextFunctionsKernel :=
  parseOptionEqSomeGet verifiedFrontendNumber_context_functions_present_kernel
end Lanius.Extraction
