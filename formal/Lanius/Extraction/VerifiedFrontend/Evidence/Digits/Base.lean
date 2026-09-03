import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_evidence_core_present_kernel :
    verifiedFrontendDigitsArtifact.core_program.isSome = true := by
  with_unfolding_all rfl
theorem verifiedFrontendDigits_evidence_base_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCachedBase
      verifiedFrontendPackSurfaceNodeCountsKernel 2
      verifiedFrontendDigitsArtifact verifiedFrontendDigitsSurfaceKernel = true := by
  with_unfolding_all rfl
end Lanius.Extraction
