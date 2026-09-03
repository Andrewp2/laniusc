import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendToken_context_constants_present_kernel :
    (buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendTokenAllocationKernel.unit.moduleId)
      verifiedFrontendTokenAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendTokenAllocationKernel.unit.surface.items)
      verifiedFrontendTokenAllocationKernel.unit.core.constants).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenContextConstantsKernel :=
  (buildConstantEntries
    (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendTokenAllocationKernel.unit.moduleId)
    verifiedFrontendTokenAllocationKernel.constantDeclarationStart
    (collectConstants verifiedFrontendTokenAllocationKernel.unit.surface.items)
    verifiedFrontendTokenAllocationKernel.unit.core.constants).get
      verifiedFrontendToken_context_constants_present_kernel
theorem verifiedFrontendToken_context_constants_found_kernel :
    buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendTokenAllocationKernel.unit.moduleId)
      verifiedFrontendTokenAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendTokenAllocationKernel.unit.surface.items)
      verifiedFrontendTokenAllocationKernel.unit.core.constants = some verifiedFrontendTokenContextConstantsKernel :=
  parseOptionEqSomeGet verifiedFrontendToken_context_constants_present_kernel
end Lanius.Extraction
