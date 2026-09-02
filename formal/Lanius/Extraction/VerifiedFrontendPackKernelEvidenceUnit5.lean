import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendDecimal_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCached
      verifiedFrontendPackSurfaceNodeCountsKernel 5
      verifiedFrontendDecimalArtifact verifiedFrontendDecimalSurfaceKernel = true := by
  with_unfolding_all rfl

theorem verifiedFrontendDecimal_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 5
      verifiedFrontendDecimalArtifact :=
  CompleteChecker.checkUnitEvidenceStructureCached_sound
    verifiedFrontendDecimal_evidence_checked_kernel

end Lanius.Extraction

