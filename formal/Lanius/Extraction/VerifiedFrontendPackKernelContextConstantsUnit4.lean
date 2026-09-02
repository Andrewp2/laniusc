import Lanius.Extraction.VerifiedFrontendPackKernelContextStructDetails
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendCanonicalTokens_context_constants_present_kernel :
    (buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendCanonicalTokensAllocationKernel.unit.moduleId)
      verifiedFrontendCanonicalTokensAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendCanonicalTokensAllocationKernel.unit.surface.items)
      verifiedFrontendCanonicalTokensAllocationKernel.unit.core.constants).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensContextConstantsKernel :=
  (buildConstantEntries
    (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendCanonicalTokensAllocationKernel.unit.moduleId)
    verifiedFrontendCanonicalTokensAllocationKernel.constantDeclarationStart
    (collectConstants verifiedFrontendCanonicalTokensAllocationKernel.unit.surface.items)
    verifiedFrontendCanonicalTokensAllocationKernel.unit.core.constants).get
      verifiedFrontendCanonicalTokens_context_constants_present_kernel
theorem verifiedFrontendCanonicalTokens_context_constants_found_kernel :
    buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendCanonicalTokensAllocationKernel.unit.moduleId)
      verifiedFrontendCanonicalTokensAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendCanonicalTokensAllocationKernel.unit.surface.items)
      verifiedFrontendCanonicalTokensAllocationKernel.unit.core.constants = some verifiedFrontendCanonicalTokensContextConstantsKernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_context_constants_present_kernel
end Lanius.Extraction
