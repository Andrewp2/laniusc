import Lanius.Extraction.VerifiedFrontendPackKernelContextBase
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_context_imports_kernel :
    ArtifactPackContextChecker.collectUnitImports verifiedFrontendPackDecodedUnitsKernel
      verifiedFrontendSymbolProgramUnitKernel verifiedFrontendSymbolProgramUnitKernel.surface.items =
        some [⟨7, 3⟩] := by
  with_unfolding_all rfl
end Lanius.Extraction
