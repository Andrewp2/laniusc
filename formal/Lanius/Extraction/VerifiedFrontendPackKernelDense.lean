import Lanius.Extraction.VerifiedFrontendPackKernelWire

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendPack_dense_checked_kernel :
    coreNodeIdsDense verifiedFrontendPackWireKernel = true := by
  cbv

end Lanius.Extraction
