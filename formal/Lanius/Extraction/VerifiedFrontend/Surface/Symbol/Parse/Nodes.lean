import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Reconstruction
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Parse.Token
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Parse.Metadata

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendSymbol_nodes_cached_trace_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendSymbolArtifact
      verifiedFrontendSymbolParseView 0 verifiedFrontendSymbolArtifact.parse_nodes = true := by
  exact verifiedFrontendSymbol_validated_nodes_kernel

theorem verifiedFrontendSymbol_nodes_trace_checked_kernel :
    checkNodesFromView laniusGrammar verifiedFrontendSymbolArtifact
      verifiedFrontendSymbolView 0 verifiedFrontendSymbolArtifact.parse_nodes = true := by
  change checkNodesFromView laniusGrammar verifiedFrontendSymbolArtifact
    verifiedFrontendSymbolParseView.artifactView 0
    verifiedFrontendSymbolArtifact.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar verifiedFrontendSymbolArtifact
    verifiedFrontendSymbolParseView]
  exact verifiedFrontendSymbol_nodes_cached_trace_checked_kernel

theorem verifiedFrontendSymbolParseValidTraceKernel :
    ParseArtifactValid verifiedFrontendSymbolArtifact :=
  parseArtifactValid_of_view_checks verifiedFrontendSymbolArtifact
    verifiedFrontendSymbolView verifiedFrontendSymbolRootTraceKernel
    verifiedFrontendSymbol_token_trace_checked_kernel
    verifiedFrontendSymbol_semantic_trace_checked_kernel
    verifiedFrontendSymbol_nodes_trace_checked_kernel
    verifiedFrontendSymbol_root_trace_found_kernel
    verifiedFrontendSymbol_root_trace_shape_kernel

end Lanius.Extraction

namespace Lanius.Extraction

end Lanius.Extraction
