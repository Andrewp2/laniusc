import Lanius.Extraction.VerifiedFrontendUnitCanonicalTokensCacheParse
import Lanius.Extraction.VerifiedFrontendUnitCanonicalTokensCacheToken
import Lanius.Extraction.VerifiedFrontendUnitCanonicalTokensCacheSource

namespace Lanius.Extraction
def verifiedFrontendCanonicalTokensCache : ArtifactCache := {
  leafCapacity := 64
  parseNodes := verifiedFrontendCanonicalTokensParseNodeTree
  tokens := verifiedFrontendCanonicalTokensTokenTree
  primarySourceBytes := verifiedFrontendCanonicalTokensSourceByteTree
}
end Lanius.Extraction
