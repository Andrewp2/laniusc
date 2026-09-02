import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit4Indexes

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_lowering_lookups_checked_kernel :
    typeRowsHaveLoweringEvidenceMaterialized
      verifiedFrontendCanonicalTokensLoweringNodeIndexDataKernel
      verifiedFrontendCanonicalTokensArtifact.types = true := by
  with_unfolding_all rfl

end Lanius.Extraction
