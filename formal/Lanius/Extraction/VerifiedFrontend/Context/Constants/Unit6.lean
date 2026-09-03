import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendNumber_context_constants_present_kernel :
    (buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendNumberAllocationKernel.unit.moduleId)
      verifiedFrontendNumberAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendNumberAllocationKernel.unit.surface.items)
      verifiedFrontendNumberAllocationKernel.unit.core.constants).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendNumberContextConstantsKernel :=
  (buildConstantEntries
    (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendNumberAllocationKernel.unit.moduleId)
    verifiedFrontendNumberAllocationKernel.constantDeclarationStart
    (collectConstants verifiedFrontendNumberAllocationKernel.unit.surface.items)
    verifiedFrontendNumberAllocationKernel.unit.core.constants).get
      verifiedFrontendNumber_context_constants_present_kernel
theorem verifiedFrontendNumber_context_constants_found_kernel :
    buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendNumberAllocationKernel.unit.moduleId)
      verifiedFrontendNumberAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendNumberAllocationKernel.unit.surface.items)
      verifiedFrontendNumberAllocationKernel.unit.core.constants = some verifiedFrontendNumberContextConstantsKernel :=
  parseOptionEqSomeGet verifiedFrontendNumber_context_constants_present_kernel
end Lanius.Extraction
