import Lanius.Extraction.VerifiedFrontend.Assembly.Wire
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendPack_canonical_checked_kernel :
    coreProgramValuesCanonical verifiedFrontendPackWireKernel = true := by
  kernel_rfl

end Lanius.Extraction
