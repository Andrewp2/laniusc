import Lanius.Extraction.VerifiedFrontend.Evidence.Symbol.Base
import Lanius.Extraction.VerifiedFrontend.Evidence.Symbol.Witnesses

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendSymbol_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureWitnessed
      verifiedFrontendPackSurfaceNodeCountsKernel 7
      verifiedFrontendSymbolArtifact verifiedFrontendSymbolSurfaceKernel
      verifiedFrontendSymbolEvidenceWitnessView = true := by
  unfold CompleteChecker.checkUnitEvidenceStructureWitnessed
  simp only [verifiedFrontendSymbol_evidence_core_present_kernel,
    verifiedFrontendSymbol_evidence_base_checked_kernel,
    verifiedFrontendSymbol_evidence_witnesses_checked_kernel, Bool.true_and]

theorem verifiedFrontendSymbol_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 7
      verifiedFrontendSymbolArtifact :=
  CompleteChecker.checkUnitEvidenceStructureWitnessed_sound
    verifiedFrontendSymbol_evidence_checked_kernel

end Lanius.Extraction
