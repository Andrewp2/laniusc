import Lanius.Extraction.VerifiedFrontendPackKernelContextType
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker ArtifactPackContextChecker
theorem verifiedFrontendSymbol_context_struct_details_present_kernel :
    (buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendSymbolAllocationKernel.unit.moduleId)
      verifiedFrontendSymbolAllocationKernel.structureDeclarationStart verifiedFrontendSymbolAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendSymbolAllocationKernel.unit.surface.items)
      verifiedFrontendSymbolAllocationKernel.unit.core.structures).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolContextStructDetailsKernel :=
  (buildStructDetails
    (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendSymbolAllocationKernel.unit.moduleId)
    verifiedFrontendSymbolAllocationKernel.structureDeclarationStart verifiedFrontendSymbolAllocationKernel.structureTypeStart
    (collectStructures verifiedFrontendSymbolAllocationKernel.unit.surface.items)
    verifiedFrontendSymbolAllocationKernel.unit.core.structures).get
      verifiedFrontendSymbol_context_struct_details_present_kernel
theorem verifiedFrontendSymbol_context_struct_details_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendSymbolAllocationKernel.unit.moduleId)
      verifiedFrontendSymbolAllocationKernel.structureDeclarationStart verifiedFrontendSymbolAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendSymbolAllocationKernel.unit.surface.items)
      verifiedFrontendSymbolAllocationKernel.unit.core.structures =
        some verifiedFrontendSymbolContextStructDetailsKernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_context_struct_details_present_kernel
end Lanius.Extraction
