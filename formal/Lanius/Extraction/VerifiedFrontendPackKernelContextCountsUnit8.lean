import Lanius.Extraction.VerifiedFrontendPackKernelDecodedUnit8
namespace Lanius.Extraction
set_option maxRecDepth 100000
open ArtifactContextChecker
theorem verifiedFrontendRawLexer_context_counts_kernel :
    ((collectStructures verifiedFrontendRawLexerProgramUnitKernel.surface.items).length,
      (collectTypeAliases verifiedFrontendRawLexerProgramUnitKernel.surface.items).length,
      (collectConstants verifiedFrontendRawLexerProgramUnitKernel.surface.items).length,
      (collectFunctions verifiedFrontendRawLexerProgramUnitKernel.surface.items).length) =
      (1, 0, 3, 8) := by
  with_unfolding_all rfl
end Lanius.Extraction
