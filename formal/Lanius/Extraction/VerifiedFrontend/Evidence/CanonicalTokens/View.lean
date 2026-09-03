import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Data.Cache
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.TypeTreeWell
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.TypeTreeRep
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.LoweringTreeWell
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.LoweringTreeRep

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
