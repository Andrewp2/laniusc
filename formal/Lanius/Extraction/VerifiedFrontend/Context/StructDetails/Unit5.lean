import Lanius.Extraction.VerifiedFrontend.Context.Type
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker ArtifactPackContextChecker
theorem verifiedFrontendDecimal_context_struct_details_present_kernel :
    (buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendDecimalAllocationKernel.unit.moduleId)
      verifiedFrontendDecimalAllocationKernel.structureDeclarationStart verifiedFrontendDecimalAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendDecimalAllocationKernel.unit.surface.items)
      verifiedFrontendDecimalAllocationKernel.unit.core.structures).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDecimalContextStructDetailsKernel :=
  (buildStructDetails
    (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendDecimalAllocationKernel.unit.moduleId)
    verifiedFrontendDecimalAllocationKernel.structureDeclarationStart verifiedFrontendDecimalAllocationKernel.structureTypeStart
    (collectStructures verifiedFrontendDecimalAllocationKernel.unit.surface.items)
    verifiedFrontendDecimalAllocationKernel.unit.core.structures).get
      verifiedFrontendDecimal_context_struct_details_present_kernel
theorem verifiedFrontendDecimal_context_struct_details_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendDecimalAllocationKernel.unit.moduleId)
      verifiedFrontendDecimalAllocationKernel.structureDeclarationStart verifiedFrontendDecimalAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendDecimalAllocationKernel.unit.surface.items)
      verifiedFrontendDecimalAllocationKernel.unit.core.structures =
        some verifiedFrontendDecimalContextStructDetailsKernel :=
  parseOptionEqSomeGet verifiedFrontendDecimal_context_struct_details_present_kernel
end Lanius.Extraction
