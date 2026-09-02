import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendDigits_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCached
      verifiedFrontendPackSurfaceNodeCountsKernel 2
      verifiedFrontendDigitsArtifact verifiedFrontendDigitsSurfaceKernel = true := by
  with_unfolding_all rfl

theorem verifiedFrontendDigits_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 2
      verifiedFrontendDigitsArtifact :=
  CompleteChecker.checkUnitEvidenceStructureCached_sound
    verifiedFrontendDigits_evidence_checked_kernel

end Lanius.Extraction

