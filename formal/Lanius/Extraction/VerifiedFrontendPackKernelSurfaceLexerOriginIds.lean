import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaimsTrace
import Lanius.Extraction.VerifiedFrontendUnitLexerOrigins

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendLexer_origin_trace_ids_dense_kernel :
    verifiedFrontendLexerOrigins.claims.nodes.map (·.id) ==
      List.range verifiedFrontendLexerOrigins.claims.nodes.length := by
  with_unfolding_all rfl
end Lanius.Extraction
