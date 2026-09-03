import Lanius.Extraction.VerifiedFrontend.Artifact.Decimal.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.View.Assembly
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_origin_nodes_checked_kernel :
    nodeOriginPathsValid verifiedFrontendDecimalArtifact verifiedFrontendDecimalView
      (verifiedFrontendDecimalOrigins).claims.nodes (verifiedFrontendDecimalOrigins).nodePaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
