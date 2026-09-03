import Lanius.Extraction.VerifiedFrontend.Evidence.Number.Witnesses.TypedLowering
import Lanius.Extraction.VerifiedFrontend.Evidence.Number.Witnesses.TypeLowering

namespace Lanius.Extraction
theorem verifiedFrontendNumber_evidence_witnesses_checked_kernel :
    checkEvidenceWitnesses verifiedFrontendNumberEvidenceWitnessView = true := by
  unfold checkEvidenceWitnesses
  change (checkTypedLoweringWitnesses verifiedFrontendNumberEvidenceTypeTree
      verifiedFrontendNumberArtifact.lowering verifiedFrontendNumberLoweringTypeRefs &&
    checkTypeLoweringWitnesses verifiedFrontendNumberEvidenceLoweringTree
      verifiedFrontendNumberArtifact.types verifiedFrontendNumberTypeLoweringRefs) = true
  simp only [verifiedFrontendNumber_typed_lowering_witnesses_checked_kernel,
    verifiedFrontendNumber_type_lowering_witnesses_checked_kernel, Bool.true_and]
end Lanius.Extraction
