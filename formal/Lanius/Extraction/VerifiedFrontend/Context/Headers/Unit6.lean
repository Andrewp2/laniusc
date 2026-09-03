import Lanius.Extraction.VerifiedFrontend.Context.Allocations
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactPackContextChecker
theorem verifiedFrontendNumber_context_headers_present_kernel :
    (buildUnitHeaders verifiedFrontendNumberAllocationKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendNumberContextHeadersKernel :=
  (buildUnitHeaders verifiedFrontendNumberAllocationKernel).get
    verifiedFrontendNumber_context_headers_present_kernel
theorem verifiedFrontendNumber_context_headers_found_kernel :
    buildUnitHeaders verifiedFrontendNumberAllocationKernel =
      some verifiedFrontendNumberContextHeadersKernel :=
  parseOptionEqSomeGet verifiedFrontendNumber_context_headers_present_kernel
end Lanius.Extraction
