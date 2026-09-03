import Lanius.Extraction.VerifiedFrontend.Evidence.Number.View

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_type_lowering_witnesses_checked_kernel :
    checkTypeLoweringWitnesses verifiedFrontendNumberEvidenceLoweringTree
      verifiedFrontendNumberArtifact.types verifiedFrontendNumberTypeLoweringRefs = true := by
  with_unfolding_all rfl
end Lanius.Extraction
