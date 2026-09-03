import Lanius.Extraction.VerifiedFrontend.Evidence.RawLexer.Base
import Lanius.Extraction.VerifiedFrontend.Evidence.RawLexer.Witnesses

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendRawLexer_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureWitnessed
      verifiedFrontendPackSurfaceNodeCountsKernel 8
      verifiedFrontendRawLexerArtifact verifiedFrontendRawLexerSurfaceKernel
      verifiedFrontendRawLexerEvidenceWitnessView = true := by
  unfold CompleteChecker.checkUnitEvidenceStructureWitnessed
  simp only [verifiedFrontendRawLexer_evidence_core_present_kernel,
    verifiedFrontendRawLexer_evidence_base_checked_kernel,
    verifiedFrontendRawLexer_evidence_witnesses_checked_kernel, Bool.true_and]

theorem verifiedFrontendRawLexer_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 8
      verifiedFrontendRawLexerArtifact :=
  CompleteChecker.checkUnitEvidenceStructureWitnessed_sound
    verifiedFrontendRawLexer_evidence_checked_kernel

end Lanius.Extraction
