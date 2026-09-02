import Lanius.Extraction.VerifiedFrontendPackKernelContextStructDetails
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendDigits_context_constants_present_kernel :
    (buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendDigitsAllocationKernel.unit.moduleId)
      verifiedFrontendDigitsAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendDigitsAllocationKernel.unit.surface.items)
      verifiedFrontendDigitsAllocationKernel.unit.core.constants).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDigitsContextConstantsKernel :=
  (buildConstantEntries
    (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendDigitsAllocationKernel.unit.moduleId)
    verifiedFrontendDigitsAllocationKernel.constantDeclarationStart
    (collectConstants verifiedFrontendDigitsAllocationKernel.unit.surface.items)
    verifiedFrontendDigitsAllocationKernel.unit.core.constants).get
      verifiedFrontendDigits_context_constants_present_kernel
theorem verifiedFrontendDigits_context_constants_found_kernel :
    buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendDigitsAllocationKernel.unit.moduleId)
      verifiedFrontendDigitsAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendDigitsAllocationKernel.unit.surface.items)
      verifiedFrontendDigitsAllocationKernel.unit.core.constants = some verifiedFrontendDigitsContextConstantsKernel :=
  parseOptionEqSomeGet verifiedFrontendDigits_context_constants_present_kernel
end Lanius.Extraction
