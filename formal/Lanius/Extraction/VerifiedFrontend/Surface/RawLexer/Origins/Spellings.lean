import Lanius.Extraction.VerifiedFrontend.Artifact.RawLexer.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_origin_spellings_checked_kernel :
    spellingOriginPathsValid verifiedFrontendRawLexerArtifact verifiedFrontendRawLexerView
      (verifiedFrontendRawLexerOrigins).claims.spellings (verifiedFrontendRawLexerOrigins).spellingPaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction
