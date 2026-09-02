import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendNumber_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCached
      verifiedFrontendPackSurfaceNodeCountsKernel 6
      verifiedFrontendNumberArtifact verifiedFrontendNumberSurfaceKernel = true := by
  with_unfolding_all rfl

theorem verifiedFrontendNumber_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 6
      verifiedFrontendNumberArtifact :=
  CompleteChecker.checkUnitEvidenceStructureCached_sound
    verifiedFrontendNumber_evidence_checked_kernel

end Lanius.Extraction

