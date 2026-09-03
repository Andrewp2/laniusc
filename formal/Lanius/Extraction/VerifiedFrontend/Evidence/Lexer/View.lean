import Lanius.Extraction.VerifiedFrontend.Evidence.Lexer.Data
import Lanius.Extraction.VerifiedFrontend.Evidence.Base

namespace Lanius.Extraction

set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendLexer_evidence_type_tree_well_formed_kernel :
    verifiedFrontendLexerEvidenceTypeTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendLexer_evidence_type_tree_represents_kernel :
    verifiedFrontendLexerEvidenceTypeTree.Represents
      verifiedFrontendLexerArtifact.types := by
  with_unfolding_all rfl

theorem verifiedFrontendLexer_evidence_lowering_tree_well_formed_kernel :
    verifiedFrontendLexerEvidenceLoweringTree.WellFormed 64 := by
  apply Lanius.Data.SeqTree.wellFormed_sound
  with_unfolding_all rfl

theorem verifiedFrontendLexer_evidence_lowering_tree_represents_kernel :
    verifiedFrontendLexerEvidenceLoweringTree.Represents
      verifiedFrontendLexerArtifact.lowering := by
  with_unfolding_all rfl

def verifiedFrontendLexerEvidenceWitnessView :
    EvidenceWitnessView verifiedFrontendLexerArtifact := {
  cache := verifiedFrontendLexerEvidenceWitnessCache
  typesWellFormed := verifiedFrontendLexer_evidence_type_tree_well_formed_kernel
  typesRepresent := verifiedFrontendLexer_evidence_type_tree_represents_kernel
  loweringWellFormed :=
    verifiedFrontendLexer_evidence_lowering_tree_well_formed_kernel
  loweringRepresent :=
    verifiedFrontendLexer_evidence_lowering_tree_represents_kernel
}

end Lanius.Extraction
