import Lanius.Extraction.VerifiedFrontendUnitRawLexerOrigins
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexerView
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_origin_nodes_checked_kernel :
    nodeOriginPathsValid verifiedFrontendRawLexerArtifact verifiedFrontendRawLexerView
      (verifiedFrontendRawLexerOrigins).claims.nodes (verifiedFrontendRawLexerOrigins).nodePaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
