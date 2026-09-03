import Lanius.Extraction.VerifiedFrontend.Assembly.Wire

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendPack_canonical_checked_kernel :
    coreProgramValuesCanonical verifiedFrontendPackWireKernel = true := by
  cbv

end Lanius.Extraction
