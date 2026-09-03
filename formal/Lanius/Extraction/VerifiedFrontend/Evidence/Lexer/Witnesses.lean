import Lanius.Extraction.VerifiedFrontend.Evidence.Lexer.TypedLoweringWitnesses
import Lanius.Extraction.VerifiedFrontend.Evidence.Lexer.TypeLoweringWitnesses

namespace Lanius.Extraction
theorem verifiedFrontendLexer_evidence_witnesses_checked_kernel :
    checkEvidenceWitnesses verifiedFrontendLexerEvidenceWitnessView = true := by
  unfold checkEvidenceWitnesses
  change (checkTypedLoweringWitnesses verifiedFrontendLexerEvidenceTypeTree
      verifiedFrontendLexerArtifact.lowering
      verifiedFrontendLexerLoweringTypeRefs &&
    checkTypeLoweringWitnesses verifiedFrontendLexerEvidenceLoweringTree
      verifiedFrontendLexerArtifact.types
      verifiedFrontendLexerTypeLoweringRefs) = true
  simp only [verifiedFrontendLexer_typed_lowering_witnesses_checked_kernel,
    verifiedFrontendLexer_type_lowering_witnesses_checked_kernel, Bool.true_and]
end Lanius.Extraction
