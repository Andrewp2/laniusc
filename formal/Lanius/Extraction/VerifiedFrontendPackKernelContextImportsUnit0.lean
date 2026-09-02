import Lanius.Extraction.VerifiedFrontendPackKernelContextBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendLexer_context_imports_kernel :
    ArtifactPackContextChecker.collectUnitImports verifiedFrontendPackDecodedUnitsKernel
      verifiedFrontendLexerProgramUnitKernel verifiedFrontendLexerProgramUnitKernel.surface.items = some [] := by
  with_unfolding_all rfl
end Lanius.Extraction
