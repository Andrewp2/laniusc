import Lanius.Extraction.VerifiedFrontend.Evidence.Number.Data
import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendNumber_evidence_type_tree_well_formed_kernel :
    verifiedFrontendNumberEvidenceTypeTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendNumber_evidence_type_tree_represents_kernel :
    verifiedFrontendNumberEvidenceTypeTree.Represents verifiedFrontendNumberArtifact.types := by
  with_unfolding_all rfl

theorem verifiedFrontendNumber_evidence_lowering_tree_well_formed_kernel :
    verifiedFrontendNumberEvidenceLoweringTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendNumber_evidence_lowering_tree_represents_kernel :
    verifiedFrontendNumberEvidenceLoweringTree.Represents verifiedFrontendNumberArtifact.lowering := by
  with_unfolding_all rfl

def verifiedFrontendNumberEvidenceWitnessView : EvidenceWitnessView verifiedFrontendNumberArtifact := {
  cache := verifiedFrontendNumberEvidenceWitnessCache
  typesWellFormed := verifiedFrontendNumber_evidence_type_tree_well_formed_kernel
  typesRepresent := verifiedFrontendNumber_evidence_type_tree_represents_kernel
  loweringWellFormed := verifiedFrontendNumber_evidence_lowering_tree_well_formed_kernel
  loweringRepresent := verifiedFrontendNumber_evidence_lowering_tree_represents_kernel
}

end Lanius.Extraction
