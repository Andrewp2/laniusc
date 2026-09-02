import Lanius.Extraction.VerifiedFrontendPackKernelContextAllocations
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactPackContextChecker
theorem verifiedFrontendDecimal_context_headers_present_kernel :
    (buildUnitHeaders verifiedFrontendDecimalAllocationKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDecimalContextHeadersKernel :=
  (buildUnitHeaders verifiedFrontendDecimalAllocationKernel).get
    verifiedFrontendDecimal_context_headers_present_kernel
theorem verifiedFrontendDecimal_context_headers_found_kernel :
    buildUnitHeaders verifiedFrontendDecimalAllocationKernel =
      some verifiedFrontendDecimalContextHeadersKernel :=
  parseOptionEqSomeGet verifiedFrontendDecimal_context_headers_present_kernel
end Lanius.Extraction
