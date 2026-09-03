import Lanius.Extraction.VerifiedFrontend.Evidence.Number.View

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_typed_lowering_witnesses_checked_kernel :
    checkTypedLoweringWitnesses verifiedFrontendNumberEvidenceTypeTree
      verifiedFrontendNumberArtifact.lowering verifiedFrontendNumberLoweringTypeRefs = true := by
  with_unfolding_all rfl
end Lanius.Extraction
