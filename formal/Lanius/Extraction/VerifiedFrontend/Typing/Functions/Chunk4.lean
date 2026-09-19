import Lanius.Extraction.VerifiedFrontend.Typing.Base
import Lanius.Extraction.KernelReduction
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendPack_functions_chunk4_present_kernel :
    (CoreTyping.checkFunctions verifiedFrontendPackProgramKernel
      verifiedFrontendPackFunctionsChunk4Kernel).isSome = true := by
  kernel_rfl
end Lanius.Extraction
