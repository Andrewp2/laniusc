import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnits

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendPack_lowering_covers_core_kernel :
    CompleteChecker.packLoweringCoversCore
      verifiedFrontendPack verifiedFrontendPackWireKernel = true := by
  cbv

end Lanius.Extraction
