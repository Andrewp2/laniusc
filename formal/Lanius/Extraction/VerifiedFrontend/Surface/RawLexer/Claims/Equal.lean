import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Claims.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.RawLexer.Origins
import Lanius.Extraction.KernelSurfacePhases
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_claims_equal_kernel :
    (verifiedFrontendRawLexerOrigins).claims = verifiedFrontendRawLexerClaimsKernel := by
  rfl
end Lanius.Extraction
