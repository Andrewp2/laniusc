import Lanius.Extraction.VerifiedFrontend.Evidence.Decimal.View

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_typed_lowering_witnesses_checked_kernel :
    checkTypedLoweringWitnesses verifiedFrontendDecimalEvidenceTypeTree
      verifiedFrontendDecimalArtifact.lowering verifiedFrontendDecimalLoweringTypeRefs = true := by
  with_unfolding_all rfl
end Lanius.Extraction
