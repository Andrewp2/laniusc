import Lanius.Extraction.VerifiedFrontend.Evidence.Decimal.Base
import Lanius.Extraction.VerifiedFrontend.Evidence.Decimal.Witnesses.Assembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendDecimal_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureWitnessed
      verifiedFrontendPackSurfaceNodeCountsKernel 5
      verifiedFrontendDecimalArtifact verifiedFrontendDecimalSurfaceKernel
      verifiedFrontendDecimalEvidenceWitnessView = true := by
  unfold CompleteChecker.checkUnitEvidenceStructureWitnessed
  simp only [verifiedFrontendDecimal_evidence_core_present_kernel,
    verifiedFrontendDecimal_evidence_base_checked_kernel,
    verifiedFrontendDecimal_evidence_witnesses_checked_kernel, Bool.true_and]

theorem verifiedFrontendDecimal_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 5
      verifiedFrontendDecimalArtifact :=
  CompleteChecker.checkUnitEvidenceStructureWitnessed_sound
    verifiedFrontendDecimal_evidence_checked_kernel

end Lanius.Extraction
