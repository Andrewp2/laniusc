import Lanius.Extraction.VerifiedFrontend.Context.Type
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactContextChecker ArtifactPackContextChecker
theorem verifiedFrontendCanonicalTokens_context_struct_details_present_kernel :
    (buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendCanonicalTokensAllocationKernel.unit.moduleId)
      verifiedFrontendCanonicalTokensAllocationKernel.structureDeclarationStart verifiedFrontendCanonicalTokensAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendCanonicalTokensAllocationKernel.unit.surface.items)
      verifiedFrontendCanonicalTokensAllocationKernel.unit.core.structures).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensContextStructDetailsKernel :=
  (buildStructDetails
    (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendCanonicalTokensAllocationKernel.unit.moduleId)
    verifiedFrontendCanonicalTokensAllocationKernel.structureDeclarationStart verifiedFrontendCanonicalTokensAllocationKernel.structureTypeStart
    (collectStructures verifiedFrontendCanonicalTokensAllocationKernel.unit.surface.items)
    verifiedFrontendCanonicalTokensAllocationKernel.unit.core.structures).get
      verifiedFrontendCanonicalTokens_context_struct_details_present_kernel
theorem verifiedFrontendCanonicalTokens_context_struct_details_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextKernel.forModule verifiedFrontendCanonicalTokensAllocationKernel.unit.moduleId)
      verifiedFrontendCanonicalTokensAllocationKernel.structureDeclarationStart verifiedFrontendCanonicalTokensAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendCanonicalTokensAllocationKernel.unit.surface.items)
      verifiedFrontendCanonicalTokensAllocationKernel.unit.core.structures =
        some verifiedFrontendCanonicalTokensContextStructDetailsKernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_context_struct_details_present_kernel
end Lanius.Extraction
