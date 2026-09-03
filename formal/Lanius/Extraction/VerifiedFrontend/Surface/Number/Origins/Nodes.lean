import Lanius.Extraction.VerifiedFrontend.Artifact.Number.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Number.View.Assembly
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_origin_nodes_checked_kernel :
    nodeOriginPathsValid verifiedFrontendNumberArtifact verifiedFrontendNumberView
      (verifiedFrontendNumberOrigins).claims.nodes
      (verifiedFrontendNumberOrigins).nodePaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
