import Lanius.Extraction.VerifiedFrontendPackKernelTypedBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false
theorem verifiedFrontendPack_function47_present_kernel :
    (CoreTyping.checkFunction verifiedFrontendPackProgramKernel
      verifiedFrontendPackFunction47Kernel).isSome = true := by
  cbv
def verifiedFrontendPackFunction47TypedKernel :=
  (CoreTyping.checkFunction verifiedFrontendPackProgramKernel
    verifiedFrontendPackFunction47Kernel).get
      verifiedFrontendPack_function47_present_kernel
theorem verifiedFrontendPack_function47_found_kernel :
    CoreTyping.checkFunction verifiedFrontendPackProgramKernel
      verifiedFrontendPackFunction47Kernel =
        some verifiedFrontendPackFunction47TypedKernel :=
  parseOptionEqSomeGet verifiedFrontendPack_function47_present_kernel
end Lanius.Extraction
