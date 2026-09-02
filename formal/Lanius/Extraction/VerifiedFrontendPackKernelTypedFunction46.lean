import Lanius.Extraction.VerifiedFrontendPackKernelTypedBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false
theorem verifiedFrontendPack_function46_present_kernel :
    (CoreTyping.checkFunction verifiedFrontendPackProgramKernel
      verifiedFrontendPackFunction46Kernel).isSome = true := by
  cbv
def verifiedFrontendPackFunction46TypedKernel :=
  (CoreTyping.checkFunction verifiedFrontendPackProgramKernel
    verifiedFrontendPackFunction46Kernel).get
      verifiedFrontendPack_function46_present_kernel
theorem verifiedFrontendPack_function46_found_kernel :
    CoreTyping.checkFunction verifiedFrontendPackProgramKernel
      verifiedFrontendPackFunction46Kernel =
        some verifiedFrontendPackFunction46TypedKernel :=
  parseOptionEqSomeGet verifiedFrontendPack_function46_present_kernel
end Lanius.Extraction
