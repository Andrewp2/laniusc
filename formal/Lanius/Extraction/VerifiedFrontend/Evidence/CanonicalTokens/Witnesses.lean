import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.TypedLoweringWitnesses
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.TypeLoweringWitnesses

namespace Lanius.Extraction

theorem verifiedFrontendCanonicalTokens_evidence_witnesses_checked_kernel :
    checkEvidenceWitnesses
      verifiedFrontendCanonicalTokensEvidenceWitnessView = true := by
  unfold checkEvidenceWitnesses
  change (checkTypedLoweringWitnesses
      verifiedFrontendCanonicalTokensEvidenceTypeTree
      verifiedFrontendCanonicalTokensArtifact.lowering
      verifiedFrontendCanonicalTokensLoweringTypeRefs &&
    checkTypeLoweringWitnesses
      verifiedFrontendCanonicalTokensEvidenceLoweringTree
      verifiedFrontendCanonicalTokensArtifact.types
      verifiedFrontendCanonicalTokensTypeLoweringRefs) = true
  simp only [
    verifiedFrontendCanonicalTokens_typed_lowering_witnesses_checked_kernel,
    verifiedFrontendCanonicalTokens_type_lowering_witnesses_checked_kernel,
    Bool.true_and]

end Lanius.Extraction
