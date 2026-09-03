import Lanius.Extraction.VerifiedFrontend.Typing.Base
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Function45
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Function46
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Function47
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendPack_functions_chunk15_present_kernel :
    (CoreTyping.checkFunctions verifiedFrontendPackProgramKernel
      verifiedFrontendPackFunctionsChunk15Kernel).isSome = true := by
  rw [show verifiedFrontendPackFunctionsChunk15Kernel =
    [verifiedFrontendPackFunction45Kernel, verifiedFrontendPackFunction46Kernel,
      verifiedFrontendPackFunction47Kernel] by with_unfolding_all rfl]
  simp [CoreTyping.checkFunctions,
    verifiedFrontendPack_function45_found_kernel,
    verifiedFrontendPack_function46_found_kernel,
    verifiedFrontendPack_function47_found_kernel]
end Lanius.Extraction
