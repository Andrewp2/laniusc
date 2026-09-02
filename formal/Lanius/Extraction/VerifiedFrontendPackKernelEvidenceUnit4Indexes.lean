import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit4TypeIndexCertificate
import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit4LoweringIndexCertificate

namespace Lanius.Extraction

def verifiedFrontendCanonicalTokensEvidenceNodeIndexesKernel :
    EvidenceNodeIndexes verifiedFrontendCanonicalTokensArtifact.types
      verifiedFrontendCanonicalTokensArtifact.lowering := {
  typeNodes := verifiedFrontendCanonicalTokensTypeNodeIndexDataKernel
  loweringNodes := verifiedFrontendCanonicalTokensLoweringNodeIndexDataKernel
  typeNodesCanonical := verifiedFrontendCanonicalTokensTypeNodeIndexDataKernel_eq
  loweringNodesCanonical :=
    verifiedFrontendCanonicalTokensLoweringNodeIndexDataKernel_eq
}

end Lanius.Extraction
