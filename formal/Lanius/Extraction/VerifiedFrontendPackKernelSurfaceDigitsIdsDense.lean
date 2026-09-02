import Lanius.Extraction.VerifiedFrontendUnitDigitsOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigitsView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_ids_dense_kernel :
    (verifiedFrontendDigitsOrigins).claims.nodes.map (·.id) ==
      List.range (verifiedFrontendDigitsOrigins).claims.nodes.length := by
  with_unfolding_all rfl
end Lanius.Extraction
