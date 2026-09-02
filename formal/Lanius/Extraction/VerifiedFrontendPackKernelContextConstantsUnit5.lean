import Lanius.Extraction.VerifiedFrontendPackKernelContextStructDetails
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendDecimal_context_constants_present_kernel :
    (buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendDecimalAllocationKernel.unit.moduleId)
      verifiedFrontendDecimalAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendDecimalAllocationKernel.unit.surface.items)
      verifiedFrontendDecimalAllocationKernel.unit.core.constants).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDecimalContextConstantsKernel :=
  (buildConstantEntries
    (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendDecimalAllocationKernel.unit.moduleId)
    verifiedFrontendDecimalAllocationKernel.constantDeclarationStart
    (collectConstants verifiedFrontendDecimalAllocationKernel.unit.surface.items)
    verifiedFrontendDecimalAllocationKernel.unit.core.constants).get
      verifiedFrontendDecimal_context_constants_present_kernel
theorem verifiedFrontendDecimal_context_constants_found_kernel :
    buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendDecimalAllocationKernel.unit.moduleId)
      verifiedFrontendDecimalAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendDecimalAllocationKernel.unit.surface.items)
      verifiedFrontendDecimalAllocationKernel.unit.core.constants = some verifiedFrontendDecimalContextConstantsKernel :=
  parseOptionEqSomeGet verifiedFrontendDecimal_context_constants_present_kernel
end Lanius.Extraction
