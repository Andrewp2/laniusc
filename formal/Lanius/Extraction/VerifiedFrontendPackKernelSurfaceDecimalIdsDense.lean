import Lanius.Extraction.VerifiedFrontendUnitDecimalOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDecimalView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_ids_dense_kernel :
    (verifiedFrontendDecimalOrigins).claims.nodes.map (·.id) ==
      List.range (verifiedFrontendDecimalOrigins).claims.nodes.length := by
  with_unfolding_all rfl
end Lanius.Extraction
