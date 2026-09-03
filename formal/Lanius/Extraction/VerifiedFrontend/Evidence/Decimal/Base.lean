import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_evidence_core_present_kernel :
    verifiedFrontendDecimalArtifact.core_program.isSome = true := by
  with_unfolding_all rfl
theorem verifiedFrontendDecimal_evidence_base_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCachedBase
      verifiedFrontendPackSurfaceNodeCountsKernel 5
      verifiedFrontendDecimalArtifact verifiedFrontendDecimalSurfaceKernel = true := by
  with_unfolding_all rfl
end Lanius.Extraction
