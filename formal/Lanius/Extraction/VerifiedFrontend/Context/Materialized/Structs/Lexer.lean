import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Structs.Base

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

open ArtifactContextChecker

theorem verifiedFrontendLexer_context_struct_details_materialized_found_kernel :
    buildStructDetails
      (verifiedFrontendPackTypeContextMaterializedKernel.forModule
        verifiedFrontendLexerAllocationKernel.unit.moduleId)
      verifiedFrontendLexerAllocationKernel.structureDeclarationStart
      verifiedFrontendLexerAllocationKernel.structureTypeStart
      (collectStructures verifiedFrontendLexerAllocationKernel.unit.surface.items)
      verifiedFrontendLexerAllocationKernel.unit.core.structures =
        some (verifiedFrontendPackMaterializedStructDetails 0 3 0) := by
  cbv

end Lanius.Extraction
