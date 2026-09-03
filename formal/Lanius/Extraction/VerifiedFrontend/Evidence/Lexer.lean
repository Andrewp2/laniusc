import Lanius.Extraction.VerifiedFrontend.Evidence.Lexer.Base
import Lanius.Extraction.VerifiedFrontend.Evidence.Lexer.Witnesses

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendLexer_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureWitnessed
      verifiedFrontendPackSurfaceNodeCountsKernel 0
      verifiedFrontendLexerArtifact verifiedFrontendLexerSurfaceKernel
      verifiedFrontendLexerEvidenceWitnessView = true := by
  unfold CompleteChecker.checkUnitEvidenceStructureWitnessed
  simp only [verifiedFrontendLexer_evidence_core_present_kernel,
    verifiedFrontendLexer_evidence_base_checked_kernel,
    verifiedFrontendLexer_evidence_witnesses_checked_kernel, Bool.true_and]

theorem verifiedFrontendLexer_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 0
      verifiedFrontendLexerArtifact :=
  CompleteChecker.checkUnitEvidenceStructureWitnessed_sound
    verifiedFrontendLexer_evidence_checked_kernel

end Lanius.Extraction
