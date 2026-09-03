import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Data.Cache
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.TypeTree.WellFormed
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.TypeTree.Representation
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.LoweringTree.WellFormed
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.LoweringTree.Representation

namespace Lanius.Extraction

def verifiedFrontendCanonicalTokensEvidenceWitnessView :
    EvidenceWitnessView verifiedFrontendCanonicalTokensArtifact := {
  cache := verifiedFrontendCanonicalTokensEvidenceWitnessCache
  typesWellFormed :=
    verifiedFrontendCanonicalTokens_evidence_type_tree_well_formed_kernel
  typesRepresent :=
    verifiedFrontendCanonicalTokens_evidence_type_tree_represents_kernel
  loweringWellFormed :=
    verifiedFrontendCanonicalTokens_evidence_lowering_tree_well_formed_kernel
  loweringRepresent :=
    verifiedFrontendCanonicalTokens_evidence_lowering_tree_represents_kernel
}

end Lanius.Extraction
