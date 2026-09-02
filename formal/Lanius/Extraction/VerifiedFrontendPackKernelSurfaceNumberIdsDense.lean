import Lanius.Extraction.VerifiedFrontendUnitNumberOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumberView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_ids_dense_kernel :
    (verifiedFrontendNumberOrigins).claims.nodes.map (·.id) ==
      List.range (verifiedFrontendNumberOrigins).claims.nodes.length := by
  with_unfolding_all rfl
end Lanius.Extraction
