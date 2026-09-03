import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Cache.Parse.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Cache.Token
import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Cache.Source
namespace Lanius.Extraction
def verifiedFrontendSymbolCache : ArtifactCache := {
  leafCapacity := 64
  parseNodes := verifiedFrontendSymbolParseNodeTree
  tokens := verifiedFrontendSymbolTokenTree
  primarySourceBytes := verifiedFrontendSymbolSourceByteTree
}
end Lanius.Extraction
