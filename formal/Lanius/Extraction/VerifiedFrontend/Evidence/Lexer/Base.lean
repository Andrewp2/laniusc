import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendLexer_evidence_core_present_kernel :
    verifiedFrontendLexerArtifact.core_program.isSome = true := by
  with_unfolding_all rfl
theorem verifiedFrontendLexer_evidence_base_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCachedBase
      verifiedFrontendPackSurfaceNodeCountsKernel 0
      verifiedFrontendLexerArtifact verifiedFrontendLexerSurfaceKernel = true := by
  with_unfolding_all rfl
end Lanius.Extraction
