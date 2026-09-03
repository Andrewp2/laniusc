import Lanius.Extraction.VerifiedFrontend.Evidence.RawLexer.Witnesses.TypedLowering
import Lanius.Extraction.VerifiedFrontend.Evidence.RawLexer.Witnesses.TypeLowering

namespace Lanius.Extraction
theorem verifiedFrontendRawLexer_evidence_witnesses_checked_kernel :
    checkEvidenceWitnesses verifiedFrontendRawLexerEvidenceWitnessView = true := by
  unfold checkEvidenceWitnesses
  change (checkTypedLoweringWitnesses verifiedFrontendRawLexerEvidenceTypeTree
      verifiedFrontendRawLexerArtifact.lowering verifiedFrontendRawLexerLoweringTypeRefs &&
    checkTypeLoweringWitnesses verifiedFrontendRawLexerEvidenceLoweringTree
      verifiedFrontendRawLexerArtifact.types verifiedFrontendRawLexerTypeLoweringRefs) = true
  simp only [verifiedFrontendRawLexer_typed_lowering_witnesses_checked_kernel,
    verifiedFrontendRawLexer_type_lowering_witnesses_checked_kernel, Bool.true_and]
end Lanius.Extraction
