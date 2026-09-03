import Lanius.Extraction.VerifiedFrontend.Evidence.Lexer.View

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendLexer_typed_lowering_witnesses_checked_kernel :
    checkTypedLoweringWitnesses verifiedFrontendLexerEvidenceTypeTree
      verifiedFrontendLexerArtifact.lowering
      verifiedFrontendLexerLoweringTypeRefs = true := by
  with_unfolding_all rfl
end Lanius.Extraction
