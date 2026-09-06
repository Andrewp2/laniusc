import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Parse
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Token
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.Source

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

