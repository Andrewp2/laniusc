import Lanius.Extraction.VerifiedFrontend.Context.Constants.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendSymbol_context_functions_present_kernel :
    (buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendSymbolAllocationKernel.unit.moduleId)
      verifiedFrontendSymbolAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendSymbolAllocationKernel.unit.surface.items)
      verifiedFrontendSymbolAllocationKernel.unit.core.functions).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolContextFunctionsKernel :=
  (buildFunctionHeaders
    (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendSymbolAllocationKernel.unit.moduleId)
    verifiedFrontendSymbolAllocationKernel.functionDeclarationStart
    (collectFunctions verifiedFrontendSymbolAllocationKernel.unit.surface.items)
    verifiedFrontendSymbolAllocationKernel.unit.core.functions).get
      verifiedFrontendSymbol_context_functions_present_kernel
theorem verifiedFrontendSymbol_context_functions_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendSymbolAllocationKernel.unit.moduleId)
      verifiedFrontendSymbolAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendSymbolAllocationKernel.unit.surface.items)
      verifiedFrontendSymbolAllocationKernel.unit.core.functions = some verifiedFrontendSymbolContextFunctionsKernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_context_functions_present_kernel
end Lanius.Extraction
