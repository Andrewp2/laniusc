import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendLexer_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCached
      verifiedFrontendPackSurfaceNodeCountsKernel 0
      verifiedFrontendLexerArtifact verifiedFrontendLexerSurfaceKernel = true := by
  with_unfolding_all rfl

theorem verifiedFrontendLexer_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 0
      verifiedFrontendLexerArtifact :=
  CompleteChecker.checkUnitEvidenceStructureCached_sound
    verifiedFrontendLexer_evidence_checked_kernel

end Lanius.Extraction
