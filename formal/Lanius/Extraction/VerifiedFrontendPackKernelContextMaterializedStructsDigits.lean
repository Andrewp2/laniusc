import Lanius.Extraction.VerifiedFrontendPackKernelContextMaterializedStructsBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

open ArtifactContextChecker

theorem verifiedFrontendDigits_context_struct_details_materialized_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextMaterializedKernel.forModule
        verifiedFrontendDigitsAllocationKernel.unit.moduleId)
      verifiedFrontendDigitsAllocationKernel.structureDeclarationStart
      verifiedFrontendDigitsAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendDigitsAllocationKernel.unit.surface.items)
      verifiedFrontendDigitsAllocationKernel.unit.core.structures =
        some (verifiedFrontendPackMaterializedStructDetails 7 3 2) := by
  cbv

end Lanius.Extraction

