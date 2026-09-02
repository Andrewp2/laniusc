import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendToken_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCached
      verifiedFrontendPackSurfaceNodeCountsKernel 3
      verifiedFrontendTokenArtifact verifiedFrontendTokenSurfaceKernel = true := by
  with_unfolding_all rfl

theorem verifiedFrontendToken_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 3
      verifiedFrontendTokenArtifact :=
  CompleteChecker.checkUnitEvidenceStructureCached_sound
    verifiedFrontendToken_evidence_checked_kernel

end Lanius.Extraction

