import Lanius.Extraction.VerifiedFrontendUnitTokenOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceTokenView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendToken_origin_nodes_checked_kernel :
    nodeOriginPathsValid verifiedFrontendTokenArtifact verifiedFrontendTokenView
      (verifiedFrontendTokenOrigins).claims.nodes (verifiedFrontendTokenOrigins).nodePaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
