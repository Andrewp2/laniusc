import Lanius.Extraction.VerifiedFrontend.Context.Type
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker ArtifactPackContextChecker
theorem verifiedFrontendDigits_context_struct_details_present_kernel :
    (buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendDigitsAllocationKernel.unit.moduleId)
      verifiedFrontendDigitsAllocationKernel.structureDeclarationStart verifiedFrontendDigitsAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendDigitsAllocationKernel.unit.surface.items)
      verifiedFrontendDigitsAllocationKernel.unit.core.structures).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDigitsContextStructDetailsKernel :=
  (buildStructDetails
    (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendDigitsAllocationKernel.unit.moduleId)
    verifiedFrontendDigitsAllocationKernel.structureDeclarationStart verifiedFrontendDigitsAllocationKernel.structureTypeStart
    (collectStructures verifiedFrontendDigitsAllocationKernel.unit.surface.items)
    verifiedFrontendDigitsAllocationKernel.unit.core.structures).get
      verifiedFrontendDigits_context_struct_details_present_kernel
theorem verifiedFrontendDigits_context_struct_details_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendDigitsAllocationKernel.unit.moduleId)
      verifiedFrontendDigitsAllocationKernel.structureDeclarationStart verifiedFrontendDigitsAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendDigitsAllocationKernel.unit.surface.items)
      verifiedFrontendDigitsAllocationKernel.unit.core.structures =
        some verifiedFrontendDigitsContextStructDetailsKernel :=
  parseOptionEqSomeGet verifiedFrontendDigits_context_struct_details_present_kernel
end Lanius.Extraction
