import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Base
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.CorePresent
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Witnesses

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureWitnessed
      verifiedFrontendPackSurfaceNodeCountsKernel 4
      verifiedFrontendCanonicalTokensArtifact verifiedFrontendCanonicalTokensSurfaceKernel
      verifiedFrontendCanonicalTokensEvidenceWitnessView = true := by
  unfold CompleteChecker.checkUnitEvidenceStructureWitnessed
  simp only [
    verifiedFrontendCanonicalTokens_evidence_core_present_kernel,
    verifiedFrontendCanonicalTokens_evidence_remainder_checked_kernel,
    verifiedFrontendCanonicalTokens_evidence_witnesses_checked_kernel,
    Bool.true_and]

theorem verifiedFrontendCanonicalTokens_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 4
      verifiedFrontendCanonicalTokensArtifact :=
  CompleteChecker.checkUnitEvidenceStructureWitnessed_sound
    verifiedFrontendCanonicalTokens_evidence_checked_kernel

end Lanius.Extraction
