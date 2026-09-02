import Lanius.Extraction.VerifiedFrontendPackKernelContextAllocations
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactPackContextChecker
theorem verifiedFrontendToken_context_headers_present_kernel :
    (buildUnitHeaders verifiedFrontendTokenAllocationKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenContextHeadersKernel :=
  (buildUnitHeaders verifiedFrontendTokenAllocationKernel).get
    verifiedFrontendToken_context_headers_present_kernel
theorem verifiedFrontendToken_context_headers_found_kernel :
    buildUnitHeaders verifiedFrontendTokenAllocationKernel =
      some verifiedFrontendTokenContextHeadersKernel :=
  parseOptionEqSomeGet verifiedFrontendToken_context_headers_present_kernel
end Lanius.Extraction
