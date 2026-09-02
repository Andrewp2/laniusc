import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceBase

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCached
      verifiedFrontendPackSurfaceNodeCountsKernel 4
      verifiedFrontendCanonicalTokensArtifact verifiedFrontendCanonicalTokensSurfaceKernel = true := by
  with_unfolding_all rfl

theorem verifiedFrontendCanonicalTokens_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 4
      verifiedFrontendCanonicalTokensArtifact :=
  CompleteChecker.checkUnitEvidenceStructureCached_sound
    verifiedFrontendCanonicalTokens_evidence_checked_kernel

end Lanius.Extraction

