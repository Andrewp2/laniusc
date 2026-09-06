import Lanius.Extraction.VerifiedFrontend.Surface.Token.Reconstruction
import Lanius.Extraction.VerifiedFrontend.Surface.Token.Parse.Token
import Lanius.Extraction.VerifiedFrontend.Surface.Token.Parse.Metadata

namespace Lanius.Extraction
set_option maxRecDepth 500000
theorem verifiedFrontendToken_nodes_cached_trace_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendTokenArtifact verifiedFrontendTokenParseView 0
      verifiedFrontendTokenArtifact.parse_nodes = true := by
  exact verifiedFrontendToken_validated_nodes_kernel

theorem verifiedFrontendToken_nodes_trace_checked_kernel :
    checkNodesFromView laniusGrammar verifiedFrontendTokenArtifact verifiedFrontendTokenView 0
      verifiedFrontendTokenArtifact.parse_nodes = true := by
  change checkNodesFromView laniusGrammar verifiedFrontendTokenArtifact
    verifiedFrontendTokenParseView.artifactView 0 verifiedFrontendTokenArtifact.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar verifiedFrontendTokenArtifact verifiedFrontendTokenParseView]
  exact verifiedFrontendToken_nodes_cached_trace_checked_kernel

theorem verifiedFrontendTokenParseValidTraceKernel : ParseArtifactValid verifiedFrontendTokenArtifact :=
  parseArtifactValid_of_view_checks verifiedFrontendTokenArtifact verifiedFrontendTokenView
    verifiedFrontendTokenRootTraceKernel verifiedFrontendToken_token_trace_checked_kernel
    verifiedFrontendToken_semantic_trace_checked_kernel verifiedFrontendToken_nodes_trace_checked_kernel
    verifiedFrontendToken_root_trace_found_kernel verifiedFrontendToken_root_trace_shape_kernel
end Lanius.Extraction

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

end Lanius.Extraction
