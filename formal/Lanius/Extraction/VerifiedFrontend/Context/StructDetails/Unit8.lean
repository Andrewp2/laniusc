import Lanius.Extraction.VerifiedFrontend.Context.Type
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker ArtifactPackContextChecker
theorem verifiedFrontendRawLexer_context_struct_details_present_kernel :
    (buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendRawLexerAllocationKernel.unit.moduleId)
      verifiedFrontendRawLexerAllocationKernel.structureDeclarationStart verifiedFrontendRawLexerAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendRawLexerAllocationKernel.unit.surface.items)
      verifiedFrontendRawLexerAllocationKernel.unit.core.structures).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerContextStructDetailsKernel :=
  (buildStructDetails
    (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendRawLexerAllocationKernel.unit.moduleId)
    verifiedFrontendRawLexerAllocationKernel.structureDeclarationStart verifiedFrontendRawLexerAllocationKernel.structureTypeStart
    (collectStructures verifiedFrontendRawLexerAllocationKernel.unit.surface.items)
    verifiedFrontendRawLexerAllocationKernel.unit.core.structures).get
      verifiedFrontendRawLexer_context_struct_details_present_kernel
theorem verifiedFrontendRawLexer_context_struct_details_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendRawLexerAllocationKernel.unit.moduleId)
      verifiedFrontendRawLexerAllocationKernel.structureDeclarationStart verifiedFrontendRawLexerAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendRawLexerAllocationKernel.unit.surface.items)
      verifiedFrontendRawLexerAllocationKernel.unit.core.structures =
        some verifiedFrontendRawLexerContextStructDetailsKernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_context_struct_details_present_kernel
end Lanius.Extraction
