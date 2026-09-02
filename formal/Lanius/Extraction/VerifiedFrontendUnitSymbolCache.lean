import Lanius.Extraction.VerifiedFrontendUnitSymbolCacheParse
import Lanius.Extraction.VerifiedFrontendUnitSymbolCacheToken
import Lanius.Extraction.VerifiedFrontendUnitSymbolCacheSource
namespace Lanius.Extraction
def verifiedFrontendSymbolCache : ArtifactCache := {
  leafCapacity := 64
  parseNodes := verifiedFrontendSymbolParseNodeTree
  tokens := verifiedFrontendSymbolTokenTree
  primarySourceBytes := verifiedFrontendSymbolSourceByteTree
}
end Lanius.Extraction
