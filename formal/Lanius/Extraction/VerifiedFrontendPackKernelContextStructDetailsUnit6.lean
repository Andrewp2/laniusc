import Lanius.Extraction.VerifiedFrontendPackKernelContextType
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker ArtifactPackContextChecker
theorem verifiedFrontendNumber_context_struct_details_present_kernel :
    (buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendNumberAllocationKernel.unit.moduleId)
      verifiedFrontendNumberAllocationKernel.structureDeclarationStart verifiedFrontendNumberAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendNumberAllocationKernel.unit.surface.items)
      verifiedFrontendNumberAllocationKernel.unit.core.structures).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendNumberContextStructDetailsKernel :=
  (buildStructDetails
    (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendNumberAllocationKernel.unit.moduleId)
    verifiedFrontendNumberAllocationKernel.structureDeclarationStart verifiedFrontendNumberAllocationKernel.structureTypeStart
    (collectStructures verifiedFrontendNumberAllocationKernel.unit.surface.items)
    verifiedFrontendNumberAllocationKernel.unit.core.structures).get
      verifiedFrontendNumber_context_struct_details_present_kernel
theorem verifiedFrontendNumber_context_struct_details_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendNumberAllocationKernel.unit.moduleId)
      verifiedFrontendNumberAllocationKernel.structureDeclarationStart verifiedFrontendNumberAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendNumberAllocationKernel.unit.surface.items)
      verifiedFrontendNumberAllocationKernel.unit.core.structures =
        some verifiedFrontendNumberContextStructDetailsKernel :=
  parseOptionEqSomeGet verifiedFrontendNumber_context_struct_details_present_kernel
end Lanius.Extraction
