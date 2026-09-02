import Lanius.Extraction.VerifiedFrontendUnitDigitsOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigitsView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_origin_nodes_checked_kernel :
    nodeOriginPathsValid verifiedFrontendDigitsArtifact verifiedFrontendDigitsView
      (verifiedFrontendDigitsOrigins).claims.nodes (verifiedFrontendDigitsOrigins).nodePaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
