import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaimsTrace
import Lanius.Extraction.VerifiedFrontendUnitLexerOrigins
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendLexer_node_origins_0_checked_kernel :
    nodeOriginPathsValid verifiedFrontendLexerArtifact verifiedFrontendLexerView
      (verifiedFrontendLexerOrigins.claims.nodes.take 277)
      (verifiedFrontendLexerOrigins.nodePaths.take 277) = true := by
  with_unfolding_all rfl
end Lanius.Extraction
