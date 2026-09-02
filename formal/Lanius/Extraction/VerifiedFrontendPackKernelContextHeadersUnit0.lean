import Lanius.Extraction.VerifiedFrontendPackKernelContextAllocations
import Lanius.Extraction.ArtifactPackContextPhaseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
open ArtifactPackContextChecker
theorem verifiedFrontendLexer_context_headers_present_kernel :
    (buildUnitHeaders verifiedFrontendLexerAllocationKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendLexerContextHeadersKernel :=
  (buildUnitHeaders verifiedFrontendLexerAllocationKernel).get
    verifiedFrontendLexer_context_headers_present_kernel
theorem verifiedFrontendLexer_context_headers_found_kernel :
    buildUnitHeaders verifiedFrontendLexerAllocationKernel =
      some verifiedFrontendLexerContextHeadersKernel :=
  parseOptionEqSomeGet verifiedFrontendLexer_context_headers_present_kernel
end Lanius.Extraction
