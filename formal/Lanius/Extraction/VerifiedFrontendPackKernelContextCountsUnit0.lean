import Lanius.Extraction.VerifiedFrontendPackKernelDecodedUnit0
namespace Lanius.Extraction
set_option maxRecDepth 100000
open ArtifactContextChecker
theorem verifiedFrontendLexer_context_counts_kernel :
    ((collectStructures verifiedFrontendLexerProgramUnitKernel.surface.items).length,
      (collectTypeAliases verifiedFrontendLexerProgramUnitKernel.surface.items).length,
      (collectConstants verifiedFrontendLexerProgramUnitKernel.surface.items).length,
      (collectFunctions verifiedFrontendLexerProgramUnitKernel.surface.items).length) =
      (1, 1, 7, 18) := by
  with_unfolding_all rfl
end Lanius.Extraction
