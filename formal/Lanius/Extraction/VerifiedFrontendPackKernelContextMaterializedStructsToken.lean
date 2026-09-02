import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedStructsBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

open ArtifactContextChecker

theorem verifiedFrontendToken_context_struct_details_materialized_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextMaterializedKernel.forModule
        verifiedFrontendTokenAllocationKernel.unit.moduleId)
      verifiedFrontendTokenAllocationKernel.structureDeclarationStart
      verifiedFrontendTokenAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendTokenAllocationKernel.unit.surface.items)
      verifiedFrontendTokenAllocationKernel.unit.core.structures =
        some ⟨[], []⟩ := by
  with_unfolding_all rfl

end Lanius.Extraction

