import Lanius.Extraction.VerifiedFrontend.Evidence.Decimal.Data
import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendDecimal_evidence_type_tree_well_formed_kernel :
    verifiedFrontendDecimalEvidenceTypeTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendDecimal_evidence_type_tree_represents_kernel :
    verifiedFrontendDecimalEvidenceTypeTree.Represents verifiedFrontendDecimalArtifact.types := by
  with_unfolding_all rfl

theorem verifiedFrontendDecimal_evidence_lowering_tree_well_formed_kernel :
    verifiedFrontendDecimalEvidenceLoweringTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendDecimal_evidence_lowering_tree_represents_kernel :
    verifiedFrontendDecimalEvidenceLoweringTree.Represents verifiedFrontendDecimalArtifact.lowering := by
  with_unfolding_all rfl

def verifiedFrontendDecimalEvidenceWitnessView : EvidenceWitnessView verifiedFrontendDecimalArtifact := {
  cache := verifiedFrontendDecimalEvidenceWitnessCache
  typesWellFormed := verifiedFrontendDecimal_evidence_type_tree_well_formed_kernel
  typesRepresent := verifiedFrontendDecimal_evidence_type_tree_represents_kernel
  loweringWellFormed := verifiedFrontendDecimal_evidence_lowering_tree_well_formed_kernel
  loweringRepresent := verifiedFrontendDecimal_evidence_lowering_tree_represents_kernel
}

end Lanius.Extraction
