import Lanius.Extraction.VerifiedFrontend.Evidence.Digits.TypedLoweringWitnesses
import Lanius.Extraction.VerifiedFrontend.Evidence.Digits.TypeLoweringWitnesses

namespace Lanius.Extraction
theorem verifiedFrontendDigits_evidence_witnesses_checked_kernel :
    checkEvidenceWitnesses verifiedFrontendDigitsEvidenceWitnessView = true := by
  unfold checkEvidenceWitnesses
  change (checkTypedLoweringWitnesses verifiedFrontendDigitsEvidenceTypeTree
      verifiedFrontendDigitsArtifact.lowering verifiedFrontendDigitsLoweringTypeRefs &&
    checkTypeLoweringWitnesses verifiedFrontendDigitsEvidenceLoweringTree
      verifiedFrontendDigitsArtifact.types verifiedFrontendDigitsTypeLoweringRefs) = true
  simp only [verifiedFrontendDigits_typed_lowering_witnesses_checked_kernel,
    verifiedFrontendDigits_type_lowering_witnesses_checked_kernel, Bool.true_and]
end Lanius.Extraction
