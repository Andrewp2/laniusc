import Lanius.Extraction.VerifiedFrontend.Evidence.Lexer.View

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendLexer_type_lowering_witnesses_checked_kernel :
    checkTypeLoweringWitnesses verifiedFrontendLexerEvidenceLoweringTree
      verifiedFrontendLexerArtifact.types
      verifiedFrontendLexerTypeLoweringRefs = true := by
  with_unfolding_all rfl
end Lanius.Extraction
