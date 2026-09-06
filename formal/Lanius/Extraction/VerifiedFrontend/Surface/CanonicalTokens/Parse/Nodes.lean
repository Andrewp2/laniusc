import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Token
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Parse.Metadata

namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_nodes_cached_trace_checked_kernel :
    checkNodesFromParseView laniusGrammar verifiedFrontendCanonicalTokensArtifact verifiedFrontendCanonicalTokensParseView 0
      verifiedFrontendCanonicalTokensArtifact.parse_nodes = true := by
  exact verifiedFrontendCanonicalTokens_validated_nodes_kernel

theorem verifiedFrontendCanonicalTokens_nodes_trace_checked_kernel :
    checkNodesFromView laniusGrammar verifiedFrontendCanonicalTokensArtifact
      verifiedFrontendCanonicalTokensView 0
      verifiedFrontendCanonicalTokensArtifact.parse_nodes = true := by
  change checkNodesFromView laniusGrammar verifiedFrontendCanonicalTokensArtifact
    verifiedFrontendCanonicalTokensParseView.artifactView 0
    verifiedFrontendCanonicalTokensArtifact.parse_nodes = true
  rw [← checkNodesFromParseView_eq laniusGrammar
    verifiedFrontendCanonicalTokensArtifact
    verifiedFrontendCanonicalTokensParseView]
  exact verifiedFrontendCanonicalTokens_nodes_cached_trace_checked_kernel

theorem verifiedFrontendCanonicalTokensParseValidTraceKernel :
    ParseArtifactValid verifiedFrontendCanonicalTokensArtifact :=
  parseArtifactValid_of_view_checks verifiedFrontendCanonicalTokensArtifact verifiedFrontendCanonicalTokensView
    verifiedFrontendCanonicalTokensRootTraceKernel
    verifiedFrontendCanonicalTokens_token_trace_checked_kernel
    verifiedFrontendCanonicalTokens_semantic_trace_checked_kernel
    verifiedFrontendCanonicalTokens_nodes_trace_checked_kernel
    verifiedFrontendCanonicalTokens_root_trace_found_kernel
    verifiedFrontendCanonicalTokens_root_trace_shape_kernel

end Lanius.Extraction
