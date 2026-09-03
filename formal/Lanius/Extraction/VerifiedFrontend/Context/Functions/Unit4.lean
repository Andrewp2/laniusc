import Lanius.Extraction.VerifiedFrontend.Context.Constants.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendCanonicalTokens_context_functions_present_kernel :
    (buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendCanonicalTokensAllocationKernel.unit.moduleId)
      verifiedFrontendCanonicalTokensAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendCanonicalTokensAllocationKernel.unit.surface.items)
      verifiedFrontendCanonicalTokensAllocationKernel.unit.core.functions).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensContextFunctionsKernel :=
  (buildFunctionHeaders
    (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendCanonicalTokensAllocationKernel.unit.moduleId)
    verifiedFrontendCanonicalTokensAllocationKernel.functionDeclarationStart
    (collectFunctions verifiedFrontendCanonicalTokensAllocationKernel.unit.surface.items)
    verifiedFrontendCanonicalTokensAllocationKernel.unit.core.functions).get
      verifiedFrontendCanonicalTokens_context_functions_present_kernel
theorem verifiedFrontendCanonicalTokens_context_functions_found_kernel :
    buildFunctionHeaders
      (verifiedFrontendPackConstantContextKernel.forModule verifiedFrontendCanonicalTokensAllocationKernel.unit.moduleId)
      verifiedFrontendCanonicalTokensAllocationKernel.functionDeclarationStart
      (collectFunctions verifiedFrontendCanonicalTokensAllocationKernel.unit.surface.items)
      verifiedFrontendCanonicalTokensAllocationKernel.unit.core.functions = some verifiedFrontendCanonicalTokensContextFunctionsKernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_context_functions_present_kernel
end Lanius.Extraction
