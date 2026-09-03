import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.View.Assembly
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_origin_nodes_checked_kernel :
    nodeOriginPathsValid verifiedFrontendCanonicalTokensArtifact verifiedFrontendCanonicalTokensView
      (verifiedFrontendCanonicalTokensOrigins).claims.nodes (verifiedFrontendCanonicalTokensOrigins).nodePaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
