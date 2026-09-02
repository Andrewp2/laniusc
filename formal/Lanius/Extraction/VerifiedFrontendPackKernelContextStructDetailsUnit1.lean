import Lanius.Extraction.VerifiedFrontendPackKernelContextType
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker ArtifactPackContextChecker
theorem verifiedFrontendTokenScan_context_struct_details_present_kernel :
    (buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendTokenScanAllocationKernel.unit.moduleId)
      verifiedFrontendTokenScanAllocationKernel.structureDeclarationStart verifiedFrontendTokenScanAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendTokenScanAllocationKernel.unit.surface.items)
      verifiedFrontendTokenScanAllocationKernel.unit.core.structures).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenScanContextStructDetailsKernel :=
  (buildStructDetails
    (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendTokenScanAllocationKernel.unit.moduleId)
    verifiedFrontendTokenScanAllocationKernel.structureDeclarationStart verifiedFrontendTokenScanAllocationKernel.structureTypeStart
    (collectStructures verifiedFrontendTokenScanAllocationKernel.unit.surface.items)
    verifiedFrontendTokenScanAllocationKernel.unit.core.structures).get
      verifiedFrontendTokenScan_context_struct_details_present_kernel
theorem verifiedFrontendTokenScan_context_struct_details_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendTokenScanAllocationKernel.unit.moduleId)
      verifiedFrontendTokenScanAllocationKernel.structureDeclarationStart verifiedFrontendTokenScanAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendTokenScanAllocationKernel.unit.surface.items)
      verifiedFrontendTokenScanAllocationKernel.unit.core.structures =
        some verifiedFrontendTokenScanContextStructDetailsKernel :=
  parseOptionEqSomeGet verifiedFrontendTokenScan_context_struct_details_present_kernel
end Lanius.Extraction
