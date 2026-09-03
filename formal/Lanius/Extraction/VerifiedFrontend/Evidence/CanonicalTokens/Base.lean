import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.NodeCount
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.ResolutionRows
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.TypeRows
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.TypePremises
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.LoweringRows
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.LoweringPremises

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_evidence_remainder_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureCachedBase
      verifiedFrontendPackSurfaceNodeCountsKernel 4
      verifiedFrontendCanonicalTokensArtifact
      verifiedFrontendCanonicalTokensSurfaceKernel = true := by
  unfold CompleteChecker.checkUnitEvidenceStructureCachedBase
  simp only [
    verifiedFrontendCanonicalTokens_evidence_node_count_checked_kernel,
    verifiedFrontendCanonicalTokens_evidence_resolution_checked_kernel,
    verifiedFrontendCanonicalTokens_evidence_type_rows_checked_kernel,
    verifiedFrontendCanonicalTokens_evidence_lowering_rows_checked_kernel,
    verifiedFrontendCanonicalTokens_evidence_type_premises_checked_kernel,
    verifiedFrontendCanonicalTokens_evidence_lowering_premises_checked_kernel,
    Bool.true_and]

end Lanius.Extraction
