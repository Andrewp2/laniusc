import Lanius.Extraction.VerifiedFrontend.Typing.Base
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false
theorem verifiedFrontendPack_constants_chunk7_present_kernel :
    (CoreTyping.checkConstants verifiedFrontendPackProgramKernel
      verifiedFrontendPackConstantsChunk7Kernel).isSome = true := by
  cbv
end Lanius.Extraction
