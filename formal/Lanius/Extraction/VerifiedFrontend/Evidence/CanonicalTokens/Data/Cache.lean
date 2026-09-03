import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Data.TypeTree
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Data.LoweringTree
import Lanius.Extraction.VerifiedFrontend.Evidence.CanonicalTokens.Data.Refs

namespace Lanius.Extraction

def verifiedFrontendCanonicalTokensEvidenceWitnessCache : EvidenceWitnessCache := {
  leafCapacity := 64
  types := verifiedFrontendCanonicalTokensEvidenceTypeTree
  lowering := verifiedFrontendCanonicalTokensEvidenceLoweringTree
  loweringTypeRefs := verifiedFrontendCanonicalTokensLoweringTypeRefs
  typeLoweringRefs := verifiedFrontendCanonicalTokensTypeLoweringRefs
}

end Lanius.Extraction
