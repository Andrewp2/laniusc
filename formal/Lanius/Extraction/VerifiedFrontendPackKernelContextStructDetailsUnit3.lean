import Lanius.Extraction.VerifiedFrontendPackKernelContextType
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker ArtifactPackContextChecker
theorem verifiedFrontendToken_context_struct_details_present_kernel :
    (buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendTokenAllocationKernel.unit.moduleId)
      verifiedFrontendTokenAllocationKernel.structureDeclarationStart verifiedFrontendTokenAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendTokenAllocationKernel.unit.surface.items)
      verifiedFrontendTokenAllocationKernel.unit.core.structures).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenContextStructDetailsKernel :=
  (buildStructDetails
    (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendTokenAllocationKernel.unit.moduleId)
    verifiedFrontendTokenAllocationKernel.structureDeclarationStart verifiedFrontendTokenAllocationKernel.structureTypeStart
    (collectStructures verifiedFrontendTokenAllocationKernel.unit.surface.items)
    verifiedFrontendTokenAllocationKernel.unit.core.structures).get
      verifiedFrontendToken_context_struct_details_present_kernel
theorem verifiedFrontendToken_context_struct_details_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendTokenAllocationKernel.unit.moduleId)
      verifiedFrontendTokenAllocationKernel.structureDeclarationStart verifiedFrontendTokenAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendTokenAllocationKernel.unit.surface.items)
      verifiedFrontendTokenAllocationKernel.unit.core.structures =
        some verifiedFrontendTokenContextStructDetailsKernel :=
  parseOptionEqSomeGet verifiedFrontendToken_context_struct_details_present_kernel
end Lanius.Extraction
