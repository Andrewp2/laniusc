import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Structs.Base

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

open ArtifactContextChecker

theorem verifiedFrontendNumber_context_struct_details_materialized_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextMaterializedKernel.forModule
        verifiedFrontendNumberAllocationKernel.unit.moduleId)
      verifiedFrontendNumberAllocationKernel.structureDeclarationStart
      verifiedFrontendNumberAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendNumberAllocationKernel.unit.surface.items)
      verifiedFrontendNumberAllocationKernel.unit.core.structures =
        some ⟨[], []⟩ := by
  with_unfolding_all rfl

end Lanius.Extraction
