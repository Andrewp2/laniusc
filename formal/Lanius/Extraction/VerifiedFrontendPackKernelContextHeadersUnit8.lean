import Lanius.Extraction.VerifiedFrontendPackKernelContextAllocations
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactPackContextChecker
theorem verifiedFrontendRawLexer_context_headers_present_kernel :
    (buildUnitHeaders verifiedFrontendRawLexerAllocationKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerContextHeadersKernel :=
  (buildUnitHeaders verifiedFrontendRawLexerAllocationKernel).get
    verifiedFrontendRawLexer_context_headers_present_kernel
theorem verifiedFrontendRawLexer_context_headers_found_kernel :
    buildUnitHeaders verifiedFrontendRawLexerAllocationKernel =
      some verifiedFrontendRawLexerContextHeadersKernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_context_headers_present_kernel
end Lanius.Extraction
