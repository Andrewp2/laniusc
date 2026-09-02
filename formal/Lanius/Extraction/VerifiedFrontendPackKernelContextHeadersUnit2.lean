import Lanius.Extraction.VerifiedFrontendPackKernelContextAllocations
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactPackContextChecker
theorem verifiedFrontendDigits_context_headers_present_kernel :
    (buildUnitHeaders verifiedFrontendDigitsAllocationKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDigitsContextHeadersKernel :=
  (buildUnitHeaders verifiedFrontendDigitsAllocationKernel).get
    verifiedFrontendDigits_context_headers_present_kernel
theorem verifiedFrontendDigits_context_headers_found_kernel :
    buildUnitHeaders verifiedFrontendDigitsAllocationKernel =
      some verifiedFrontendDigitsContextHeadersKernel :=
  parseOptionEqSomeGet verifiedFrontendDigits_context_headers_present_kernel
end Lanius.Extraction
