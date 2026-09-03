import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendTokenScan_context_constants_present_kernel :
    (buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendTokenScanAllocationKernel.unit.moduleId)
      verifiedFrontendTokenScanAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendTokenScanAllocationKernel.unit.surface.items)
      verifiedFrontendTokenScanAllocationKernel.unit.core.constants).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenScanContextConstantsKernel :=
  (buildConstantEntries
    (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendTokenScanAllocationKernel.unit.moduleId)
    verifiedFrontendTokenScanAllocationKernel.constantDeclarationStart
    (collectConstants verifiedFrontendTokenScanAllocationKernel.unit.surface.items)
    verifiedFrontendTokenScanAllocationKernel.unit.core.constants).get
      verifiedFrontendTokenScan_context_constants_present_kernel
theorem verifiedFrontendTokenScan_context_constants_found_kernel :
    buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendTokenScanAllocationKernel.unit.moduleId)
      verifiedFrontendTokenScanAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendTokenScanAllocationKernel.unit.surface.items)
      verifiedFrontendTokenScanAllocationKernel.unit.core.constants = some verifiedFrontendTokenScanContextConstantsKernel :=
  parseOptionEqSomeGet verifiedFrontendTokenScan_context_constants_present_kernel
end Lanius.Extraction
