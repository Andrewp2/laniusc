import Lanius.Extraction.VerifiedFrontend.Evidence.Symbol.Data
import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendSymbol_evidence_type_tree_well_formed_kernel :
    verifiedFrontendSymbolEvidenceTypeTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendSymbol_evidence_type_tree_represents_kernel :
    verifiedFrontendSymbolEvidenceTypeTree.Represents verifiedFrontendSymbolArtifact.types := by
  with_unfolding_all rfl

theorem verifiedFrontendSymbol_evidence_lowering_tree_well_formed_kernel :
    verifiedFrontendSymbolEvidenceLoweringTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendSymbol_evidence_lowering_tree_represents_kernel :
    verifiedFrontendSymbolEvidenceLoweringTree.Represents verifiedFrontendSymbolArtifact.lowering := by
  with_unfolding_all rfl

def verifiedFrontendSymbolEvidenceWitnessView : EvidenceWitnessView verifiedFrontendSymbolArtifact := {
  cache := verifiedFrontendSymbolEvidenceWitnessCache
  typesWellFormed := verifiedFrontendSymbol_evidence_type_tree_well_formed_kernel
  typesRepresent := verifiedFrontendSymbol_evidence_type_tree_represents_kernel
  loweringWellFormed := verifiedFrontendSymbol_evidence_lowering_tree_well_formed_kernel
  loweringRepresent := verifiedFrontendSymbol_evidence_lowering_tree_represents_kernel
}

end Lanius.Extraction
