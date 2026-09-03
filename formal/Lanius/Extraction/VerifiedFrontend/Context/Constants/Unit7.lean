import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendSymbol_context_constants_present_kernel :
    (buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendSymbolAllocationKernel.unit.moduleId)
      verifiedFrontendSymbolAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendSymbolAllocationKernel.unit.surface.items)
      verifiedFrontendSymbolAllocationKernel.unit.core.constants).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolContextConstantsKernel :=
  (buildConstantEntries
    (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendSymbolAllocationKernel.unit.moduleId)
    verifiedFrontendSymbolAllocationKernel.constantDeclarationStart
    (collectConstants verifiedFrontendSymbolAllocationKernel.unit.surface.items)
    verifiedFrontendSymbolAllocationKernel.unit.core.constants).get
      verifiedFrontendSymbol_context_constants_present_kernel
theorem verifiedFrontendSymbol_context_constants_found_kernel :
    buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendSymbolAllocationKernel.unit.moduleId)
      verifiedFrontendSymbolAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendSymbolAllocationKernel.unit.surface.items)
      verifiedFrontendSymbolAllocationKernel.unit.core.constants = some verifiedFrontendSymbolContextConstantsKernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_context_constants_present_kernel
end Lanius.Extraction
