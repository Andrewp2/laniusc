import Lanius.Extraction.VerifiedFrontend.Typing.Base
import Lanius.Extraction.KernelReduction
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendPack_constants_chunk3_present_kernel :
    (CoreTyping.checkConstants verifiedFrontendPackProgramKernel
      verifiedFrontendPackConstantsChunk3Kernel).isSome = true := by
  kernel_rfl
end Lanius.Extraction
