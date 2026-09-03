import Lanius.Extraction.VerifiedFrontend.Context.Base
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_context_imports_kernel :
    ArtifactPackContextChecker.collectUnitImports verifiedFrontendPackDecodedUnitsKernel
      verifiedFrontendDecimalProgramUnitKernel verifiedFrontendDecimalProgramUnitKernel.surface.items =
        some [⟨5, 3⟩, ⟨5, 2⟩, ⟨5, 1⟩] := by
  with_unfolding_all rfl
end Lanius.Extraction
