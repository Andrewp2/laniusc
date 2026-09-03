import Lanius.Extraction.VerifiedFrontend.Evidence.RawLexer.View

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_type_lowering_witnesses_checked_kernel :
    checkTypeLoweringWitnesses verifiedFrontendRawLexerEvidenceLoweringTree
      verifiedFrontendRawLexerArtifact.types verifiedFrontendRawLexerTypeLoweringRefs = true := by
  with_unfolding_all rfl
end Lanius.Extraction
