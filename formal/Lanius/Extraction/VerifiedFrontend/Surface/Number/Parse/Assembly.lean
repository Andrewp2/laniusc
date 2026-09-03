import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Number.View.Assembly
import Lanius.Extraction.KernelSurfacePhases

namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

kernel_surface_parse verifiedFrontendNumber_parse_checked_kernel for
  verifiedFrontendNumberArtifact, verifiedFrontendNumberView

end Lanius.Extraction
