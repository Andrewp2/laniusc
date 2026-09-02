import Lanius.Extraction.VerifiedFrontendPackKernelTypedBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false
theorem verifiedFrontendPack_functions_chunk11_present_kernel :
    (CoreTyping.checkFunctions verifiedFrontendPackProgramKernel
      verifiedFrontendPackFunctionsChunk11Kernel).isSome = true := by
  cbv
end Lanius.Extraction

