import Lanius.Extraction.VerifiedFrontend.Context.Type
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker ArtifactPackContextChecker
theorem verifiedFrontendLexer_context_struct_details_present_kernel :
    (buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendLexerAllocationKernel.unit.moduleId)
      verifiedFrontendLexerAllocationKernel.structureDeclarationStart verifiedFrontendLexerAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendLexerAllocationKernel.unit.surface.items)
      verifiedFrontendLexerAllocationKernel.unit.core.structures).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendLexerContextStructDetailsKernel :=
  (buildStructDetails
    (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendLexerAllocationKernel.unit.moduleId)
    verifiedFrontendLexerAllocationKernel.structureDeclarationStart verifiedFrontendLexerAllocationKernel.structureTypeStart
    (collectStructures verifiedFrontendLexerAllocationKernel.unit.surface.items)
    verifiedFrontendLexerAllocationKernel.unit.core.structures).get
      verifiedFrontendLexer_context_struct_details_present_kernel
theorem verifiedFrontendLexer_context_struct_details_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendLexerAllocationKernel.unit.moduleId)
      verifiedFrontendLexerAllocationKernel.structureDeclarationStart verifiedFrontendLexerAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendLexerAllocationKernel.unit.surface.items)
      verifiedFrontendLexerAllocationKernel.unit.core.structures =
        some verifiedFrontendLexerContextStructDetailsKernel :=
  parseOptionEqSomeGet verifiedFrontendLexer_context_struct_details_present_kernel
end Lanius.Extraction
