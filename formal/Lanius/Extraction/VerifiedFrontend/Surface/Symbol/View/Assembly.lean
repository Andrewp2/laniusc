import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Parse.WellFormed
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Parse.Representation
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Token.WellFormed
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Token.Representation
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Source.WellFormed
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Source.Representation

namespace Lanius.Extraction
def verifiedFrontendSymbolView : ArtifactView verifiedFrontendSymbolArtifact := {
  cache := verifiedFrontendSymbolCache
  parseNodesWellFormed := verifiedFrontendSymbol_parse_tree_well_formed_kernel
  parseNodesRepresent := verifiedFrontendSymbol_parse_tree_represents_kernel
  tokensWellFormed := verifiedFrontendSymbol_token_tree_well_formed_kernel
  tokensRepresent := verifiedFrontendSymbol_token_tree_represents_kernel
  sourceBytesWellFormed := verifiedFrontendSymbol_source_tree_well_formed_kernel
  sourceBytesRepresent := verifiedFrontendSymbol_source_tree_represents_kernel
}

end Lanius.Extraction
