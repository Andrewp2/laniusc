import Lanius.Extraction.VerifiedFrontendPackKernelTypedBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false
theorem verifiedFrontendPack_function45_present_kernel :
    (CoreTyping.checkFunction verifiedFrontendPackProgramKernel
      verifiedFrontendPackFunction45Kernel).isSome = true := by
  cbv
def verifiedFrontendPackFunction45TypedKernel :=
  (CoreTyping.checkFunction verifiedFrontendPackProgramKernel
    verifiedFrontendPackFunction45Kernel).get
      verifiedFrontendPack_function45_present_kernel
theorem verifiedFrontendPack_function45_found_kernel :
    CoreTyping.checkFunction verifiedFrontendPackProgramKernel
      verifiedFrontendPackFunction45Kernel =
        some verifiedFrontendPackFunction45TypedKernel :=
  parseOptionEqSomeGet verifiedFrontendPack_function45_present_kernel
end Lanius.Extraction
