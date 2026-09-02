import Lanius.Extraction.VerifiedFrontendUnitSymbolOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_ids_dense_kernel :
    (verifiedFrontendSymbolOrigins).claims.nodes.map (·.id) ==
      List.range (verifiedFrontendSymbolOrigins).claims.nodes.length := by
  with_unfolding_all rfl
end Lanius.Extraction
