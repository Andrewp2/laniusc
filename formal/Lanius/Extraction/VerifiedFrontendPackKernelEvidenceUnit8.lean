import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendRawLexer_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCached
      verifiedFrontendPackSurfaceNodeCountsKernel 8
      verifiedFrontendRawLexerArtifact verifiedFrontendRawLexerSurfaceKernel = true := by
  with_unfolding_all rfl

theorem verifiedFrontendRawLexer_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 8
      verifiedFrontendRawLexerArtifact :=
  CompleteChecker.checkUnitEvidenceStructureCached_sound
    verifiedFrontendRawLexer_evidence_checked_kernel

end Lanius.Extraction

