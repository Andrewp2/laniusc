import Lanius.Extraction.VerifiedFrontend.Evidence.Digits.Data
import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendDigits_evidence_type_tree_well_formed_kernel :
    verifiedFrontendDigitsEvidenceTypeTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendDigits_evidence_type_tree_represents_kernel :
    verifiedFrontendDigitsEvidenceTypeTree.Represents verifiedFrontendDigitsArtifact.types := by
  with_unfolding_all rfl

theorem verifiedFrontendDigits_evidence_lowering_tree_well_formed_kernel :
    verifiedFrontendDigitsEvidenceLoweringTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendDigits_evidence_lowering_tree_represents_kernel :
    verifiedFrontendDigitsEvidenceLoweringTree.Represents verifiedFrontendDigitsArtifact.lowering := by
  with_unfolding_all rfl

def verifiedFrontendDigitsEvidenceWitnessView : EvidenceWitnessView verifiedFrontendDigitsArtifact := {
  cache := verifiedFrontendDigitsEvidenceWitnessCache
  typesWellFormed := verifiedFrontendDigits_evidence_type_tree_well_formed_kernel
  typesRepresent := verifiedFrontendDigits_evidence_type_tree_represents_kernel
  loweringWellFormed := verifiedFrontendDigits_evidence_lowering_tree_well_formed_kernel
  loweringRepresent := verifiedFrontendDigits_evidence_lowering_tree_represents_kernel
}

end Lanius.Extraction
