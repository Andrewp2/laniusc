import Lanius.Extraction.VerifiedFrontendPackKernelWire

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendPack_typed_checked_kernel :
    (CoreTyping.checkProgram
      (CoreDecode.program verifiedFrontendPackWireKernel)).isSome = true := by
  cbv

def verifiedFrontendPackTypedKernel :=
  (CoreTyping.checkProgram
    (CoreDecode.program verifiedFrontendPackWireKernel)).get
      verifiedFrontendPack_typed_checked_kernel

theorem verifiedFrontendPackTypedKernel_eq :
    CoreTyping.checkProgram
        (CoreDecode.program verifiedFrontendPackWireKernel) =
      some verifiedFrontendPackTypedKernel := by
  generalize found : CoreTyping.checkProgram
    (CoreDecode.program verifiedFrontendPackWireKernel) = result
  cases result <;> simp_all [verifiedFrontendPackTypedKernel]

end Lanius.Extraction
