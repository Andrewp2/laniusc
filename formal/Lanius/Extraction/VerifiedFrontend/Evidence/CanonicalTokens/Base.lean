import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Nodes.Count
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Rows.Resolution
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Rows.Type
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Premises.Type
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Rows.Lowering
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Premises.Lowering

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
