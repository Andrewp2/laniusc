import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Parse.WellFormed
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Parse.Representation
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Token.WellFormed
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Token.Representation
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Source.WellFormed
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Source.Representation

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
