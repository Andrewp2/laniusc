import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Structs.Base

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

open ArtifactContextChecker

theorem verifiedFrontendCanonicalTokens_context_struct_details_materialized_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextMaterializedKernel.forModule
        verifiedFrontendCanonicalTokensAllocationKernel.unit.moduleId)
      verifiedFrontendCanonicalTokensAllocationKernel.structureDeclarationStart
      verifiedFrontendCanonicalTokensAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendCanonicalTokensAllocationKernel.unit.surface.items)
      verifiedFrontendCanonicalTokensAllocationKernel.unit.core.structures =
        some ⟨[], []⟩ := by
  with_unfolding_all rfl

end Lanius.Extraction
