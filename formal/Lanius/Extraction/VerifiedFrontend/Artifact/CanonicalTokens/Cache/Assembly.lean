import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Token
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Source

namespace Lanius.Extraction
def verifiedFrontendCanonicalTokensCache : ArtifactCache := {
  leafCapacity := 64
  parseNodes := verifiedFrontendCanonicalTokensParseNodeTree
  tokens := verifiedFrontendCanonicalTokensTokenTree
  primarySourceBytes := verifiedFrontendCanonicalTokensSourceByteTree
}
end Lanius.Extraction
