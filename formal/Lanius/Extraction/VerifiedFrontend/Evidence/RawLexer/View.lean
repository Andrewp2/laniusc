import Lanius.Extraction.VerifiedFrontend.Evidence.RawLexer.Data
import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendRawLexer_evidence_type_tree_well_formed_kernel :
    verifiedFrontendRawLexerEvidenceTypeTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendRawLexer_evidence_type_tree_represents_kernel :
    verifiedFrontendRawLexerEvidenceTypeTree.Represents verifiedFrontendRawLexerArtifact.types := by
  with_unfolding_all rfl

theorem verifiedFrontendRawLexer_evidence_lowering_tree_well_formed_kernel :
    verifiedFrontendRawLexerEvidenceLoweringTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendRawLexer_evidence_lowering_tree_represents_kernel :
    verifiedFrontendRawLexerEvidenceLoweringTree.Represents verifiedFrontendRawLexerArtifact.lowering := by
  with_unfolding_all rfl

def verifiedFrontendRawLexerEvidenceWitnessView : EvidenceWitnessView verifiedFrontendRawLexerArtifact := {
  cache := verifiedFrontendRawLexerEvidenceWitnessCache
  typesWellFormed := verifiedFrontendRawLexer_evidence_type_tree_well_formed_kernel
  typesRepresent := verifiedFrontendRawLexer_evidence_type_tree_represents_kernel
  loweringWellFormed := verifiedFrontendRawLexer_evidence_lowering_tree_well_formed_kernel
  loweringRepresent := verifiedFrontendRawLexer_evidence_lowering_tree_represents_kernel
}

end Lanius.Extraction
