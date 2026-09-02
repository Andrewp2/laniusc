import Lanius.Extraction.VerifiedFrontendUnitRawLexerOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_ids_dense_kernel :
    (verifiedFrontendRawLexerOrigins).claims.nodes.map (·.id) ==
      List.range (verifiedFrontendRawLexerOrigins).claims.nodes.length := by
  with_unfolding_all rfl
end Lanius.Extraction
