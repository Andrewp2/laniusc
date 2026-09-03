import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.View.Assembly
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

kernel_surface_parse verifiedFrontendRawLexer_parse_checked_kernel for
  verifiedFrontendRawLexerArtifact, verifiedFrontendRawLexerView

end Lanius.Extraction
