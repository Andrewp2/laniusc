import Lanius.Extraction.VerifiedFrontendPackKernelContextAllocations
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactPackContextChecker
theorem verifiedFrontendSymbol_context_headers_present_kernel :
    (buildUnitHeaders verifiedFrontendSymbolAllocationKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolContextHeadersKernel :=
  (buildUnitHeaders verifiedFrontendSymbolAllocationKernel).get
    verifiedFrontendSymbol_context_headers_present_kernel
theorem verifiedFrontendSymbol_context_headers_found_kernel :
    buildUnitHeaders verifiedFrontendSymbolAllocationKernel =
      some verifiedFrontendSymbolContextHeadersKernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_context_headers_present_kernel
end Lanius.Extraction
