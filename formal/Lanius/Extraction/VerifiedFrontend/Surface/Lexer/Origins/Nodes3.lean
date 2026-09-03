import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Claims.Trace
import Lanius.Extraction.VerifiedFrontend.Artifact.Lexer.Origins
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendLexer_node_origins_3_checked_kernel :
    nodeOriginPathsValid verifiedFrontendLexerArtifact verifiedFrontendLexerView
      (verifiedFrontendLexerOrigins.claims.nodes.drop 831)
      (verifiedFrontendLexerOrigins.nodePaths.drop 831) = true := by
  with_unfolding_all rfl
end Lanius.Extraction
