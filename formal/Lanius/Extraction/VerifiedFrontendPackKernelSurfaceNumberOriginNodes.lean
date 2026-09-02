import Lanius.Extraction.VerifiedFrontendUnitNumberOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumberView
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
