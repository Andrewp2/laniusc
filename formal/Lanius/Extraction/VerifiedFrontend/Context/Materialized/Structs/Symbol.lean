import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Structs.Base
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

open ArtifactContextChecker

theorem verifiedFrontendSymbol_context_struct_details_materialized_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextMaterializedKernel.forModule
        verifiedFrontendSymbolAllocationKernel.unit.moduleId)
      verifiedFrontendSymbolAllocationKernel.structureDeclarationStart
      verifiedFrontendSymbolAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendSymbolAllocationKernel.unit.surface.items)
      verifiedFrontendSymbolAllocationKernel.unit.core.structures =
        some (verifiedFrontendPackMaterializedStructDetails 10 2 3) := by
  kernel_rfl

end Lanius.Extraction
