import Lanius.Extraction.VerifiedFrontend.Evidence.Decimal.TypedLoweringWitnesses
import Lanius.Extraction.VerifiedFrontend.Evidence.Decimal.TypeLoweringWitnesses

namespace Lanius.Extraction
theorem verifiedFrontendDecimal_evidence_witnesses_checked_kernel :
    checkEvidenceWitnesses verifiedFrontendDecimalEvidenceWitnessView = true := by
  unfold checkEvidenceWitnesses
  change (checkTypedLoweringWitnesses verifiedFrontendDecimalEvidenceTypeTree
      verifiedFrontendDecimalArtifact.lowering verifiedFrontendDecimalLoweringTypeRefs &&
    checkTypeLoweringWitnesses verifiedFrontendDecimalEvidenceLoweringTree
      verifiedFrontendDecimalArtifact.types verifiedFrontendDecimalTypeLoweringRefs) = true
  simp only [verifiedFrontendDecimal_typed_lowering_witnesses_checked_kernel,
    verifiedFrontendDecimal_type_lowering_witnesses_checked_kernel, Bool.true_and]
end Lanius.Extraction
