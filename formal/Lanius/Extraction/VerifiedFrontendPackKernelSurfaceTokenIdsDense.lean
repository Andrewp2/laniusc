import Lanius.Extraction.VerifiedFrontendUnitTokenOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceTokenView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendToken_ids_dense_kernel :
    (verifiedFrontendTokenOrigins).claims.nodes.map (·.id) ==
      List.range (verifiedFrontendTokenOrigins).claims.nodes.length := by
  with_unfolding_all rfl
end Lanius.Extraction
