import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.ParseWell
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.ParseRep
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.TokenWell
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.TokenRep
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.SourceWell
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.View.SourceRep

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
