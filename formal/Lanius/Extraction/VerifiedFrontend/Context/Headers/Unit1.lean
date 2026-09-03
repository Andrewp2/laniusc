import Lanius.Extraction.VerifiedFrontend.Context.Allocations
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactPackContextChecker
theorem verifiedFrontendTokenScan_context_headers_present_kernel :
    (buildUnitHeaders verifiedFrontendTokenScanAllocationKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenScanContextHeadersKernel :=
  (buildUnitHeaders verifiedFrontendTokenScanAllocationKernel).get
    verifiedFrontendTokenScan_context_headers_present_kernel
theorem verifiedFrontendTokenScan_context_headers_found_kernel :
    buildUnitHeaders verifiedFrontendTokenScanAllocationKernel =
      some verifiedFrontendTokenScanContextHeadersKernel :=
  parseOptionEqSomeGet verifiedFrontendTokenScan_context_headers_present_kernel
end Lanius.Extraction
