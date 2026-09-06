import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Parse
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Token
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Source

namespace Lanius.Extraction
def verifiedFrontendCanonicalTokensView :
    ArtifactView verifiedFrontendCanonicalTokensArtifact := {
  cache := verifiedFrontendCanonicalTokensCache
  parseNodesWellFormed :=
    verifiedFrontendCanonicalTokens_parse_tree_well_formed_kernel
  parseNodesRepresent :=
    verifiedFrontendCanonicalTokens_parse_tree_represents_kernel
  tokensWellFormed :=
    verifiedFrontendCanonicalTokens_token_tree_well_formed_kernel
  tokensRepresent :=
    verifiedFrontendCanonicalTokens_token_tree_represents_kernel
  sourceBytesWellFormed :=
    verifiedFrontendCanonicalTokens_source_tree_well_formed_kernel
  sourceBytesRepresent :=
    verifiedFrontendCanonicalTokens_source_tree_represents_kernel
}
end Lanius.Extraction

