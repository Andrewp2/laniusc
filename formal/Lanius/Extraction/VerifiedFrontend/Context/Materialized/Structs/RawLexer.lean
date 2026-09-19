import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Structs.Base
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

open ArtifactContextChecker

theorem verifiedFrontendRawLexer_context_struct_details_materialized_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextMaterializedKernel.forModule
        verifiedFrontendRawLexerAllocationKernel.unit.moduleId)
      verifiedFrontendRawLexerAllocationKernel.structureDeclarationStart
      verifiedFrontendRawLexerAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendRawLexerAllocationKernel.unit.surface.items)
      verifiedFrontendRawLexerAllocationKernel.unit.core.structures =
        some (verifiedFrontendPackMaterializedStructDetails 12 3 4) := by
  kernel_rfl

end Lanius.Extraction
