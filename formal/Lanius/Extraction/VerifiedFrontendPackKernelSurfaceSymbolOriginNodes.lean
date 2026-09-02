import Lanius.Extraction.VerifiedFrontendUnitSymbolOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_origin_nodes_checked_kernel :
    nodeOriginPathsValid verifiedFrontendSymbolArtifact verifiedFrontendSymbolView
      (verifiedFrontendSymbolOrigins).claims.nodes (verifiedFrontendSymbolOrigins).nodePaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
