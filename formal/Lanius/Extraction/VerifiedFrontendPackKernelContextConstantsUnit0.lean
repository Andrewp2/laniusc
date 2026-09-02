import Lanius.Extraction.VerifiedFrontendPackKernelContextStructDetails
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendLexer_context_constants_present_kernel :
    (buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendLexerAllocationKernel.unit.moduleId)
      verifiedFrontendLexerAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendLexerAllocationKernel.unit.surface.items)
      verifiedFrontendLexerAllocationKernel.unit.core.constants).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendLexerContextConstantsKernel :=
  (buildConstantEntries
    (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendLexerAllocationKernel.unit.moduleId)
    verifiedFrontendLexerAllocationKernel.constantDeclarationStart
    (collectConstants verifiedFrontendLexerAllocationKernel.unit.surface.items)
    verifiedFrontendLexerAllocationKernel.unit.core.constants).get
      verifiedFrontendLexer_context_constants_present_kernel
theorem verifiedFrontendLexer_context_constants_found_kernel :
    buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendLexerAllocationKernel.unit.moduleId)
      verifiedFrontendLexerAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendLexerAllocationKernel.unit.surface.items)
      verifiedFrontendLexerAllocationKernel.unit.core.constants = some verifiedFrontendLexerContextConstantsKernel :=
  parseOptionEqSomeGet verifiedFrontendLexer_context_constants_present_kernel
end Lanius.Extraction
