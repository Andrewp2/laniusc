import Lanius.Extraction.VerifiedFrontend.Evidence.Digits.Base
import Lanius.Extraction.VerifiedFrontend.Evidence.Digits.Witnesses.Assembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendDigits_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureWitnessed
      verifiedFrontendPackSurfaceNodeCountsKernel 2
      verifiedFrontendDigitsArtifact verifiedFrontendDigitsSurfaceKernel
      verifiedFrontendDigitsEvidenceWitnessView = true := by
  unfold CompleteChecker.checkUnitEvidenceStructureWitnessed
  simp only [verifiedFrontendDigits_evidence_core_present_kernel,
    verifiedFrontendDigits_evidence_base_checked_kernel,
    verifiedFrontendDigits_evidence_witnesses_checked_kernel, Bool.true_and]

theorem verifiedFrontendDigits_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 2
      verifiedFrontendDigitsArtifact :=
  CompleteChecker.checkUnitEvidenceStructureWitnessed_sound
    verifiedFrontendDigits_evidence_checked_kernel

end Lanius.Extraction
