import Lanius.Extraction.VerifiedFrontendUnitTokenScanOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceTokenScanView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_ids_dense_kernel :
    (verifiedFrontendTokenScanOrigins).claims.nodes.map (·.id) ==
      List.range (verifiedFrontendTokenScanOrigins).claims.nodes.length := by
  with_unfolding_all rfl
end Lanius.Extraction
