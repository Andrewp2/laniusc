import Lanius.Extraction.VerifiedFrontend.Evidence.Symbol.View

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_typed_lowering_witnesses_checked_kernel :
    checkTypedLoweringWitnesses verifiedFrontendSymbolEvidenceTypeTree
      verifiedFrontendSymbolArtifact.lowering verifiedFrontendSymbolLoweringTypeRefs = true := by
  with_unfolding_all rfl
end Lanius.Extraction
