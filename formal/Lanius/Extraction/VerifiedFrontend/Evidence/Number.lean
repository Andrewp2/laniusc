import Lanius.Extraction.VerifiedFrontend.Evidence.Number.Base
import Lanius.Extraction.VerifiedFrontend.Evidence.Number.Witnesses.Assembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendNumber_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureWitnessed
      verifiedFrontendPackSurfaceNodeCountsKernel 6
      verifiedFrontendNumberArtifact verifiedFrontendNumberSurfaceKernel
      verifiedFrontendNumberEvidenceWitnessView = true := by
  unfold CompleteChecker.checkUnitEvidenceStructureWitnessed
  simp only [verifiedFrontendNumber_evidence_core_present_kernel,
    verifiedFrontendNumber_evidence_base_checked_kernel,
    verifiedFrontendNumber_evidence_witnesses_checked_kernel, Bool.true_and]

theorem verifiedFrontendNumber_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 6
      verifiedFrontendNumberArtifact :=
  CompleteChecker.checkUnitEvidenceStructureWitnessed_sound
    verifiedFrontendNumber_evidence_checked_kernel

end Lanius.Extraction
