import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker
theorem verifiedFrontendRawLexer_context_constants_present_kernel :
    (buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendRawLexerAllocationKernel.unit.moduleId)
      verifiedFrontendRawLexerAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendRawLexerAllocationKernel.unit.surface.items)
      verifiedFrontendRawLexerAllocationKernel.unit.core.constants).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerContextConstantsKernel :=
  (buildConstantEntries
    (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendRawLexerAllocationKernel.unit.moduleId)
    verifiedFrontendRawLexerAllocationKernel.constantDeclarationStart
    (collectConstants verifiedFrontendRawLexerAllocationKernel.unit.surface.items)
    verifiedFrontendRawLexerAllocationKernel.unit.core.constants).get
      verifiedFrontendRawLexer_context_constants_present_kernel
theorem verifiedFrontendRawLexer_context_constants_found_kernel :
    buildConstantEntries
      (verifiedFrontendPackDeclarationContextKernel.forModule verifiedFrontendRawLexerAllocationKernel.unit.moduleId)
      verifiedFrontendRawLexerAllocationKernel.constantDeclarationStart
      (collectConstants verifiedFrontendRawLexerAllocationKernel.unit.surface.items)
      verifiedFrontendRawLexerAllocationKernel.unit.core.constants = some verifiedFrontendRawLexerContextConstantsKernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_context_constants_present_kernel
end Lanius.Extraction
