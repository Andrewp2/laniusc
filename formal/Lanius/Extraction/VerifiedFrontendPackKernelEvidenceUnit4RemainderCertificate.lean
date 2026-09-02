import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit4Indexes

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_evidence_remainder_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCachedBase
      verifiedFrontendPackSurfaceNodeCountsKernel 4
      verifiedFrontendCanonicalTokensArtifact
      verifiedFrontendCanonicalTokensSurfaceKernel = true := by
  with_unfolding_all rfl

end Lanius.Extraction
