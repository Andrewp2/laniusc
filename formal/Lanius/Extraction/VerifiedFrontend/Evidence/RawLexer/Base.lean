import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_evidence_core_present_kernel :
    verifiedFrontendRawLexerArtifact.core_program.isSome = true := by
  with_unfolding_all rfl
theorem verifiedFrontendRawLexer_evidence_base_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCachedBase
      verifiedFrontendPackSurfaceNodeCountsKernel 8
      verifiedFrontendRawLexerArtifact verifiedFrontendRawLexerSurfaceKernel = true := by
  with_unfolding_all rfl
end Lanius.Extraction
