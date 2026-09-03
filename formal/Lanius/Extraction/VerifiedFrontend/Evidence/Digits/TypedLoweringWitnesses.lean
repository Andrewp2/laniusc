import Lanius.Extraction.VerifiedFrontend.Evidence.Digits.View

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_typed_lowering_witnesses_checked_kernel :
    checkTypedLoweringWitnesses verifiedFrontendDigitsEvidenceTypeTree
      verifiedFrontendDigitsArtifact.lowering verifiedFrontendDigitsLoweringTypeRefs = true := by
  with_unfolding_all rfl
end Lanius.Extraction
