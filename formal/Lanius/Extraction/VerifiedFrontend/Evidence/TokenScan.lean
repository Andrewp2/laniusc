import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendTokenScan_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCached
      verifiedFrontendPackSurfaceNodeCountsKernel 1
      verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanSurfaceKernel = true := by
  with_unfolding_all rfl

theorem verifiedFrontendTokenScan_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 1
      verifiedFrontendTokenScanArtifact :=
  CompleteChecker.checkUnitEvidenceStructureCached_sound
    verifiedFrontendTokenScan_evidence_checked_kernel

end Lanius.Extraction
