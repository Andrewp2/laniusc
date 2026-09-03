import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Structs.Base

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

open ArtifactContextChecker

theorem verifiedFrontendTokenScan_context_struct_details_materialized_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextMaterializedKernel.forModule
        verifiedFrontendTokenScanAllocationKernel.unit.moduleId)
      verifiedFrontendTokenScanAllocationKernel.structureDeclarationStart
      verifiedFrontendTokenScanAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendTokenScanAllocationKernel.unit.surface.items)
      verifiedFrontendTokenScanAllocationKernel.unit.core.structures =
        some (verifiedFrontendPackMaterializedStructDetails 3 4 1) := by
  cbv

end Lanius.Extraction
